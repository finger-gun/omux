import AppKit
import OmuxCore

enum WorkspaceWindowFloatingModalDropResolver {
    static func rootSplitDirection(
        frame: NSRect,
        overlayBounds: NSRect,
        threshold: CGFloat
    ) -> PaneSplitDropDirection? {
        guard overlayBounds.width > 0, overlayBounds.height > 0 else {
            return nil
        }

        let candidates: [(PaneSplitDropDirection, CGFloat)] = [
            (.left, frame.minX),
            (.right, overlayBounds.maxX - frame.maxX),
            (.up, frame.minY),
            (.down, overlayBounds.maxY - frame.maxY),
        ].filter { $0.1 <= threshold }

        return candidates.min { $0.1 < $1.1 }?.0
    }
}

enum WorkspaceSidebarDragPlanner {
    /// Returns the insertion index for `pointerY` in `candidateCenterYs`.
    ///
    /// - Precondition: `candidateCenterYs` is sorted in descending (high-to-low) Y order.
    static func insertionIndex(candidateCenterYs: [CGFloat], pointerY: CGFloat) -> Int {
        assert(
            zip(candidateCenterYs, candidateCenterYs.dropFirst()).allSatisfy { $0 >= $1 },
            "candidateCenterYs must be sorted in descending Y order"
        )

        for (index, centerY) in candidateCenterYs.enumerated() {
            if pointerY >= centerY {
                return index
            }
        }
        return candidateCenterYs.count
    }
}
