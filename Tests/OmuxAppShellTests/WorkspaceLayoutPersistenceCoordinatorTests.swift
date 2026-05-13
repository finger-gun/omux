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

    func testScheduleLayoutSaveHonorsDebounceWindow() async {
        var saveCount = 0
        let persisted = expectation(description: "layout persisted")
        let sleepStarted = expectation(description: "debounce sleep started")

        let coordinator = WorkspaceLayoutPersistenceCoordinator(
            debounceNanoseconds: 50_000_000,
            sleep: { nanoseconds in
                sleepStarted.fulfill()
                try? await Task.sleep(nanoseconds: nanoseconds)
            },
            persistLayout: {
                saveCount += 1
                persisted.fulfill()
            }
        )

        coordinator.scheduleLayoutSave()
        await fulfillment(of: [sleepStarted], timeout: 1)
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(saveCount, 0)
        await fulfillment(of: [persisted], timeout: 1)

        XCTAssertEqual(saveCount, 1)
    }
}
