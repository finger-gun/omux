import CSQLite
import Foundation

public protocol VaultAgentAdapter: Sendable {
    var kind: VaultAgentKind { get }
    func discoverSessions() async throws -> [VaultIndexedSession]
}

public enum VaultAdapterFactory {
    public static func adapters(configuration: VaultConfiguration) -> [VaultAgentAdapter] {
        [
            CopilotVaultAdapter(root: configuration.home(for: .copilot), configuration: configuration),
            CodexVaultAdapter(root: configuration.home(for: .codex), configuration: configuration),
            GeminiVaultAdapter(root: configuration.home(for: .gemini), configuration: configuration),
            JSONLDirectoryVaultAdapter(kind: .claude, root: configuration.home(for: .claude), sourceKind: "claude_jsonl", globHint: "projects", configuration: configuration),
            SQLiteBackedVaultAdapter(kind: .opencode, root: configuration.home(for: .opencode), databaseNames: ["opencode.db", "state.db", "db.sqlite"], sourceKind: "opencode_db", configuration: configuration),
            JSONLDirectoryVaultAdapter(kind: .pi, root: configuration.home(for: .pi), sourceKind: "pi_jsonl", globHint: nil, configuration: configuration),
            JSONLDirectoryVaultAdapter(kind: .rovodev, root: configuration.home(for: .rovodev), sourceKind: "rovodev_jsonl", globHint: nil, configuration: configuration),
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
        let sqlite = SQLiteBackedVaultAdapter(
            kind: .codex,
            root: root,
            databaseNames: ["state_5.sqlite", "state_4.sqlite", "state.sqlite", "sqlite/codex-dev.db"],
            sourceKind: "codex_sqlite",
            configuration: configuration
        )
        let sqliteSessions = (try? await sqlite.discoverSessions()) ?? []
        if sqliteSessions.isEmpty == false {
            return sqliteSessions
        }
        let jsonl = JSONLDirectoryVaultAdapter(
            kind: .codex,
            root: root,
            sourceKind: "codex_jsonl",
            globHint: "sessions",
            configuration: configuration
        )
        return (try? await jsonl.discoverSessions()) ?? []
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
        let sessionID = normalizedSessionID(from: file, kind: kind)
        let lines = (try? String(contentsOf: file, encoding: .utf8))?.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) ?? []
        var title: String?
        var cwd: String?
        var model: String?
        var branch: String?
        var firstUserText: String?
        var firstMessageText: String?

        for line in lines {
            guard let object = parseJSONObject(line) else { continue }
            title = title ?? firstString(object, keys: ["title", "summary", "name"])
            cwd = cwd ?? firstString(object, keys: ["cwd", "workingDirectory", "working_directory", "workspace", "projectPath"])
            model = model ?? firstString(object, keys: ["model", "modelName"])
            branch = branch ?? firstString(object, keys: ["git_branch", "gitBranch", "branch"])
            if let text = text(from: object) {
                let role = firstString(object, keys: ["role", "type", "author"]) ?? "message"
                firstMessageText = firstMessageText ?? text
                if role.lowercased().contains("user") {
                    firstUserText = firstUserText ?? text
                }
            }
        }

        let displayTitle = title ?? firstUserText?.firstLine(maxLength: 80) ?? firstMessageText?.firstLine(maxLength: 80) ?? file.deletingPathExtension().lastPathComponent
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
            previewAvailable: false,
            resumeAvailable: configuration.resumeCommand(for: kind, sessionID: sessionID) != nil
        )
        return VaultIndexedSession(
            summary: summary,
            resumeSnapshot: nil,
            turns: []
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
        let dbURL = root.appendingPathComponent("session-store.db", isDirectory: false)
        return (try? discoverSessionStore(dbURL: dbURL)) ?? []
    }

    private func discoverSessionStore(dbURL: URL) throws -> [VaultIndexedSession] {
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            return []
        }
        let db = try ExternalSQLiteDatabase(url: dbURL)
        let tables = try db.query("SELECT name FROM sqlite_master WHERE type = 'table'") { sqliteText($0, 0) ?? "" }
        guard tables.contains("sessions") else {
            return []
        }
        let sessionColumns = try db.query("PRAGMA table_info(sessions)") { sqliteText($0, 1) ?? "" }
        guard let idColumn = preferred(["id", "session_id", "sessionId"], in: sessionColumns) else {
            return []
        }
        let titleColumn = preferred(["summary", "title", "name"], in: sessionColumns)
        let cwdColumn = preferred(["cwd", "working_directory", "workingDirectory", "repo_path", "repository"], in: sessionColumns)
        let modelColumn = preferred(["model", "model_name"], in: sessionColumns)
        let branchColumn = preferred(["git_branch", "branch"], in: sessionColumns)
        let updatedColumn = preferred(["updated_at", "updatedAt", "modified_at", "modifiedAt", "created_at", "createdAt"], in: sessionColumns)

        let qIDColumn = sqliteIdentifier(idColumn)
        let qTitleColumn = titleColumn.map(sqliteIdentifier)
        let qCwdColumn = cwdColumn.map(sqliteIdentifier)
        let qModelColumn = modelColumn.map(sqliteIdentifier)
        let qBranchColumn = branchColumn.map(sqliteIdentifier)
        let qUpdatedColumn = updatedColumn.map(sqliteIdentifier)

        let selected = [
            "s.\(qIDColumn)",
            qTitleColumn.map { "s.\($0)" } ?? "NULL",
            qCwdColumn.map { "s.\($0)" } ?? "NULL",
            qModelColumn.map { "s.\($0)" } ?? "NULL",
            qBranchColumn.map { "s.\($0)" } ?? "NULL",
            qUpdatedColumn.map { "s.\($0)" } ?? "NULL",
        ].joined(separator: ", ")
        let order = qUpdatedColumn.map { " ORDER BY s.\($0) DESC" } ?? ""

        return try db.query("SELECT \(selected) FROM sessions s\(order) LIMIT 10000") { statement in
            let sessionID = sqliteText(statement, 0) ?? UUID().uuidString
            let title = sqliteText(statement, 1)?.firstLine(maxLength: 80).nilIfEmpty ?? "Untitled Copilot Session"
            let rawTimestampText = sqliteText(statement, 5)
            let modifiedAt = parseTimestampDate(rawNumeric: sqliteInt(statement, 5), rawText: rawTimestampText)
                ?? ((try? FileManager.default.attributesOfItem(atPath: dbURL.path))?[.modificationDate] as? Date)
                ?? Date()
            let summary = VaultSessionSummary(
                id: "\(kind.rawValue):\(sessionID)",
                agent: kind,
                sourceKind: "copilot_sqlite",
                sourcePath: dbURL.path,
                title: title,
                workingDirectory: sqliteText(statement, 2),
                model: sqliteText(statement, 3),
                gitBranch: sqliteText(statement, 4),
                modifiedAt: modifiedAt,
                previewAvailable: title.isEmpty == false,
                resumeAvailable: configuration.resumeCommand(for: kind, sessionID: sessionID) != nil
            )
            return VaultIndexedSession(
                summary: summary,
                resumeSnapshot: nil,
                turns: []
            )
        }
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
        let chatFiles = SessionFileScanner.files(under: tmpRoot, extensions: ["jsonl"], limit: 500)
            .filter { $0.deletingLastPathComponent().lastPathComponent == "chats" }
        let chatSessions = mergePreferNewest(chatFiles.compactMap { parseChatFile($0) })
        if chatSessions.isEmpty == false {
            return chatSessions
        }

        let files = SessionFileScanner.files(under: tmpRoot, extensions: ["json"])
            .filter { $0.lastPathComponent == "logs.json" }
        return mergePreferNewest(files.flatMap { parseLogsFile($0) })
    }

    private func parseChatFile(_ file: URL) -> VaultIndexedSession? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              let content = try? String(contentsOf: file, encoding: .utf8)
        else {
            return nil
        }

        let fallbackModified = attributes[.modificationDate] as? Date ?? Date()
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        var discoveredSessionID: String?
        var title: String?
        var latest: Date?
        var firstUserText: String?
        var firstMessageText: String?

        for line in lines {
            guard let object = parseJSONObject(line) else { continue }
            discoveredSessionID = discoveredSessionID ?? firstString(object, keys: ["sessionId", "session_id", "id"])
            if let set = object["$set"] as? [String: Any],
               let updated = firstDate(set, keys: ["lastUpdated", "updatedAt", "updated_at"]) {
                latest = latest.map { max($0, updated) } ?? updated
            }
            if let updated = firstDate(object, keys: ["lastUpdated", "updatedAt", "updated_at", "timestamp", "createdAt", "created_at"]) {
                latest = latest.map { max($0, updated) } ?? updated
            }
            guard let text = text(from: object) else { continue }
            let role = firstString(object, keys: ["type", "role", "author"]) ?? "message"
            firstMessageText = firstMessageText ?? text
            if role.lowercased().contains("user") {
                firstUserText = firstUserText ?? text
            }
        }

        let rawID = discoveredSessionID ?? sessionID(from: file)
        title = firstUserText?.firstLine(maxLength: 80) ?? firstMessageText?.firstLine(maxLength: 80) ?? rawID
        let workingDirectory = geminiProjectRoot(forChatFile: file)
        let summary = VaultSessionSummary(
            id: "\(kind.rawValue):\(rawID)",
            agent: kind,
            sourceKind: "gemini_jsonl",
            sourcePath: file.path,
            title: title ?? rawID,
            workingDirectory: workingDirectory,
            modifiedAt: latest ?? fallbackModified,
            previewAvailable: false,
            resumeAvailable: configuration.resumeCommand(for: kind, sessionID: rawID) != nil
        )
        return VaultIndexedSession(summary: summary, resumeSnapshot: nil, turns: [])
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
            var firstUserText: String?
            var firstMessageText: String?
            for row in sortedRows {
                guard let text = text(from: row) else { continue }
                let modified = firstDate(row, keys: ["timestamp", "createdAt", "updatedAt"]) ?? fallbackModified
                latest = latest.map { max($0, modified) } ?? modified
                let role = firstString(row, keys: ["type", "role", "author"]) ?? "message"
                firstMessageText = firstMessageText ?? text
                if role.lowercased().contains("user") {
                    firstUserText = firstUserText ?? text
                }
            }

            guard firstMessageText != nil else {
                return nil
            }

            let title = firstUserText?.firstLine(maxLength: 80)
                ?? firstMessageText?.firstLine(maxLength: 80)
                ?? sessionID
            let summary = VaultSessionSummary(
                id: normalizedSessionID,
                agent: kind,
                sourceKind: "gemini_logs",
                sourcePath: file.path,
                title: title,
                workingDirectory: workingDirectory,
                modifiedAt: latest ?? fallbackModified,
                previewAvailable: false,
                resumeAvailable: configuration.resumeCommand(for: kind, sessionID: sessionID) != nil
            )
            return VaultIndexedSession(
                summary: summary,
                resumeSnapshot: nil,
                turns: []
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

    private func geminiProjectRoot(forChatFile file: URL) -> String? {
        let projectDirectory = file
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let projectRootFile = projectDirectory.appendingPathComponent(".project_root")
        if let path = try? String(contentsOf: projectRootFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           path.isEmpty == false {
            return NSString(string: path).expandingTildeInPath
        }
        return inferredProjectPath(named: projectDirectory.lastPathComponent)
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
        for dbURL in candidates where FileManager.default.fileExists(atPath: dbURL.path) {
            let sessions = (try? discoverSessions(in: dbURL)) ?? []
            if sessions.isEmpty == false {
                return sessions
            }
        }
        return []
    }

    private func discoverSessions(in dbURL: URL) throws -> [VaultIndexedSession] {
        let db = try ExternalSQLiteDatabase(url: dbURL)
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
        let updatedColumn = preferred(["updated_at_ms", "modified_at_ms", "updatedAt", "updated_at", "modifiedAt", "modified_at", "createdAt", "created_at", "timestamp", "mtime"], in: columns)
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
            if let parsedDate = parseTimestampDate(rawNumeric: sqliteInt(statement, 5), rawText: sqliteText(statement, 5)) {
                modifiedAt = parsedDate
            } else {
                let attributes = try? FileManager.default.attributesOfItem(atPath: dbURL.path)
                modifiedAt = attributes?[.modificationDate] as? Date ?? Date()
            }
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
                resumeAvailable: configuration.resumeCommand(for: kind, sessionID: sessionID) != nil
            )
            return VaultIndexedSession(
                summary: summary,
                resumeSnapshot: nil,
                turns: []
            )
        }
    }
}

private enum SessionFileScanner {
    static func files(under root: URL, extensions: Set<String>, limit: Int = 5000) -> [URL] {
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
        .prefix(limit)
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

private func parseTimestampDate(rawNumeric: Int64, rawText: String?) -> Date? {
    if let rawText = rawText?.trimmingCharacters(in: .whitespacesAndNewlines),
       rawText.isEmpty == false {
        if let isoDate = parseISO8601Date(rawText) {
            return isoDate
        }
        if let numericDate = Double(rawText), numericDate > 0 {
            return dateFromUnixTimestamp(numericDate)
        }
    }
    if rawNumeric > 0 {
        return dateFromUnixTimestamp(Double(rawNumeric))
    }
    return nil
}

private func dateFromUnixTimestamp(_ value: Double) -> Date {
    if value > 10_000_000_000 {
        return Date(timeIntervalSince1970: value / 1000)
    }
    return Date(timeIntervalSince1970: value)
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

private func normalizedSessionID(from file: URL, kind: VaultAgentKind) -> String {
    let rawID = sessionID(from: file)
    guard kind == .codex else {
        return rawID
    }
    let uuidLength = 36
    guard rawID.count > uuidLength else {
        return rawID
    }
    let suffix = String(rawID.suffix(uuidLength))
    guard UUID(uuidString: suffix) != nil else {
        return rawID
    }
    return suffix
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

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
