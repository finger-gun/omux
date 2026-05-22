import CSQLite
import Foundation
import OmuxConfig

public actor VaultStore {
    private let database: VaultSQLiteDatabase
    private let configuration: VaultConfiguration
    private let adapters: [VaultAgentAdapter]

    public init(
        databaseURL: URL = OmuxConfigPaths.vaultDatabaseURL,
        configuration: VaultConfiguration = VaultConfiguration(),
        adapters: [VaultAgentAdapter]? = nil
    ) throws {
        self.database = try VaultSQLiteDatabase(url: databaseURL)
        self.configuration = configuration
        self.adapters = adapters ?? VaultAdapterFactory.adapters(configuration: configuration)
    }

    public func reindex(agent filter: VaultAgentKind? = nil) async throws -> [String] {
        guard configuration.enabled else {
            return ["Agent Sessions are disabled."]
        }

        var warnings: [String] = []
        for adapter in adapters {
            let isInScope = filter == nil || filter == adapter.kind
            guard isInScope else {
                continue
            }
            let isActive = (adapter.isExternal || configuration.includedAgents.contains(adapter.kind))
            do {
                let visibleSessions: [VaultIndexedSession]
                if isActive {
                    let sessions = try await adapter.discoverSessions()
                    visibleSessions = sessions.filter { shouldExclude($0.summary) == false }
                } else {
                    visibleSessions = []
                }
                let indexedSourceKinds = Set(visibleSessions.map(\.summary.sourceKind))
                try database.inTransaction {
                    for session in visibleSessions {
                        try upsert(session.summary)
                    }
                    try cleanupObsoleteSourceKinds(for: adapter.kind, indexedSourceKinds: indexedSourceKinds)
                    for prefix in adapter.sourceKindPrefixes where prefix.isEmpty == false {
                        try cleanupObsoleteSourceKindPrefixes(
                            for: adapter.kind,
                            prefix: prefix,
                            indexedSourceKinds: indexedSourceKinds
                        )
                    }
                }
            } catch {
                warnings.append("\(adapter.kind.rawValue): \(error)")
            }
        }
        return warnings
    }

    public func list(limit: Int = 100, offset: Int = 0) throws -> VaultSearchResponse {
        try search(VaultSearchRequest(query: "", offset: offset, limit: limit))
    }

    public func availableAgents() throws -> [VaultAgentKind] {
        try database.query(
            """
            SELECT s.agent
            FROM agent_sessions s
            WHERE \(Self.visibleSessionWhereClause)
            GROUP BY s.agent
            ORDER BY MAX(s.updated_at_ms) DESC
            """
        ) { statement in
            sqliteText(statement, 0).flatMap(VaultAgentKind.init(rawValue:))
        }.compactMap { $0 }
    }

    public func search(_ request: VaultSearchRequest) throws -> VaultSearchResponse {
        let trimmed = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        var bindings: [SQLiteBinding] = []
        var whereClauses: [String] = [Self.visibleSessionWhereClause]

        if let agents = request.agents, agents.isEmpty == false {
            let placeholders = agents.map { _ in "?" }.joined(separator: ", ")
            whereClauses.append("s.agent IN (\(placeholders))")
            bindings += agents.map { .string($0.rawValue) }
        }
        if let workingDirectory = request.workingDirectory, workingDirectory.isEmpty == false {
            whereClauses.append("s.cwd = ?")
            bindings.append(.string(workingDirectory))
        }
        if let prefixes = request.workingDirectoryPrefixes?.filter({ $0.isEmpty == false }), prefixes.isEmpty == false {
            let prefixClauses = prefixes.map { _ in
                "(s.cwd = ? OR s.cwd LIKE ? ESCAPE '\\')"
            }.joined(separator: " OR ")
            whereClauses.append("(\(prefixClauses))")
            for prefix in prefixes {
                bindings.append(.string(prefix))
                bindings.append(.string(sqlLikeEscaped(prefix) + "/%"))
            }
        }
        if trimmed.isEmpty == false {
            let searchTokens = searchTokens(for: trimmed)
            guard searchTokens.isEmpty == false else {
                return VaultSearchResponse(sessions: [], totalCount: 0)
            }
            let metadataClauses = searchTokens.map { _ in
                """
                (
                  s.title LIKE ? ESCAPE '\\'
                  OR s.agent LIKE ? ESCAPE '\\'
                  OR s.cwd LIKE ? ESCAPE '\\'
                  OR s.id LIKE ? ESCAPE '\\'
                  OR s.raw_id LIKE ? ESCAPE '\\'
                )
                """
            }.joined(separator: " AND ")
            whereClauses.append(metadataClauses)
            bindings += searchTokens.flatMap { token -> [SQLiteBinding] in
                let pattern = searchLikePattern(for: token)
                return [.string(pattern), .string(pattern), .string(pattern), .string(pattern), .string(pattern)]
            }
        }

        let baseWhere = "WHERE " + whereClauses.joined(separator: " AND ")
        let total = try count("SELECT COUNT(*) FROM agent_sessions s \(baseWhere)", bindings: bindings)
        let rows = try database.query(
            """
            SELECT s.id, s.agent, s.source_kind, s.source_path, s.title, s.cwd, s.updated_at_ms
            FROM agent_sessions s
            \(baseWhere)
            ORDER BY s.updated_at_ms DESC
            LIMIT ? OFFSET ?
            """,
            bindings: bindings + [.int(Int64(request.limit)), .int(Int64(request.offset))],
            row: decodeSummary
        )
        return VaultSearchResponse(sessions: rows, totalCount: total)
    }

    public func preview(sessionID: String, maxBytes: Int? = nil) throws -> VaultPreview? {
        guard let session = try session(id: sessionID) else {
            return nil
        }
        return VaultPreview(session: session, turns: [], truncated: false)
    }

    public func resumeSnapshot(sessionID: String) throws -> VaultResumeSnapshot? {
        guard let session = try session(id: sessionID) else {
            return nil
        }
        let rawID = Self.rawSessionID(session.id)
        return VaultResumeSnapshot(
            kind: session.agent,
            sessionID: rawID,
            workingDirectory: session.workingDirectory,
            resumeCommand: resumeCommand(for: session.agent, sessionID: rawID, sourceKind: session.sourceKind)
        )
    }

    public func export(ids: [String]) throws -> Data {
        var seenIDs = Set<String>()
        let uniqueIds = ids.filter { seenIDs.insert($0).inserted }
        let sessions = try uniqueIds.compactMap { try session(id: $0) }
        return try JSONEncoder.agentSessions.encode(VaultExportBundle(sessions: sessions, resumeSnapshots: [:], turns: [:]))
    }

    public func `import`(data: Data) throws {
        let bundle = try JSONDecoder.agentSessions.decode(VaultExportBundle.self, from: data)
        for session in bundle.sessions {
            try upsert(session, preserveDeleted: false)
        }
    }

    public func delete(sessionID: String) throws {
        try database.write(
            "UPDATE agent_sessions SET deleted = 1 WHERE id = ?",
            bindings: [.string(sessionID)]
        )
    }

    private static let visibleSessionWhereClause = """
    s.deleted = 0
    AND s.title NOT GLOB '????????-????-????-????-????????????'
    """

    private func upsert(_ summary: VaultSessionSummary, preserveDeleted: Bool = true) throws {
        let deleted = preserveDeleted ? (try existingDeletedValue(for: summary.id)) : 0
        try database.write(
            """
            INSERT OR REPLACE INTO agent_sessions
            (id, raw_id, agent, source_kind, source_path, cwd, title, updated_at_ms, deleted, indexed_at_ms)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .string(summary.id),
                .string(Self.rawSessionID(summary.id)),
                .string(summary.agent.rawValue),
                .string(summary.sourceKind),
                summary.sourcePath.map(SQLiteBinding.string) ?? .null,
                summary.workingDirectory.map(SQLiteBinding.string) ?? .null,
                .string(summary.title),
                .int(Int64(summary.modifiedAt.timeIntervalSince1970 * 1000)),
                .int(deleted),
                .int(Int64(Date().timeIntervalSince1970 * 1000)),
            ]
        )
    }

    private func session(id: String) throws -> VaultSessionSummary? {
        try database.query(
            """
            SELECT s.id, s.agent, s.source_kind, s.source_path, s.title, s.cwd, s.updated_at_ms
            FROM agent_sessions s
            WHERE s.id = ? AND s.deleted = 0
            """,
            bindings: [.string(id)],
            row: decodeSummary
        ).first
    }

    private static func rawSessionID(_ id: String) -> String {
        guard let separator = id.firstIndex(of: ":") else {
            return id
        }
        return String(id[id.index(after: separator)...])
    }

    private func existingDeletedValue(for sessionID: String) throws -> Int64 {
        try database.query(
            "SELECT deleted FROM agent_sessions WHERE id = ?",
            bindings: [.string(sessionID)]
        ) { statement in
            sqliteInt(statement, 0)
        }.first ?? 0
    }

    private func cleanupObsoleteSourceKinds(for agent: VaultAgentKind, indexedSourceKinds: Set<String>) throws {
        switch agent {
        case .copilot:
            if indexedSourceKinds.contains("copilot_sqlite") {
                try database.write(
                    "DELETE FROM agent_sessions WHERE agent = ? AND source_kind = ?",
                    bindings: [.string(agent.rawValue), .string("copilot_session_state")]
                )
            }
        case .codex:
            if indexedSourceKinds.contains("codex_sqlite") {
                try database.write(
                    "DELETE FROM agent_sessions WHERE agent = ? AND source_kind = ?",
                    bindings: [.string(agent.rawValue), .string("codex_jsonl")]
                )
            }
        default:
            break
        }
    }

    private func cleanupObsoleteSourceKindPrefixes(for agent: VaultAgentKind, prefix: String, indexedSourceKinds: Set<String>) throws {
        let indexed = indexedSourceKinds.filter { $0.hasPrefix(prefix) }
        if indexed.isEmpty {
            try database.write(
                "DELETE FROM agent_sessions WHERE agent = ? AND source_kind LIKE ? ESCAPE '\\'",
                bindings: [.string(agent.rawValue), .string(sqlLikeEscaped(prefix) + "%")]
            )
            return
        }
        let placeholders = indexed.map { _ in "?" }.joined(separator: ", ")
        var bindings: [SQLiteBinding] = [
            .string(agent.rawValue),
            .string(sqlLikeEscaped(prefix) + "%"),
        ]
        bindings += indexed.map(SQLiteBinding.string)
        try database.write(
            """
            DELETE FROM agent_sessions
            WHERE agent = ?
              AND source_kind LIKE ? ESCAPE '\\'
              AND source_kind NOT IN (\(placeholders))
            """,
            bindings: bindings
        )
    }

    private func count(_ sql: String, bindings: [SQLiteBinding]) throws -> Int {
        try database.query(sql, bindings: bindings) { statement in
            Int(sqliteInt(statement, 0))
        }.first ?? 0
    }

    private func decodeSummary(_ statement: OpaquePointer) throws -> VaultSessionSummary {
        let agent = sqliteText(statement, 1).flatMap(VaultAgentKind.init(rawValue:)) ?? .custom
        let rawID = Self.rawSessionID(sqliteText(statement, 0) ?? "")
        return VaultSessionSummary(
            id: sqliteText(statement, 0) ?? "",
            agent: agent,
            sourceKind: sqliteText(statement, 2) ?? "",
            sourcePath: sqliteText(statement, 3),
            title: sqliteText(statement, 4) ?? "Untitled",
            workingDirectory: sqliteText(statement, 5),
            modifiedAt: Date(timeIntervalSince1970: TimeInterval(sqliteInt(statement, 6)) / 1000),
            previewAvailable: false,
            resumeAvailable: resumeCommand(for: agent, sessionID: rawID, sourceKind: sqliteText(statement, 2)) != nil
        )
    }

    private func resumeCommand(for agent: VaultAgentKind, sessionID: String, sourceKind: String?) -> String? {
        if let sourceKind,
           let sourceMatchedAdapter = adapters.first(where: { adapter in
               adapter.sourceKindPrefixes.contains(where: { prefix in
                   prefix.isEmpty == false && sourceKind.hasPrefix(prefix)
               })
           }),
           let template = sourceMatchedAdapter.resumeCommandTemplate {
            return template.replacingOccurrences(of: "{session_id}", with: shellQuoted(sessionID))
        }

        if let command = configuration.resumeCommand(for: agent, sessionID: sessionID) {
            return command
        }
        let adapter = adapters.first { $0.kind == agent }
        guard let template = adapter?.resumeCommandTemplate else {
            return nil
        }
        return template.replacingOccurrences(of: "{session_id}", with: shellQuoted(sessionID))
    }

    private func shouldExclude(_ summary: VaultSessionSummary) -> Bool {
        guard let path = summary.sourcePath ?? summary.workingDirectory else {
            return false
        }
        let normalizedPath = URL(fileURLWithPath: expandHome(path)).standardized.path
        return configuration.excludedPaths.contains { excluded in
            let excludedPath = URL(fileURLWithPath: expandHome(excluded)).standardized.path
            return normalizedPath == excludedPath || normalizedPath.hasPrefix(excludedPath + "/")
        }
    }
}

private func searchTokens(for raw: String) -> [String] {
    raw
        .split { character in
            character.isLetter == false && character.isNumber == false
        }
        .map(String.init)
        .filter { $0.isEmpty == false }
}

private func searchLikePattern(for raw: String) -> String {
    "%\(sqlLikeEscaped(raw))%"
}

private func sqlLikeEscaped(_ raw: String) -> String {
    raw
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "%", with: "\\%")
        .replacingOccurrences(of: "_", with: "\\_")
}

private func expandHome(_ path: String) -> String {
    if path == "~" {
        return FileManager.default.homeDirectoryForCurrentUser.path
    }
    if path.hasPrefix("~/") {
        return FileManager.default.homeDirectoryForCurrentUser.path + String(path.dropFirst())
    }
    return path
}

private func shellQuoted(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

extension JSONEncoder {
    static var agentSessions: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

extension JSONDecoder {
    static var agentSessions: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
