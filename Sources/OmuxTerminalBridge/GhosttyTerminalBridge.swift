import AppKit
import Foundation
import OmuxConfig
import OmuxCore

#if canImport(CGhostty)
import CGhostty
#endif

public struct TerminalSurfaceDescriptor: Equatable, Sendable {
    public let paneID: PaneID
    public let runtimeSurfaceID: String

    public init(paneID: PaneID, runtimeSurfaceID: String) {
        self.paneID = paneID
        self.runtimeSurfaceID = runtimeSurfaceID
    }
}

public struct TerminalSessionAttachment: Equatable, Sendable {
    public let sessionID: SessionID
    public let paneID: PaneID
    public let runtimeSurfaceID: String

    public init(sessionID: SessionID, paneID: PaneID, runtimeSurfaceID: String) {
        self.sessionID = sessionID
        self.paneID = paneID
        self.runtimeSurfaceID = runtimeSurfaceID
    }
}

public protocol GhosttyRuntime {
    func applyCompiledConfig(path: URL) throws -> [OmuxConfigDiagnostic]
    func refreshCompiledConfig(path: URL) throws -> [OmuxConfigDiagnostic]
    func createSurface(for paneID: PaneID) throws -> String
    func attach(session: SessionDescriptor, to runtimeSurfaceID: String) throws
    func destroySurface(runtimeSurfaceID: String) throws
    @MainActor func makeHostedSurfaceView(
        for paneID: PaneID,
        runtimeSurfaceID: String
    ) -> NSView?
    func ownsSession(for runtimeSurfaceID: String) -> Bool
    func send(text: String, to runtimeSurfaceID: String) throws
    func handle(_ event: NormalizedKeyEvent, on runtimeSurfaceID: String) throws
    func resizeSurface(runtimeSurfaceID: String, columns: Int, rows: Int) throws
    func setSurfaceFocused(runtimeSurfaceID: String, focused: Bool)
    func setTerminalActionHandler(
        _ handler: (@Sendable (RuntimeTerminalActionRecord) -> Bool)?
    )
    func snapshot(
        paneID: PaneID,
        sessionID: SessionID,
        descriptor: SessionDescriptor,
        runtimeSurfaceID: String,
        fallbackSize: TerminalSize
    ) -> TerminalSessionSnapshot?
}

public extension GhosttyRuntime {
    func applyCompiledConfig(path: URL) throws -> [OmuxConfigDiagnostic] {
        _ = path
        return []
    }

    func refreshCompiledConfig(path: URL) throws -> [OmuxConfigDiagnostic] {
        _ = path
        return []
    }

    func ownsSession(for runtimeSurfaceID: String) -> Bool {
        _ = runtimeSurfaceID
        return false
    }

    func send(text: String, to runtimeSurfaceID: String) throws {
        _ = text
        _ = runtimeSurfaceID
    }

    func handle(_ event: NormalizedKeyEvent, on runtimeSurfaceID: String) throws {
        _ = event
        _ = runtimeSurfaceID
    }

    func resizeSurface(runtimeSurfaceID: String, columns: Int, rows: Int) throws {
        _ = runtimeSurfaceID
        _ = columns
        _ = rows
    }

    func setSurfaceFocused(runtimeSurfaceID: String, focused: Bool) {
        _ = runtimeSurfaceID
        _ = focused
    }

    func setTerminalActionHandler(
        _ handler: (@Sendable (RuntimeTerminalActionRecord) -> Bool)?
    ) {
        _ = handler
    }

    func snapshot(
        paneID: PaneID,
        sessionID: SessionID,
        descriptor: SessionDescriptor,
        runtimeSurfaceID: String,
        fallbackSize: TerminalSize
    ) -> TerminalSessionSnapshot? {
        _ = paneID
        _ = sessionID
        _ = descriptor
        _ = runtimeSurfaceID
        _ = fallbackSize
        return nil
    }
}

public final class UnavailableGhosttyRuntime: GhosttyRuntime {
    public init() {}

    public func createSurface(for paneID: PaneID) throws -> String {
        "surface:\(paneID.rawValue)"
    }

    public func attach(session: SessionDescriptor, to runtimeSurfaceID: String) throws {
        _ = session
        _ = runtimeSurfaceID
    }

    public func destroySurface(runtimeSurfaceID: String) throws {
        _ = runtimeSurfaceID
    }

    @MainActor
    public func makeHostedSurfaceView(
        for paneID: PaneID,
        runtimeSurfaceID: String
    ) -> NSView? {
        _ = paneID
        _ = runtimeSurfaceID
        return nil
    }
}

public enum TerminalBridgeError: Error {
    case missingSurface(PaneID)
    case missingSession(PaneID)
}

public struct TerminalSessionSnapshot: Equatable, Sendable {
    public let paneID: PaneID
    public let sessionID: SessionID
    public let runtimeSurfaceID: String
    public let transcript: String
    public let currentInput: String
    public let shell: String
    public let workingDirectory: String
    public let columns: Int
    public let rows: Int

    public init(
        paneID: PaneID,
        sessionID: SessionID,
        runtimeSurfaceID: String,
        transcript: String,
        currentInput: String,
        shell: String,
        workingDirectory: String,
        columns: Int = 80,
        rows: Int = 24
    ) {
        self.paneID = paneID
        self.sessionID = sessionID
        self.runtimeSurfaceID = runtimeSurfaceID
        self.transcript = transcript
        self.currentInput = currentInput
        self.shell = shell
        self.workingDirectory = workingDirectory
        self.columns = columns
        self.rows = rows
    }

    public var renderedText: String {
        transcript + currentInput
    }
}

public final class GhosttyTerminalBridge: @unchecked Sendable {
    private final class SessionState {
        let descriptor: SessionDescriptor
        let runtimeSurfaceID: String
        let runtimeSession: InteractiveTerminalRuntimeSession?
        let screenBuffer: TerminalScreenBuffer?
        let runtimeOwned: Bool
        var size: TerminalSize

        init(
            descriptor: SessionDescriptor,
            runtimeSurfaceID: String,
            runtimeSession: InteractiveTerminalRuntimeSession?,
            screenBuffer: TerminalScreenBuffer?,
            runtimeOwned: Bool,
            size: TerminalSize = .default
        ) {
            self.descriptor = descriptor
            self.runtimeSurfaceID = runtimeSurfaceID
            self.runtimeSession = runtimeSession
            self.screenBuffer = screenBuffer
            self.runtimeOwned = runtimeOwned
            self.size = size
        }
    }

    private let dependency: GhosttyPinnedDependency
    private let runtime: any GhosttyRuntime
    private let lock = NSLock()
    private var surfaces: [PaneID: TerminalSurfaceDescriptor] = [:]
    private var sessionsByPane: [PaneID: SessionID] = [:]
    private var sessionStateByPane: [PaneID: SessionState] = [:]
    private var observers: [PaneID: [UUID: @Sendable (TerminalSessionSnapshot) -> Void]] = [:]
    private var terminalActionObservers: [UUID: @Sendable (TerminalActionEvent) -> Void] = [:]

    public init(
        dependency: GhosttyPinnedDependency = .foundationDefault(),
        runtime: (any GhosttyRuntime)? = nil,
        compiledConfigPath: URL? = nil
    ) {
        self.dependency = dependency
        self.runtime = runtime ?? defaultGhosttyRuntime(compiledConfigPath: compiledConfigPath)
        self.runtime.setTerminalActionHandler { [weak self] record in
            self?.handleRuntimeTerminalAction(record) ?? false
        }
    }

    public var pinnedDependency: GhosttyPinnedDependency {
        dependency
    }

    @discardableResult
    public func applyCompiledConfig(path: URL) throws -> [OmuxConfigDiagnostic] {
        try runtime.applyCompiledConfig(path: path)
    }

    @discardableResult
    public func refreshCompiledConfig(path: URL) throws -> [OmuxConfigDiagnostic] {
        try runtime.refreshCompiledConfig(path: path)
    }

    @MainActor
    public func makeHostedPaneView(
        for pane: Pane,
        isFocused: Bool,
        themePalette: TerminalThemePalette = .defaultDark,
        onFocus: @escaping @MainActor (PaneID) -> Void
    ) -> HostedTerminalPaneView {
        HostedTerminalPaneView(
            pane: pane,
            bridge: self,
            isFocused: isFocused,
            themePalette: themePalette,
            onFocus: onFocus
        )
    }

    @discardableResult
    public func createSurface(for pane: Pane) throws -> TerminalSurfaceDescriptor {
        lock.lock()
        if let existing = surfaces[pane.id] {
            lock.unlock()
            return existing
        }
        lock.unlock()

        let runtimeSurfaceID = try runtime.createSurface(for: pane.id)
        let descriptor = TerminalSurfaceDescriptor(
            paneID: pane.id,
            runtimeSurfaceID: runtimeSurfaceID
        )

        lock.lock()
        if let existing = surfaces[pane.id] {
            lock.unlock()
            try? runtime.destroySurface(runtimeSurfaceID: runtimeSurfaceID)
            return existing
        }
        surfaces[pane.id] = descriptor
        lock.unlock()
        return descriptor
    }

    public func attach(session: SessionDescriptor, to pane: Pane) throws -> TerminalSessionAttachment {
        let surface = try createSurface(for: pane)
        let runtimeOwned: Bool
        do {
            try runtime.attach(session: session, to: surface.runtimeSurfaceID)
            runtimeOwned = runtime.ownsSession(for: surface.runtimeSurfaceID)
        } catch {
            fputs("warning: failed to attach Ghostty runtime surface \(surface.runtimeSurfaceID): \(error)\n", stderr)
            runtimeOwned = false
        }

        let runtimeSession: InteractiveTerminalRuntimeSession?
        let screenBuffer: TerminalScreenBuffer?
        if runtimeOwned {
            runtimeSession = nil
            screenBuffer = nil
        } else {
            runtimeSession = try InteractiveTerminalRuntimeSession(
                descriptor: session,
                initialSize: .default,
                onOutput: { [weak self] data in
                    self?.acceptRuntimeOutput(data, for: pane.id)
                }
            )
            screenBuffer = TerminalScreenBuffer()
        }

        lock.lock()
        sessionsByPane[pane.id] = session.id
        sessionStateByPane[pane.id] = SessionState(
            descriptor: session,
            runtimeSurfaceID: surface.runtimeSurfaceID,
            runtimeSession: runtimeSession,
            screenBuffer: screenBuffer,
            runtimeOwned: runtimeOwned
        )
        lock.unlock()

        publishSnapshot(for: pane.id)

        return TerminalSessionAttachment(
            sessionID: session.id,
            paneID: pane.id,
            runtimeSurfaceID: surface.runtimeSurfaceID
        )
    }

    public func teardown(paneID: PaneID) throws {
        lock.lock()
        let surface = surfaces.removeValue(forKey: paneID)
        sessionsByPane.removeValue(forKey: paneID)
        let sessionState = sessionStateByPane.removeValue(forKey: paneID)
        observers.removeValue(forKey: paneID)
        lock.unlock()

        guard let surface else {
            throw TerminalBridgeError.missingSurface(paneID)
        }

        sessionState?.runtimeSession?.stop()
        try runtime.destroySurface(runtimeSurfaceID: surface.runtimeSurfaceID)
    }

    public func surface(for paneID: PaneID) -> TerminalSurfaceDescriptor? {
        lock.lock()
        defer { lock.unlock() }
        return surfaces[paneID]
    }

    public func attachedSession(for paneID: PaneID) -> SessionID? {
        lock.lock()
        defer { lock.unlock() }
        return sessionsByPane[paneID]
    }

    public func snapshot(for paneID: PaneID) -> TerminalSessionSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return makeSnapshot(for: paneID)
    }

    @discardableResult
    public func addObserver(
        for paneID: PaneID,
        observer: @escaping @Sendable (TerminalSessionSnapshot) -> Void
    ) -> UUID {
        let token = UUID()
        let snapshot: TerminalSessionSnapshot?
        lock.lock()
        var paneObservers = observers[paneID, default: [:]]
        paneObservers[token] = observer
        observers[paneID] = paneObservers
        snapshot = makeSnapshot(for: paneID)
        lock.unlock()

        if let snapshot {
            observer(snapshot)
        }

        return token
    }

    public func removeObserver(for paneID: PaneID, token: UUID) {
        lock.lock()
        observers[paneID]?.removeValue(forKey: token)
        lock.unlock()
    }

    @discardableResult
    public func addTerminalActionObserver(
        observer: @escaping @Sendable (TerminalActionEvent) -> Void
    ) -> UUID {
        let token = UUID()
        lock.lock()
        terminalActionObservers[token] = observer
        lock.unlock()
        return token
    }

    public func removeTerminalActionObserver(token: UUID) {
        lock.lock()
        terminalActionObservers.removeValue(forKey: token)
        lock.unlock()
    }

    public func handle(_ event: NormalizedKeyEvent, inPane paneID: PaneID) throws {
        guard event.route != .shortcut else {
            return
        }

        lock.lock()
        let state = sessionStateByPane[paneID]
        lock.unlock()

        if let state, state.runtimeOwned {
            try runtime.handle(event, on: state.runtimeSurfaceID)
            publishSnapshot(for: paneID)
            return
        }

        guard event.phase == .keyDown else {
            return
        }

        let data = data(for: event)
        guard data.isEmpty == false else {
            return
        }

        try write(data, toPane: paneID)
    }

    public func run(command: String, inPane paneID: PaneID) throws {
        lock.lock()
        let state = sessionStateByPane[paneID]
        lock.unlock()

        guard let state else {
            throw TerminalBridgeError.missingSession(paneID)
        }

        if state.runtimeOwned {
            try runtime.send(text: command, to: state.runtimeSurfaceID)
            try runtime.handle(Self.returnKeyEvent(), on: state.runtimeSurfaceID)
            publishSnapshot(for: paneID)
            return
        }

        var commandData = Data(command.utf8)
        commandData.append(0x0D)
        try write(commandData, toPane: paneID)
    }

    public func send(text: String, toPane paneID: PaneID) throws {
        lock.lock()
        let state = sessionStateByPane[paneID]
        lock.unlock()

        if let state, state.runtimeOwned {
            try runtime.send(text: text, to: state.runtimeSurfaceID)
            publishSnapshot(for: paneID)
            return
        }

        try write(Data(text.utf8), toPane: paneID)
    }

    public func resize(paneID: PaneID, columns: Int, rows: Int) throws {
        lock.lock()
        guard let state = sessionStateByPane[paneID] else {
            lock.unlock()
            throw TerminalBridgeError.missingSession(paneID)
        }
        state.size = TerminalSize(columns: columns, rows: rows)
        lock.unlock()

        if state.runtimeOwned {
            try runtime.resizeSurface(
                runtimeSurfaceID: state.runtimeSurfaceID,
                columns: state.size.columns,
                rows: state.size.rows
            )
        } else {
            try state.runtimeSession?.resize(to: state.size)
        }
        publishSnapshot(for: paneID)
    }

    private func write(_ data: Data, toPane paneID: PaneID) throws {
        lock.lock()
        guard let state = sessionStateByPane[paneID] else {
            lock.unlock()
            throw TerminalBridgeError.missingSession(paneID)
        }
        lock.unlock()

        guard let runtimeSession = state.runtimeSession else {
            if let text = String(data: data, encoding: .utf8) {
                try runtime.send(text: text, to: state.runtimeSurfaceID)
                publishSnapshot(for: paneID)
                return
            }

            throw TerminalBridgeError.missingSession(paneID)
        }

        try runtimeSession.write(data)
    }

    private func acceptRuntimeOutput(_ data: Data, for paneID: PaneID) {
        lock.lock()
        sessionStateByPane[paneID]?.screenBuffer?.apply(data)
        lock.unlock()
        publishSnapshot(for: paneID)
    }

    private func publishSnapshot(for paneID: PaneID) {
        let snapshot: TerminalSessionSnapshot?
        let paneObservers: [@Sendable (TerminalSessionSnapshot) -> Void]
        lock.lock()
        snapshot = makeSnapshot(for: paneID)
        paneObservers = observers[paneID]?.map(\.value) ?? []
        lock.unlock()

        guard let snapshot else {
            return
        }

        for observer in paneObservers {
            observer(snapshot)
        }
    }

    private func handleRuntimeTerminalAction(_ record: RuntimeTerminalActionRecord) -> Bool {
        let event: TerminalActionEvent?
        let actionObservers: [@Sendable (TerminalActionEvent) -> Void]
        lock.lock()
        if let surface = surfaces.values.first(where: { $0.runtimeSurfaceID == record.runtimeSurfaceID }),
           let sessionID = sessionsByPane[surface.paneID]
        {
            event = TerminalActionEvent(
                paneID: surface.paneID,
                sessionID: sessionID,
                runtimeSurfaceID: record.runtimeSurfaceID,
                action: record.action
            )
            actionObservers = terminalActionObservers.map(\.value)
        } else {
            event = nil
            actionObservers = []
        }
        lock.unlock()

        guard let event else {
            return false
        }

        for observer in actionObservers {
            observer(event)
        }
        return true
    }

    private func makeSnapshot(for paneID: PaneID) -> TerminalSessionSnapshot? {
        guard let state = sessionStateByPane[paneID],
              let sessionID = sessionsByPane[paneID]
        else {
            return nil
        }

        if state.runtimeOwned {
            return runtime.snapshot(
                paneID: paneID,
                sessionID: sessionID,
                descriptor: state.descriptor,
                runtimeSurfaceID: state.runtimeSurfaceID,
                fallbackSize: state.size
            )
        }

        return TerminalSessionSnapshot(
            paneID: paneID,
            sessionID: sessionID,
            runtimeSurfaceID: state.runtimeSurfaceID,
            transcript: state.screenBuffer?.renderedText ?? "",
            currentInput: "",
            shell: state.descriptor.shell,
            workingDirectory: state.descriptor.workingDirectory,
            columns: state.size.columns,
            rows: state.size.rows
        )
    }

    private func data(for event: NormalizedKeyEvent) -> Data {
        if let controlData = controlData(for: event) {
            return controlData
        }

        guard let text = event.text else {
            return Data()
        }

        return Data(text.utf8)
    }

    private func controlData(for event: NormalizedKeyEvent) -> Data? {
        let keyCode = event.keyCode

        if event.modifiers.intersection([.leftControl, .rightControl]).isEmpty == false,
           let controlScalar = controlScalar(for: event.key) {
            return Data([controlScalar])
        }

        switch keyCode {
        case 36?:
            return Data([0x0D])
        case 48?:
            return Data([0x09])
        case 51?:
            return Data([0x7F])
        case 117?:
            return Data("\u{1B}[3~".utf8)
        case 123?:
            return Data("\u{1B}[D".utf8)
        case 124?:
            return Data("\u{1B}[C".utf8)
        case 125?:
            return Data("\u{1B}[B".utf8)
        case 126?:
            return Data("\u{1B}[A".utf8)
        case 115?:
            return Data("\u{1B}[H".utf8)
        case 119?:
            return Data("\u{1B}[F".utf8)
        default:
            break
        }

        switch event.key {
        case "\r", "\n":
            return Data([0x0D])
        case "\t":
            return Data([0x09])
        case "\u{7F}":
            return Data([0x7F])
        default:
            return nil
        }
    }

    private func controlScalar(for key: String) -> UInt8? {
        guard let scalar = key.uppercased().unicodeScalars.first else {
            return nil
        }

        switch scalar.value {
        case 64...95:
            return UInt8(scalar.value - 64)
        case 63:
            return 0x7F
        default:
            return nil
        }
    }

    private static func returnKeyEvent() -> NormalizedKeyEvent {
        NormalizedKeyEvent(
            keyCode: 36,
            key: "\r",
            text: "\r",
            modifiers: [],
            phase: .keyDown,
            isRepeat: false,
            route: .terminal
        )
    }

    @MainActor
    func makeHostedSurfaceContentHost(
        for pane: Pane,
        isFocused: Bool,
        themePalette: TerminalThemePalette = .defaultDark,
        onFocus: @escaping @MainActor (PaneID) -> Void
    ) -> any TerminalSurfaceContentHosting {
        if let surface = surface(for: pane.id),
            let runtimeView = runtime.makeHostedSurfaceView(for: pane.id, runtimeSurfaceID: surface.runtimeSurfaceID) {
            return RuntimeTerminalSurfaceContentHost(
                pane: pane,
                runtimeView: runtimeView,
                bridge: self,
                isFocused: isFocused,
                themePalette: themePalette,
                onFocus: onFocus
            )
        }

        return FallbackTerminalSurfaceContentHost(
            pane: pane,
            bridge: self,
            isFocused: isFocused,
            themePalette: themePalette,
            onFocus: onFocus
        )
    }

    func setHostedSurfaceFocused(paneID: PaneID, isFocused: Bool) {
        lock.lock()
        let runtimeSurfaceID = sessionStateByPane[paneID]?.runtimeSurfaceID
        lock.unlock()
        guard let runtimeSurfaceID else {
            return
        }

        runtime.setSurfaceFocused(runtimeSurfaceID: runtimeSurfaceID, focused: isFocused)
    }
}

private func defaultGhosttyRuntime(compiledConfigPath: URL?) -> any GhosttyRuntime {
    if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        || NSClassFromString("XCTestCase") != nil
    {
        return UnavailableGhosttyRuntime()
    }

#if canImport(CGhostty)
    return CGhosttyRuntime(compiledConfigPath: compiledConfigPath)
#else
    return UnavailableGhosttyRuntime()
#endif
}
