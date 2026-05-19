import Foundation
import Testing
@testable import OmuxConfig
@testable import OmuxVault

@Suite("Vault")
struct OmuxVaultTests {
    @Test("JSONL adapter indexes normalized session and resume command")
    func jsonlAdapterIndexesSession() async throws {
        let root = try temporaryDirectory()
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let file = sessions.appendingPathComponent("rollout-abc123.jsonl")
        try """
        {"role":"user","content":"Implement Vault","cwd":"/tmp/project","model":"gpt-test","git_branch":"main"}
        {"role":"assistant","content":"Done"}
        """.write(to: file, atomically: true, encoding: .utf8)

        let store = try VaultStore(
            databaseURL: root.appendingPathComponent("agent-sessions.sqlite"),
            configuration: VaultConfiguration(enabled: true, includedAgents: [.codex]),
            adapters: [
                JSONLDirectoryVaultAdapter(
                    kind: .codex,
                    root: root,
                    sourceKind: "codex_jsonl",
                    globHint: "sessions",
                    configuration: VaultConfiguration(includedAgents: [.codex])
                ),
            ]
        )

        let warnings = try await store.reindex()
        #expect(warnings.isEmpty, "warnings: \(warnings)")
        let list = try await store.list()
        #expect(list.totalCount == 1, "list: \(list)")
        #expect(list.sessions.first?.agent == .codex)
        #expect(list.sessions.first?.workingDirectory == "/tmp/project")
        let preview = try await store.preview(sessionID: "codex:abc123")
        #expect(preview?.turns.isEmpty == true)
        let snapshot = try await store.resumeSnapshot(sessionID: "codex:abc123")
        #expect(snapshot?.resumeCommand == "codex resume 'abc123'")
    }

    @Test("Vault export and import preserves sessions")
    func exportImportPreservesSessions() async throws {
        let root = try temporaryDirectory()
        let source = try VaultStore(databaseURL: root.appendingPathComponent("source.sqlite"), configuration: VaultConfiguration())
        let bundle = VaultExportBundle(
            sessions: [
                VaultSessionSummary(
                    id: "copilot:one",
                    agent: .copilot,
                    sourceKind: "fixture",
                    title: "Copilot session",
                    workingDirectory: "/tmp",
                    modifiedAt: Date(timeIntervalSince1970: 1),
                    previewAvailable: true,
                    resumeAvailable: true
                ),
            ],
            resumeSnapshots: [:],
            turns: [:]
        )
        try await source.import(data: JSONEncoder.agentSessionsTest.encode(bundle))
        let data = try await source.export(ids: ["copilot:one"])

        let target = try VaultStore(databaseURL: root.appendingPathComponent("target.sqlite"), configuration: VaultConfiguration())
        try await target.import(data: data)
        let result = try await target.search(VaultSearchRequest(query: "copilot"))
        #expect(result.totalCount == 1)
        #expect(try await target.preview(sessionID: "copilot:one")?.turns.isEmpty == true)
    }

    @Test("Vault search can scope sessions by workspace path prefixes")
    func searchScopesByWorkspacePathPrefixes() async throws {
        let root = try temporaryDirectory()
        let store = try VaultStore(databaseURL: root.appendingPathComponent("agent-sessions.sqlite"), configuration: VaultConfiguration())
        let bundle = VaultExportBundle(
            sessions: [
                VaultSessionSummary(
                    id: "copilot:current-root",
                    agent: .copilot,
                    sourceKind: "fixture",
                    title: "Current root",
                    workingDirectory: "/tmp/omux",
                    modifiedAt: Date(timeIntervalSince1970: 3),
                    previewAvailable: false,
                    resumeAvailable: true
                ),
                VaultSessionSummary(
                    id: "copilot:current-child",
                    agent: .copilot,
                    sourceKind: "fixture",
                    title: "Current child",
                    workingDirectory: "/tmp/omux/Sources",
                    modifiedAt: Date(timeIntervalSince1970: 2),
                    previewAvailable: false,
                    resumeAvailable: true
                ),
                VaultSessionSummary(
                    id: "copilot:other",
                    agent: .copilot,
                    sourceKind: "fixture",
                    title: "Other",
                    workingDirectory: "/tmp/other",
                    modifiedAt: Date(timeIntervalSince1970: 1),
                    previewAvailable: false,
                    resumeAvailable: true
                ),
            ],
            resumeSnapshots: [:],
            turns: [:]
        )
        try await store.import(data: JSONEncoder.agentSessionsTest.encode(bundle))

        let result = try await store.search(VaultSearchRequest(workingDirectoryPrefixes: ["/tmp/omux"]))
        #expect(result.totalCount == 2)
        #expect(result.sessions.map(\.id) == ["copilot:current-root", "copilot:current-child"])
    }

    @Test("Vault hides UUID-only sessions from browse results")
    func hidesUUIDOnlySessionsFromBrowseResults() async throws {
        let root = try temporaryDirectory()
        let store = try VaultStore(databaseURL: root.appendingPathComponent("agent-sessions.sqlite"), configuration: VaultConfiguration())
        let bundle = VaultExportBundle(
            sessions: [
                VaultSessionSummary(
                    id: "copilot:empty",
                    agent: .copilot,
                    sourceKind: "fixture",
                    title: "20936e63-4f27-4f1b-b61b-1248b38b0000",
                    workingDirectory: "/tmp/project",
                    modifiedAt: Date(timeIntervalSince1970: 2),
                    previewAvailable: true,
                    resumeAvailable: true
                ),
                VaultSessionSummary(
                    id: "copilot:named",
                    agent: .copilot,
                    sourceKind: "fixture",
                    title: "Create release notes",
                    workingDirectory: "/tmp/project",
                    modifiedAt: Date(timeIntervalSince1970: 1),
                    previewAvailable: false,
                    resumeAvailable: true
                ),
            ],
            resumeSnapshots: [:],
            turns: [:]
        )
        try await store.import(data: JSONEncoder.agentSessionsTest.encode(bundle))

        let list = try await store.list()
        #expect(list.sessions.map(\.id) == ["copilot:named"])
        #expect(list.totalCount == 1)
        let search = try await store.search(VaultSearchRequest(query: "created"))
        #expect(search.sessions.isEmpty)
        #expect(search.totalCount == 0)
    }

    @Test("Vault search ignores punctuation-only FTS queries")
    func searchIgnoresPunctuationOnlyQueries() async throws {
        let root = try temporaryDirectory()
        let store = try VaultStore(databaseURL: root.appendingPathComponent("agent-sessions.sqlite"), configuration: VaultConfiguration())
        let bundle = VaultExportBundle(
            sessions: [
                VaultSessionSummary(
                    id: "codex:one",
                    agent: .codex,
                    sourceKind: "fixture",
                    title: "Implement parser",
                    workingDirectory: "/tmp/project",
                    modifiedAt: Date(timeIntervalSince1970: 1),
                    previewAvailable: true,
                    resumeAvailable: true
                ),
            ],
            resumeSnapshots: [:],
            turns: [:]
        )
        try await store.import(data: JSONEncoder.agentSessionsTest.encode(bundle))

        let result = try await store.search(VaultSearchRequest(query: "{"))

        #expect(result.sessions.isEmpty)
        #expect(result.totalCount == 0)
    }

    @Test("Vault search matches title prefixes")
    func searchMatchesTitlePrefixes() async throws {
        let root = try temporaryDirectory()
        let store = try VaultStore(databaseURL: root.appendingPathComponent("agent-sessions.sqlite"), configuration: VaultConfiguration())
        let bundle = VaultExportBundle(
            sessions: [
                VaultSessionSummary(
                    id: "codex:previous",
                    agent: .codex,
                    sourceKind: "fixture",
                    title: "A previous agent produced the plan below",
                    workingDirectory: "/tmp/omux",
                    modifiedAt: Date(timeIntervalSince1970: 2),
                    previewAvailable: true,
                    resumeAvailable: true
                ),
                VaultSessionSummary(
                    id: "gemini:hello",
                    agent: .gemini,
                    sourceKind: "fixture",
                    title: "hello",
                    workingDirectory: "/tmp/omux",
                    modifiedAt: Date(timeIntervalSince1970: 1),
                    previewAvailable: true,
                    resumeAvailable: true
                ),
            ],
            resumeSnapshots: [:],
            turns: [:]
        )
        try await store.import(data: JSONEncoder.agentSessionsTest.encode(bundle))

        let prefix = try await store.search(VaultSearchRequest(query: "pre"))
        #expect(prefix.sessions.map(\.id) == ["codex:previous"])

        let fuzzyTitle = try await store.search(VaultSearchRequest(query: "a p"))
        #expect(fuzzyTitle.sessions.map(\.id) == ["codex:previous"])

        let title = try await store.search(VaultSearchRequest(query: "previous"))
        #expect(title.sessions.map(\.id) == ["codex:previous"])
    }

    @Test("Codex adapter prefers SQLite thread timestamps")
    func codexAdapterPrefersSQLiteThreadTimestamps() async throws {
        let root = try temporaryDirectory()
        let db = root.appendingPathComponent("state_5.sqlite")
        try runSQLite(db, """
        create table threads (
          id text primary key,
          rollout_path text not null,
          created_at integer not null,
          updated_at integer not null,
          source text not null,
          model_provider text not null,
          cwd text not null,
          title text not null,
          sandbox_policy text not null,
          approval_mode text not null,
          updated_at_ms integer,
          model text,
          git_branch text
        );
        insert into threads values (
          'thread-new',
          '/tmp/rollout.jsonl',
          1,
          1,
          'codex',
          'openai',
          '/tmp/newer',
          'Newest Codex Thread',
          'workspace-write',
          'on-request',
          1778954251000,
          'gpt-test',
          'main'
        );
        """)

        let store = try VaultStore(
            databaseURL: root.appendingPathComponent("agent-sessions.sqlite"),
            configuration: VaultConfiguration(enabled: true, includedAgents: [.codex]),
            adapters: [CodexVaultAdapter(root: root, configuration: VaultConfiguration(enabled: true, includedAgents: [.codex]))]
        )

        _ = try await store.reindex()
        let list = try await store.list()
        #expect(list.sessions.first?.id == "codex:thread-new")
        #expect(list.sessions.first?.workingDirectory == "/tmp/newer")
        #expect(list.sessions.first?.modifiedAt == Date(timeIntervalSince1970: 1_778_954_251))
    }

    @Test("Codex adapter uses SQLite over JSONL and normalizes rollout IDs")
    func codexAdapterUsesSQLiteOverJSONLAndNormalizesRolloutIDs() async throws {
        let root = try temporaryDirectory()
        let threadID = "019e3c00-73e7-7fc0-8336-288a009a73a1"
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try #"{"role":"user","content":"JSONL fallback","cwd":"/tmp/jsonl"}"#.write(
            to: sessions.appendingPathComponent("rollout-2026-05-18T18-52-03-\(threadID).jsonl"),
            atomically: true,
            encoding: .utf8
        )
        try runSQLite(root.appendingPathComponent("state_5.sqlite"), """
        create table threads (
          id text primary key,
          title text,
          cwd text,
          updated_at_ms integer
        );
        insert into threads values (
          '\(threadID)',
          'SQLite title',
          '/tmp/sqlite',
          1778954251000
        );
        """)

        let configuration = VaultConfiguration(enabled: true, includedAgents: [.codex])
        let store = try VaultStore(
            databaseURL: root.appendingPathComponent("agent-sessions.sqlite"),
            configuration: configuration,
            adapters: [CodexVaultAdapter(root: root, configuration: configuration)]
        )

        _ = try await store.reindex()
        let list = try await store.list()

        #expect(list.sessions.map(\.id) == ["codex:\(threadID)"])
        #expect(list.sessions.first?.sourceKind == "codex_sqlite")
        #expect(list.sessions.first?.title == "SQLite title")
        #expect(list.sessions.first?.workingDirectory == "/tmp/sqlite")
    }

    @Test("Codex adapter falls back to JSONL when SQLite is empty")
    func codexAdapterFallsBackToJSONLWhenSQLiteIsEmpty() async throws {
        let root = try temporaryDirectory()
        let threadID = "019e316b-a612-7003-a8ec-757cf8c89a42"
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try #"{"role":"user","content":"Fallback title","cwd":"/tmp/fallback"}"#.write(
            to: sessions.appendingPathComponent("rollout-2026-05-16T17-33-18-\(threadID).jsonl"),
            atomically: true,
            encoding: .utf8
        )
        try runSQLite(root.appendingPathComponent("state_5.sqlite"), """
        create table threads (
          id text primary key,
          title text,
          cwd text,
          updated_at_ms integer
        );
        """)

        let configuration = VaultConfiguration(enabled: true, includedAgents: [.codex])
        let store = try VaultStore(
            databaseURL: root.appendingPathComponent("agent-sessions.sqlite"),
            configuration: configuration,
            adapters: [CodexVaultAdapter(root: root, configuration: configuration)]
        )

        _ = try await store.reindex()
        let list = try await store.list()

        #expect(list.sessions.map(\.id) == ["codex:\(threadID)"])
        #expect(list.sessions.first?.sourceKind == "codex_jsonl")
        #expect(list.sessions.first?.title == "Fallback title")
    }

    @Test("Vault reindex removes obsolete Codex JSONL rows after SQLite indexing")
    func vaultReindexRemovesObsoleteCodexJSONLRowsAfterSQLiteIndexing() async throws {
        let root = try temporaryDirectory()
        let threadID = "019e3c00-73e7-7fc0-8336-288a009a73a1"
        try runSQLite(root.appendingPathComponent("state_5.sqlite"), """
        create table threads (
          id text primary key,
          title text,
          cwd text,
          updated_at_ms integer
        );
        insert into threads values (
          '\(threadID)',
          'Primary',
          '/tmp/primary',
          1778954251000
        );
        """)
        let configuration = VaultConfiguration(enabled: true, includedAgents: [.codex])
        let store = try VaultStore(
            databaseURL: root.appendingPathComponent("agent-sessions.sqlite"),
            configuration: configuration,
            adapters: [CodexVaultAdapter(root: root, configuration: configuration)]
        )
        let bundle = VaultExportBundle(
            sessions: [
                VaultSessionSummary(
                    id: "codex:stale-jsonl",
                    agent: .codex,
                    sourceKind: "codex_jsonl",
                    title: "Stale JSONL",
                    workingDirectory: "/tmp/stale",
                    modifiedAt: Date(timeIntervalSince1970: 1),
                    previewAvailable: false,
                    resumeAvailable: true
                ),
            ],
            resumeSnapshots: [:],
            turns: [:]
        )
        try await store.import(data: JSONEncoder.agentSessionsTest.encode(bundle))

        _ = try await store.reindex()
        let list = try await store.list()

        #expect(list.sessions.map(\.id) == ["codex:\(threadID)"])
        #expect(list.sessions.first?.sourceKind == "codex_sqlite")
    }

    @Test("Vault preserves hidden Codex session across JSONL to SQLite replacement")
    func vaultPreservesHiddenCodexSessionAcrossJSONLToSQLiteReplacement() async throws {
        let root = try temporaryDirectory()
        let threadID = "019e3c00-73e7-7fc0-8336-288a009a73a1"
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try #"{"role":"user","content":"Fallback before DB","cwd":"/tmp/project"}"#.write(
            to: sessions.appendingPathComponent("rollout-2026-05-18T18-52-03-\(threadID).jsonl"),
            atomically: true,
            encoding: .utf8
        )
        let configuration = VaultConfiguration(enabled: true, includedAgents: [.codex])
        let store = try VaultStore(
            databaseURL: root.appendingPathComponent("agent-sessions.sqlite"),
            configuration: configuration,
            adapters: [CodexVaultAdapter(root: root, configuration: configuration)]
        )
        _ = try await store.reindex()
        #expect(try await store.list().sessions.map(\.id) == ["codex:\(threadID)"])

        try await store.delete(sessionID: "codex:\(threadID)")
        try runSQLite(root.appendingPathComponent("state_5.sqlite"), """
        create table threads (
          id text primary key,
          title text,
          cwd text,
          updated_at_ms integer
        );
        insert into threads values (
          '\(threadID)',
          'Primary after delete',
          '/tmp/project',
          1778954251000
        );
        """)

        _ = try await store.reindex()

        #expect(try await store.list().totalCount == 0)
        #expect(try await store.resumeSnapshot(sessionID: "codex:\(threadID)") == nil)
    }

    @Test("Gemini adapter indexes tmp logs array")
    func geminiAdapterIndexesTmpLogsArray() async throws {
        let root = try temporaryDirectory()
        let tmp = root.appendingPathComponent("tmp", isDirectory: true)
            .appendingPathComponent("omux", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let logs = tmp.appendingPathComponent("logs.json")
        try """
        [
          {
            "sessionId": "gemini-one",
            "messageId": 0,
            "type": "user",
            "message": "hello gemini",
            "timestamp": "2026-05-18T12:04:15.729Z"
          },
          {
            "sessionId": "gemini-one",
            "messageId": 1,
            "type": "assistant",
            "message": "hello user",
            "timestamp": "2026-05-18T12:04:16.729Z"
          }
        ]
        """.write(to: logs, atomically: true, encoding: .utf8)

        let store = try VaultStore(
            databaseURL: root.appendingPathComponent("agent-sessions.sqlite"),
            configuration: VaultConfiguration(enabled: true, includedAgents: [.gemini]),
            adapters: [GeminiVaultAdapter(root: root, configuration: VaultConfiguration(enabled: true, includedAgents: [.gemini]))]
        )

        _ = try await store.reindex()
        let list = try await store.list()
        #expect(list.sessions.map(\.id) == ["gemini:gemini-one"])
        #expect(list.sessions.first?.agent == .gemini)
        #expect(list.sessions.first?.title == "hello gemini")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        #expect(list.sessions.first?.modifiedAt == formatter.date(from: "2026-05-18T12:04:16.729Z"))
        #expect(try await store.preview(sessionID: "gemini:gemini-one")?.turns.isEmpty == true)
    }

    @Test("Gemini adapter indexes chat JSONL sessions")
    func geminiAdapterIndexesChatJSONLSessions() async throws {
        let root = try temporaryDirectory()
        let project = root.appendingPathComponent("tmp/omux", isDirectory: true)
        let chats = project.appendingPathComponent("chats", isDirectory: true)
        try FileManager.default.createDirectory(at: chats, withIntermediateDirectories: true)
        try "/tmp/omux\n".write(to: project.appendingPathComponent(".project_root"), atomically: true, encoding: .utf8)
        try """
        {"sessionId":"gemini-session","startTime":"2026-05-18T12:04:12.103Z","lastUpdated":"2026-05-18T12:04:12.103Z"}
        {"id":"turn-1","timestamp":"2026-05-18T12:04:17.137Z","type":"user","content":[{"text":"hello from gemini"}]}
        {"$set":{"lastUpdated":"2026-05-18T12:04:21.798Z"}}
        """.write(to: chats.appendingPathComponent("session-2026-05-18T12-04-gemini-session.jsonl"), atomically: true, encoding: .utf8)

        let store = try VaultStore(
            databaseURL: root.appendingPathComponent("agent-sessions.sqlite"),
            configuration: VaultConfiguration(enabled: true, includedAgents: [.gemini]),
            adapters: [GeminiVaultAdapter(root: root, configuration: VaultConfiguration(enabled: true, includedAgents: [.gemini]))]
        )

        _ = try await store.reindex()
        let list = try await store.list()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        #expect(list.sessions.map(\.id) == ["gemini:gemini-session"])
        #expect(list.sessions.first?.sourceKind == "gemini_jsonl")
        #expect(list.sessions.first?.title == "hello from gemini")
        #expect(list.sessions.first?.workingDirectory == "/tmp/omux")
        #expect(list.sessions.first?.modifiedAt == formatter.date(from: "2026-05-18T12:04:21.798Z"))
    }

    @Test("SQLite adapter parses text timestamps for Copilot sessions")
    func sqliteAdapterParsesTextTimestamps() async throws {
        let root = try temporaryDirectory()
        let db = root.appendingPathComponent("session-store.db")
        try runSQLite(db, """
        create table sessions (
          id text primary key,
          title text,
          cwd text,
          updatedAt text
        );
        insert into sessions values (
          'session-a',
          'Newest Copilot Session',
          '/tmp/newest',
          '2026-05-19T08:31:45.000Z'
        );
        """)

        let store = try VaultStore(
            databaseURL: root.appendingPathComponent("agent-sessions.sqlite"),
            configuration: VaultConfiguration(enabled: true, includedAgents: [.copilot]),
            adapters: [
                SQLiteBackedVaultAdapter(
                    kind: .copilot,
                    root: root,
                    databaseNames: ["session-store.db"],
                    sourceKind: "copilot_sqlite",
                    configuration: VaultConfiguration(enabled: true, includedAgents: [.copilot])
                ),
            ]
        )

        _ = try await store.reindex()
        let list = try await store.list()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        #expect(list.sessions.map(\.id) == ["copilot:session-a"])
        #expect(list.sessions.first?.workingDirectory == "/tmp/newest")
        #expect(list.sessions.first?.modifiedAt == formatter.date(from: "2026-05-19T08:31:45.000Z"))
    }

    @Test("Copilot adapter uses sessions table over session-state file mtimes")
    func copilotAdapterUsesSessionsTableOverSessionStateFileMtimes() async throws {
        let root = try temporaryDirectory()
        let state = root.appendingPathComponent("session-state/session-a", isDirectory: true)
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        let stateFile = state.appendingPathComponent("events.jsonl")
        try #"{"role":"user","content":"fallback title","cwd":"/tmp/fallback"}"#.write(to: stateFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_900_000_000)],
            ofItemAtPath: stateFile.path
        )

        let db = root.appendingPathComponent("session-store.db")
        try runSQLite(db, """
        create table sessions (
          id text primary key,
          cwd text,
          repository text,
          host_type text,
          branch text,
          summary text,
          created_at text,
          updated_at text
        );
        create table turns (
          id integer primary key,
          session_id text not null,
          turn_index integer not null,
          user_message text,
          assistant_response text,
          timestamp text
        );
        insert into sessions values (
          'session-a',
          '/tmp/store',
          'finger-gun/omux',
          'cli',
          'main',
          'Store title',
          '2026-05-18T07:00:00.000Z',
          '2026-05-18T07:00:01.000Z'
        );
        insert into turns values (
          1,
          'session-a',
          0,
          'hello from store',
          null,
          '2026-05-18T07:00:02.000Z'
        );
        """)

        let store = try VaultStore(
            databaseURL: root.appendingPathComponent("agent-sessions.sqlite"),
            configuration: VaultConfiguration(enabled: true, includedAgents: [.copilot]),
            adapters: [CopilotVaultAdapter(root: root, configuration: VaultConfiguration(enabled: true, includedAgents: [.copilot]))]
        )

        _ = try await store.reindex()
        let list = try await store.list()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        #expect(list.sessions.map(\.id) == ["copilot:session-a"])
        #expect(list.sessions.first?.title == "Store title")
        #expect(list.sessions.first?.workingDirectory == "/tmp/store")
        #expect(list.sessions.first?.modifiedAt == formatter.date(from: "2026-05-18T07:00:01.000Z"))
    }

    @Test("Copilot adapter ignores session-state fallback without sessions table")
    func copilotAdapterIgnoresSessionStateFallbackWithoutSessionsTable() async throws {
        let root = try temporaryDirectory()
        let state = root.appendingPathComponent("session-state/session-a", isDirectory: true)
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        try #"{"role":"user","content":"fallback title","cwd":"/tmp/fallback"}"#.write(
            to: state.appendingPathComponent("events.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let store = try VaultStore(
            databaseURL: root.appendingPathComponent("agent-sessions.sqlite"),
            configuration: VaultConfiguration(enabled: true, includedAgents: [.copilot]),
            adapters: [CopilotVaultAdapter(root: root, configuration: VaultConfiguration(enabled: true, includedAgents: [.copilot]))]
        )

        _ = try await store.reindex()

        #expect(try await store.list().sessions.isEmpty)
    }

    @Test("Vault reindex preserves cached rows missing from adapter result")
    func vaultReindexPreservesCachedRowsMissingFromAdapterResult() async throws {
        let root = try temporaryDirectory()
        let store = try VaultStore(
            databaseURL: root.appendingPathComponent("agent-sessions.sqlite"),
            configuration: VaultConfiguration(enabled: true, includedAgents: [.copilot]),
            adapters: [StaticVaultAdapter(kind: .copilot, sessions: [
                VaultSessionSummary(
                    id: "copilot:fresh",
                    agent: .copilot,
                    sourceKind: "copilot_sqlite",
                    title: "Fresh",
                    workingDirectory: "/tmp/project",
                    modifiedAt: Date(timeIntervalSince1970: 2),
                    previewAvailable: false,
                    resumeAvailable: true
                ),
            ])]
        )
        let bundle = VaultExportBundle(
            sessions: [
                VaultSessionSummary(
                    id: "copilot:stale",
                    agent: .copilot,
                    sourceKind: "copilot_sqlite",
                    title: "Cached",
                    workingDirectory: "/tmp/project",
                    modifiedAt: Date(timeIntervalSince1970: 1),
                    previewAvailable: false,
                    resumeAvailable: true
                ),
            ],
            resumeSnapshots: [:],
            turns: [:]
        )
        try await store.import(data: JSONEncoder.agentSessionsTest.encode(bundle))

        _ = try await store.reindex()
        let list = try await store.list()

        #expect(list.sessions.map(\.id) == ["copilot:fresh", "copilot:stale"])
    }

    @Test("Vault reindex removes obsolete Copilot session-state rows")
    func vaultReindexRemovesObsoleteCopilotSessionStateRows() async throws {
        let root = try temporaryDirectory()
        let store = try VaultStore(
            databaseURL: root.appendingPathComponent("agent-sessions.sqlite"),
            configuration: VaultConfiguration(enabled: true, includedAgents: [.copilot]),
            adapters: [StaticVaultAdapter(kind: .copilot, sessions: [
                VaultSessionSummary(
                    id: "copilot:fresh",
                    agent: .copilot,
                    sourceKind: "copilot_sqlite",
                    title: "Fresh",
                    workingDirectory: "/tmp/project",
                    modifiedAt: Date(timeIntervalSince1970: 2),
                    previewAvailable: false,
                    resumeAvailable: true
                ),
            ])]
        )
        let bundle = VaultExportBundle(
            sessions: [
                VaultSessionSummary(
                    id: "copilot:stale",
                    agent: .copilot,
                    sourceKind: "copilot_session_state",
                    title: "Stale",
                    workingDirectory: "/tmp/project",
                    modifiedAt: Date(timeIntervalSince1970: 1),
                    previewAvailable: false,
                    resumeAvailable: true
                ),
            ],
            resumeSnapshots: [:],
            turns: [:]
        )
        try await store.import(data: JSONEncoder.agentSessionsTest.encode(bundle))

        _ = try await store.reindex()
        let list = try await store.list()

        #expect(list.sessions.map(\.id) == ["copilot:fresh"])
    }

    @Test("Vault available agents returns agents with visible rows")
    func vaultAvailableAgentsReturnsAgentsWithVisibleRows() async throws {
        let root = try temporaryDirectory()
        let store = try VaultStore(databaseURL: root.appendingPathComponent("agent-sessions.sqlite"), configuration: VaultConfiguration())
        let bundle = VaultExportBundle(
            sessions: [
                VaultSessionSummary(
                    id: "copilot:visible",
                    agent: .copilot,
                    sourceKind: "fixture",
                    title: "Visible",
                    workingDirectory: "/tmp",
                    modifiedAt: Date(timeIntervalSince1970: 2),
                    previewAvailable: false,
                    resumeAvailable: true
                ),
                VaultSessionSummary(
                    id: "codex:hidden",
                    agent: .codex,
                    sourceKind: "fixture",
                    title: "Hidden",
                    workingDirectory: "/tmp",
                    modifiedAt: Date(timeIntervalSince1970: 1),
                    previewAvailable: false,
                    resumeAvailable: true
                ),
            ],
            resumeSnapshots: [:],
            turns: [:]
        )
        try await store.import(data: JSONEncoder.agentSessionsTest.encode(bundle))
        try await store.delete(sessionID: "codex:hidden")

        let agents = try await store.availableAgents()

        #expect(agents == [.copilot])
    }

    @Test("Copilot adapter sorts by sessions updated timestamp")
    func copilotAdapterSortsBySessionsUpdatedTimestamp() async throws {
        let root = try temporaryDirectory()
        let db = root.appendingPathComponent("session-store.db")
        try runSQLite(db, """
        create table sessions (
          id text primary key,
          cwd text,
          repository text,
          host_type text,
          branch text,
          summary text,
          created_at text,
          updated_at text
        );
        create table turns (
          id integer primary key,
          session_id text not null,
          turn_index integer not null,
          user_message text,
          assistant_response text,
          timestamp text
        );
        insert into sessions values (
          'session-a',
          '/tmp/store',
          'finger-gun/omux',
          'cli',
          'main',
          'Store title',
          '2026-05-01T07:00:00.000Z',
          '2026-05-19T07:00:01.000Z'
        );
        insert into sessions values (
          'session-b',
          '/tmp/store',
          'finger-gun/omux',
          'cli',
          'main',
          'Older store title',
          '2026-05-01T07:00:00.000Z',
          '2026-05-18T07:00:01.000Z'
        );
        insert into turns values (
          1,
          'session-b',
          0,
          'newer turn ignored for sidebar ordering',
          null,
          '2026-05-20T07:00:02.000Z'
        );
        """)

        let store = try VaultStore(
            databaseURL: root.appendingPathComponent("agent-sessions.sqlite"),
            configuration: VaultConfiguration(enabled: true, includedAgents: [.copilot]),
            adapters: [CopilotVaultAdapter(root: root, configuration: VaultConfiguration(enabled: true, includedAgents: [.copilot]))]
        )

        _ = try await store.reindex()
        let list = try await store.list()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        #expect(list.sessions.map(\.id) == ["copilot:session-a", "copilot:session-b"])
        #expect(list.sessions.first?.modifiedAt == formatter.date(from: "2026-05-19T07:00:01.000Z"))
    }

    @Test("Vault store marks indexed session deleted")
    func vaultStoreMarksIndexedSessionDeleted() async throws {
        let root = try temporaryDirectory()
        let store = try VaultStore(databaseURL: root.appendingPathComponent("agent-sessions.sqlite"), configuration: VaultConfiguration())
        let bundle = VaultExportBundle(
            sessions: [
                VaultSessionSummary(
                    id: "copilot:delete-me",
                    agent: .copilot,
                    sourceKind: "fixture",
                    title: "Delete me",
                    workingDirectory: "/tmp",
                    modifiedAt: Date(timeIntervalSince1970: 1),
                    previewAvailable: true,
                    resumeAvailable: true
                ),
            ],
            resumeSnapshots: [:],
            turns: [:]
        )
        try await store.import(data: JSONEncoder.agentSessionsTest.encode(bundle))
        #expect(try await store.list().totalCount == 1)

        try await store.delete(sessionID: "copilot:delete-me")

        #expect(try await store.list().totalCount == 0)
        #expect(try await store.preview(sessionID: "copilot:delete-me") == nil)
        #expect(try await store.resumeSnapshot(sessionID: "copilot:delete-me") == nil)
    }

    @Test("Vault store preserves Copilot source session when hiding locally")
    func vaultStorePreservesCopilotSourceSessionWhenHidingLocally() async throws {
        let root = try temporaryDirectory()
        let state = root.appendingPathComponent("session-state/session-a", isDirectory: true)
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        try #"{"role":"user","content":"delete source"}"#.write(
            to: state.appendingPathComponent("events.jsonl"),
            atomically: true,
            encoding: .utf8
        )
        let db = root.appendingPathComponent("session-store.db")
        try runSQLite(db, """
        create table sessions (id text primary key, summary text, updated_at text);
        create table turns (id integer primary key, session_id text not null, turn_index integer, user_message text, timestamp text);
        insert into sessions values ('session-a', 'Delete source', '2026-05-18T07:00:01.000Z');
        insert into turns values (1, 'session-a', 0, 'hello', '2026-05-18T07:00:02.000Z');
        """)
        let configuration = VaultConfiguration(
            enabled: true,
            includedAgents: [.copilot],
            agentHomes: [.copilot: root.path]
        )
        let store = try VaultStore(
            databaseURL: root.appendingPathComponent("agent-sessions.sqlite"),
            configuration: configuration,
            adapters: [CopilotVaultAdapter(root: root, configuration: configuration)]
        )
        _ = try await store.reindex()
        #expect(try await store.list().totalCount == 1)

        try await store.delete(sessionID: "copilot:session-a")

        #expect(try await store.list().totalCount == 0)
        #expect(FileManager.default.fileExists(atPath: state.path) == true)
        let remainingSessions = try sqliteScalar(db, "select count(*) from sessions where id = 'session-a'")
        let remainingTurns = try sqliteScalar(db, "select count(*) from turns where session_id = 'session-a'")
        #expect(remainingSessions == 1)
        #expect(remainingTurns == 1)
        _ = try await store.reindex()
        #expect(try await store.list().totalCount == 0)
    }

    @Test("Vault watch sources use narrow agent homes")
    func watchSourcesUseNarrowAgentHomes() throws {
        let root = try temporaryDirectory()
        let codexHome = root.appendingPathComponent("codex", isDirectory: true)
        let geminiHome = root.appendingPathComponent("gemini", isDirectory: true)
        let geminiTmp = geminiHome.appendingPathComponent("tmp", isDirectory: true)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: geminiTmp, withIntermediateDirectories: true)

        let configuration = VaultConfiguration(
            enabled: true,
            includedAgents: [.codex, .gemini, .custom],
            agentHomes: [
                .codex: codexHome.path,
                .gemini: geminiHome.path,
                .custom: root.appendingPathComponent("custom", isDirectory: true).path,
            ]
        )

        let sources = VaultWatchSourceFactory.sources(configuration: configuration)
        #expect(sources.contains(VaultWatchSource(agent: .codex, url: codexHome)))
        #expect(sources.contains(VaultWatchSource(agent: .gemini, url: geminiTmp)))
        #expect(sources.contains { $0.agent == .custom } == false)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("omux-vault-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private struct StaticVaultAdapter: VaultAgentAdapter {
    let kind: VaultAgentKind
    let sessions: [VaultSessionSummary]

    func discoverSessions() async throws -> [VaultIndexedSession] {
        sessions.map { VaultIndexedSession(summary: $0, resumeSnapshot: nil, turns: []) }
    }
}

private func runSQLite(_ db: URL, _ sql: String) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    process.arguments = [db.path, sql]
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
}

private func sqliteScalar(_ db: URL, _ sql: String) throws -> Int {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    process.arguments = [db.path, sql]
    process.standardOutput = output
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
    let data = output.fileHandleForReading.readDataToEndOfFile()
    return Int(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) ?? -1
}

private extension JSONEncoder {
    static var agentSessionsTest: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
