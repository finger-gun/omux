import AppKit
import Foundation
import OmuxConfig
import OmuxCore
import CGhostty

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
    func selection(for runtimeSurfaceID: String) -> RuntimeTerminalSelection?
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
        defaultSize: TerminalSize
    ) -> TerminalSessionSnapshot?
    func scrollbackSnapshot(runtimeSurfaceID: String, maxBytes: Int, maxLines: Int) -> PaneScrollbackSnapshot?
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

    func selection(for runtimeSurfaceID: String) -> RuntimeTerminalSelection? {
        _ = runtimeSurfaceID
        return nil
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
        defaultSize: TerminalSize
    ) -> TerminalSessionSnapshot? {
        _ = paneID
        _ = sessionID
        _ = descriptor
        _ = runtimeSurfaceID
        _ = defaultSize
        return nil
    }

    func scrollbackSnapshot(runtimeSurfaceID: String, maxBytes: Int, maxLines: Int) -> PaneScrollbackSnapshot? {
        _ = runtimeSurfaceID
        _ = maxBytes
        _ = maxLines
        return nil
    }
}

public enum TerminalBridgeError: Error {
    case missingSurface(PaneID)
    case missingSession(PaneID)
    case runtimeAttachFailed(String)
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

public struct RuntimeTerminalSelection: Equatable, Sendable {
    public let text: String
    public let offset: Int
    public let length: Int

    public init(text: String, offset: Int, length: Int) {
        self.text = text
        self.offset = max(offset, 0)
        self.length = max(length, 0)
    }

    public var range: NSRange {
        NSRange(location: offset, length: length)
    }
}

public final class GhosttyTerminalBridge: @unchecked Sendable {
    private final class SessionState {
        var descriptor: SessionDescriptor
        let runtimeSurfaceID: String
        var size: TerminalSize

        init(
            descriptor: SessionDescriptor,
            runtimeSurfaceID: String,
            size: TerminalSize = .default
        ) {
            self.descriptor = descriptor
            self.runtimeSurfaceID = runtimeSurfaceID
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
        try attachRuntimeSession(session, to: surface.runtimeSurfaceID)

        lock.lock()
        sessionsByPane[pane.id] = session.id
        sessionStateByPane[pane.id] = SessionState(
            descriptor: session,
            runtimeSurfaceID: surface.runtimeSurfaceID
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

        _ = sessionState
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

    public func scrollbackSnapshot(
        for paneID: PaneID,
        maxBytes: Int = PaneScrollbackSnapshot.defaultMaxBytes,
        maxLines: Int = PaneScrollbackSnapshot.defaultMaxLines
    ) -> PaneScrollbackSnapshot? {
        lock.lock()
        let runtimeSurfaceID = sessionStateByPane[paneID]?.runtimeSurfaceID
        lock.unlock()
        guard let runtimeSurfaceID else {
            return nil
        }
        return runtime.scrollbackSnapshot(
            runtimeSurfaceID: runtimeSurfaceID,
            maxBytes: maxBytes,
            maxLines: maxLines
        )
    }

    public func selection(forPane paneID: PaneID) -> RuntimeTerminalSelection? {
        lock.lock()
        let runtimeSurfaceID = sessionStateByPane[paneID]?.runtimeSurfaceID
        lock.unlock()
        guard let runtimeSurfaceID else {
            return nil
        }
        return runtime.selection(for: runtimeSurfaceID)
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
        lock.lock()
        let state = sessionStateByPane[paneID]
        lock.unlock()

        guard let state else {
            throw TerminalBridgeError.missingSession(paneID)
        }

        guard event.route != .shortcut else {
            return
        }

        try runtime.handle(event, on: state.runtimeSurfaceID)
        publishSnapshot(for: paneID)
    }

    public func run(command: String, inPane paneID: PaneID) throws {
        lock.lock()
        let state = sessionStateByPane[paneID]
        lock.unlock()

        guard let state else {
            throw TerminalBridgeError.missingSession(paneID)
        }

        try runtime.send(text: command, to: state.runtimeSurfaceID)
        try runtime.handle(Self.returnKeyEvent(), on: state.runtimeSurfaceID)
        publishSnapshot(for: paneID)
    }

    public func send(text: String, toPane paneID: PaneID) throws {
        lock.lock()
        let state = sessionStateByPane[paneID]
        lock.unlock()

        guard let state else {
            throw TerminalBridgeError.missingSession(paneID)
        }

        try runtime.send(text: text, to: state.runtimeSurfaceID)
        publishSnapshot(for: paneID)
    }

    public func resize(paneID: PaneID, columns: Int, rows: Int) throws {
        lock.lock()
        guard let state = sessionStateByPane[paneID] else {
            lock.unlock()
            throw TerminalBridgeError.missingSession(paneID)
        }
        state.size = TerminalSize(columns: columns, rows: rows)
        lock.unlock()

        try runtime.resizeSurface(
            runtimeSurfaceID: state.runtimeSurfaceID,
            columns: state.size.columns,
            rows: state.size.rows
        )
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

    private func attachRuntimeSession(
        _ session: SessionDescriptor,
        to runtimeSurfaceID: String,
        maximumAttempts: Int = 3
    ) throws {
        let attempts = max(1, maximumAttempts)
        for attempt in 1...attempts {
            do {
                try runtime.attach(session: session, to: runtimeSurfaceID)
                if runtime.ownsSession(for: runtimeSurfaceID) {
                    return
                }
            } catch {
                fputs(
                    "warning: failed to attach Ghostty runtime surface \(runtimeSurfaceID) (attempt \(attempt)/\(attempts)): \(error)\n",
                    stderr
                )
            }

            if attempt < attempts {
                Thread.sleep(forTimeInterval: 0.1)
            }
        }

        throw TerminalBridgeError.runtimeAttachFailed(runtimeSurfaceID)
    }

    private func handleRuntimeTerminalAction(_ record: RuntimeTerminalActionRecord) -> Bool {
        let event: TerminalActionEvent?
        let actionObservers: [@Sendable (TerminalActionEvent) -> Void]
        lock.lock()
        if let surface = surfaces.values.first(where: { $0.runtimeSurfaceID == record.runtimeSurfaceID }),
           let sessionID = sessionsByPane[surface.paneID]
        {
            if case .workingDirectoryChanged(let path) = record.action,
               var descriptor = sessionStateByPane[surface.paneID]?.descriptor {
                descriptor.workingDirectory = path
                sessionStateByPane[surface.paneID]?.descriptor = descriptor
            }
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

        return runtime.snapshot(
            paneID: paneID,
            sessionID: sessionID,
            descriptor: state.descriptor,
            runtimeSurfaceID: state.runtimeSurfaceID,
            defaultSize: state.size
        )
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

        preconditionFailure("Missing Ghostty runtime view for pane \(pane.id.rawValue)")
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
    CGhosttyRuntime(compiledConfigPath: compiledConfigPath)
}
