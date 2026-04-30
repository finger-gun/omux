import AppKit
import Foundation
import OmuxCore

#if canImport(CGhostty)
import CGhostty

enum CGhosttyRuntimeError: Error {
    case missingSurface(String)
    case appInitializationFailed
    case globalInitializationFailed(Int32)
    case surfaceInitializationFailed(String)
}

@MainActor
private final class GhosttyHostedSurfaceView: NSView {
    private weak var runtime: CGhosttyRuntime?
    private let runtimeSurfaceID: String

    init(runtime: CGhosttyRuntime, runtimeSurfaceID: String) {
        self.runtime = runtime
        self.runtimeSurfaceID = runtimeSurfaceID
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        runtime?.syncHostedSurfaceMetrics(runtimeSurfaceID: runtimeSurfaceID, view: self)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        runtime?.syncHostedSurfaceMetrics(runtimeSurfaceID: runtimeSurfaceID, view: self)
    }
}

public final class CGhosttyRuntime: @unchecked Sendable, GhosttyRuntime {
    private final class SurfaceState: @unchecked Sendable {
        let paneID: PaneID
        let hostView: GhosttyHostedSurfaceView
        var surface: ghostty_surface_t?
        var descriptor: SessionDescriptor?
        var retainedCStringPointers: [UnsafeMutablePointer<CChar>] = []
        var size: TerminalSize = .default

        init(paneID: PaneID, hostView: GhosttyHostedSurfaceView) {
            self.paneID = paneID
            self.hostView = hostView
        }

        deinit {
            retainedCStringPointers.forEach { free($0) }
        }

        func retainCString(_ value: String) -> UnsafeMutablePointer<CChar>? {
            guard let pointer = strdup(value) else {
                return nil
            }
            retainedCStringPointers.append(pointer)
            return pointer
        }
    }

    private final class AppState: @unchecked Sendable {
        let config: ghostty_config_t?
        let app: ghostty_app_t?
        private weak var owner: CGhosttyRuntime?

        init(owner: CGhosttyRuntime) {
            self.owner = owner

            let config = ghostty_config_new()
            ghostty_config_finalize(config)

            var runtimeConfig = ghostty_runtime_config_s(
                userdata: Unmanaged.passUnretained(owner).toOpaque(),
                supports_selection_clipboard: false,
                wakeup_cb: { userdata in
                    guard let userdata else { return }
                    let owner = Unmanaged<CGhosttyRuntime>.fromOpaque(userdata).takeUnretainedValue()
                    owner.scheduleTick()
                },
                action_cb: { _, _, _ in false },
                read_clipboard_cb: { _, _, _ in false },
                confirm_read_clipboard_cb: { _, _, _, _ in },
                write_clipboard_cb: { _, _, _, _, _ in },
                close_surface_cb: nil
            )

            self.config = config
            self.app = ghostty_app_new(&runtimeConfig, config)
        }

        deinit {
            if let app {
                ghostty_app_free(app)
            }
            if let config {
                ghostty_config_free(config)
            }
        }
    }

    private let lock = NSLock()
    private let tickLock = NSLock()
    private var appState: AppState?
    private var surfaces: [String: SurfaceState] = [:]
    private var tickScheduled = false

    public init() {}

    public func createSurface(for paneID: PaneID) throws -> String {
        let runtimeSurfaceID = "cghostty:\(paneID.rawValue)"
        let hostView = makeHostView(runtime: self, runtimeSurfaceID: runtimeSurfaceID)

        lock.lock()
        defer { lock.unlock() }

        if surfaces[runtimeSurfaceID] == nil {
            surfaces[runtimeSurfaceID] = SurfaceState(paneID: paneID, hostView: hostView)
        }

        return runtimeSurfaceID
    }

    public func attach(session: SessionDescriptor, to runtimeSurfaceID: String) throws {
        let appState = try ensureAppState()
        let state = try surfaceState(for: runtimeSurfaceID)

        if let existingSurface = state.surface {
            ghostty_surface_free(existingSurface)
            state.surface = nil
            state.retainedCStringPointers.removeAll(keepingCapacity: false)
        }

        let (width, height, scale, isWindowFocused) = mainActorValue {
            let backingBounds = state.hostView.convertToBacking(state.hostView.bounds)
            let window = state.hostView.window
            return (
                UInt32(max(backingBounds.width, 640)),
                UInt32(max(backingBounds.height, 360)),
                window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1,
                window?.isKeyWindow ?? false
            )
        }

        var config = ghostty_surface_config_new()
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform.macos.nsview = Unmanaged.passUnretained(state.hostView).toOpaque()
        config.userdata = nil
        config.scale_factor = scale
        config.font_size = 12
        config.working_directory = UnsafePointer(state.retainCString(session.workingDirectory))
        config.command = UnsafePointer(state.retainCString(session.shell))
        config.initial_input = nil
        config.wait_after_command = false
        config.context = GHOSTTY_SURFACE_CONTEXT_SPLIT

        guard let app = appState.app else {
            throw CGhosttyRuntimeError.appInitializationFailed
        }

        guard let surface = createGhosttySurface(app: app, config: &config) else {
            throw CGhosttyRuntimeError.surfaceInitializationFailed(runtimeSurfaceID)
        }

        state.surface = surface
        state.descriptor = session
        runOnMain {
            ghostty_surface_set_content_scale(surface, scale, scale)
            ghostty_surface_set_size(surface, width, height)
            ghostty_app_set_focus(app, isWindowFocused)
        }
        scheduleTick()
    }

    public func destroySurface(runtimeSurfaceID: String) throws {
        let state: SurfaceState
        lock.lock()
        guard let removed = surfaces.removeValue(forKey: runtimeSurfaceID) else {
            lock.unlock()
            throw CGhosttyRuntimeError.missingSurface(runtimeSurfaceID)
        }
        state = removed
        lock.unlock()

        if let surface = state.surface {
            runOnMain {
                ghostty_surface_free(surface)
            }
        }
    }

    @MainActor
    public func makeHostedSurfaceView(
        for paneID: PaneID,
        runtimeSurfaceID: String
    ) -> NSView? {
        _ = paneID
        lock.lock()
        let hostView = surfaces[runtimeSurfaceID]?.hostView
        lock.unlock()
        return hostView
    }

    public func ownsSession(for runtimeSurfaceID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return surfaces[runtimeSurfaceID]?.surface != nil
    }

    public func send(text: String, to runtimeSurfaceID: String) throws {
        let state = try surfaceState(for: runtimeSurfaceID)
        guard let surface = state.surface else {
            throw CGhosttyRuntimeError.missingSurface(runtimeSurfaceID)
        }

        text.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(text.utf8.count))
        }
        scheduleTick()
    }

    public func handle(_ event: NormalizedKeyEvent, on runtimeSurfaceID: String) throws {
        let state = try surfaceState(for: runtimeSurfaceID)
        guard let surface = state.surface else {
            throw CGhosttyRuntimeError.missingSurface(runtimeSurfaceID)
        }

        var keyEvent = ghostty_input_key_s(
            action: event.isRepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS,
            mods: ghosttyModifiers(from: event.modifiers),
            consumed_mods: ghosttyModifiers(from: event.modifiers),
            keycode: UInt32(event.keyCode ?? 0),
            text: nil,
            unshifted_codepoint: event.key.unicodeScalars.first?.value ?? 0,
            composing: event.route == .composition
        )

        let consumed: Bool
        if let text = event.text, text.isEmpty == false {
            consumed = text.withCString { ptr in
                keyEvent.text = ptr
                return ghostty_surface_key(surface, keyEvent)
            }
        } else {
            consumed = ghostty_surface_key(surface, keyEvent)
        }

        if consumed == false, let text = event.text, text.isEmpty == false {
            try send(text: text, to: runtimeSurfaceID)
            return
        }

        scheduleTick()
    }

    public func resizeSurface(runtimeSurfaceID: String, columns: Int, rows: Int) throws {
        let state = try surfaceState(for: runtimeSurfaceID)
        guard let surface = state.surface else {
            throw CGhosttyRuntimeError.missingSurface(runtimeSurfaceID)
        }

        state.size = TerminalSize(columns: columns, rows: rows)
        let size = mainActorValue {
            state.hostView.convertToBacking(state.hostView.bounds).size
        }
        runOnMain {
            ghostty_surface_set_size(
                surface,
                UInt32(max(size.width, 1)),
                UInt32(max(size.height, 1))
            )
        }
        scheduleTick()
    }

    public func setSurfaceFocused(runtimeSurfaceID: String, focused: Bool) {
        guard let state = try? surfaceState(for: runtimeSurfaceID),
              let surface = state.surface
        else {
            return
        }

        let app = appState?.app
        runOnMain {
            ghostty_surface_set_focus(surface, focused)
            if let app {
                ghostty_app_set_focus(app, focused)
            }
        }
        scheduleTick()
    }

    public func snapshot(
        paneID: PaneID,
        sessionID: SessionID,
        descriptor: SessionDescriptor,
        runtimeSurfaceID: String,
        fallbackSize: TerminalSize
    ) -> TerminalSessionSnapshot? {
        guard let state = try? surfaceState(for: runtimeSurfaceID),
              let surface = state.surface
        else {
            return nil
        }

        let size = ghostty_surface_size(surface)
        return TerminalSessionSnapshot(
            paneID: paneID,
            sessionID: sessionID,
            runtimeSurfaceID: runtimeSurfaceID,
            transcript: "",
            currentInput: "",
            shell: descriptor.shell,
            workingDirectory: descriptor.workingDirectory,
            columns: size.columns > 0 ? Int(size.columns) : fallbackSize.columns,
            rows: size.rows > 0 ? Int(size.rows) : fallbackSize.rows
        )
    }

    @MainActor
    func syncHostedSurfaceMetrics(runtimeSurfaceID: String, view: NSView) {
        guard let state = try? surfaceState(for: runtimeSurfaceID),
              let surface = state.surface
        else {
            return
        }

        let backingBounds = view.convertToBacking(view.bounds)
        let xScale = max(backingBounds.width / max(view.bounds.width, 1), 1)
        let yScale = max(backingBounds.height / max(view.bounds.height, 1), 1)

        ghostty_surface_set_content_scale(surface, xScale, yScale)
        ghostty_surface_set_size(
            surface,
            UInt32(max(backingBounds.width, 1)),
            UInt32(max(backingBounds.height, 1))
        )

        if let displayID = view.window?.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            ghostty_surface_set_display_id(surface, displayID.uint32Value)
        }

        scheduleTick()
    }

    private func ensureAppState() throws -> AppState {
        lock.lock()
        defer { lock.unlock() }

        if let appState {
            return appState
        }

        try ensureGhosttyInitialized()

        let newState = AppState(owner: self)
        appState = newState
        return newState
    }

    private func surfaceState(for runtimeSurfaceID: String) throws -> SurfaceState {
        lock.lock()
        defer { lock.unlock() }

        guard let state = surfaces[runtimeSurfaceID] else {
            throw CGhosttyRuntimeError.missingSurface(runtimeSurfaceID)
        }

        return state
    }

    private func scheduleTick() {
        guard let app = currentApp() else {
            return
        }

        if Thread.isMainThread {
            ghostty_app_tick(app)
            return
        }

        tickLock.lock()
        if tickScheduled {
            tickLock.unlock()
            return
        }
        tickScheduled = true
        tickLock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.tickLock.lock()
            self.tickScheduled = false
            self.tickLock.unlock()

            guard let app = self.currentApp() else {
                return
            }

            ghostty_app_tick(app)
        }
    }

    private func ghosttyModifiers(from modifiers: KeyModifiers) -> ghostty_input_mods_e {
        var rawValue = UInt32(GHOSTTY_MODS_NONE.rawValue)

        if modifiers.contains(.leftShift) { rawValue |= UInt32(GHOSTTY_MODS_SHIFT.rawValue) }
        if modifiers.contains(.rightShift) { rawValue |= UInt32(GHOSTTY_MODS_SHIFT_RIGHT.rawValue) }
        if modifiers.contains(.leftControl) { rawValue |= UInt32(GHOSTTY_MODS_CTRL.rawValue) }
        if modifiers.contains(.rightControl) { rawValue |= UInt32(GHOSTTY_MODS_CTRL_RIGHT.rawValue) }
        if modifiers.contains(.leftOption) { rawValue |= UInt32(GHOSTTY_MODS_ALT.rawValue) }
        if modifiers.contains(.rightOption) { rawValue |= UInt32(GHOSTTY_MODS_ALT_RIGHT.rawValue) }
        if modifiers.contains(.leftCommand) { rawValue |= UInt32(GHOSTTY_MODS_SUPER.rawValue) }
        if modifiers.contains(.rightCommand) { rawValue |= UInt32(GHOSTTY_MODS_SUPER_RIGHT.rawValue) }
        if modifiers.contains(.capsLock) { rawValue |= UInt32(GHOSTTY_MODS_CAPS.rawValue) }

        return ghostty_input_mods_e(rawValue)
    }

    private func currentApp() -> ghostty_app_t? {
        lock.lock()
        defer { lock.unlock() }
        return appState?.app
    }
}

private func makeHostView(
    runtime: CGhosttyRuntime,
    runtimeSurfaceID: String
) -> GhosttyHostedSurfaceView {
    if Thread.isMainThread {
        return MainActor.assumeIsolated {
            GhosttyHostedSurfaceView(runtime: runtime, runtimeSurfaceID: runtimeSurfaceID)
        }
    }

    var hostView: GhosttyHostedSurfaceView?
    DispatchQueue.main.sync {
        hostView = MainActor.assumeIsolated {
            GhosttyHostedSurfaceView(runtime: runtime, runtimeSurfaceID: runtimeSurfaceID)
        }
    }

    return hostView!
}

private func createGhosttySurface(
    app: ghostty_app_t,
    config: inout ghostty_surface_config_s
) -> ghostty_surface_t? {
    var localConfig = config
    if Thread.isMainThread {
        return ghostty_surface_new(app, &localConfig)
    }

    var surface: ghostty_surface_t?
    runOnMain {
        surface = ghostty_surface_new(app, &localConfig)
    }
    return surface
}

private final class GhosttyBootstrapState: @unchecked Sendable {
    let lock = NSLock()
    var didInitialize = false
}

private let ghosttyBootstrapState = GhosttyBootstrapState()

private func ensureGhosttyInitialized() throws {
    ghosttyBootstrapState.lock.lock()
    defer { ghosttyBootstrapState.lock.unlock() }

    if ghosttyBootstrapState.didInitialize {
        return
    }

    var argv = CommandLine.arguments.map { strdup($0) }
    defer {
        argv.forEach { free($0) }
    }

    let result = argv.withUnsafeMutableBufferPointer { buffer in
        ghostty_init(UInt(buffer.count), buffer.baseAddress)
    }

    guard result == 0 else {
        throw CGhosttyRuntimeError.globalInitializationFailed(result)
    }

    ghosttyBootstrapState.didInitialize = true
}

private func runOnMain(_ body: @escaping () -> Void) {
    if Thread.isMainThread {
        body()
        return
    }

    DispatchQueue.main.sync(execute: body)
}

@discardableResult
private func mainActorValue<T: Sendable>(_ body: @escaping @MainActor () -> T) -> T {
    if Thread.isMainThread {
        return MainActor.assumeIsolated(body)
    }

    return DispatchQueue.main.sync {
        MainActor.assumeIsolated(body)
    }
}
#endif
