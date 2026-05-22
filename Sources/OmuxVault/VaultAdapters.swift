import CSQLite
import Darwin
import Foundation
import OmuxConfig

public protocol VaultAgentAdapter: Sendable {
    var kind: VaultAgentKind { get }
    var isExternal: Bool { get }
    var sourceKindPrefixes: [String] { get }
    var resumeCommandTemplate: String? { get }
    func discoverSessions() async throws -> [VaultIndexedSession]
}

public extension VaultAgentAdapter {
    var isExternal: Bool { false }
    var sourceKindPrefixes: [String] { [] }
    var resumeCommandTemplate: String? { nil }
}

public enum VaultAdapterFactory {
    public static func adapters(configuration: VaultConfiguration) -> [VaultAgentAdapter] {
        var adapters: [VaultAgentAdapter] = [
            CopilotVaultAdapter(root: configuration.home(for: .copilot), configuration: configuration),
            CodexVaultAdapter(root: configuration.home(for: .codex), configuration: configuration),
            GeminiVaultAdapter(root: configuration.home(for: .gemini), configuration: configuration),
        ]
        if configuration.externalAdaptersEnabled {
            adapters += PluginAgentSessionsAdapterDiscovery.adapters(configuration: configuration).map {
                ExternalCommandVaultAdapter(configuration: $0)
            }
            adapters += configuration.externalAdapters.map {
                ExternalCommandVaultAdapter(configuration: $0)
            }
        }
        return adapters
    }
}

public enum PluginAgentSessionsAdapterDiscovery {
    public static func adapters(
        configuration: VaultConfiguration,
        pluginsDirectoryURL: URL = OmuxConfigPaths.pluginsDirectoryURL,
        fileManager: FileManager = .default
    ) -> [VaultConfiguration.ExternalAdapterConfiguration] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: pluginsDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return entries
            .filter { isDirectory($0, fileManager: fileManager) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { adapter(forPluginDirectory: $0, configuration: configuration, fileManager: fileManager) }
    }

    private static func adapter(
        forPluginDirectory pluginDirectory: URL,
        configuration: VaultConfiguration,
        fileManager: FileManager
    ) -> VaultConfiguration.ExternalAdapterConfiguration? {
        let manifestURL = pluginDirectory.appendingPathComponent("omux-plugin.toml", isDirectory: false)
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return nil
        }
        let parseResult = OmuxTOMLParser.parse(fileAt: manifestURL)
        guard let document = parseResult.document, parseResult.diagnostics.isEmpty else {
            return nil
        }
        guard document.value(for: "kind")?.stringValue == "plugin" else {
            return nil
        }
        let pluginID = document.value(for: "id")?.stringValue?.nilIfBlank ?? pluginDirectory.lastPathComponent
        let commandName = document.value(in: "plugin", for: "command")?.stringValue?.nilIfBlank ?? pluginID
        let entrypoint = document.value(in: "plugin", for: "entrypoint")?.stringValue?.nilIfBlank ?? "plugin"
        let executableURL = pluginDirectory.appendingPathComponent(entrypoint, isDirectory: false)
        guard isExecutableRegularFile(executableURL, fileManager: fileManager) else {
            return nil
        }
        guard let callback = document.value(in: "agent-sessions", for: "callback")?.stringValue?.nilIfBlank else {
            return nil
        }
        let manifestName = document.value(in: "agent-sessions", for: "name")?.stringValue?.nilIfBlank
        let manifestAgent = document.value(in: "agent-sessions", for: "agent")?.stringValue?.nilIfBlank
        let adapterName = manifestName ?? manifestAgent ?? commandName
        let setting = configuration.externalAdapterSettings[adapterName]
            ?? configuration.externalAdapterSettings[commandName]
            ?? configuration.externalAdapterSettings[pluginID]
        if setting?.enabled == false {
            return nil
        }
        let agent = VaultAgentKind(rawValue: adapterName) ?? .external(adapterName)
        let sourceKind = document.value(in: "agent-sessions", for: "source_kind")?.stringValue?.nilIfBlank
            ?? "\(agent.rawValue)_plugin"
        let manifestResumeCommand = document.value(in: "agent-sessions", for: "resume_command")?.stringValue?.nilIfBlank
        let resumeCommand = setting?.resumeCommand?.nilIfBlank ?? manifestResumeCommand
        let arguments = [callback] + stringArray(document.value(in: "agent-sessions", for: "arguments"))
        return VaultConfiguration.ExternalAdapterConfiguration(
            id: commandName,
            agent: agent,
            executablePath: executableURL.path,
            arguments: arguments,
            sourceKind: sourceKind,
            resumeCommand: resumeCommand
        )
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func isExecutableRegularFile(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue == false
        else {
            return false
        }
        return fileManager.isExecutableFile(atPath: url.path)
    }

    private static func stringArray(_ value: OmuxTOMLValue?) -> [String] {
        guard case .array(let values) = value else {
            return []
        }
        return values.compactMap(\.stringValue)
    }
}

public struct ExternalCommandVaultAdapter: VaultAgentAdapter {
    public let kind: VaultAgentKind
    public let adapterID: String
    public let executablePath: String
    public let arguments: [String]
    public let sourceKind: String
    public let resumeCommandTemplate: String?
    public let isExternal = true
    private let executionTimeoutNanoseconds: UInt64 = 30_000_000_000

    public var sourceKindPrefixes: [String] {
        [sourceKind]
    }

    public init(configuration: VaultConfiguration.ExternalAdapterConfiguration) {
        self.kind = configuration.agent
        self.adapterID = configuration.id
        self.executablePath = configuration.executablePath
        self.arguments = configuration.arguments
        self.sourceKind = configuration.sourceKind
        self.resumeCommandTemplate = configuration.resumeCommand
    }

    public func discoverSessions() async throws -> [VaultIndexedSession] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.environment = pluginEnvironment()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()

        let stdoutHandle = stdout.fileHandleForReading
        let stderrHandle = stderr.fileHandleForReading
        let stdoutTask = Task.detached { stdoutHandle.readDataToEndOfFile() }
        let stderrTask = Task.detached { stderrHandle.readDataToEndOfFile() }

        let startedAt = DispatchTime.now().uptimeNanoseconds
        while process.isRunning {
            let elapsed = DispatchTime.now().uptimeNanoseconds - startedAt
            if elapsed >= executionTimeoutNanoseconds {
                process.terminate()
                try? await Task.sleep(nanoseconds: 200_000_000)
                if process.isRunning {
                    process.interrupt()
                }
                if await waitForExit(process, timeoutNanoseconds: 500_000_000) == false, process.processIdentifier > 0 {
                    _ = kill(process.processIdentifier, SIGKILL)
                    _ = await waitForExit(process, timeoutNanoseconds: 1_000_000_000)
                }
                if process.isRunning == false {
                    process.waitUntilExit()
                }
                let stderrOutput = String(decoding: await stderrTask.value, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                throw NSError(domain: "OmuxVaultExternalAdapter", code: 124, userInfo: [
                    NSLocalizedDescriptionKey: "external adapter '\(adapterID)' timed out after \(executionTimeoutNanoseconds / 1_000_000_000)s: \(stderrOutput)"
                ])
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(decoding: await stderrTask.value, as: UTF8.self)
            throw NSError(domain: "OmuxVaultExternalAdapter", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "external adapter '\(adapterID)' failed: \(message.trimmingCharacters(in: .whitespacesAndNewlines))"
            ])
        }

        let payload = await stdoutTask.value
        guard payload.isEmpty == false else {
            return []
        }
        let sessions = try JSONDecoder().decode(ExternalSessionRecordList.self, from: payload).sessions
        return mergePreferNewest(sessions.compactMap { record in
            guard let rawID = (record.sessionID ?? record.id)?.nilIfBlank else {
                return nil
            }
            let updated = record.modifiedAtDate ?? record.updatedAtDate ?? Date()
            let agent = record.agent.flatMap(VaultAgentKind.init(rawValue:)) ?? kind
            let summary = VaultSessionSummary(
                id: "\(agent.rawValue):\(rawID)",
                agent: agent,
                sourceKind: sourceKind,
                sourcePath: record.sourcePath,
                title: record.title?.firstLine(maxLength: 80).nilIfEmpty ?? rawID,
                workingDirectory: record.cwd,
                model: record.model,
                gitBranch: record.gitBranch,
                modifiedAt: updated,
                previewAvailable: false,
                resumeAvailable: resumeCommandTemplate != nil
            )
            return VaultIndexedSession(summary: summary, resumeSnapshot: nil, turns: [])
        })
    }

    private func pluginEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let executableURL = URL(fileURLWithPath: executablePath)
        environment["OMUX_PLUGIN_COMMAND"] = adapterID
        environment["OMUX_PLUGIN_EXECUTABLE"] = executablePath
        environment["OMUX_PLUGINS_DIR"] = executableURL.deletingLastPathComponent().path
        if environment["OMUX_CLI"] == nil,
           let bundledCLIURL = bundledCLIURL() {
            environment["OMUX_CLI"] = bundledCLIURL.path
        }
        return environment
    }

    private func bundledCLIURL() -> URL? {
        let bundleURL = Bundle.main.bundleURL
        let candidates = [
            bundleURL.appendingPathComponent("Contents/MacOS/omux", isDirectory: false),
            URL(fileURLWithPath: "/Applications/OpenMUX.app/Contents/MacOS/omux", isDirectory: false),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private func waitForExit(_ process: Process, timeoutNanoseconds: UInt64) async -> Bool {
        let start = DispatchTime.now().uptimeNanoseconds
        while process.isRunning {
            if DispatchTime.now().uptimeNanoseconds - start >= timeoutNanoseconds {
                return false
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return true
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

    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct ExternalSessionRecord: Decodable {
    let id: String?
    let sessionID: String?
    let agent: String?
    let title: String?
    let cwd: String?
    let model: String?
    let gitBranch: String?
    let sourcePath: String?
    let modifiedAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case sessionID = "session_id"
        case agent
        case title
        case cwd
        case model
        case gitBranch = "git_branch"
        case sourcePath = "source_path"
        case modifiedAt = "modified_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try? container.decodeIfPresent(String.self, forKey: .id)
        sessionID = try? container.decodeIfPresent(String.self, forKey: .sessionID)
        agent = try? container.decodeIfPresent(String.self, forKey: .agent)
        title = try? container.decodeIfPresent(String.self, forKey: .title)
        cwd = try? container.decodeIfPresent(String.self, forKey: .cwd)
        model = try? container.decodeIfPresent(String.self, forKey: .model)
        gitBranch = try? container.decodeIfPresent(String.self, forKey: .gitBranch)
        sourcePath = try? container.decodeIfPresent(String.self, forKey: .sourcePath)
        modifiedAt = Self.decodeDateString(from: container, key: .modifiedAt)
        updatedAt = Self.decodeDateString(from: container, key: .updatedAt)
    }

    private static func decodeDateString(from container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> String? {
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }
        return nil
    }

    var modifiedAtDate: Date? {
        modifiedAt.flatMap(parseExternalDate)
    }

    var updatedAtDate: Date? {
        updatedAt.flatMap(parseExternalDate)
    }
}

private struct ExternalSessionRecordList: Decodable {
    let sessions: [ExternalSessionRecord]

    init(from decoder: Decoder) throws {
        if let array = try? [ExternalSessionRecord](from: decoder) {
            sessions = array
            return
        }
        let object = try Container(from: decoder)
        sessions = object.sessions
    }

    private struct Container: Decodable {
        let sessions: [ExternalSessionRecord]
    }
}

private func parseExternalDate(_ value: String) -> Date? {
    if let date = parseISO8601Date(value) {
        return date
    }
    if let numeric = Double(value) {
        return dateFromUnixTimestamp(numeric)
    }
    return nil
}
