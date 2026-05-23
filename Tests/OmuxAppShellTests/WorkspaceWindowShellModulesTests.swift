import XCTest
@testable import OmuxAppShell
import OmuxCore
import AppKit

final class WorkspaceWindowShellModulesTests: XCTestCase {
    func testFloatingModalRootSplitDirectionPrefersNearestEligibleEdge() {
        let frame = NSRect(x: 4, y: 60, width: 120, height: 80)
        let bounds = NSRect(x: 0, y: 0, width: 800, height: 600)

        let direction = WorkspaceWindowFloatingModalDropResolver.rootSplitDirection(
            frame: frame,
            overlayBounds: bounds,
            threshold: 32
        )

        XCTAssertEqual(direction, .left)
    }

    func testFloatingModalRootSplitDirectionReturnsNilOutsideThreshold() {
        let frame = NSRect(x: 200, y: 200, width: 160, height: 120)
        let bounds = NSRect(x: 0, y: 0, width: 800, height: 600)

        let direction = WorkspaceWindowFloatingModalDropResolver.rootSplitDirection(
            frame: frame,
            overlayBounds: bounds,
            threshold: 24
        )

        XCTAssertNil(direction)
    }

    func testWorkspaceSidebarDragPlannerInsertionIndexUsesFirstCenterAbovePointer() {
        XCTAssertEqual(
            WorkspaceSidebarDragPlanner.insertionIndex(candidateCenterYs: [300, 240, 180], pointerY: 241),
            1
        )
        XCTAssertEqual(
            WorkspaceSidebarDragPlanner.insertionIndex(candidateCenterYs: [300, 240, 180], pointerY: 120),
            3
        )
    }
}
