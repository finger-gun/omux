import Foundation
import Testing
@testable import OmuxConfig
@testable import OmuxVault

@Suite("Vault")
struct OmuxVaultTests {
    @Test("JSONL adapter indexes transcript turns and resume command")
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
            databaseURL: root.appendingPathComponent("vault.sqlite"),
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
        #expect(preview?.turns.contains(where: { $0.text.contains("Vault") }) == true)
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
            resumeSnapshots: [
                "copilot:one": VaultResumeSnapshot(kind: .copilot, sessionID: "one", workingDirectory: "/tmp", resumeCommand: "copilot --resume 'one'"),
            ],
            turns: [
                "copilot:one": [
                    VaultTranscriptTurn(sessionID: "copilot:one", turnID: "0", role: "user", text: "hello copilot", ordinal: 0, modifiedAt: Date(timeIntervalSince1970: 1)),
                ],
            ]
        )
        try await source.import(data: JSONEncoder.vaultTest.encode(bundle))
        let data = try await source.export(ids: ["copilot:one"])

        let target = try VaultStore(databaseURL: root.appendingPathComponent("target.sqlite"), configuration: VaultConfiguration())
        try await target.import(data: data)
        let result = try await target.search(VaultSearchRequest(query: "copilot"))
        #expect(result.totalCount == 1)
        #expect(try await target.preview(sessionID: "copilot:one")?.turns.first?.text == "hello copilot")
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
            databaseURL: root.appendingPathComponent("vault.sqlite"),
            configuration: VaultConfiguration(enabled: true, includedAgents: [.codex]),
            adapters: [CodexVaultAdapter(root: root, configuration: VaultConfiguration(enabled: true, includedAgents: [.codex]))]
        )

        _ = try await store.reindex()
        let list = try await store.list()
        #expect(list.sessions.first?.id == "codex:thread-new")
        #expect(list.sessions.first?.workingDirectory == "/tmp/newer")
        #expect(list.sessions.first?.modifiedAt == Date(timeIntervalSince1970: 1_778_954_251))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("omux-vault-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
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

private extension JSONEncoder {
    static var vaultTest: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
