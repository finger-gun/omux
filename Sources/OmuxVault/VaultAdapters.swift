import CSQLite
import Foundation

public protocol VaultAgentAdapter: Sendable {
    var kind: VaultAgentKind { get }
    func discoverSessions() async throws -> [VaultIndexedSession]
}

public enum VaultAdapterFactory {
    public static func adapters(configuration: VaultConfiguration) -> [VaultAgentAdapter] {
        [
            CodexVaultAdapter(root: configuration.home(for: .codex), configuration: configuration),
            JSONLDirectoryVaultAdapter(kind: .claude, root: configuration.home(for: .claude), sourceKind: "claude_jsonl", globHint: "projects", configuration: configuration),
            SQLiteBackedVaultAdapter(kind: .opencode, root: configuration.home(for: .opencode), databaseNames: ["opencode.db", "state.db", "db.sqlite"], sourceKind: "opencode_db", configuration: configuration),
            JSONLDirectoryVaultAdapter(kind: .pi, root: configuration.home(for: .pi), sourceKind: "pi_jsonl", globHint: nil, configuration: configuration),
            JSONLDirectoryVaultAdapter(kind: .rovodev, root: configuration.home(for: .rovodev), sourceKind: "rovodev_jsonl", globHint: nil, configuration: configuration),
            CopilotVaultAdapter(root: configuration.home(for: .copilot), configuration: configuration),
            GeminiVaultAdapter(root: configuration.home(for: .gemini), configuration: configuration),
        ]
    }
}

public struct CodexVaultAdapter: VaultAgentAdapter {
    public let kind: VaultAgentKind = .codex
    public let root: URL
    private let configuration: VaultConfiguration

    public init(root: URL, configuration: VaultConfiguration) {
        self.root = root
        self.configuration = configuration
    }

    public func discoverSessions() async throws -> [VaultIndexedSession] {
        let jsonl = JSONLDirectoryVaultAdapter(
            kind: .codex,
            root: root,
            sourceKind: "codex_jsonl",
            globHint: "sessions",
            configuration: configuration
        )
        let sqlite = SQLiteBackedVaultAdapter(
            kind: .codex,
            root: root,
            databaseNames: ["state_5.sqlite", "state_4.sqlite", "state.sqlite", "sqlite/codex-dev.db"],
            sourceKind: "codex_sqlite",
            configuration: configuration
        )
        let jsonlSessions = (try? await jsonl.discoverSessions()) ?? []
        let sqliteSessions = (try? await sqlite.discoverSessions()) ?? []
        return mergePreferNewest(jsonlSessions + sqliteSessions)
    }
}

public struct JSONLDirectoryVaultAdapter: VaultAgentAdapter {
    public let kind: VaultAgentKind
    public let root: URL
    public let sourceKind: String
    public let globHint: String?
    private let configuration: VaultConfiguration

    public init(kind: VaultAgentKind, root: URL, sourceKind: String, globHint: String?, configuration: VaultConfiguration) {
        self.kind = kind
        self.root = root
        self.sourceKind = sourceKind
        self.globHint = globHint
        self.configuration = configuration
    }

    public func discoverSessions() async throws -> [VaultIndexedSession] {
        let searchRoot = globHint.map { root.appendingPathComponent($0, isDirectory: true) } ?? root
        let files = SessionFileScanner.files(under: searchRoot, extensions: ["jsonl", "json"])
        return mergePreferNewest(files.compactMap { file in
            parse(file: file)
        })
    }

    func parse(file: URL) -> VaultIndexedSession? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path) else {
            return nil
        }
        let modified = attributes[.modificationDate] as? Date ?? Date()
        let sessionID = sessionID(from: file)
        let lines = (try? String(contentsOf: file, encoding: .utf8))?.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) ?? []
        var title: String?
        var cwd: String?
        var model: String?
        var branch: String?
        var turns: [VaultTranscriptTurn] = []

        for (index, line) in lines.enumerated() {
            guard let object = parseJSONObject(line) else { continue }
            title = title ?? firstString(object, keys: ["title", "summary", "name"])
            cwd = cwd ?? firstString(object, keys: ["cwd", "workingDirectory", "working_directory", "workspace", "projectPath"])
            model = model ?? firstString(object, keys: ["model", "modelName"])
            branch = branch ?? firstString(object, keys: ["git_branch", "gitBranch", "branch"])
            if let text = text(from: object) {
                let normalizedSessionID = "\(kind.rawValue):\(sessionID)"
                let role = firstString(object, keys: ["role", "type", "author"]) ?? "message"
                turns.append(VaultTranscriptTurn(
                    sessionID: normalizedSessionID,
                    turnID: firstString(object, keys: ["id", "turnID", "messageID"]) ?? "\(index)",
                    role: role,
                    text: text,
                    ordinal: index,
                    modifiedAt: modified
                ))
            }
        }

        let displayTitle = title ?? turns.first(where: { $0.role.lowercased().contains("user") })?.text.firstLine(maxLength: 80) ?? file.deletingPathExtension().lastPathComponent
        let resume = configuration.resumeCommand(for: kind, sessionID: sessionID)
        let summary = VaultSessionSummary(
            id: "\(kind.rawValue):\(sessionID)",
            agent: kind,
            sourceKind: sourceKind,
            sourcePath: file.path,
            title: displayTitle,
            workingDirectory: cwd,
            model: model,
            gitBranch: branch,
            modifiedAt: modified,
            previewAvailable: turns.isEmpty == false,
            resumeAvailable: resume != nil
        )
        return VaultIndexedSession(
            summary: summary,
            resumeSnapshot: VaultResumeSnapshot(kind: kind, sessionID: sessionID, workingDirectory: cwd, resumeCommand: resume),
            turns: turns
        )
    }
}

public struct CopilotVaultAdapter: VaultAgentAdapter {
    public let kind: VaultAgentKind = .copilot
    public let root: URL
    private let configuration: VaultConfiguration

    public init(root: URL, configuration: VaultConfiguration) {
        self.root = root
        self.configuration = configuration
    }

    public func discoverSessions() async throws -> [VaultIndexedSession] {
        let stateRoot = root.appendingPathComponent("session-state", isDirectory: true)
        let stateSessions = SessionFileScanner.files(under: stateRoot, extensions: ["jsonl", "json"])
            .compactMap { parseStateFile($0) }
        let dbURL = root.appendingPathComponent("session-store.db", isDirectory: false)
        let dbSessions = SQLiteBackedVaultAdapter(
            kind: .copilot,
            root: root,
            databaseNames: [dbURL.lastPathComponent],
            sourceKind: "copilot_sqlite",
            configuration: configuration
        )
        let sqliteSessions = (try? await dbSessions.discoverSessions()) ?? []
        return mergePreferNewest(stateSessions + sqliteSessions)
    }

    private func parseStateFile(_ file: URL) -> VaultIndexedSession? {
        JSONLDirectoryVaultAdapter(
            kind: .copilot,
            root: file.deletingLastPathComponent(),
            sourceKind: "copilot_session_state",
            globHint: nil,
            configuration: configuration
        )
        .parse(file: file)
    }
}

public struct GeminiVaultAdapter: VaultAgentAdapter {
    public let kind: VaultAgentKind = .gemini
    public let root: URL
    private let configuration: VaultConfiguration

    public init(root: URL, configuration: VaultConfiguration) {
        self.root = root
        self.configuration = configuration
    }

    public func discoverSessions() async throws -> [VaultIndexedSession] {
        let tmpRoot = root.appendingPathComponent("tmp", isDirectory: true)
        let files = SessionFileScanner.files(under: tmpRoot, extensions: ["json"])
            .filter { $0.lastPathComponent == "logs.json" }
        return mergePreferNewest(files.flatMap { parseLogsFile($0) })
    }

    private func parseLogsFile(_ file: URL) -> [VaultIndexedSession] {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              let data = try? Data(contentsOf: file),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return []
        }

        let fallbackModified = attributes[.modificationDate] as? Date ?? Date()
        let projectName = file.deletingLastPathComponent().lastPathComponent
        let workingDirectory = inferredProjectPath(named: projectName)

        let grouped = Dictionary(grouping: rows) { row in
            firstString(row, keys: ["sessionId", "session_id", "id"]) ?? UUID().uuidString
        }

        return grouped.compactMap { sessionID, sessionRows in
            let sortedRows = sessionRows.sorted { lhs, rhs in
                let left = firstInt(lhs, keys: ["messageId", "message_id", "ordinal"]) ?? 0
                let right = firstInt(rhs, keys: ["messageId", "message_id", "ordinal"]) ?? 0
                return left < right
            }

            var latest: Date?
            let normalizedSessionID = "\(kind.rawValue):\(sessionID)"
            let turns = sortedRows.enumerated().compactMap { index, row -> VaultTranscriptTurn? in
                guard let text = text(from: row) else {
                    return nil
                }
                let modified = firstDate(row, keys: ["timestamp", "createdAt", "updatedAt"]) ?? fallbackModified
                latest = latest.map { max($0, modified) } ?? modified
                return VaultTranscriptTurn(
                    sessionID: normalizedSessionID,
                    turnID: firstString(row, keys: ["messageId", "message_id", "id"]) ?? "\(index)",
                    role: firstString(row, keys: ["type", "role", "author"]) ?? "message",
                    text: text,
                    ordinal: index,
                    modifiedAt: modified
                )
            }

            guard turns.isEmpty == false else {
                return nil
            }

            let title = turns.first(where: { $0.role.lowercased().contains("user") })?.text.firstLine(maxLength: 80)
                ?? turns.first?.text.firstLine(maxLength: 80)
                ?? sessionID
            let resume = configuration.resumeCommand(for: kind, sessionID: sessionID)
            let summary = VaultSessionSummary(
                id: normalizedSessionID,
                agent: kind,
                sourceKind: "gemini_logs",
                sourcePath: file.path,
                title: title,
                workingDirectory: workingDirectory,
                modifiedAt: latest ?? fallbackModified,
                previewAvailable: true,
                resumeAvailable: resume != nil
            )
            return VaultIndexedSession(
                summary: summary,
                resumeSnapshot: VaultResumeSnapshot(kind: kind, sessionID: sessionID, workingDirectory: workingDirectory, resumeCommand: resume),
                turns: turns
            )
        }
    }

    private func inferredProjectPath(named projectName: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent("projects", isDirectory: true).appendingPathComponent(projectName, isDirectory: true),
            home.appendingPathComponent("Developer", isDirectory: true).appendingPathComponent(projectName, isDirectory: true),
            home.appendingPathComponent("Documents", isDirectory: true).appendingPathComponent(projectName, isDirectory: true),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }?.path
    }
}

public struct SQLiteBackedVaultAdapter: VaultAgentAdapter {
    public let kind: VaultAgentKind
    public let root: URL
    public let databaseNames: [String]
    public let sourceKind: String
    private let configuration: VaultConfiguration

    public init(kind: VaultAgentKind, root: URL, databaseNames: [String], sourceKind: String, configuration: VaultConfiguration) {
        self.kind = kind
        self.root = root
        self.databaseNames = databaseNames
        self.sourceKind = sourceKind
        self.configuration = configuration
    }

    public func discoverSessions() async throws -> [VaultIndexedSession] {
        let candidates = databaseNames.map { root.appendingPathComponent($0, isDirectory: false) }
        guard let dbURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            return []
        }
        let copyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("omux-vault-\(kind.rawValue)-\(UUID().uuidString).sqlite")
        try backupSQLiteDatabase(from: dbURL, to: copyURL)
        defer { try? FileManager.default.removeItem(at: copyURL) }
        let db = try VaultSQLiteDatabase(url: copyURL)
        let tables = try db.query("SELECT name FROM sqlite_master WHERE type = 'table'") { sqliteText($0, 0) ?? "" }
        let table = ["threads", "sessions", "session"].first(where: tables.contains)
        guard let table else {
            return []
        }
        let columns = try db.query("PRAGMA table_info(\(table))") { sqliteText($0, 1) ?? "" }
        let idColumn = preferred(["id", "session_id", "sessionId"], in: columns)
        guard let idColumn else {
            return []
        }
        let titleColumn = preferred(["title", "name", "summary", "first_user_message"], in: columns)
        let cwdColumn = preferred(["cwd", "working_directory", "workingDirectory", "project_path"], in: columns)
        let modelColumn = preferred(["model", "model_name"], in: columns)
        let branchColumn = preferred(["git_branch", "branch"], in: columns)
        let updatedColumn = preferred(["updated_at_ms", "modified_at_ms", "updatedAt", "mtime"], in: columns)
        let selected = [
            idColumn,
            titleColumn,
            cwdColumn,
            modelColumn,
            branchColumn,
            updatedColumn,
        ].map { $0 ?? "NULL" }.joined(separator: ", ")
        return try db.query("SELECT \(selected) FROM \(table) LIMIT 10000") { statement in
            let sessionID = sqliteText(statement, 0) ?? UUID().uuidString
            let title = sqliteText(statement, 1)?.firstLine(maxLength: 80) ?? sessionID
            let cwd = sqliteText(statement, 2)
            let model = sqliteText(statement, 3)
            let branch = sqliteText(statement, 4)
            let modifiedAt: Date
            let rawTime = sqliteInt(statement, 5)
            if rawTime > 10_000_000_000 {
                modifiedAt = Date(timeIntervalSince1970: TimeInterval(rawTime) / 1000)
            } else if rawTime > 0 {
                modifiedAt = Date(timeIntervalSince1970: TimeInterval(rawTime))
            } else {
                let attributes = try? FileManager.default.attributesOfItem(atPath: dbURL.path)
                modifiedAt = attributes?[.modificationDate] as? Date ?? Date()
            }
            let resume = configuration.resumeCommand(for: kind, sessionID: sessionID)
            let summary = VaultSessionSummary(
                id: "\(kind.rawValue):\(sessionID)",
                agent: kind,
                sourceKind: sourceKind,
                sourcePath: dbURL.path,
                title: title,
                workingDirectory: cwd,
                model: model,
                gitBranch: branch,
                modifiedAt: modifiedAt,
                previewAvailable: title.isEmpty == false,
                resumeAvailable: resume != nil
            )
            let turn = VaultTranscriptTurn(
                sessionID: summary.id,
                turnID: "title",
                role: "summary",
                text: title,
                ordinal: 0,
                modifiedAt: modifiedAt
            )
            return VaultIndexedSession(
                summary: summary,
                resumeSnapshot: VaultResumeSnapshot(kind: kind, sessionID: sessionID, workingDirectory: cwd, resumeCommand: resume),
                turns: [turn]
            )
        }
    }
}

private enum SessionFileScanner {
    static func files(under root: URL, extensions: Set<String>) -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path),
              let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
              )
        else {
            return []
        }
        return enumerator.compactMap { item -> URL? in
            guard let url = item as? URL,
                  extensions.contains(url.pathExtension.lowercased()),
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            else {
                return nil
            }
            return url
        }
        .sorted { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left > right
        }
        .prefix(5000)
        .map { $0 }
    }
}

private func parseJSONObject(_ text: String) -> [String: Any]? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty == false,
          let data = trimmed.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        return nil
    }
    return object
}

private func firstString(_ object: [String: Any], keys: [String]) -> String? {
    for key in keys {
        if let value = object[key] as? String, value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return value
        }
        if let value = object[key] as? [String: Any],
           let nested = firstString(value, keys: ["text", "content", "value"]) {
            return nested
        }
    }
    return nil
}

private func firstInt(_ object: [String: Any], keys: [String]) -> Int? {
    for key in keys {
        if let value = object[key] as? Int {
            return value
        }
        if let value = object[key] as? NSNumber {
            return value.intValue
        }
        if let value = object[key] as? String, let intValue = Int(value) {
            return intValue
        }
    }
    return nil
}

private func firstDate(_ object: [String: Any], keys: [String]) -> Date? {
    for key in keys {
        guard let value = object[key] as? String else {
            continue
        }
        if let date = parseISO8601Date(value) {
            return date
        }
    }
    return nil
}

private func parseISO8601Date(_ value: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: value) {
        return date
    }
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: value)
}

private func text(from object: [String: Any]) -> String? {
    if let value = firstString(object, keys: ["text", "content", "message", "prompt", "response", "first_user_message"]) {
        return value
    }
    if let message = object["message"] as? [String: Any],
       let value = firstString(message, keys: ["content", "text"]) {
        return value
    }
    if let content = object["content"] as? [[String: Any]] {
        let joined = content.compactMap { firstString($0, keys: ["text", "content"]) }.joined(separator: "\n")
        return joined.isEmpty ? nil : joined
    }
    return nil
}

private func sessionID(from file: URL) -> String {
    if file.lastPathComponent == "events.jsonl" || file.lastPathComponent == "vscode.metadata.json" {
        return file.deletingLastPathComponent().lastPathComponent
    }
    let name = file.deletingPathExtension().lastPathComponent
    if name.hasPrefix("rollout-") {
        return String(name.dropFirst("rollout-".count))
    }
    return name
}

private func mergePreferNewest(_ sessions: [VaultIndexedSession]) -> [VaultIndexedSession] {
    var merged: [String: VaultIndexedSession] = [:]
    for session in sessions {
        if let existing = merged[session.summary.id],
           existing.summary.modifiedAt >= session.summary.modifiedAt {
            continue
        }
        merged[session.summary.id] = session
    }
    return Array(merged.values).sorted { $0.summary.modifiedAt > $1.summary.modifiedAt }
}

private func backupSQLiteDatabase(from sourceURL: URL, to destinationURL: URL) throws {
    try? FileManager.default.removeItem(at: destinationURL)
    var source: OpaquePointer?
    var destination: OpaquePointer?
    guard sqlite3_open_v2(sourceURL.path, &source, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
          let source
    else {
        let message = source.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open source SQLite database"
        if let source {
            sqlite3_close(source)
        }
        throw VaultSQLiteError.open(message)
    }
    defer { sqlite3_close(source) }

    guard sqlite3_open_v2(destinationURL.path, &destination, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
          let destination
    else {
        let message = destination.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open destination SQLite database"
        if let destination {
            sqlite3_close(destination)
        }
        throw VaultSQLiteError.open(message)
    }
    defer { sqlite3_close(destination) }

    guard let backup = sqlite3_backup_init(destination, "main", source, "main") else {
        throw VaultSQLiteError.step(String(cString: sqlite3_errmsg(destination)))
    }
    defer { sqlite3_backup_finish(backup) }

    let result = sqlite3_backup_step(backup, -1)
    guard result == SQLITE_DONE else {
        throw VaultSQLiteError.step(String(cString: sqlite3_errmsg(destination)))
    }
}

private func preferred(_ candidates: [String], in columns: [String]) -> String? {
    candidates.first { columns.contains($0) }
}

private extension String {
    func firstLine(maxLength: Int) -> String {
        let line = split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? self
        if line.count <= maxLength {
            return line
        }
        return String(line.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
