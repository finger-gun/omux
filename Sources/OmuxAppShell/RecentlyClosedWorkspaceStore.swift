import Foundation
import OmuxConfig
import OmuxCore

struct RecentlyClosedWorkspaceEntry: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case workspacePaths
        case rootPath
        case closedAt
        case workspace
    }

    let id: WorkspaceID
    let name: String
    let workspacePaths: [String]
    let closedAt: Date
    let workspace: Workspace

    init(
        id: WorkspaceID,
        name: String,
        workspacePaths: [String],
        closedAt: Date,
        workspace: Workspace
    ) {
        self.id = id
        self.name = name
        self.workspacePaths = workspacePaths
        self.closedAt = closedAt
        self.workspace = workspace
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(WorkspaceID.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        let workspace = try container.decode(Workspace.self, forKey: .workspace)
        let closedAt = try container.decode(Date.self, forKey: .closedAt)
        let workspacePaths = try container.decodeIfPresent([String].self, forKey: .workspacePaths)
            ?? Self.workspacePaths(for: workspace)
            ?? container.decodeIfPresent(String.self, forKey: .rootPath).map { [$0] }
            ?? []

        self.init(
            id: id,
            name: name,
            workspacePaths: workspacePaths,
            closedAt: closedAt,
            workspace: workspace
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(workspacePaths, forKey: .workspacePaths)
        try container.encode(closedAt, forKey: .closedAt)
        try container.encode(workspace, forKey: .workspace)
    }

    var primaryWorkspacePath: String? {
        workspacePaths.first
    }

    var workspacePathSummary: String {
        guard let firstPath = workspacePaths.first else {
            return "No tab working directories"
        }
        guard workspacePaths.count > 1 else {
            return firstPath
        }
        return "\(firstPath) +\(workspacePaths.count - 1) more"
    }

    fileprivate static func workspacePaths(for workspace: Workspace) -> [String]? {
        let paths = workspace.tabs.compactMap { tab in
            tab.focusedPane?.terminalState.reportedWorkingDirectory
                ?? tab.focusedPane?.terminalSession?.workingDirectory
        }
        .compactMap { path in
            let normalizedPath = OmuxWorkspacePathResolver.resolve(path) ?? path
            return normalizedPath.isEmpty ? nil : normalizedPath
        }

        guard paths.isEmpty == false else {
            return nil
        }

        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }
}

final class RecentlyClosedWorkspaceStore: @unchecked Sendable {
    static let maxEntries = 20
    static let shared = RecentlyClosedWorkspaceStore(
        fileURL: appStateDirectoryURL()
            .appendingPathComponent("recently-closed.json", isDirectory: false)
    )

    private let lock = NSLock()
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL) {
        self.fileURL = fileURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    private static func appStateDirectoryURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenMUX", isDirectory: true)
            .appendingPathComponent("WorkspaceState", isDirectory: true)
    }

    func add(_ workspace: Workspace) {
        lock.lock()
        var entries = loadLocked().filter { $0.id != workspace.id }
        entries.insert(
            RecentlyClosedWorkspaceEntry(
                id: workspace.id,
                name: workspace.name,
                workspacePaths: RecentlyClosedWorkspaceEntry.workspacePaths(for: workspace) ?? [],
                closedAt: Date(),
                workspace: workspace
            ),
            at: 0
        )
        if entries.count > Self.maxEntries {
            entries.removeSubrange(Self.maxEntries...)
        }
        saveLocked(entries)
        lock.unlock()
    }

    func remove(byID workspaceID: WorkspaceID) {
        lock.lock()
        let updatedEntries = loadLocked().filter { $0.id != workspaceID }
        saveLocked(updatedEntries)
        lock.unlock()
    }

    func find(byPath path: String) -> RecentlyClosedWorkspaceEntry? {
        let normalizedPath = OmuxWorkspacePathResolver.resolve(path) ?? path
        lock.lock()
        let entry = loadLocked().first { entry in
            entry.workspacePaths.contains(normalizedPath)
        }
        lock.unlock()
        return entry
    }

    func load() -> [RecentlyClosedWorkspaceEntry] {
        lock.lock()
        let entries = loadLocked()
        lock.unlock()
        return entries
    }

    func save(_ entries: [RecentlyClosedWorkspaceEntry]) {
        lock.lock()
        saveLocked(entries)
        lock.unlock()
    }

    func clear() {
        save([])
    }

    private func loadLocked() -> [RecentlyClosedWorkspaceEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        do {
            return try decoder.decode([RecentlyClosedWorkspaceEntry].self, from: Data(contentsOf: fileURL))
        } catch {
            fputs("warning: failed to decode recently closed workspace state \(fileURL.path): \(error)\n", stderr)
            return []
        }
    }

    private func saveLocked(_ entries: [RecentlyClosedWorkspaceEntry]) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            fputs("warning: failed to encode recently closed workspace state \(fileURL.path): \(error)\n", stderr)
        }
    }
}
