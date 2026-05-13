import Foundation

@MainActor
final class WorkspaceLayoutPersistenceCoordinator {
    private let debounceNanoseconds: UInt64
    private let sleep: @Sendable (UInt64) async -> Void
    private let persistLayout: @MainActor () -> Void
    private var pendingLayoutSave = false
    private var task: Task<Void, Never>?

    init(
        debounceNanoseconds: UInt64 = 250_000_000,
        sleep: @escaping @Sendable (UInt64) async -> Void = { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        },
        persistLayout: @escaping @MainActor () -> Void
    ) {
        self.debounceNanoseconds = debounceNanoseconds
        self.sleep = sleep
        self.persistLayout = persistLayout
    }

    func scheduleLayoutSave() {
        pendingLayoutSave = true
        guard task == nil else {
            return
        }

        task = Task { [weak self] in
            guard let self else {
                return
            }
            await self.sleep(self.debounceNanoseconds)
            guard Task.isCancelled == false else {
                return
            }
            await MainActor.run {
                self.flushLayoutSave()
            }
        }
    }

    func flushLayoutSave() {
        task?.cancel()
        task = nil

        guard pendingLayoutSave else {
            return
        }
        pendingLayoutSave = false
        persistLayout()
    }

    deinit {
        task?.cancel()
    }
}
