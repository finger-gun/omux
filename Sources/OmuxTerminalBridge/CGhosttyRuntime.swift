import AppKit
import Foundation
import OmuxConfig
import OmuxCore

#if canImport(CGhostty)
import CGhostty

enum CGhosttyRuntimeError: Error {
    case missingSurface(String)
    case appInitializationFailed
    case globalInitializationFailed(Int32)
    case surfaceInitializationFailed(String)
    case compiledConfigNotFound(String)
}

@MainActor
private final class GhosttyHostedSurfaceView: RuntimeTerminalHostView {
    private weak var runtime: CGhosttyRuntime?
    private let runtimeSurfaceID: String

    init(runtime: CGhosttyRuntime, runtimeSurfaceID: String) {
        self.runtime = runtime
        self.runtimeSurfaceID = runtimeSurfaceID
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        normalizedKeyHandler = { [weak self] event in
            guard let self else { return }
            self.runtime?.handleHostedSurfaceKeyEvent(event, runtimeSurfaceID: self.runtimeSurfaceID)
        }
        committedTextHandler = { [weak self] text in
            guard let self else { return }
            self.runtime?.handleHostedSurfaceCommittedText(text, runtimeSurfaceID: self.runtimeSurfaceID)
        }
        accumulatedTextHandler = { [weak self] event, text in
            guard let self else { return }
            self.runtime?.handleHostedSurfaceAccumulatedText(
                event,
                text: text,
                runtimeSurfaceID: self.runtimeSurfaceID
            )
        }
        preeditHandler = { [weak self] text in
            guard let self else { return }
            self.runtime?.setHostedSurfacePreedit(text, runtimeSurfaceID: self.runtimeSurfaceID)
        }
        imeRectProvider = { [weak self] in
            guard let self else { return .zero }
            return self.runtime?.hostedSurfaceIMERect(runtimeSurfaceID: self.runtimeSurfaceID) ?? .zero
        }
        translatedKeyEventProvider = { [weak self] event in
            guard let self else { return event }
            return self.runtime?.translatedHostedSurfaceKeyEvent(
                for: event,
                runtimeSurfaceID: self.runtimeSurfaceID
            ) ?? event
        }
        copyHandler = { [weak self] in
            guard let self else { return }
            self.runtime?.performHostedSurfaceBindingAction(
                "copy_to_clipboard",
                runtimeSurfaceID: self.runtimeSurfaceID
            )
        }
        pasteHandler = { [weak self] in
            guard let self else { return }
            self.runtime?.performHostedSurfaceBindingAction(
                "paste_from_clipboard",
                runtimeSurfaceID: self.runtimeSurfaceID
            )
        }
        selectAllHandler = { [weak self] in
            guard let self else { return }
            self.runtime?.performHostedSurfaceBindingAction(
                "select_all",
                runtimeSurfaceID: self.runtimeSurfaceID
            )
        }
        mouseButtonHandler = { [weak self] state, buttonNumber, modifiers in
            guard let self else { return false }
            return self.runtime?.performHostedSurfaceMouseButton(
                state,
                buttonNumber: buttonNumber,
                modifiers: modifiers,
                runtimeSurfaceID: self.runtimeSurfaceID
            ) ?? false
        }
        mousePositionHandler = { [weak self] point, modifiers in
            guard let self else { return }
            self.runtime?.performHostedSurfaceMousePosition(
                point,
                modifiers: modifiers,
                runtimeSurfaceID: self.runtimeSurfaceID
            )
        }
        mouseScrollHandler = { [weak self] deltaX, deltaY, precise, momentum in
            guard let self else { return }
            self.runtime?.performHostedSurfaceMouseScroll(
                deltaX: deltaX,
                deltaY: deltaY,
                precise: precise,
                momentum: momentum,
                runtimeSurfaceID: self.runtimeSurfaceID
            )
        }
        mousePressureHandler = { [weak self] stage, pressure in
            guard let self else { return }
            self.runtime?.performHostedSurfaceMousePressure(
                stage: stage,
                pressure: pressure,
                runtimeSurfaceID: self.runtimeSurfaceID
            )
        }
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
        var config: ghostty_config_t?
        let app: ghostty_app_t?
        private weak var owner: CGhosttyRuntime?

        init(owner: CGhosttyRuntime, configFileURL: URL?) throws {
            self.owner = owner

            let config = ghostty_config_new()
            if let configFileURL {
                configFileURL.path.withCString { path in
                    ghostty_config_load_file(config, path)
                }
            }
            ghostty_config_finalize(config)

            var runtimeConfig = ghostty_runtime_config_s(
                userdata: Unmanaged.passUnretained(owner).toOpaque(),
                supports_selection_clipboard: false,
                wakeup_cb: { userdata in
                    guard let userdata else { return }
                    let owner = Unmanaged<CGhosttyRuntime>.fromOpaque(userdata).takeUnretainedValue()
                    owner.scheduleTick()
                },
                action_cb: { app, target, action in
                    guard let app else { return false }
                    guard let userdata = ghostty_app_userdata(app) else { return false }
                    let owner = Unmanaged<CGhosttyRuntime>.fromOpaque(userdata).takeUnretainedValue()
                    return owner.handleAction(target: target, action: action)
                },
                read_clipboard_cb: { userdata, location, state in
                    guard let userdata else { return false }
                    let owner = Unmanaged<CGhosttyRuntime>.fromOpaque(userdata).takeUnretainedValue()
                    return owner.readClipboard(for: location, state: state)
                },
                confirm_read_clipboard_cb: { _, _, _, _ in },
                write_clipboard_cb: { userdata, location, content, len, confirm in
                    guard let userdata else { return }
                    let owner = Unmanaged<CGhosttyRuntime>.fromOpaque(userdata).takeUnretainedValue()
                    owner.writeClipboard(
                        for: location,
                        content: content,
                        len: len,
                        confirm: confirm
                    )
                },
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
    private var focusedRuntimeSurfaceID: String?
    private var tickScheduled = false
    private var compiledConfigPath: URL?
    private var terminalActionHandler: (@Sendable (RuntimeTerminalActionRecord) -> Bool)?

    public init(compiledConfigPath: URL? = nil) {
        self.compiledConfigPath = compiledConfigPath
    }

    public func applyCompiledConfig(path: URL) throws -> [OmuxConfigDiagnostic] {
        try replaceCompiledConfig(path: path, updateRunningApp: true)
    }

    public func refreshCompiledConfig(path: URL) throws -> [OmuxConfigDiagnostic] {
        try replaceCompiledConfig(path: path, updateRunningApp: true)
    }

    public func setTerminalActionHandler(
        _ handler: (@Sendable (RuntimeTerminalActionRecord) -> Bool)?
    ) {
        lock.lock()
        terminalActionHandler = handler
        lock.unlock()
    }

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
        config.userdata = Unmanaged.passUnretained(state.hostView).toOpaque()
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

    private func handleAction(target: ghostty_target_s, action: ghostty_action_s) -> Bool {
        guard target.tag == GHOSTTY_TARGET_SURFACE,
              let runtimeSurfaceID = runtimeSurfaceID(for: target.target.surface)
        else {
            return false
        }

        let translation = translateAction(action)
        guard case .supported(let terminalAction) = translation else {
            return false
        }

        lock.lock()
        let handler = terminalActionHandler
        lock.unlock()
        return handler?(RuntimeTerminalActionRecord(runtimeSurfaceID: runtimeSurfaceID, action: terminalAction)) ?? false
    }

    private func runtimeSurfaceID(for surface: ghostty_surface_t?) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return surfaces.first(where: { $0.value.surface == surface })?.key
    }

    private func translateAction(_ action: ghostty_action_s) -> TerminalActionTranslation {
        switch action.tag {
        case GHOSTTY_ACTION_PWD:
            guard let pwd = action.action.pwd.pwd.map(String.init(cString:)) else {
                return .deferred
            }
            return .supported(.workingDirectoryChanged(pwd))
        case GHOSTTY_ACTION_SET_TITLE:
            guard let title = action.action.set_title.title.map(String.init(cString:)) else {
                return .deferred
            }
            return .supported(.titleChanged(title))
        case GHOSTTY_ACTION_SET_TAB_TITLE:
            guard let title = action.action.set_tab_title.title.map(String.init(cString:)) else {
                return .deferred
            }
            return .supported(.tabTitleChanged(title))
        case GHOSTTY_ACTION_OPEN_URL:
            guard let urlPointer = action.action.open_url.url else {
                return .deferred
            }
            let utf8Pointer = UnsafeRawPointer(urlPointer).assumingMemoryBound(to: UInt8.self)
            let buffer = UnsafeBufferPointer(start: utf8Pointer, count: Int(action.action.open_url.len))
            let url = String(decoding: buffer, as: UTF8.self)
            let kind: TerminalOpenURLKind
            switch action.action.open_url.kind {
            case GHOSTTY_ACTION_OPEN_URL_KIND_TEXT:
                kind = .text
            case GHOSTTY_ACTION_OPEN_URL_KIND_HTML:
                kind = .html
            default:
                kind = .unknown
            }
            return .supported(.openURL(url: url, kind: kind))
        case GHOSTTY_ACTION_DESKTOP_NOTIFICATION:
            guard let titlePointer = action.action.desktop_notification.title else {
                return .deferred
            }
            let title = String(cString: titlePointer)
            let body = action.action.desktop_notification.body.map(String.init(cString:))
            return .supported(.desktopNotification(title: title, body: body))
        case GHOSTTY_ACTION_RING_BELL:
            return .supported(.bell)
        case GHOSTTY_ACTION_COMMAND_FINISHED:
            let exitCode = action.action.command_finished.exit_code >= 0 ? Int(action.action.command_finished.exit_code) : nil
            return .supported(
                .commandFinished(
                    exitCode: exitCode,
                    durationNanoseconds: action.action.command_finished.duration
                )
            )
        case GHOSTTY_ACTION_PROGRESS_REPORT:
            let state: TerminalProgressState
            switch action.action.progress_report.state {
            case GHOSTTY_PROGRESS_STATE_SET:
                state = .active
            case GHOSTTY_PROGRESS_STATE_ERROR:
                state = .error
            case GHOSTTY_PROGRESS_STATE_INDETERMINATE:
                state = .indeterminate
            case GHOSTTY_PROGRESS_STATE_PAUSE:
                state = .paused
            default:
                state = .removed
            }
            let progress = action.action.progress_report.progress >= 0 ? Int(action.action.progress_report.progress) : nil
            return .supported(.progressReported(state: state, progress: progress))
        case GHOSTTY_ACTION_SHOW_CHILD_EXITED:
            return .supported(
                .childExited(
                    exitCode: Int(action.action.child_exited.exit_code),
                    elapsedMilliseconds: action.action.child_exited.timetime_ms
                )
            )
        case GHOSTTY_ACTION_RENDERER_HEALTH:
            let isHealthy = action.action.renderer_health == GHOSTTY_RENDERER_HEALTH_HEALTHY
            return .supported(.rendererHealthChanged(isHealthy: isHealthy))
        case GHOSTTY_ACTION_NEW_WINDOW,
             GHOSTTY_ACTION_NEW_TAB,
             GHOSTTY_ACTION_CLOSE_TAB,
             GHOSTTY_ACTION_NEW_SPLIT,
             GHOSTTY_ACTION_CLOSE_ALL_WINDOWS,
             GHOSTTY_ACTION_TOGGLE_MAXIMIZE,
             GHOSTTY_ACTION_TOGGLE_FULLSCREEN,
             GHOSTTY_ACTION_TOGGLE_TAB_OVERVIEW,
             GHOSTTY_ACTION_TOGGLE_WINDOW_DECORATIONS,
             GHOSTTY_ACTION_TOGGLE_QUICK_TERMINAL,
             GHOSTTY_ACTION_TOGGLE_COMMAND_PALETTE,
             GHOSTTY_ACTION_TOGGLE_VISIBILITY,
             GHOSTTY_ACTION_MOVE_TAB,
             GHOSTTY_ACTION_GOTO_TAB,
             GHOSTTY_ACTION_GOTO_SPLIT,
             GHOSTTY_ACTION_GOTO_WINDOW,
             GHOSTTY_ACTION_RESIZE_SPLIT,
             GHOSTTY_ACTION_EQUALIZE_SPLITS,
             GHOSTTY_ACTION_TOGGLE_SPLIT_ZOOM,
             GHOSTTY_ACTION_PRESENT_TERMINAL,
             GHOSTTY_ACTION_OPEN_CONFIG,
             GHOSTTY_ACTION_FLOAT_WINDOW,
             GHOSTTY_ACTION_CHECK_FOR_UPDATES,
             GHOSTTY_ACTION_CLOSE_WINDOW:
            return .rejected
        default:
            return .deferred
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

        let action: ghostty_input_action_e
        switch event.phase {
        case .keyDown:
            action = event.isRepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
        case .keyUp:
            action = GHOSTTY_ACTION_RELEASE
        }

        var keyEvent = ghostty_input_key_s(
            action: action,
            mods: ghosttyModifiers(from: event.modifiers),
            consumed_mods: ghosttyConsumedModifiers(
                surface: surface,
                originalModifiers: event.modifiers
            ),
            keycode: UInt32(event.keyCode ?? 0),
            text: nil,
            unshifted_codepoint: event.key.unicodeScalars.first?.value ?? 0,
            composing: event.route == .composition
        )

        if let text = sanitizedKeyEventText(event.text) {
            _ = text.withCString { ptr in
                keyEvent.text = ptr
                return ghostty_surface_key(surface, keyEvent)
            }
        } else {
            _ = ghostty_surface_key(surface, keyEvent)
        }

        scheduleTick()
    }

    @MainActor
    fileprivate func handleHostedSurfaceKeyEvent(
        _ event: NormalizedKeyEvent,
        runtimeSurfaceID: String
    ) {
        do {
            try handle(event, on: runtimeSurfaceID)
        } catch {
            NSSound.beep()
        }
    }

    @MainActor
    fileprivate func handleHostedSurfaceCommittedText(
        _ text: String,
        runtimeSurfaceID: String
    ) {
        do {
            try send(text: text, to: runtimeSurfaceID)
        } catch {
            NSSound.beep()
        }
    }

    @MainActor
    fileprivate func handleHostedSurfaceAccumulatedText(
        _ event: NormalizedKeyEvent,
        text: String,
        runtimeSurfaceID: String
    ) {
        var accumulatedEvent = event
        accumulatedEvent.text = text
        accumulatedEvent.route = .terminal
        do {
            try handle(accumulatedEvent, on: runtimeSurfaceID)
        } catch {
            NSSound.beep()
        }
    }

    @MainActor
    fileprivate func setHostedSurfacePreedit(
        _ text: String?,
        runtimeSurfaceID: String
    ) {
        guard let state = try? surfaceState(for: runtimeSurfaceID),
              let surface = state.surface
        else {
            return
        }

        if let text, text.isEmpty == false {
            text.withCString { ptr in
                ghostty_surface_preedit(surface, ptr, UInt(text.utf8.count))
            }
        } else {
            ghostty_surface_preedit(surface, nil, 0)
        }
        scheduleTick()
    }

    @MainActor
    fileprivate func hostedSurfaceIMERect(runtimeSurfaceID: String) -> NSRect {
        guard let state = try? surfaceState(for: runtimeSurfaceID),
              let surface = state.surface
        else {
            return .zero
        }

        var x: Double = 0
        var y: Double = 0
        var width: Double = 0
        var height: Double = 0
        ghostty_surface_ime_point(surface, &x, &y, &width, &height)

        let view = state.hostView
        let viewRect = NSRect(
            x: x,
            y: view.frame.size.height - y,
            width: width,
            height: max(height, 0)
        )
        let windowRect = view.convert(viewRect, to: nil)
        guard let window = view.window else {
            return windowRect
        }
        return window.convertToScreen(windowRect)
    }

    @MainActor
    fileprivate func translatedHostedSurfaceKeyEvent(
        for event: NSEvent,
        runtimeSurfaceID: String
    ) -> NSEvent {
        guard let state = try? surfaceState(for: runtimeSurfaceID),
              let surface = state.surface
        else {
            return event
        }

        let translatedGhosttyMods = appKitModifierFlags(
            from: ghostty_surface_key_translation_mods(
                surface,
                ghosttyModifiers(from: KeyModifiers(appKitEvent: event))
            )
        )

        var translationMods = event.modifierFlags
        for flag in [NSEvent.ModifierFlags.shift, .control, .option, .command] {
            if translatedGhosttyMods.contains(flag) {
                translationMods.insert(flag)
            } else {
                translationMods.remove(flag)
            }
        }

        guard translationMods != event.modifierFlags else {
            return event
        }

        return NSEvent.keyEvent(
            with: event.type,
            location: event.locationInWindow,
            modifierFlags: translationMods,
            timestamp: event.timestamp,
            windowNumber: event.windowNumber,
            context: nil,
            characters: event.characters(byApplyingModifiers: translationMods) ?? "",
            charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
            isARepeat: event.isARepeat,
            keyCode: event.keyCode
        ) ?? event
    }

    @MainActor
    fileprivate func performHostedSurfaceBindingAction(
        _ action: String,
        runtimeSurfaceID: String
    ) {
        guard let state = try? surfaceState(for: runtimeSurfaceID),
              let surface = state.surface
        else {
            NSSound.beep()
            return
        }

        let handled = action.withCString { ptr in
            ghostty_surface_binding_action(surface, ptr, UInt(action.utf8.count))
        }
        if handled == false {
            NSSound.beep()
            return
        }
        scheduleTick()
    }

    @MainActor
    fileprivate func performHostedSurfaceMouseButton(
        _ state: ghostty_input_mouse_state_e,
        buttonNumber: Int,
        modifiers: KeyModifiers,
        runtimeSurfaceID: String
    ) -> Bool {
        guard let stateRef = try? surfaceState(for: runtimeSurfaceID),
              let surface = stateRef.surface
        else {
            NSSound.beep()
            return false
        }

        let handled = ghostty_surface_mouse_button(
            surface,
            state,
            ghosttyMouseButton(for: buttonNumber),
            ghosttyModifiers(from: modifiers)
        )
        scheduleTick()
        return handled
    }

    @MainActor
    fileprivate func performHostedSurfaceMousePosition(
        _ point: CGPoint?,
        modifiers: KeyModifiers,
        runtimeSurfaceID: String
    ) {
        guard let stateRef = try? surfaceState(for: runtimeSurfaceID),
              let surface = stateRef.surface
        else {
            return
        }

        let runtimePoint = runtimeMousePoint(for: point, in: stateRef.hostView)
        ghostty_surface_mouse_pos(
            surface,
            runtimePoint.x,
            runtimePoint.y,
            ghosttyModifiers(from: modifiers)
        )
        scheduleTick()
    }

    @MainActor
    fileprivate func performHostedSurfaceMouseScroll(
        deltaX: Double,
        deltaY: Double,
        precise: Bool,
        momentum: NSEvent.Phase,
        runtimeSurfaceID: String
    ) {
        guard let stateRef = try? surfaceState(for: runtimeSurfaceID),
              let surface = stateRef.surface
        else {
            return
        }

        let mods = scrollMods(precise: precise, momentum: momentum)
        ghostty_surface_mouse_scroll(surface, deltaX, deltaY, mods)
        scheduleTick()
    }

    @MainActor
    fileprivate func performHostedSurfaceMousePressure(
        stage: Int,
        pressure: Double,
        runtimeSurfaceID: String
    ) {
        guard let stateRef = try? surfaceState(for: runtimeSurfaceID),
              let surface = stateRef.surface
        else {
            return
        }

        ghostty_surface_mouse_pressure(surface, UInt32(max(stage, 0)), pressure)
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
        lock.lock()
        if focused {
            focusedRuntimeSurfaceID = runtimeSurfaceID
        } else if focusedRuntimeSurfaceID == runtimeSurfaceID {
            focusedRuntimeSurfaceID = nil
        }
        lock.unlock()
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

        let newState = try AppState(owner: self, configFileURL: compiledConfigPath)
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

        if modifiers.contains(.leftShift) || modifiers.contains(.rightShift) {
            rawValue |= UInt32(GHOSTTY_MODS_SHIFT.rawValue)
        }
        if modifiers.contains(.rightShift) { rawValue |= UInt32(GHOSTTY_MODS_SHIFT_RIGHT.rawValue) }

        if modifiers.contains(.leftControl) || modifiers.contains(.rightControl) {
            rawValue |= UInt32(GHOSTTY_MODS_CTRL.rawValue)
        }
        if modifiers.contains(.rightControl) { rawValue |= UInt32(GHOSTTY_MODS_CTRL_RIGHT.rawValue) }

        if modifiers.contains(.leftOption) || modifiers.contains(.rightOption) {
            rawValue |= UInt32(GHOSTTY_MODS_ALT.rawValue)
        }
        if modifiers.contains(.rightOption) { rawValue |= UInt32(GHOSTTY_MODS_ALT_RIGHT.rawValue) }

        if modifiers.contains(.leftCommand) || modifiers.contains(.rightCommand) {
            rawValue |= UInt32(GHOSTTY_MODS_SUPER.rawValue)
        }
        if modifiers.contains(.rightCommand) { rawValue |= UInt32(GHOSTTY_MODS_SUPER_RIGHT.rawValue) }

        if modifiers.contains(.capsLock) { rawValue |= UInt32(GHOSTTY_MODS_CAPS.rawValue) }

        return ghostty_input_mods_e(rawValue)
    }

    private func ghosttyMouseButton(for buttonNumber: Int) -> ghostty_input_mouse_button_e {
        switch buttonNumber {
        case 0:
            return GHOSTTY_MOUSE_LEFT
        case 1:
            return GHOSTTY_MOUSE_RIGHT
        case 2:
            return GHOSTTY_MOUSE_MIDDLE
        case 3:
            return GHOSTTY_MOUSE_FOUR
        case 4:
            return GHOSTTY_MOUSE_FIVE
        case 5:
            return GHOSTTY_MOUSE_SIX
        case 6:
            return GHOSTTY_MOUSE_SEVEN
        case 7:
            return GHOSTTY_MOUSE_EIGHT
        case 8:
            return GHOSTTY_MOUSE_NINE
        case 9:
            return GHOSTTY_MOUSE_TEN
        case 10:
            return GHOSTTY_MOUSE_ELEVEN
        default:
            return GHOSTTY_MOUSE_UNKNOWN
        }
    }

    @MainActor
    private func runtimeMousePoint(for point: CGPoint?, in hostView: NSView) -> (x: Double, y: Double) {
        guard let point else {
            return (-1, -1)
        }
        return (
            Double(point.x),
            Double(max(hostView.bounds.height - point.y, 0))
        )
    }

    private func scrollMods(precise: Bool, momentum: NSEvent.Phase) -> ghostty_input_scroll_mods_t {
        var rawValue: Int32 = precise ? 0b0000_0001 : 0
        rawValue |= Int32(ghosttyMomentum(from: momentum).rawValue) << 1
        return rawValue
    }

    private func ghosttyMomentum(from phase: NSEvent.Phase) -> ghostty_input_mouse_momentum_e {
        switch phase {
        case .began:
            return GHOSTTY_MOUSE_MOMENTUM_BEGAN
        case .stationary:
            return GHOSTTY_MOUSE_MOMENTUM_STATIONARY
        case .changed:
            return GHOSTTY_MOUSE_MOMENTUM_CHANGED
        case .ended:
            return GHOSTTY_MOUSE_MOMENTUM_ENDED
        case .cancelled:
            return GHOSTTY_MOUSE_MOMENTUM_CANCELLED
        case .mayBegin:
            return GHOSTTY_MOUSE_MOMENTUM_MAY_BEGIN
        default:
            return GHOSTTY_MOUSE_MOMENTUM_NONE
        }
    }

    private func appKitModifierFlags(from mods: ghostty_input_mods_e) -> NSEvent.ModifierFlags {
        var flags = NSEvent.ModifierFlags(rawValue: 0)
        if mods.rawValue & GHOSTTY_MODS_SHIFT.rawValue != 0 { flags.insert(.shift) }
        if mods.rawValue & GHOSTTY_MODS_CTRL.rawValue != 0 { flags.insert(.control) }
        if mods.rawValue & GHOSTTY_MODS_ALT.rawValue != 0 { flags.insert(.option) }
        if mods.rawValue & GHOSTTY_MODS_SUPER.rawValue != 0 { flags.insert(.command) }
        if mods.rawValue & GHOSTTY_MODS_CAPS.rawValue != 0 { flags.insert(.capsLock) }
        return flags
    }

    private func ghosttyModifiers(from flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var rawValue = UInt32(GHOSTTY_MODS_NONE.rawValue)
        if flags.contains(.shift) { rawValue |= UInt32(GHOSTTY_MODS_SHIFT.rawValue) }
        if flags.contains(.control) { rawValue |= UInt32(GHOSTTY_MODS_CTRL.rawValue) }
        if flags.contains(.option) { rawValue |= UInt32(GHOSTTY_MODS_ALT.rawValue) }
        if flags.contains(.command) { rawValue |= UInt32(GHOSTTY_MODS_SUPER.rawValue) }
        if flags.contains(.capsLock) { rawValue |= UInt32(GHOSTTY_MODS_CAPS.rawValue) }
        return ghostty_input_mods_e(rawValue)
    }

    private func ghosttyConsumedModifiers(
        surface: ghostty_surface_t,
        originalModifiers: KeyModifiers
    ) -> ghostty_input_mods_e {
        var translatedModifiers = ghostty_surface_key_translation_mods(
            surface,
            ghosttyModifiers(from: originalModifiers)
        )
        translatedModifiers = ghostty_input_mods_e(
            translatedModifiers.rawValue
                & ~GHOSTTY_MODS_CTRL.rawValue
                & ~GHOSTTY_MODS_CTRL_RIGHT.rawValue
                & ~GHOSTTY_MODS_SUPER.rawValue
                & ~GHOSTTY_MODS_SUPER_RIGHT.rawValue
        )
        return translatedModifiers
    }

    private func currentApp() -> ghostty_app_t? {
        lock.lock()
        defer { lock.unlock() }
        return appState?.app
    }

    private func sanitizedKeyEventText(_ text: String?) -> String? {
        guard let text, text.isEmpty == false else {
            return nil
        }

        if text.count == 1, let scalar = text.unicodeScalars.first {
            if scalar.value < 0x20 {
                return nil
            }
            if scalar.value >= 0xF700 && scalar.value <= 0xF8FF {
                return nil
            }
        }

        return text
    }

    private func readClipboard(
        for location: ghostty_clipboard_e,
        state: UnsafeMutableRawPointer?
    ) -> Bool {
        guard location == GHOSTTY_CLIPBOARD_STANDARD,
              let surface = firstSurface(for: location)
        else {
            return false
        }
        guard let string = HostedRuntimeClipboard.readString(for: location) else {
            return false
        }
        string.withCString { ptr in
            ghostty_surface_complete_clipboard_request(surface, ptr, state, false)
        }
        return true
    }

    private func writeClipboard(
        for location: ghostty_clipboard_e,
        content: UnsafePointer<ghostty_clipboard_content_s>?,
        len: Int,
        confirm: Bool
    ) {
        _ = confirm
        guard location == GHOSTTY_CLIPBOARD_STANDARD,
              let content,
              len > 0
        else {
            return
        }

        let items = UnsafeBufferPointer(start: content, count: len)
        HostedRuntimeClipboard.write(items, for: location)
    }

    private func firstSurface(for location: ghostty_clipboard_e) -> ghostty_surface_t? {
        guard location == GHOSTTY_CLIPBOARD_STANDARD else {
            return nil
        }
        lock.lock()
        defer { lock.unlock() }
        if let focusedRuntimeSurfaceID {
            return surfaces[focusedRuntimeSurfaceID]?.surface
        }
        return surfaces.values.compactMap(\.surface).first
    }

    private func replaceCompiledConfig(path: URL, updateRunningApp: Bool) throws -> [OmuxConfigDiagnostic] {
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw CGhosttyRuntimeError.compiledConfigNotFound(path.path)
        }

        let loadResult = loadConfig(path: path)
        compiledConfigPath = path

        guard updateRunningApp else {
            if let config = loadResult.config {
                ghostty_config_free(config)
            }
            return loadResult.diagnostics
        }

        lock.lock()
        let appState = self.appState
        lock.unlock()

        guard let appState, let newConfig = loadResult.config, let app = appState.app else {
            if let config = loadResult.config {
                ghostty_config_free(config)
            }
            return loadResult.diagnostics
        }

        runOnMain {
            ghostty_app_update_config(app, newConfig)
        }

        let previousConfig = appState.config
        appState.config = newConfig
        if let previousConfig {
            ghostty_config_free(previousConfig)
        }

        return loadResult.diagnostics
    }

    private func loadConfig(path: URL) -> (config: ghostty_config_t?, diagnostics: [OmuxConfigDiagnostic]) {
        let config = ghostty_config_new()
        path.path.withCString { value in
            ghostty_config_load_file(config, value)
        }
        ghostty_config_finalize(config)
        return (config, diagnostics(for: config, filePath: path.path))
    }

    private func diagnostics(for config: ghostty_config_t?, filePath: String?) -> [OmuxConfigDiagnostic] {
        guard let config else {
            return []
        }

        let count = ghostty_config_diagnostics_count(config)
        guard count > 0 else {
            return []
        }

        return (0..<Int(count)).compactMap { index in
            let diagnostic = ghostty_config_get_diagnostic(config, UInt32(index))
            guard let message = diagnostic.message else {
                return nil
            }

            return OmuxConfigDiagnostic(
                severity: .warning,
                message: String(cString: message),
                filePath: filePath
            )
        }
    }
}

enum HostedRuntimeClipboard {
    static func readString(
        for location: ghostty_clipboard_e,
        pasteboardProvider: (ghostty_clipboard_e) -> NSPasteboard? = defaultPasteboard(for:)
    ) -> String? {
        guard location == GHOSTTY_CLIPBOARD_STANDARD else {
            return nil
        }
        guard let pasteboard = pasteboardProvider(location) else {
            return nil
        }
        return pasteboard.string(forType: .string)
    }

    static func write(
        _ content: UnsafeBufferPointer<ghostty_clipboard_content_s>,
        for location: ghostty_clipboard_e,
        pasteboardProvider: (ghostty_clipboard_e) -> NSPasteboard? = defaultPasteboard(for:)
    ) {
        guard location == GHOSTTY_CLIPBOARD_STANDARD else {
            return
        }
        guard let pasteboard = pasteboardProvider(location),
              let text = textPlainContent(from: content)
        else {
            return
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    static func textPlainContent(from content: UnsafeBufferPointer<ghostty_clipboard_content_s>) -> String? {
        content.first { item in
            guard let mime = item.mime else { return false }
            return String(cString: mime) == "text/plain"
        }.flatMap { item -> String? in
            guard let data = item.data else { return nil }
            return String(cString: data)
        }
    }

    private static func defaultPasteboard(for location: ghostty_clipboard_e) -> NSPasteboard? {
        guard location == GHOSTTY_CLIPBOARD_STANDARD else {
            return nil
        }
        return .general
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
