import CoreServices
import Foundation
import OmuxVault

@MainActor
final class VaultIndexRefreshCoordinator {
    struct Timing: Sendable {
        let debounce: TimeInterval
        let minimumInterval: TimeInterval

        init(debounce: TimeInterval = 4, minimumInterval: TimeInterval = 20) {
            self.debounce = debounce
            self.minimumInterval = minimumInterval
        }
    }

    private let reindex: @Sendable (VaultAgentKind) async throws -> [String]
    private let timing: Timing
    private let onReindexed: @MainActor (Set<VaultAgentKind>) -> Void
    private var dirtyAgents = Set<VaultAgentKind>()
    private var dirtySince: [VaultAgentKind: Date] = [:]
    private var lastIndexedAt: [VaultAgentKind: Date] = [:]
    private var scheduledTask: Task<Void, Never>?
    private var isIndexing = false

    init(
        vaultStore: VaultStore,
        timing: Timing = Timing(),
        onReindexed: @escaping @MainActor (Set<VaultAgentKind>) -> Void
    ) {
        self.reindex = { agent in
            try await vaultStore.reindex(agent: agent)
        }
        self.timing = timing
        self.onReindexed = onReindexed
    }

    init(
        timing: Timing = Timing(),
        reindex: @escaping @Sendable (VaultAgentKind) async throws -> [String],
        onReindexed: @escaping @MainActor (Set<VaultAgentKind>) -> Void
    ) {
        self.reindex = reindex
        self.timing = timing
        self.onReindexed = onReindexed
    }

    deinit {
        scheduledTask?.cancel()
    }

    func markDirty(_ agent: VaultAgentKind) {
        dirtyAgents.insert(agent)
        dirtySince[agent] = dirtySince[agent] ?? Date()
        scheduleNextRun()
    }

    private func scheduleNextRun() {
        guard isIndexing == false, dirtyAgents.isEmpty == false else {
            return
        }
        let delay = nextDelay()
        scheduledTask?.cancel()
        scheduledTask = Task { [weak self] in
            let nanoseconds = UInt64(max(0, delay) * 1_000_000_000)
            if nanoseconds > 0 {
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
            await MainActor.run {
                self?.runDueAgents()
            }
        }
    }

    private func runDueAgents() {
        guard isIndexing == false else {
            return
        }
        scheduledTask = nil
        let now = Date()
        let dueAgents = dirtyAgents
            .filter { isDue(agent: $0, at: now) }
            .sorted { $0.rawValue < $1.rawValue }

        guard dueAgents.isEmpty == false else {
            scheduleNextRun()
            return
        }

        isIndexing = true
        Task { [weak self] in
            var completed = Set<VaultAgentKind>()
            for agent in dueAgents {
                do {
                    let warnings = try await self?.reindex(agent) ?? []
                    for warning in warnings {
                        fputs("Agent Sessions background index warning: \(warning)\n", stderr)
                    }
                    completed.insert(agent)
                } catch {
                    fputs("Agent Sessions background index failed for \(agent.rawValue): \(error)\n", stderr)
                }
            }
            await MainActor.run {
                self?.finishIndexing(completed: completed)
            }
        }
    }

    private func finishIndexing(completed: Set<VaultAgentKind>) {
        let now = Date()
        for agent in completed {
            dirtyAgents.remove(agent)
            dirtySince.removeValue(forKey: agent)
            lastIndexedAt[agent] = now
        }
        isIndexing = false
        if completed.isEmpty == false {
            onReindexed(completed)
        }
        scheduleNextRun()
    }

    private func nextDelay() -> TimeInterval {
        let now = Date()
        let nextDate = dirtyAgents
            .map { nextAllowedDate(for: $0, at: now) }
            .min() ?? now
        return max(0, nextDate.timeIntervalSince(now))
    }

    private func isDue(agent: VaultAgentKind, at now: Date) -> Bool {
        nextAllowedDate(for: agent, at: now) <= now
    }

    private func nextAllowedDate(for agent: VaultAgentKind, at now: Date) -> Date {
        let debounceDate = (dirtySince[agent] ?? now).addingTimeInterval(timing.debounce)
        let intervalDate = lastIndexedAt[agent]?.addingTimeInterval(timing.minimumInterval) ?? now
        return max(debounceDate, intervalDate)
    }
}

final class VaultSourceEventWatcher {
    private let queue = DispatchQueue(label: "dev.openmux.agent-sessions-source-events", qos: .utility)
    private let sources: [(agent: VaultAgentKind, path: String)]
    private let onDirty: @MainActor (VaultAgentKind) -> Void
    private var stream: FSEventStreamRef?

    init(sources: [VaultWatchSource], onDirty: @escaping @MainActor (VaultAgentKind) -> Void) {
        self.sources = sources.map { ($0.agent, $0.url.path) }
        self.onDirty = onDirty
    }

    deinit {
        stop()
    }

    func start() {
        guard stream == nil, sources.isEmpty == false else {
            return
        }

        let paths = Array(Set(sources.map(\.path))) as CFArray
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        guard let stream = FSEventStreamCreate(
            nil,
            Self.handleEvents,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            5,
            flags
        ) else {
            return
        }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else {
            return
        }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private static let handleEvents: FSEventStreamCallback = { _, context, count, eventPaths, _, _ in
        guard let context else {
            return
        }
        let watcher = Unmanaged<VaultSourceEventWatcher>.fromOpaque(context).takeUnretainedValue()
        let array = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as NSArray
        let paths = array.compactMap { $0 as? String }
        watcher.handle(paths: Array(paths.prefix(count)))
    }

    private func handle(paths: [String]) {
        let dirtyAgents = Set(paths.compactMap(agent(forChangedPath:)))
        guard dirtyAgents.isEmpty == false else {
            return
        }
        Task { @MainActor [onDirty] in
            for agent in dirtyAgents {
                onDirty(agent)
            }
        }
    }

    private func agent(forChangedPath changedPath: String) -> VaultAgentKind? {
        let standardized = URL(fileURLWithPath: changedPath).standardizedFileURL.path
        return sources.first { source in
            standardized == source.path || standardized.hasPrefix(source.path + "/")
        }?.agent
    }
}
