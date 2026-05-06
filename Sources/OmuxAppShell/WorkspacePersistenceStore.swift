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

enum WorkspacePersistenceSnapshotMode: Equatable {
    case layoutOnly
    case includeScrollback(maxBytes: Int = PaneScrollbackSnapshot.defaultMaxBytes, maxLines: Int = PaneScrollbackSnapshot.defaultMaxLines)
}

@MainActor
final class WorkspacePersistenceStore: WorkspacePersistenceStoring {
    static let shared = WorkspacePersistenceStore(
        defaults: appDefaults(),
        fallbackDefaults: .standard,
        stateFileURL: appStateFileURL(),
        scrollbackPayloadStore: WorkspaceScrollbackPayloadStore(directoryURL: appScrollbackDirectory()),
        backupDirectory: appBackupDirectory()
    )
    static let suiteName = "dev.fingergun.omux"

    private let defaults: UserDefaults
    private let fallbackDefaults: UserDefaults?
    private let stateFileURL: URL?
    private let scrollbackPayloadStore: WorkspaceScrollbackPayloadStore?
    private let backupDirectory: URL?
    private let key = "dev.fingergun.omux.workspacePersistence"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        defaults: UserDefaults = WorkspacePersistenceStore.appDefaults(),
        fallbackDefaults: UserDefaults? = nil,
        stateFileURL: URL? = nil,
        scrollbackPayloadStore: WorkspaceScrollbackPayloadStore? = nil,
        backupDirectory: URL? = nil
    ) {
        self.defaults = defaults
        self.fallbackDefaults = fallbackDefaults
        self.stateFileURL = stateFileURL
        self.scrollbackPayloadStore = scrollbackPayloadStore
        self.backupDirectory = backupDirectory
    }

    func load() -> WorkspacePersistenceSnapshot? {
        if let snapshot = loadSnapshotFromStateFile() {
            return snapshot
        }

        if let snapshot = loadSnapshot(from: defaults) {
            save(snapshot)
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
            backupStoredSnapshotFromStateFile()
            backupStoredSnapshot(from: defaults)
            removeStateFile()
            defaults.removeObject(forKey: key)
            defaults.synchronize()
            return
        }

        do {
            let snapshotToStore = scrollbackPayloadStore?.persistPayloads(in: snapshot) ?? snapshot
            let data = try encoder.encode(snapshotToStore)
            if let stateFileURL {
                backupStoredSnapshotFromStateFile()
                try FileManager.default.createDirectory(
                    at: stateFileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: stateFileURL, options: .atomic)
                defaults.removeObject(forKey: key)
                defaults.synchronize()
            } else {
                backupStoredSnapshot(from: defaults)
                defaults.set(data, forKey: key)
                defaults.synchronize()
            }
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

    private static func appStateFileURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenMUX", isDirectory: true)
            .appendingPathComponent("WorkspaceState", isDirectory: true)
            .appendingPathComponent("current.json", isDirectory: false)
    }

    private static func appScrollbackDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenMUX", isDirectory: true)
            .appendingPathComponent("Scrollback", isDirectory: true)
    }

    private func loadSnapshotFromStateFile() -> WorkspacePersistenceSnapshot? {
        guard let stateFileURL,
              FileManager.default.fileExists(atPath: stateFileURL.path)
        else {
            return nil
        }

        do {
            let snapshot = try decoder.decode(WorkspacePersistenceSnapshot.self, from: Data(contentsOf: stateFileURL))
            return scrollbackPayloadStore?.resolvePayloads(in: snapshot) ?? snapshot
        } catch {
            fputs("warning: failed to decode workspace persistence state \(stateFileURL.path): \(error)\n", stderr)
            return nil
        }
    }

    private func loadSnapshot(from defaults: UserDefaults) -> WorkspacePersistenceSnapshot? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }

        do {
            let snapshot = try decoder.decode(WorkspacePersistenceSnapshot.self, from: data)
            return scrollbackPayloadStore?.resolvePayloads(in: snapshot) ?? snapshot
        } catch {
            fputs("warning: failed to decode workspace persistence snapshot: \(error)\n", stderr)
            return nil
        }
    }

    private func backupStoredSnapshotFromStateFile() {
        guard let stateFileURL,
              let data = try? Data(contentsOf: stateFileURL)
        else {
            return
        }
        writeBackup(data)
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

    private func removeStateFile() {
        guard let stateFileURL,
              FileManager.default.fileExists(atPath: stateFileURL.path)
        else {
            return
        }

        do {
            try FileManager.default.removeItem(at: stateFileURL)
        } catch {
            fputs("warning: failed to remove workspace persistence state \(stateFileURL.path): \(error)\n", stderr)
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
                    let snapshot = try decoder.decode(WorkspacePersistenceSnapshot.self, from: Data(contentsOf: backupURL))
                    return scrollbackPayloadStore?.resolvePayloads(in: snapshot) ?? snapshot
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

@MainActor
final class WorkspaceScrollbackPayloadStore {
    private let directoryURL: URL
    private let fileManager: FileManager

    init(directoryURL: URL, fileManager: FileManager = .default) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
    }

    func persistPayloads(in snapshot: WorkspacePersistenceSnapshot) -> WorkspacePersistenceSnapshot {
        let persistedSnapshot = WorkspacePersistenceSnapshot(
            workspaces: snapshot.workspaces.map(persistPayloads(in:)),
            activeWorkspaceID: snapshot.activeWorkspaceID
        )
        removeUnreferencedPayloads(referencedIdentifiers: referencedPayloadIdentifiers(in: persistedSnapshot))
        return persistedSnapshot
    }

    func resolvePayloads(in snapshot: WorkspacePersistenceSnapshot) -> WorkspacePersistenceSnapshot {
        WorkspacePersistenceSnapshot(
            workspaces: snapshot.workspaces.map(resolvePayloads(in:)),
            activeWorkspaceID: snapshot.activeWorkspaceID
        )
    }

    private func persistPayloads(in workspace: Workspace) -> Workspace {
        Workspace(
            id: workspace.id,
            generatedName: workspace.generatedName,
            customName: workspace.customName,
            rootPath: workspace.rootPath,
            tabs: workspace.tabs.map { persistPayloads(in: $0, workspaceID: workspace.id) },
            focusedTabID: workspace.focusedTabID
        )
    }

    private func persistPayloads(in tab: Tab, workspaceID: WorkspaceID) -> Tab {
        Tab(
            id: tab.id,
            title: tab.title,
            rootLayout: transformPanes(in: tab.rootLayout) { pane in
                persistPayloads(in: pane, workspaceID: workspaceID)
            },
            focusedPaneID: tab.focusedPaneID
        )
    }

    private func persistPayloads(in pane: Pane, workspaceID: WorkspaceID) -> Pane {
        guard pane.isTerminal,
              let scrollback = pane.terminalState.restoredScrollback,
              scrollback.text.isEmpty == false,
              let storageIdentifier = write(scrollback: scrollback, workspaceID: workspaceID, paneID: pane.id)
        else {
            return pane
        }

        var terminalState = pane.terminalState
        terminalState.restoredScrollback = PaneScrollbackSnapshot(
            text: "",
            truncated: scrollback.truncated,
            storageIdentifier: storageIdentifier
        )
        var updatedPane = pane
        updatedPane.terminalState = terminalState
        return updatedPane
    }

    private func resolvePayloads(in workspace: Workspace) -> Workspace {
        Workspace(
            id: workspace.id,
            generatedName: workspace.generatedName,
            customName: workspace.customName,
            rootPath: workspace.rootPath,
            tabs: workspace.tabs.map(resolvePayloads(in:)),
            focusedTabID: workspace.focusedTabID
        )
    }

    private func resolvePayloads(in tab: Tab) -> Tab {
        Tab(
            id: tab.id,
            title: tab.title,
            rootLayout: transformPanes(in: tab.rootLayout, transform: resolvePayloads(in:)),
            focusedPaneID: tab.focusedPaneID
        )
    }

    private func resolvePayloads(in pane: Pane) -> Pane {
        guard pane.isTerminal,
              let scrollback = pane.terminalState.restoredScrollback,
              let storageIdentifier = scrollback.storageIdentifier
        else {
            return pane
        }

        guard let text = read(storageIdentifier: storageIdentifier), text.isEmpty == false else {
            var terminalState = pane.terminalState
            terminalState.restoredScrollback = nil
            var updatedPane = pane
            updatedPane.terminalState = terminalState
            return updatedPane
        }

        var terminalState = pane.terminalState
        terminalState.restoredScrollback = PaneScrollbackSnapshot(
            text: text,
            truncated: scrollback.truncated,
            storageIdentifier: storageIdentifier
        )
        var updatedPane = pane
        updatedPane.terminalState = terminalState
        return updatedPane
    }

    private func transformPanes(
        in node: TabLayoutNode,
        transform: (Pane) -> Pane
    ) -> TabLayoutNode {
        switch node {
        case .paneStack(let paneStack):
            let panes = paneStack.panes.map(transform)
            return .paneStack(PaneStack(id: paneStack.id, panes: panes, focusedPaneID: paneStack.focusedPaneID))
        case .split(let axis, let proportions, let children):
            return .split(
                axis: axis,
                proportions: proportions,
                children: children.map { transformPanes(in: $0, transform: transform) }
            )
        }
    }

    private func write(scrollback: PaneScrollbackSnapshot, workspaceID: WorkspaceID, paneID: PaneID) -> String? {
        let workspaceComponent = safePathComponent(workspaceID.rawValue)
        let paneComponent = "\(safePathComponent(paneID.rawValue)).ansi"
        let relativePath = "\(workspaceComponent)/\(paneComponent)"
        let payloadURL = directoryURL
            .appendingPathComponent(workspaceComponent, isDirectory: true)
            .appendingPathComponent(paneComponent, isDirectory: false)

        do {
            try fileManager.createDirectory(
                at: payloadURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try Data(scrollback.text.utf8).write(to: payloadURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: payloadURL.path)
            return relativePath
        } catch {
            fputs("warning: failed to persist scrollback payload \(payloadURL.path): \(error)\n", stderr)
            return nil
        }
    }

    private func read(storageIdentifier: String) -> String? {
        guard let payloadURL = payloadURL(for: storageIdentifier) else {
            return nil
        }

        do {
            return String(decoding: try Data(contentsOf: payloadURL), as: UTF8.self)
        } catch {
            fputs("warning: failed to read scrollback payload \(payloadURL.path): \(error)\n", stderr)
            return nil
        }
    }

    private func referencedPayloadIdentifiers(in snapshot: WorkspacePersistenceSnapshot) -> Set<String> {
        var identifiers = Set<String>()
        for workspace in snapshot.workspaces {
            for tab in workspace.tabs {
                for pane in tab.panes {
                    if let storageIdentifier = pane.terminalState.restoredScrollback?.storageIdentifier {
                        identifiers.insert(storageIdentifier)
                    }
                }
            }
        }
        return identifiers
    }

    private func removeUnreferencedPayloads(referencedIdentifiers: Set<String>) {
        let referencedPaths = Set(referencedIdentifiers.compactMap { payloadURL(for: $0)?.standardizedFileURL.path })
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for case let payloadURL as URL in enumerator where payloadURL.pathExtension == "ansi" {
            guard referencedPaths.contains(payloadURL.standardizedFileURL.path) == false else {
                continue
            }

            do {
                try fileManager.removeItem(at: payloadURL)
            } catch {
                fputs("warning: failed to remove unreferenced scrollback payload \(payloadURL.path): \(error)\n", stderr)
            }
        }
    }

    private func payloadURL(for storageIdentifier: String) -> URL? {
        let components = storageIdentifier.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.count == 2,
              components.allSatisfy({ $0.isEmpty == false && $0 != "." && $0 != ".." })
        else {
            return nil
        }
        return directoryURL
            .appendingPathComponent(components[0], isDirectory: true)
            .appendingPathComponent(components[1], isDirectory: false)
    }

    private func safePathComponent(_ rawValue: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        let scalars = rawValue.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let sanitized = String(scalars)
        return sanitized.isEmpty ? UUID().uuidString.lowercased() : sanitized
    }
}
