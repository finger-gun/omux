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
            return ["Vault is disabled."]
        }
        var warnings: [String] = []
        let activeAdapters = adapters.filter { adapter in
            configuration.includedAgents.contains(adapter.kind) && (filter == nil || filter == adapter.kind)
        }
        for adapter in activeAdapters {
            do {
                let sessions = try await adapter.discoverSessions()
                for session in sessions {
                    if shouldExclude(session.summary) {
                        continue
                    }
                    try upsert(session)
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
            whereClauses.append("s.working_directory = ?")
            bindings.append(.string(workingDirectory))
        }

        let baseWhere = whereClauses.isEmpty ? "" : "WHERE " + whereClauses.joined(separator: " AND ")
        let rows: [VaultSessionSummary]
        let total: Int

        if trimmed.isEmpty {
            total = try count("SELECT COUNT(*) FROM vault_sessions s \(baseWhere)", bindings: bindings)
            rows = try database.query(
                """
                SELECT s.id, s.agent, s.source_kind, s.source_path, s.title, s.working_directory, s.model,
                       s.git_branch, s.pr_url, s.modified_at_ms, s.preview_available, s.resume_available
                FROM vault_sessions s
                \(baseWhere)
                ORDER BY s.modified_at_ms DESC
                LIMIT ? OFFSET ?
                """,
                bindings: bindings + [.int(Int64(request.limit)), .int(Int64(request.offset))],
                row: decodeSummary
            )
        } else {
            guard let ftsQuery = ftsQuery(for: trimmed) else {
                return VaultSearchResponse(sessions: [], totalCount: 0)
            }
            let ftsWhere = baseWhere.isEmpty ? "WHERE vault_messages_fts MATCH ?" : "\(baseWhere) AND vault_messages_fts MATCH ?"
            let ftsBindings = bindings + [.string(ftsQuery)]
            total = try count(
                """
                SELECT COUNT(DISTINCT s.id)
                FROM vault_sessions s
                JOIN vault_messages m ON m.session_id = s.id
                JOIN vault_messages_fts ON vault_messages_fts.rowid = m.rowid
                \(ftsWhere)
                """,
                bindings: ftsBindings
            )
            rows = try database.query(
                """
                SELECT DISTINCT s.id, s.agent, s.source_kind, s.source_path, s.title, s.working_directory, s.model,
                       s.git_branch, s.pr_url, s.modified_at_ms, s.preview_available, s.resume_available
                FROM vault_sessions s
                JOIN vault_messages m ON m.session_id = s.id
                JOIN vault_messages_fts ON vault_messages_fts.rowid = m.rowid
                \(ftsWhere)
                ORDER BY s.modified_at_ms DESC
                LIMIT ? OFFSET ?
                """,
                bindings: ftsBindings + [.int(Int64(request.limit)), .int(Int64(request.offset))],
                row: decodeSummary
            )
        }
        return VaultSearchResponse(sessions: rows, totalCount: total)
    }

    private static let visibleSessionWhereClause = """
    s.title NOT GLOB '????????-????-????-????-????????????'
    """

    public func preview(sessionID: String, maxBytes: Int? = nil) throws -> VaultPreview? {
        guard let session = try session(id: sessionID) else {
            return nil
        }
        var totalBytes = 0
        let limitBytes = maxBytes ?? configuration.maxPreviewBytes
        var truncated = false
        var turns: [VaultTranscriptTurn] = []
        let rows = try database.query(
            """
            SELECT session_id, turn_id, role, text, ordinal, modified_at_ms
            FROM vault_messages
            WHERE session_id = ?
            ORDER BY ordinal ASC
            """,
            bindings: [.string(sessionID)]
        ) { statement in
            VaultTranscriptTurn(
                sessionID: sqliteText(statement, 0) ?? "",
                turnID: sqliteText(statement, 1) ?? "",
                role: sqliteText(statement, 2) ?? "",
                text: sqliteText(statement, 3) ?? "",
                ordinal: Int(sqliteInt(statement, 4)),
                modifiedAt: Date(timeIntervalSince1970: TimeInterval(sqliteInt(statement, 5)) / 1000)
            )
        }
        for row in rows {
            let size = row.text.utf8.count
            if totalBytes + size > limitBytes {
                truncated = true
                break
            }
            totalBytes += size
            turns.append(row)
        }
        return VaultPreview(session: session, turns: turns, truncated: truncated)
    }

    public func resumeSnapshot(sessionID: String) throws -> VaultResumeSnapshot? {
        let normalizedID = Self.rawSessionID(sessionID)
        return try database.query(
            """
            SELECT kind, session_id, working_directory, launch_command_json, resume_command, registration_id, metadata_json
            FROM vault_resume_snapshots
            WHERE session_id = ?
            """,
            bindings: [.string(normalizedID)]
        ) { statement in
            let kind = sqliteText(statement, 0).flatMap(VaultAgentKind.init(rawValue:)) ?? .custom
            let sessionID = sqliteText(statement, 1) ?? ""
            let launchCommand = decodeJSON([String].self, sqliteText(statement, 3))
            let metadata = decodeJSON([String: String].self, sqliteText(statement, 6)) ?? [:]
            return VaultResumeSnapshot(
                kind: kind,
                sessionID: sessionID,
                workingDirectory: sqliteText(statement, 2),
                launchCommand: launchCommand,
                resumeCommand: sqliteText(statement, 4),
                registrationID: sqliteText(statement, 5),
                metadata: metadata
            )
        }.first
    }

    public func export(ids: [String]) throws -> Data {
        var seenIDs = Set<String>()
        let uniqueIds = ids.filter { seenIDs.insert($0).inserted }
        let sessions = try uniqueIds.compactMap { try session(id: $0) }
        let snapshots = try Dictionary(uniqueKeysWithValues: uniqueIds.compactMap { id -> (String, VaultResumeSnapshot)? in
            guard let snapshot = try resumeSnapshot(sessionID: id) else { return nil }
            return (id, snapshot)
        })
        let turns = try Dictionary(uniqueKeysWithValues: uniqueIds.map { id in
            let preview = try preview(sessionID: id, maxBytes: Int.max)
            return (id, preview?.turns ?? [])
        })
        return try JSONEncoder.vault.encode(VaultExportBundle(sessions: sessions, resumeSnapshots: snapshots, turns: turns))
    }

    public func `import`(data: Data) throws {
        let bundle = try JSONDecoder.vault.decode(VaultExportBundle.self, from: data)
        for session in bundle.sessions {
            try database.inTransaction {
                try database.write(
                    """
                    INSERT OR REPLACE INTO vault_sessions
                    (id, agent, source_kind, source_path, working_directory, title, model, git_branch, pr_url,
                     modified_at_ms, preview_available, resume_available)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    bindings: summaryBindings(session)
                )
                if let snapshot = bundle.resumeSnapshots[session.id] {
                    try write(snapshot: snapshot)
                } else {
                    try deleteResumeSnapshot(sessionID: session.id)
                }
                try database.write("DELETE FROM vault_messages WHERE session_id = ?", bindings: [.string(session.id)])
                for turn in bundle.turns[session.id] ?? [] {
                    try write(turn: turn)
                }
                try database.write(
                    "INSERT OR REPLACE INTO vault_imported_sessions(session_id, imported_at_ms) VALUES (?, ?)",
                    bindings: [.string(session.id), .int(Int64(Date().timeIntervalSince1970 * 1000))]
                )
            }
        }
    }

    private func upsert(_ indexed: VaultIndexedSession) throws {
        try database.inTransaction {
            try database.write(
                """
                INSERT OR REPLACE INTO vault_sessions
                (id, agent, source_kind, source_path, working_directory, title, model, git_branch, pr_url,
                 modified_at_ms, preview_available, resume_available)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                bindings: summaryBindings(indexed.summary)
            )
            if let snapshot = indexed.resumeSnapshot {
                try write(snapshot: snapshot)
            } else {
                try deleteResumeSnapshot(sessionID: indexed.summary.id)
            }
            try database.write("DELETE FROM vault_messages WHERE session_id = ?", bindings: [.string(indexed.summary.id)])
            for turn in indexed.turns {
                try write(turn: turn)
            }
            if let sourcePath = indexed.summary.sourcePath {
                try database.write(
                    """
                    INSERT OR REPLACE INTO vault_source_state(source_key, agent, source_path, modified_at_ms, adapter_version)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    bindings: [
                        .string(indexed.summary.id),
                        .string(indexed.summary.agent.rawValue),
                        .string(sourcePath),
                        .int(Int64(indexed.summary.modifiedAt.timeIntervalSince1970 * 1000)),
                        .int(1),
                    ]
                )
            }
        }
    }

    private func write(snapshot: VaultResumeSnapshot) throws {
        try database.write(
            """
            INSERT OR REPLACE INTO vault_resume_snapshots
            (session_id, kind, working_directory, launch_command_json, resume_command, registration_id, metadata_json)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .string(snapshot.sessionID),
                .string(snapshot.kind.rawValue),
                snapshot.workingDirectory.map(SQLiteBinding.string) ?? .null,
                encodeJSON(snapshot.launchCommand).map(SQLiteBinding.string) ?? .null,
                snapshot.resumeCommand.map(SQLiteBinding.string) ?? .null,
                snapshot.registrationID.map(SQLiteBinding.string) ?? .null,
                .string(encodeJSON(snapshot.metadata) ?? "{}"),
            ]
        )
    }

    private func deleteResumeSnapshot(sessionID: String) throws {
        try database.write("DELETE FROM vault_resume_snapshots WHERE session_id = ?", bindings: [.string(sessionID)])
    }

    private func write(turn: VaultTranscriptTurn) throws {
        try database.write(
            """
            INSERT OR REPLACE INTO vault_messages
            (session_id, turn_id, role, text, ordinal, modified_at_ms)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .string(turn.sessionID),
                .string(turn.turnID),
                .string(turn.role),
                .string(turn.text),
                .int(Int64(turn.ordinal)),
                .int(Int64(turn.modifiedAt.timeIntervalSince1970 * 1000)),
            ]
        )
    }

    private func session(id: String) throws -> VaultSessionSummary? {
        try database.query(
            """
            SELECT id, agent, source_kind, source_path, title, working_directory, model,
                   git_branch, pr_url, modified_at_ms, preview_available, resume_available
            FROM vault_sessions
            WHERE id = ?
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

    private func count(_ sql: String, bindings: [SQLiteBinding]) throws -> Int {
        try database.query(sql, bindings: bindings) { statement in
            Int(sqliteInt(statement, 0))
        }.first ?? 0
    }

    private func decodeSummary(_ statement: OpaquePointer) throws -> VaultSessionSummary {
        let agent = sqliteText(statement, 1).flatMap(VaultAgentKind.init(rawValue:)) ?? .custom
        return VaultSessionSummary(
            id: sqliteText(statement, 0) ?? "",
            agent: agent,
            sourceKind: sqliteText(statement, 2) ?? "",
            sourcePath: sqliteText(statement, 3),
            title: sqliteText(statement, 4) ?? "Untitled",
            workingDirectory: sqliteText(statement, 5),
            model: sqliteText(statement, 6),
            gitBranch: sqliteText(statement, 7),
            prURL: sqliteText(statement, 8),
            modifiedAt: Date(timeIntervalSince1970: TimeInterval(sqliteInt(statement, 9)) / 1000),
            previewAvailable: sqliteInt(statement, 10) != 0,
            resumeAvailable: sqliteInt(statement, 11) != 0
        )
    }

    private func summaryBindings(_ summary: VaultSessionSummary) -> [SQLiteBinding] {
        [
            .string(summary.id),
            .string(summary.agent.rawValue),
            .string(summary.sourceKind),
            summary.sourcePath.map(SQLiteBinding.string) ?? .null,
            summary.workingDirectory.map(SQLiteBinding.string) ?? .null,
            .string(summary.title),
            summary.model.map(SQLiteBinding.string) ?? .null,
            summary.gitBranch.map(SQLiteBinding.string) ?? .null,
            summary.prURL.map(SQLiteBinding.string) ?? .null,
            .int(Int64(summary.modifiedAt.timeIntervalSince1970 * 1000)),
            .bool(summary.previewAvailable),
            .bool(summary.resumeAvailable),
        ]
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

private func ftsQuery(for raw: String) -> String? {
    let tokens = raw
        .split { character in
            character.isLetter == false && character.isNumber == false
        }
        .map(String.init)
        .filter { $0.isEmpty == false }
    guard tokens.isEmpty == false else {
        return nil
    }
    return tokens
        .map { token in
            let escaped = token.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        .joined(separator: " ")
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

private func encodeJSON<T: Encodable>(_ value: T?) -> String? {
    guard let value,
          let data = try? JSONEncoder.vault.encode(value)
    else {
        return nil
    }
    return String(data: data, encoding: .utf8)
}

private func decodeJSON<T: Decodable>(_ type: T.Type, _ string: String?) -> T? {
    guard let string, let data = string.data(using: .utf8) else {
        return nil
    }
    return try? JSONDecoder.vault.decode(type, from: data)
}

extension JSONEncoder {
    static var vault: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

extension JSONDecoder {
    static var vault: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
