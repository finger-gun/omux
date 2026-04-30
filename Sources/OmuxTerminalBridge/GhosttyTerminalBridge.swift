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
}

public final class GhosttyTerminalBridge {
    private let dependency: GhosttyPinnedDependency
    private let runtime: any GhosttyRuntime
    private let lock = NSLock()
    private var surfaces: [PaneID: TerminalSurfaceDescriptor] = [:]
    private var sessionsByPane: [PaneID: SessionID] = [:]

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
        lock.unlock()

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
}
