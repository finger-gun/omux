import Foundation
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
    func createSurface(for paneID: PaneID) throws -> String
    func attach(session: SessionDescriptor, to runtimeSurfaceID: String) throws
    func destroySurface(runtimeSurfaceID: String) throws
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
}

#if canImport(CGhostty)
public final class CGhosttyRuntime: GhosttyRuntime {
    public init() {}

    public func createSurface(for paneID: PaneID) throws -> String {
        "cghostty:\(paneID.rawValue)"
    }

    public func attach(session: SessionDescriptor, to runtimeSurfaceID: String) throws {
        _ = session
        _ = runtimeSurfaceID
    }

    public func destroySurface(runtimeSurfaceID: String) throws {
        _ = runtimeSurfaceID
    }
}
#endif

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

    public init(
        paneID: PaneID,
        sessionID: SessionID,
        runtimeSurfaceID: String,
        transcript: String,
        currentInput: String,
        shell: String,
        workingDirectory: String
    ) {
        self.paneID = paneID
        self.sessionID = sessionID
        self.runtimeSurfaceID = runtimeSurfaceID
        self.transcript = transcript
        self.currentInput = currentInput
        self.shell = shell
        self.workingDirectory = workingDirectory
    }

    public var renderedText: String {
        transcript + currentInput
    }
}

public final class GhosttyTerminalBridge: @unchecked Sendable {
    private final class SessionState {
        let descriptor: SessionDescriptor
        let runtimeSurfaceID: String
        var transcript: String
        var currentInput: String

        init(
            descriptor: SessionDescriptor,
            runtimeSurfaceID: String,
            transcript: String = "",
            currentInput: String = ""
        ) {
            self.descriptor = descriptor
            self.runtimeSurfaceID = runtimeSurfaceID
            self.transcript = transcript
            self.currentInput = currentInput
        }
    }

    private let dependency: GhosttyPinnedDependency
    private let runtime: any GhosttyRuntime
    private let lock = NSLock()
    private var surfaces: [PaneID: TerminalSurfaceDescriptor] = [:]
    private var sessionsByPane: [PaneID: SessionID] = [:]
    private var sessionStateByPane: [PaneID: SessionState] = [:]
    private var observers: [PaneID: [UUID: @Sendable (TerminalSessionSnapshot) -> Void]] = [:]

    public init(
        dependency: GhosttyPinnedDependency = .foundationDefault(),
        runtime: any GhosttyRuntime = UnavailableGhosttyRuntime()
    ) {
        self.dependency = dependency
        self.runtime = runtime
    }

    public var pinnedDependency: GhosttyPinnedDependency {
        dependency
    }

    @discardableResult
    public func createSurface(for pane: Pane) throws -> TerminalSurfaceDescriptor {
        lock.lock()
        defer { lock.unlock() }

        if let existing = surfaces[pane.id] {
            return existing
        }

        let runtimeSurfaceID = try runtime.createSurface(for: pane.id)
        let descriptor = TerminalSurfaceDescriptor(
            paneID: pane.id,
            runtimeSurfaceID: runtimeSurfaceID
        )
        surfaces[pane.id] = descriptor
        return descriptor
    }

    public func attach(session: SessionDescriptor, to pane: Pane) throws -> TerminalSessionAttachment {
        let surface = try createSurface(for: pane)
        try runtime.attach(session: session, to: surface.runtimeSurfaceID)

        lock.lock()
        sessionsByPane[pane.id] = session.id
        sessionStateByPane[pane.id] = SessionState(
            descriptor: session,
            runtimeSurfaceID: surface.runtimeSurfaceID,
            transcript: "OpenMUX session attached to \(session.workingDirectory)\n$ "
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
        sessionStateByPane.removeValue(forKey: paneID)
        observers.removeValue(forKey: paneID)
        lock.unlock()

        guard let surface else {
            throw TerminalBridgeError.missingSurface(paneID)
        }

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

    public func handle(_ event: NormalizedKeyEvent, inPane paneID: PaneID) throws {
        guard event.phase == .keyDown else {
            return
        }

        switch event.key {
        case "\u{7F}":
            lock.lock()
            sessionStateByPane[paneID]?.currentInput = String(sessionStateByPane[paneID]?.currentInput.dropLast() ?? "")
            lock.unlock()
            publishSnapshot(for: paneID)
        case "\r", "\n":
            let command: String?
            lock.lock()
            command = sessionStateByPane[paneID]?.currentInput
            sessionStateByPane[paneID]?.transcript += "\n"
            sessionStateByPane[paneID]?.currentInput = ""
            lock.unlock()
            publishSnapshot(for: paneID)

            if let command {
                try run(command: command, inPane: paneID)
            }
        default:
            guard let text = event.text, event.route != .shortcut else {
                return
            }

            lock.lock()
            sessionStateByPane[paneID]?.currentInput += text
            lock.unlock()
            publishSnapshot(for: paneID)
        }
    }

    public func run(command: String, inPane paneID: PaneID) throws {
        guard let state = snapshot(for: paneID) else {
            throw TerminalBridgeError.missingSession(paneID)
        }

        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedCommand.isEmpty {
            appendTranscript("$ ", to: paneID)
            return
        }

        appendTranscript("$ \(trimmedCommand)\n", to: paneID)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: state.shell)
            process.arguments = ["-lc", trimmedCommand]
            process.currentDirectoryURL = URL(fileURLWithPath: state.workingDirectory)

            var environment = ProcessInfo.processInfo.environment
            state.sessionEnvironment.forEach { environment[$0.key] = $0.value }
            process.environment = environment

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            do {
                try process.run()
                process.waitUntilExit()

                let data = stdout.fileHandleForReading.readDataToEndOfFile() + stderr.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                self?.appendTranscript(output.isEmpty ? "$ " : output + (output.hasSuffix("\n") ? "$ " : "\n$ "), to: paneID)
            } catch {
                self?.appendTranscript("command failed: \(error)\n$ ", to: paneID)
            }
        }
    }

    private func appendTranscript(_ text: String, to paneID: PaneID) {
        lock.lock()
        sessionStateByPane[paneID]?.transcript += text
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

    private func makeSnapshot(for paneID: PaneID) -> TerminalSessionSnapshot? {
        guard let state = sessionStateByPane[paneID],
              let sessionID = sessionsByPane[paneID]
        else {
            return nil
        }

        return TerminalSessionSnapshot(
            paneID: paneID,
            sessionID: sessionID,
            runtimeSurfaceID: state.runtimeSurfaceID,
            transcript: state.transcript,
            currentInput: state.currentInput,
            shell: state.descriptor.shell,
            workingDirectory: state.descriptor.workingDirectory
        )
    }
}

private extension Data {
    static func + (lhs: Data, rhs: Data) -> Data {
        var result = lhs
        result.append(rhs)
        return result
    }
}

private extension TerminalSessionSnapshot {
    var sessionEnvironment: [String: String] {
        [:]
    }
}
