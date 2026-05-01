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
    static let shared = WorkspacePersistenceStore()

    private let defaults: UserDefaults
    private let key = "dev.fingergun.omux.workspacePersistence"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> WorkspacePersistenceSnapshot? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }

        return try? decoder.decode(WorkspacePersistenceSnapshot.self, from: data)
    }

    func save(_ snapshot: WorkspacePersistenceSnapshot?) {
        guard let snapshot else {
            defaults.removeObject(forKey: key)
            return
        }

        guard let data = try? encoder.encode(snapshot) else {
            return
        }

        defaults.set(data, forKey: key)
    }
}
