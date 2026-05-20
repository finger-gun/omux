import AppKit
import Foundation
import OmuxCore

/// A no-op implementation of `GhosttyRuntime` used when `OMUX_UI_TEST=1` is set.
///
/// This bypasses all Metal/GPU-dependent libghostty surface creation so the app
/// can launch and reach its main window on headless CI runners that have no GPU.
public final class NullGhosttyRuntime: GhosttyRuntime, @unchecked Sendable {
    private var ownedSurfaces: Set<String> = []
    private let lock = NSLock()

    public init() {}

    public func createSurface(for paneID: PaneID) throws -> String {
        // Return a deterministic fake surface ID; no GPU resources are allocated.
        let surfaceID = "null-surface-\(paneID.rawValue)"
        lock.lock()
        ownedSurfaces.insert(surfaceID)
        lock.unlock()
        return surfaceID
    }

    public func attach(session: SessionDescriptor, to runtimeSurfaceID: String) throws {
        // No-op: there is no real terminal process to attach.
        _ = session
        _ = runtimeSurfaceID
    }

    public func ownsSession(for runtimeSurfaceID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return ownedSurfaces.contains(runtimeSurfaceID)
    }

    public func destroySurface(runtimeSurfaceID: String) throws {
        lock.lock()
        ownedSurfaces.remove(runtimeSurfaceID)
        lock.unlock()
    }

    @MainActor
    public func makeHostedSurfaceView(for paneID: PaneID, runtimeSurfaceID: String) -> NSView? {
        // Return an empty placeholder view so the host can render something.
        let view = NSView()
        view.wantsLayer = true
        return view
    }
}
