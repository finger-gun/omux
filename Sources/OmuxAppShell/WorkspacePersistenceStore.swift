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
        fallbackDefaults: .standard,
        backupDirectory: appBackupDirectory()
    )
    static let suiteName = "dev.fingergun.omux"

    private let defaults: UserDefaults
    private let fallbackDefaults: UserDefaults?
    private let backupDirectory: URL?
    private let key = "dev.fingergun.omux.workspacePersistence"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        defaults: UserDefaults = WorkspacePersistenceStore.appDefaults(),
        fallbackDefaults: UserDefaults? = nil,
        backupDirectory: URL? = nil
    ) {
        self.defaults = defaults
        self.fallbackDefaults = fallbackDefaults
        self.backupDirectory = backupDirectory
    }

    func load() -> WorkspacePersistenceSnapshot? {
        if let snapshot = loadSnapshot(from: defaults) {
            return snapshot
        }

        guard let fallbackDefaults, fallbackDefaults !== defaults else {
            return loadLatestBackup()
        }

        guard let migratedSnapshot = loadSnapshot(from: fallbackDefaults) else {
            return loadLatestBackup()
        }

        save(migratedSnapshot)
        return migratedSnapshot
    }

    func save(_ snapshot: WorkspacePersistenceSnapshot?) {
        guard let snapshot else {
            backupStoredSnapshot(from: defaults)
            defaults.removeObject(forKey: key)
            defaults.synchronize()
            return
        }

        do {
            backupStoredSnapshot(from: defaults)
            let data = try encoder.encode(snapshot)
            defaults.set(data, forKey: key)
            defaults.synchronize()
        } catch {
            fputs("warning: failed to encode workspace persistence snapshot: \(error)\n", stderr)
        }
    }

    private static func appDefaults() -> UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    private static func appBackupDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenMUX", isDirectory: true)
            .appendingPathComponent("WorkspaceBackups", isDirectory: true)
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

    private func backupStoredSnapshot(from defaults: UserDefaults) {
        guard let data = defaults.data(forKey: key) else {
            return
        }
        writeBackup(data)
    }

    private func writeBackup(_ data: Data) {
        guard let backupDirectory else {
            return
        }

        do {
            try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
            let backupURL = backupDirectory
                .appendingPathComponent("workspace-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString).json")
            try data.write(to: backupURL, options: .atomic)
        } catch {
            fputs("warning: failed to back up workspace persistence snapshot: \(error)\n", stderr)
        }
    }

    private func loadLatestBackup() -> WorkspacePersistenceSnapshot? {
        guard let backupDirectory else {
            return nil
        }

        do {
            let backups = try FileManager.default.contentsOfDirectory(
                at: backupDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
                .filter { $0.pathExtension == "json" }
                .sorted { lhs, rhs in
                    let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    return lhsDate > rhsDate
                }

            for backupURL in backups {
                do {
                    return try decoder.decode(WorkspacePersistenceSnapshot.self, from: Data(contentsOf: backupURL))
                } catch {
                    fputs("warning: failed to decode workspace persistence backup \(backupURL.path): \(error)\n", stderr)
                }
            }
        } catch {
            return nil
        }

        return nil
    }
}
