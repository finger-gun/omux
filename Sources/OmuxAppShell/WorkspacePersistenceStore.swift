import Foundation
import OmuxCore

@MainActor
protocol WorkspacePersistenceStoring: AnyObject {
    func load() -> WorkspacePersistenceSnapshot?
    func save(_ snapshot: WorkspacePersistenceSnapshot?)
}

struct WorkspacePersistenceSnapshot: Codable, Equatable {
    let workspaces: [Workspace]
    let activeWorkspaceID: WorkspaceID?
}

@MainActor
final class WorkspacePersistenceStore: WorkspacePersistenceStoring {
    static let shared = WorkspacePersistenceStore(
        defaults: appDefaults(),
        fallbackDefaults: .standard
    )
    static let suiteName = "dev.fingergun.omux"

    private let defaults: UserDefaults
    private let fallbackDefaults: UserDefaults?
    private let key = "dev.fingergun.omux.workspacePersistence"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        defaults: UserDefaults = WorkspacePersistenceStore.appDefaults(),
        fallbackDefaults: UserDefaults? = nil
    ) {
        self.defaults = defaults
        self.fallbackDefaults = fallbackDefaults
    }

    func load() -> WorkspacePersistenceSnapshot? {
        if let snapshot = loadSnapshot(from: defaults) {
            return snapshot
        }

        guard let fallbackDefaults, fallbackDefaults !== defaults else {
            return nil
        }

        guard let migratedSnapshot = loadSnapshot(from: fallbackDefaults) else {
            return nil
        }

        save(migratedSnapshot)
        return migratedSnapshot
    }

    func save(_ snapshot: WorkspacePersistenceSnapshot?) {
        guard let snapshot else {
            defaults.removeObject(forKey: key)
            fallbackDefaults?.removeObject(forKey: key)
            defaults.synchronize()
            fallbackDefaults?.synchronize()
            return
        }

        do {
            let data = try encoder.encode(snapshot)
            defaults.set(data, forKey: key)
            fallbackDefaults?.removeObject(forKey: key)
            defaults.synchronize()
            fallbackDefaults?.synchronize()
        } catch {
            fputs("warning: failed to encode workspace persistence snapshot: \(error)\n", stderr)
        }
    }

    private static func appDefaults() -> UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    private func loadSnapshot(from defaults: UserDefaults) -> WorkspacePersistenceSnapshot? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }

        do {
            return try decoder.decode(WorkspacePersistenceSnapshot.self, from: data)
        } catch {
            fputs("warning: failed to decode workspace persistence snapshot: \(error)\n", stderr)
            return nil
        }
    }
}
