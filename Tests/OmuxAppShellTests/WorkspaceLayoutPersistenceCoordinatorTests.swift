import Foundation
import XCTest
@testable import OmuxAppShell

@MainActor
final class WorkspaceLayoutPersistenceCoordinatorTests: XCTestCase {
    func testScheduleLayoutSaveCoalescesMultipleRequests() async {
        var saveCount = 0
        let persisted = expectation(description: "layout persisted once")
        let coordinator = WorkspaceLayoutPersistenceCoordinator(
            debounceNanoseconds: 20_000_000,
            sleep: { _ in },
            persistLayout: {
                saveCount += 1
                persisted.fulfill()
            }
        )

        coordinator.scheduleLayoutSave()
        coordinator.scheduleLayoutSave()
        coordinator.scheduleLayoutSave()
        await fulfillment(of: [persisted], timeout: 1)

        XCTAssertEqual(saveCount, 1)
    }

    func testFlushLayoutSavePersistsPendingWorkImmediately() {
        var saveCount = 0
        let coordinator = WorkspaceLayoutPersistenceCoordinator(
            debounceNanoseconds: 2_000_000_000,
            persistLayout: {
                saveCount += 1
            }
        )

        coordinator.scheduleLayoutSave()
        coordinator.flushLayoutSave()

        XCTAssertEqual(saveCount, 1)
    }

    func testFlushLayoutSaveIsNoopWithoutPendingWork() {
        var saveCount = 0
        let coordinator = WorkspaceLayoutPersistenceCoordinator(
            persistLayout: {
                saveCount += 1
            }
        )

        coordinator.flushLayoutSave()
        XCTAssertEqual(saveCount, 0)
    }
}
