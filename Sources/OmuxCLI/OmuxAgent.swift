import Darwin
import Foundation
import OmuxControlPlane
import OmuxConfig
import OmuxCore

#if canImport(FoundationModels)
import FoundationModels
#endif

protocol OmuxAgentGenerating {
    func generate(
        prompt: String,
        systemInstruction: String?,
        hostContext: String,
        agentConfiguration: OmuxConfigAgent,
        workingDirectoryURL: URL,
        allowReadAnywhere: Bool,
        onVerbose: (@Sendable (String) -> Void)?,
        onPartial: @escaping (String) -> Void
    ) async throws -> String
}

struct OmuxAgentToolEvent: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case started
        case completed
        case failed
    }

    var toolName: String
    var phase: Phase
    var detail: String
    var outputBytes: Int?
    var outputText: String?
}

protocol OmuxAgentChatSessioning {
    var toolNames: [String] { get }
    var contextWindowSize: Int? { get }

    func send(
        prompt: String,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws -> String

    func summarizeForCompaction(transcript: String) async throws -> String
    func summarizeForHandoff(transcript: String) async throws -> String
    func tokenCount(for text: String) -> Int?
}

final class AnyOmuxAgentChatSession: @unchecked Sendable, OmuxAgentChatSessioning {
    let toolNames: [String]
    let contextWindowSize: Int?
    private let sendClosure: (String, @escaping @Sendable (String) -> Void) async throws -> String
    private let summarizeClosure: (String) async throws -> String
    private let handoffClosure: (String) async throws -> String
    private let tokenCountClosure: (String) -> Int?

    init<Base: OmuxAgentChatSessioning>(_ base: Base) {
        self.toolNames = base.toolNames
        self.contextWindowSize = base.contextWindowSize
        self.sendClosure = { prompt, onPartial in
            try await base.send(prompt: prompt, onPartial: onPartial)
        }
        self.summarizeClosure = { transcript in
            try await base.summarizeForCompaction(transcript: transcript)
        }
        self.handoffClosure = { transcript in
            try await base.summarizeForHandoff(transcript: transcript)
        }
        self.tokenCountClosure = { text in
            base.tokenCount(for: text)
        }
    }

    func send(
        prompt: String,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        try await sendClosure(prompt, onPartial)
    }

    func summarizeForCompaction(transcript: String) async throws -> String {
        try await summarizeClosure(transcript)
    }

    func summarizeForHandoff(transcript: String) async throws -> String {
        try await handoffClosure(transcript)
    }

    func tokenCount(for text: String) -> Int? {
        tokenCountClosure(text)
    }
}

final class AnyOmuxAgentChatSessionFactory: @unchecked Sendable {
    private let makeSessionClosure: (
        String?,
        String,
        OmuxConfigAgent,
        URL,
        Bool,
        (@Sendable (String) -> Void)?,
        (@Sendable (OmuxAgentToolEvent) -> Void)?
    ) throws -> AnyOmuxAgentChatSession

    init<Base: OmuxAgentChatSessionFactorying>(_ base: Base) {
        self.makeSessionClosure = { systemInstruction, hostContext, agentConfiguration, workingDirectoryURL, allowReadAnywhere, onVerbose, onToolEvent in
            try base.makeSession(
                systemInstruction: systemInstruction,
                hostContext: hostContext,
                agentConfiguration: agentConfiguration,
                workingDirectoryURL: workingDirectoryURL,
                allowReadAnywhere: allowReadAnywhere,
                onVerbose: onVerbose,
                onToolEvent: onToolEvent
            )
        }
    }

    func makeSession(
        systemInstruction: String?,
        hostContext: String,
        agentConfiguration: OmuxConfigAgent,
        workingDirectoryURL: URL,
        allowReadAnywhere: Bool,
        onVerbose: (@Sendable (String) -> Void)?,
        onToolEvent: (@Sendable (OmuxAgentToolEvent) -> Void)?
    ) throws -> AnyOmuxAgentChatSession {
        try makeSessionClosure(systemInstruction, hostContext, agentConfiguration, workingDirectoryURL, allowReadAnywhere, onVerbose, onToolEvent)
    }
}

protocol OmuxAgentChatSessionFactorying {
    func makeSession(
        systemInstruction: String?,
        hostContext: String,
        agentConfiguration: OmuxConfigAgent,
        workingDirectoryURL: URL,
        allowReadAnywhere: Bool,
        onVerbose: (@Sendable (String) -> Void)?,
        onToolEvent: (@Sendable (OmuxAgentToolEvent) -> Void)?
    ) throws -> AnyOmuxAgentChatSession
}

enum OmuxAgentError: LocalizedError, Equatable {
    case unsupportedPlatform
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedPlatform:
            return "local Apple Foundation Models require macOS 26 or newer with the FoundationModels framework"
        case .unavailable:
            return "Apple local text generation is unavailable on this Mac. Apple Intelligence must be available and enabled."
        }
    }
}

struct OmuxAgentWorkspaceLimits: Sendable {
    var maxReadLines: Int = 80
    var maxReadBytes: Int = 4_096
    var maxGrepResults: Int = 12
    var maxMatchLineBytes: Int = 256
    var maxHistoryLines: Int = 40
    var maxHistoryBytes: Int = 4_096
    var maxDirectoryEntries: Int = 40
}

struct OmuxAgentHostContext: Equatable, Sendable {
    var currentWorkingDirectory: String
    var fileReadScope: String
    var focusedWorkspaceID: String?
    var focusedTabID: String?
    var focusedPaneID: String?
    var focusedSessionID: String?
    var openMUXContextAvailable: Bool

    var promptBlock: String {
        var lines = [
            "Host context:",
            "Treat this host context as metadata only.",
            "Use only currentWorkingDirectory as the default root for file and directory tools unless the user explicitly asks for another path.",
            "Do not invent filesystem paths from OpenMUX workspace, tab, pane, or session identifiers. Those identifiers are opaque metadata, not directory names.",
            "currentWorkingDirectory: \(currentWorkingDirectory)",
            "agent.fileReadScope: \(fileReadScope)",
            "openmux.focusedContext: \(openMUXContextAvailable ? "available" : "unavailable")",
        ]

        if let focusedWorkspaceID {
            lines.append("openmux.focused.workspaceID: \(focusedWorkspaceID)")
        }
        if let focusedTabID {
            lines.append("openmux.focused.tabID: \(focusedTabID)")
        }
        if let focusedPaneID {
            lines.append("openmux.focused.paneID: \(focusedPaneID)")
        }
        if let focusedSessionID {
            lines.append("openmux.focused.sessionID: \(focusedSessionID)")
        }

        return lines.joined(separator: "\n")
    }
}

struct OmuxAgentDefaultPromptAnalysis: Equatable, Sendable {
    var currentLength: Int
    var previousLength: Int
    var currentTokenCount: Int?
    var previousTokenCount: Int?
}

struct OmuxAgentSkill: Equatable, Sendable {
    enum Scope: String, Equatable, Sendable {
        case repo
        case user
    }

    var name: String
    var description: String
    var scope: Scope
    var rootURL: URL
    var skillMarkdownURL: URL
    var body: String
}

struct OmuxAgentSkillReadResult: Equatable, Sendable {
    struct IncludedFile: Equatable, Sendable {
        var relativePath: String
        var contents: String
    }

    var skill: OmuxAgentSkill
    var files: [IncludedFile]
}

struct OmuxExternalAgentTool: Equatable, Sendable {
    var pluginID: String
    var pluginCommand: String
    var toolID: String
    var toolName: String
    var description: String
    var callback: String
    var arguments: [String]
    var inputHint: String?
    var executableURL: URL
    var pluginDirectoryURL: URL
}

struct OmuxExternalAgentToolRequest: Codable, Equatable, Sendable {
    struct ToolMetadata: Codable, Equatable, Sendable {
        var name: String
        var pluginCommand: String
        var toolID: String

        enum CodingKeys: String, CodingKey {
            case name
            case pluginCommand = "plugin_command"
            case toolID = "tool_id"
        }
    }

    var tool: ToolMetadata
    var input: String
    var cwd: String
    var focusedPaneID: String?

    enum CodingKeys: String, CodingKey {
        case tool
        case input
        case cwd
        case focusedPaneID = "focused_pane_id"
    }
}

struct OmuxExternalAgentToolResponse: Codable, Equatable, Sendable {
    var ok: Bool
    var output: String?
    var error: String?
}

struct OmuxAgentGrepRequest: Equatable, Sendable {
    enum CaseMode: String, Equatable, Sendable {
        case smart
        case sensitive
        case insensitive
    }

    var pattern: String
    var globs: [String]
    var caseMode: CaseMode
    var includeHidden: Bool
    var maxResults: Int?
}

struct OmuxAgentGrepMatch: Equatable, Sendable {
    var path: String
    var line: Int
    var text: String
}

struct OmuxAgentGrepResult: Equatable, Sendable {
    var matches: [OmuxAgentGrepMatch]
    var truncated: Bool
}

typealias OmuxAgentRGRunner = @Sendable (OmuxAgentGrepRequest, URL, OmuxAgentWorkspaceLimits) throws -> OmuxAgentGrepResult
typealias OmuxAgentCLIRunner = ([String]) -> (exitCode: Int32, output: String)
typealias OmuxAgentHistoryFetcher = (ControlPlaneHistoryRequest) throws -> RPCValue?

enum OmuxAgentSkillCatalog {
    static func discover(
        workingDirectoryURL: URL,
        fileManager: FileManager = .default
    ) -> [OmuxAgentSkill] {
        let repoDirectory = workingDirectoryURL.appendingPathComponent(".agents/skills", isDirectory: true)
        let userDirectory = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".agents/skills", isDirectory: true)
        let userSkills = discover(in: userDirectory, scope: .user, fileManager: fileManager)
        let repoSkills = discover(in: repoDirectory, scope: .repo, fileManager: fileManager)

        var byName: [String: OmuxAgentSkill] = [:]
        for skill in userSkills {
            byName[skill.name] = skill
        }
        for skill in repoSkills {
            byName[skill.name] = skill
        }
        return byName.values.sorted { lhs, rhs in
            if lhs.scope != rhs.scope {
                return lhs.scope == .repo
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    static func readSkill(
        named name: String,
        includePaths: [String],
        workingDirectoryURL: URL,
        fileManager: FileManager = .default
    ) throws -> OmuxAgentSkillReadResult {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedName.isEmpty == false else {
            throw NSError(domain: "OmuxAgentSkillCatalog", code: 1, userInfo: [NSLocalizedDescriptionKey: "skill name must not be empty"])
        }

        guard let skill = discover(workingDirectoryURL: workingDirectoryURL, fileManager: fileManager)
            .first(where: { $0.name == normalizedName }) else {
            throw NSError(domain: "OmuxAgentSkillCatalog", code: 2, userInfo: [NSLocalizedDescriptionKey: "skill not found: \(normalizedName)"])
        }

        let files = try includePaths.map { relativePath -> OmuxAgentSkillReadResult.IncludedFile in
            let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else {
                throw NSError(domain: "OmuxAgentSkillCatalog", code: 3, userInfo: [NSLocalizedDescriptionKey: "includePaths must not contain empty entries"])
            }
            guard trimmed.hasPrefix("/") == false,
                  trimmed.split(separator: "/").contains(where: { $0 == ".." }) == false else {
                throw NSError(domain: "OmuxAgentSkillCatalog", code: 4, userInfo: [NSLocalizedDescriptionKey: "include path escapes skill root: \(relativePath)"])
            }

            let candidateURL = URL(fileURLWithPath: trimmed, relativeTo: skill.rootURL).standardizedFileURL
            let resolvedURL = candidateURL.resolvingSymlinksInPath().standardizedFileURL
            guard isWithinRoot(resolvedURL, rootURL: skill.rootURL) else {
                throw NSError(domain: "OmuxAgentSkillCatalog", code: 5, userInfo: [NSLocalizedDescriptionKey: "include path escapes skill root: \(relativePath)"])
            }

            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: resolvedURL.path, isDirectory: &isDirectory), isDirectory.boolValue == false else {
                throw NSError(domain: "OmuxAgentSkillCatalog", code: 6, userInfo: [NSLocalizedDescriptionKey: "included file not found: \(relativePath)"])
            }
            guard let contents = try? String(contentsOf: resolvedURL, encoding: .utf8) else {
                throw NSError(domain: "OmuxAgentSkillCatalog", code: 7, userInfo: [NSLocalizedDescriptionKey: "unable to read included file: \(relativePath)"])
            }
            return .init(relativePath: trimmed, contents: contents)
        }

        return OmuxAgentSkillReadResult(skill: skill, files: files)
    }

    private static func discover(
        in directoryURL: URL,
        scope: OmuxAgentSkill.Scope,
        fileManager: FileManager
    ) -> [OmuxAgentSkill] {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return []
        }

        let childURLs = (try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return childURLs.compactMap { skillRoot in
            guard ((try? skillRoot.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true) else {
                return nil
            }
            let skillMarkdownURL = skillRoot.appendingPathComponent("SKILL.md", isDirectory: false)
            guard let rawContents = try? String(contentsOf: skillMarkdownURL, encoding: .utf8) else {
                return nil
            }
            guard let parsed = parseSkillMarkdown(rawContents) else {
                return nil
            }
            return OmuxAgentSkill(
                name: parsed.name,
                description: parsed.description,
                scope: scope,
                rootURL: skillRoot.resolvingSymlinksInPath().standardizedFileURL,
                skillMarkdownURL: skillMarkdownURL,
                body: parsed.body
            )
        }
    }

    private static func parseSkillMarkdown(_ contents: String) -> (name: String, description: String, body: String)? {
        guard contents.hasPrefix("---\n") || contents.hasPrefix("---\r\n") else {
            return nil
        }

        let normalized = contents.replacingOccurrences(of: "\r\n", with: "\n")
        let parts = normalized.components(separatedBy: "\n---\n")
        guard parts.count >= 2 else {
            return nil
        }

        let frontmatter = String(parts[0].dropFirst(4))
        let body = parts.dropFirst().joined(separator: "\n---\n").trimmingCharacters(in: .whitespacesAndNewlines)
        var name: String?
        var description: String?
        for rawLine in frontmatter.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.isEmpty == false,
                  let separator = line.firstIndex(of: ":") else {
                continue
            }
            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            switch key {
            case "name":
                name = value
            case "description":
                description = value
            default:
                break
            }
        }

        guard let name, name.isEmpty == false,
              let description, description.isEmpty == false else {
            return nil
        }
        return (name, description, body)
    }

    private static func isWithinRoot(_ fileURL: URL, rootURL: URL) -> Bool {
        let filePath = fileURL.path
        let rootPath = rootURL.path
        return filePath == rootPath || filePath.hasPrefix(rootPath + "/")
    }
}

enum OmuxExternalAgentToolCatalog {
    static func discover(
        configuration: OmuxConfigAgent,
        pluginsDirectoryURL: URL = OmuxConfigPaths.pluginsDirectoryURL,
        fileManager: FileManager = .default
    ) -> [OmuxExternalAgentTool] {
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
            .flatMap { tools(forPluginDirectory: $0, configuration: configuration, fileManager: fileManager) }
            .sorted { $0.toolName.localizedCaseInsensitiveCompare($1.toolName) == .orderedAscending }
    }

    private static func tools(
        forPluginDirectory pluginDirectoryURL: URL,
        configuration: OmuxConfigAgent,
        fileManager: FileManager
    ) -> [OmuxExternalAgentTool] {
        let manifestURL = pluginDirectoryURL.appendingPathComponent("omux-plugin.toml", isDirectory: false)
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return []
        }

        let parseResult = OmuxTOMLParser.parse(fileAt: manifestURL)
        guard let document = parseResult.document, parseResult.diagnostics.isEmpty else {
            return []
        }
        guard document.value(for: "kind")?.stringValue == "plugin" else {
            return []
        }

        let pluginID = document.value(for: "id")?.stringValue?.nilIfBlank ?? pluginDirectoryURL.lastPathComponent
        let commandName = document.value(in: "plugin", for: "command")?.stringValue?.nilIfBlank ?? pluginID
        let setting = configuration.externalPlugins[commandName] ?? configuration.externalPlugins[pluginID]
        if setting?.enabled == false {
            return []
        }

        let entrypoint = document.value(in: "plugin", for: "entrypoint")?.stringValue?.nilIfBlank ?? "plugin"
        let executableURL = pluginDirectoryURL.appendingPathComponent(entrypoint, isDirectory: false)
        guard isExecutableRegularFile(executableURL, fileManager: fileManager) else {
            return []
        }

        let toolTables = document.tableNames
            .filter { $0.hasPrefix("agent-tools.") }
            .sorted()

        return toolTables.compactMap { tableName in
            let toolID = String(tableName.dropFirst("agent-tools.".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard CLIPluginRegistryCommandValidator.isValidName(toolID),
                  let description = document.value(in: tableName, for: "description")?.stringValue?.nilIfBlank,
                  let callback = document.value(in: tableName, for: "callback")?.stringValue?.nilIfBlank else {
                return nil
            }

            return OmuxExternalAgentTool(
                pluginID: pluginID,
                pluginCommand: commandName,
                toolID: toolID,
                toolName: "\(commandName).\(toolID)",
                description: description,
                callback: callback,
                arguments: stringArray(document.value(in: tableName, for: "arguments")),
                inputHint: document.value(in: tableName, for: "input_hint")?.stringValue?.nilIfBlank,
                executableURL: executableURL,
                pluginDirectoryURL: pluginDirectoryURL
            )
        }
    }

    private static func stringArray(_ value: OmuxTOMLValue?) -> [String] {
        guard case .array(let values) = value else {
            return []
        }
        return values.compactMap(\.stringValue)
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func isExecutableRegularFile(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue == false else {
            return false
        }
        return fileManager.isExecutableFile(atPath: url.path)
    }
}

private enum CLIPluginRegistryCommandValidator {
    static func isValidName(_ value: String) -> Bool {
        guard value.isEmpty == false,
              value.first != "-",
              value.first != "." else {
            return false
        }
        return value.allSatisfy { character in
            character.isLetter || character.isNumber || character == "-" || character == "_" || character == "."
        }
    }
}

final class OmuxAgentWorkspaceAccess: @unchecked Sendable {
    static let defaultExternalToolTimeoutNanoseconds = UInt64(OmuxConfigAgent.defaultExternalToolTimeoutSeconds) * 1_000_000_000

    let rootURL: URL
    let allowReadAnywhere: Bool
    let focusedPaneID: String?
    let limits: OmuxAgentWorkspaceLimits
    let fileManager: FileManager
    let rgRunner: OmuxAgentRGRunner
    let omuxCommandRunner: OmuxAgentCLIRunner?
    let historyFetcher: OmuxAgentHistoryFetcher?
    let logger: (@Sendable (String) -> Void)?
    let toolEventHandler: (@Sendable (OmuxAgentToolEvent) -> Void)?
    let externalToolTimeoutNanoseconds: UInt64

    init(
        rootURL: URL,
        allowReadAnywhere: Bool = false,
        focusedPaneID: String? = nil,
        limits: OmuxAgentWorkspaceLimits = OmuxAgentWorkspaceLimits(),
        fileManager: FileManager = .default,
        rgRunner: @escaping OmuxAgentRGRunner = OmuxAgentWorkspaceAccess.defaultRGRunner,
        omuxCommandRunner: OmuxAgentCLIRunner? = nil,
        historyFetcher: OmuxAgentHistoryFetcher? = nil,
        logger: (@Sendable (String) -> Void)? = nil,
        toolEventHandler: (@Sendable (OmuxAgentToolEvent) -> Void)? = nil,
        externalToolTimeoutNanoseconds: UInt64 = OmuxAgentWorkspaceAccess.defaultExternalToolTimeoutNanoseconds
    ) {
        self.rootURL = rootURL.resolvingSymlinksInPath().standardizedFileURL
        self.allowReadAnywhere = allowReadAnywhere
        self.focusedPaneID = focusedPaneID
        self.limits = limits
        self.fileManager = fileManager
        self.rgRunner = rgRunner
        self.omuxCommandRunner = omuxCommandRunner
        self.historyFetcher = historyFetcher
        self.logger = logger
        self.toolEventHandler = toolEventHandler
        self.externalToolTimeoutNanoseconds = externalToolTimeoutNanoseconds
    }

    func readFile(path: String, startLine: Int?, endLine: Int?) -> String {
        logger?("calling tool: read_file path=\(path) startLine=\(startLine.map(String.init) ?? "nil") endLine=\(endLine.map(String.init) ?? "nil")")
        emitToolEvent(toolName: "read_file", phase: .started, detail: "path=\(path)")
        let validated = validatedFileURL(path: path)
        if let error = validated.error {
            logger?("tool failed: read_file error=\(error)")
            emitToolEvent(toolName: "read_file", phase: .failed, detail: error)
            return error
        }
        if let fileURL = validated.url {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) else {
                logger?("tool failed: read_file error=file not found")
                emitToolEvent(toolName: "read_file", phase: .failed, detail: "file not found")
                return "ERROR: file not found: \(path)"
            }
            guard isDirectory.boolValue == false else {
                logger?("tool failed: read_file error=target is directory")
                emitToolEvent(toolName: "read_file", phase: .failed, detail: "target is directory")
                return "ERROR: directories are not supported: \(path)"
            }
            guard fileManager.isReadableFile(atPath: fileURL.path) else {
                logger?("tool failed: read_file error=file not readable")
                emitToolEvent(toolName: "read_file", phase: .failed, detail: "file not readable")
                return "ERROR: file is not readable: \(path)"
            }
            let fileSize = (try? fileManager.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.intValue
            guard let totalLines = try? Self.countLines(in: fileURL) else {
                logger?("tool failed: read_file error=unable to read file contents")
                emitToolEvent(toolName: "read_file", phase: .failed, detail: "unable to read file contents")
                return "ERROR: unable to read file: \(path)"
            }

            let requestedStart = max(startLine ?? 1, 1)
            let normalizedStart = min(requestedStart, totalLines)

            if let endLine, endLine < normalizedStart {
                logger?("tool failed: read_file error=invalid line range")
                emitToolEvent(toolName: "read_file", phase: .failed, detail: "invalid line range")
                return "ERROR: endLine must be greater than or equal to startLine"
            }

            let maxEndByLines = normalizedStart + max(limits.maxReadLines - 1, 0)
            let requestedEnd = max(endLine ?? totalLines, normalizedStart)
            let normalizedEnd = min(requestedEnd, maxEndByLines, totalLines)

            guard let excerptResult = try? Self.readExcerpt(
                from: fileURL,
                startLine: normalizedStart,
                endLine: normalizedEnd
            ) else {
                logger?("tool failed: read_file error=unable to read file contents")
                emitToolEvent(toolName: "read_file", phase: .failed, detail: "unable to read file contents")
                return "ERROR: unable to read file: \(path)"
            }

            if excerptResult.lines.isEmpty && totalLines == 1 {
                logger?("completed tool: read_file path=\(relativePath(for: fileURL)) lines=1-1 truncated=no bytes=0")
                let output = """
                PATH: \(relativePath(for: fileURL))
                LINES: 1-1 of 1
                TRUNCATED: no
                CONTENT:

                """
                emitToolEvent(toolName: "read_file", phase: .completed, detail: "path=\(relativePath(for: fileURL))", outputBytes: 0, outputText: output)
                return output
            }

            let joined = excerptResult.lines.joined(separator: "\n")
            let clipped = Self.prefix(joined, maxUTF8Bytes: limits.maxReadBytes)
            let truncated = normalizedEnd < totalLines
                || clipped.truncated
                || (fileSize.map { $0 > limits.maxReadBytes } ?? false)
            let actualEnd = excerptResult.actualEnd
            logger?("completed tool: read_file path=\(relativePath(for: fileURL)) lines=\(normalizedStart)-\(actualEnd) truncated=\(truncated ? "yes" : "no") bytes=\(clipped.text.utf8.count)")
            let output = """
            PATH: \(relativePath(for: fileURL))
            LINES: \(normalizedStart)-\(actualEnd) of \(totalLines)
            TRUNCATED: \(truncated ? "yes" : "no")
            CONTENT:
            \(clipped.text)
            """
            emitToolEvent(toolName: "read_file", phase: .completed, detail: "path=\(relativePath(for: fileURL)) lines=\(normalizedStart)-\(actualEnd)", outputBytes: clipped.text.utf8.count, outputText: output)
            return output
        }
        logger?("tool failed: read_file error=unable to validate file path")
        emitToolEvent(toolName: "read_file", phase: .failed, detail: "unable to validate file path")
        return "ERROR: unable to validate file path"
    }

    func grep(_ request: OmuxAgentGrepRequest) -> String {
        let pattern = request.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard pattern.isEmpty == false else {
            logger?("tool failed: grep_files error=empty pattern")
            emitToolEvent(toolName: "grep_files", phase: .failed, detail: "empty pattern")
            return "ERROR: grep pattern must not be empty"
        }

        let cappedRequest = OmuxAgentGrepRequest(
            pattern: pattern,
            globs: request.globs.filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false },
            caseMode: request.caseMode,
            includeHidden: request.includeHidden,
            maxResults: request.maxResults
        )
        logger?("calling tool: grep_files pattern=\(pattern) globs=\(cappedRequest.globs.count) caseMode=\(cappedRequest.caseMode.rawValue) includeHidden=\(cappedRequest.includeHidden) maxResults=\(cappedRequest.maxResults.map(String.init) ?? "default")")
        emitToolEvent(toolName: "grep_files", phase: .started, detail: "pattern=\(pattern)")

        guard let result = try? rgRunner(cappedRequest, rootURL, limits) else {
            logger?("tool failed: grep_files error=rg unavailable or failed")
            emitToolEvent(toolName: "grep_files", phase: .failed, detail: "rg unavailable or failed")
            return "ERROR: ripgrep (rg) is unavailable or search failed"
        }

        if result.matches.isEmpty {
            logger?("completed tool: grep_files matches=0 truncated=no")
            let output = "MATCHES: 0\nTRUNCATED: no"
            emitToolEvent(toolName: "grep_files", phase: .completed, detail: "matches=0", outputBytes: 0, outputText: output)
            return output
        }

        let lines = result.matches.map { match in
            "\(match.path):\(match.line): \(match.text)"
        }.joined(separator: "\n")
        logger?("completed tool: grep_files matches=\(result.matches.count) truncated=\(result.truncated ? "yes" : "no") bytes=\(lines.utf8.count)")
        let output = """
        MATCHES: \(result.matches.count)
        TRUNCATED: \(result.truncated ? "yes" : "no")
        RESULTS:
        \(lines)
        """
        emitToolEvent(toolName: "grep_files", phase: .completed, detail: "matches=\(result.matches.count)", outputBytes: lines.utf8.count, outputText: output)
        return output
    }

    func listDirectory(path: String?) -> String {
        let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetPath = (trimmed?.isEmpty == false) ? trimmed! : "."
        logger?("calling tool: list_directory path=\(targetPath)")
        emitToolEvent(toolName: "list_directory", phase: .started, detail: "path=\(targetPath)")

        let validated = validatedFileURL(path: targetPath)
        if let error = validated.error {
            logger?("tool failed: list_directory error=\(error)")
            emitToolEvent(toolName: "list_directory", phase: .failed, detail: error)
            return error
        }
        guard let directoryURL = validated.url else {
            logger?("tool failed: list_directory error=unable to validate path")
            emitToolEvent(toolName: "list_directory", phase: .failed, detail: "unable to validate path")
            return "ERROR: unable to validate directory path"
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) else {
            logger?("tool failed: list_directory error=directory not found")
            emitToolEvent(toolName: "list_directory", phase: .failed, detail: "directory not found")
            return "ERROR: directory not found: \(targetPath)"
        }
        guard isDirectory.boolValue else {
            logger?("tool failed: list_directory error=target is not a directory")
            emitToolEvent(toolName: "list_directory", phase: .failed, detail: "target is not a directory")
            return "ERROR: path is not a directory: \(targetPath)"
        }

        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isHiddenKey]
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsPackageDescendants]
        ) else {
            logger?("tool failed: list_directory error=unable to read directory contents")
            emitToolEvent(toolName: "list_directory", phase: .failed, detail: "unable to read directory contents")
            return "ERROR: unable to read directory: \(targetPath)"
        }

        let visibleURLs = urls.filter { url in
            let values = try? url.resourceValues(forKeys: keys)
            return values?.isHidden != true
        }.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }

        let entries = visibleURLs.prefix(limits.maxDirectoryEntries).map { url -> String in
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            return isDirectory ? "\(url.lastPathComponent)/" : url.lastPathComponent
        }
        let truncated = visibleURLs.count > limits.maxDirectoryEntries
        let listed = entries.joined(separator: "\n")
        logger?("completed tool: list_directory path=\(relativePath(for: directoryURL)) entries=\(entries.count) truncated=\(truncated ? "yes" : "no") bytes=\(listed.utf8.count)")
        let output = """
        PATH: \(relativePath(for: directoryURL))
        ENTRIES: \(entries.count)
        TRUNCATED: \(truncated ? "yes" : "no")
        CONTENTS:
        \(listed.isEmpty ? "(empty directory)" : listed)
        """
        emitToolEvent(toolName: "list_directory", phase: .completed, detail: "path=\(relativePath(for: directoryURL)) entries=\(entries.count)", outputBytes: listed.utf8.count, outputText: output)
        return output
    }

    func runOmuxCLI(command: String, arguments: [String]) -> String {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedCommand.isEmpty == false else {
            logger?("tool failed: run_omux_cli error=empty command")
            emitToolEvent(toolName: "run_omux_cli", phase: .failed, detail: "empty command")
            return "ERROR: command must not be empty"
        }

        guard let omuxCommandRunner else {
            logger?("tool failed: run_omux_cli error=command runner unavailable")
            emitToolEvent(toolName: "run_omux_cli", phase: .failed, detail: "command runner unavailable")
            return "ERROR: omux command execution is unavailable in this host session"
        }

        let filteredArguments = arguments.filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
        logger?("calling tool: run_omux_cli command=\(trimmedCommand) args=\(filteredArguments.joined(separator: " "))")
        emitToolEvent(toolName: "run_omux_cli", phase: .started, detail: ([trimmedCommand] + filteredArguments).joined(separator: " "))

        switch trimmedCommand {
        case "agent", "__update-helper", "__debug-update":
            logger?("tool failed: run_omux_cli error=blocked command")
            emitToolEvent(toolName: "run_omux_cli", phase: .failed, detail: "blocked command")
            return "ERROR: omux \(trimmedCommand) is not allowed from the agent tool"
        case "events":
            logger?("tool failed: run_omux_cli error=streaming command blocked")
            emitToolEvent(toolName: "run_omux_cli", phase: .failed, detail: "streaming command blocked")
            return "ERROR: omux events is not allowed from the agent tool because it is a streaming command"
        case "theme" where filteredArguments.isEmpty:
            logger?("tool failed: run_omux_cli error=interactive command blocked")
            emitToolEvent(toolName: "run_omux_cli", phase: .failed, detail: "interactive command blocked")
            return "ERROR: omux theme without arguments is not allowed from the agent tool because it is interactive"
        default:
            break
        }

        let invocation = [trimmedCommand] + filteredArguments
        if let blockedReason = Self.blockedOmuxInvocationReason(for: invocation) {
            logger?("tool failed: run_omux_cli error=\(blockedReason)")
            emitToolEvent(toolName: "run_omux_cli", phase: .failed, detail: blockedReason)
            return "ERROR: \(blockedReason)"
        }
        let result = omuxCommandRunner(invocation)
        logger?("completed tool: run_omux_cli command=\(trimmedCommand) exitCode=\(result.exitCode)")
        let output = """
        COMMAND: omux \(invocation.joined(separator: " "))
        EXIT_CODE: \(result.exitCode)
        OUTPUT:
        \(result.output.isEmpty ? "(no output)" : result.output)
        """
        emitToolEvent(toolName: "run_omux_cli", phase: .completed, detail: "command=\(trimmedCommand) exitCode=\(result.exitCode)", outputBytes: result.output.utf8.count, outputText: output)
        return output
    }

    func readTerminalHistory(paneID: String?, maxLines: Int?, maxBytes: Int?) -> String {
        let normalizedPaneID: String? = {
            let candidate = paneID ?? focusedPaneID
            guard let candidate else { return nil }
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }()
        let targetDescription = paneID == nil ? (normalizedPaneID ?? "active-workspace") : (normalizedPaneID ?? "requested-pane")
        logger?("calling tool: read_terminal_history target=\(targetDescription) maxLines=\(maxLines.map(String.init) ?? "default") maxBytes=\(maxBytes.map(String.init) ?? "default")")
        emitToolEvent(toolName: "read_terminal_history", phase: .started, detail: "target=\(targetDescription)")

        guard let historyFetcher else {
            logger?("tool failed: read_terminal_history error=history unavailable")
            emitToolEvent(toolName: "read_terminal_history", phase: .failed, detail: "history unavailable")
            return "ERROR: terminal history is unavailable in this host session"
        }

        let effectiveMaxLines = min(max(maxLines ?? limits.maxHistoryLines, 1), limits.maxHistoryLines)
        let effectiveMaxBytes = min(max(maxBytes ?? limits.maxHistoryBytes, 1), limits.maxHistoryBytes)
        let scope: ControlPlaneHistoryScope
        if let normalizedPaneID {
            scope = .pane(PaneID(rawValue: normalizedPaneID))
        } else {
            scope = .activeWorkspace
        }
        let request = ControlPlaneHistoryRequest(scope: scope, maxBytes: effectiveMaxBytes, maxLines: effectiveMaxLines)

        guard let result = try? historyFetcher(request),
              case .object(let object) = result,
              case .array(let items)? = object["items"]
        else {
            logger?("tool failed: read_terminal_history error=request failed")
            emitToolEvent(toolName: "read_terminal_history", phase: .failed, detail: "request failed")
            return "ERROR: unable to fetch terminal history"
        }

        guard let firstItem = items.first,
              case .object(let history) = firstItem
        else {
            logger?("completed tool: read_terminal_history items=0")
            let output = """
            TARGET: \(targetDescription)
            NO_HISTORY: yes
            """
            emitToolEvent(toolName: "read_terminal_history", phase: .completed, detail: "items=0", outputBytes: 0, outputText: output)
            return output
        }

        let workspaceName = Self.rpcString(history["workspaceName"]) ?? "workspace"
        let workspaceID = Self.rpcString(history["workspaceID"]) ?? "unknown"
        let tabTitle = Self.rpcString(history["tabTitle"]) ?? "tab"
        let tabID = Self.rpcString(history["tabID"]) ?? "unknown"
        let paneTitle = Self.rpcString(history["paneTitle"]) ?? "pane"
        let resolvedPaneID = Self.rpcString(history["paneID"]) ?? normalizedPaneID ?? "unknown"
        let sessionID = Self.rpcString(history["sessionID"]) ?? "unknown"
        let workingDirectory = Self.rpcNullableString(history["workingDirectory"])
        let lineCount = Self.rpcInt(history["lineCount"]) ?? 0
        let byteCount = Self.rpcInt(history["byteCount"]) ?? 0
        let truncated = Self.rpcBool(history["truncated"]) ?? false
        let unavailable = Self.rpcNullableString(history["unavailable"])
        let text = Self.rpcString(history["text"]) ?? ""
        logger?("completed tool: read_terminal_history pane=\(resolvedPaneID) lines=\(lineCount) truncated=\(truncated ? "yes" : "no") bytes=\(text.utf8.count)")
        var lines = [
            "TARGET: \(targetDescription)",
            "WORKSPACE: \(workspaceName) (\(workspaceID))",
            "TAB: \(tabTitle) (\(tabID))",
            "PANE: \(paneTitle) (\(resolvedPaneID))",
            "SESSION: \(sessionID)",
        ]
        if let workingDirectory {
            lines.append("CWD: \(workingDirectory)")
        }
        lines.append("LINES: \(lineCount)")
        lines.append("BYTES: \(byteCount)")
        lines.append("TRUNCATED: \(truncated ? "yes" : "no")")
        if let unavailable {
            lines.append("UNAVAILABLE: \(unavailable)")
        }
        lines.append("CONTENT:")
        lines.append(text.isEmpty ? "(no history)" : text)
        let output = lines.joined(separator: "\n")
        emitToolEvent(toolName: "read_terminal_history", phase: .completed, detail: "pane=\(resolvedPaneID) lines=\(lineCount)", outputBytes: text.utf8.count, outputText: output)
        return output
    }

    func listSkills() -> String {
        logger?("calling tool: list_skills")
        emitToolEvent(toolName: "list_skills", phase: .started, detail: "discover")
        let skills = OmuxAgentSkillCatalog.discover(workingDirectoryURL: rootURL, fileManager: fileManager)
        guard skills.isEmpty == false else {
            let output = "SKILLS: 0"
            emitToolEvent(toolName: "list_skills", phase: .completed, detail: "skills=0", outputBytes: 0, outputText: output)
            return output
        }

        let lines = skills.map { skill in
            "\(skill.name) | \(skill.description) | scope=\(skill.scope.rawValue) | root=\(skill.rootURL.path)"
        }.joined(separator: "\n")
        let output = """
        SKILLS: \(skills.count)
        RESULTS:
        \(lines)
        """
        logger?("completed tool: list_skills skills=\(skills.count)")
        emitToolEvent(toolName: "list_skills", phase: .completed, detail: "skills=\(skills.count)", outputBytes: lines.utf8.count, outputText: output)
        return output
    }

    func readSkill(name: String, includePaths: [String]) -> String {
        logger?("calling tool: read_skill name=\(name) includePaths=\(includePaths.count)")
        emitToolEvent(toolName: "read_skill", phase: .started, detail: "name=\(name)")
        do {
            let result = try OmuxAgentSkillCatalog.readSkill(
                named: name,
                includePaths: includePaths,
                workingDirectoryURL: rootURL,
                fileManager: fileManager
            )
            var lines = [
                "NAME: \(result.skill.name)",
                "DESCRIPTION: \(result.skill.description)",
                "SCOPE: \(result.skill.scope.rawValue)",
                "ROOT: \(result.skill.rootURL.path)",
                "SKILL_MD:",
                result.skill.body,
            ]
            if result.files.isEmpty == false {
                lines.append("INCLUDED_FILES:")
                for file in result.files {
                    lines.append("FILE: \(file.relativePath)")
                    lines.append(file.contents)
                }
            }
            let output = lines.joined(separator: "\n")
            logger?("completed tool: read_skill name=\(name) files=\(result.files.count)")
            emitToolEvent(toolName: "read_skill", phase: .completed, detail: "name=\(name) files=\(result.files.count)", outputBytes: output.utf8.count, outputText: output)
            return output
        } catch {
            let message = "ERROR: \(error.localizedDescription)"
            logger?("tool failed: read_skill error=\(message)")
            emitToolEvent(toolName: "read_skill", phase: .failed, detail: error.localizedDescription)
            return message
        }
    }

    func callExternalTool(_ tool: OmuxExternalAgentTool, input: String) async throws -> String {
        logger?("calling tool: \(tool.toolName) plugin=\(tool.pluginCommand) callback=\(tool.callback)")
        emitToolEvent(toolName: tool.toolName, phase: .started, detail: "plugin=\(tool.pluginCommand)")

        let request = OmuxExternalAgentToolRequest(
            tool: .init(name: tool.toolName, pluginCommand: tool.pluginCommand, toolID: tool.toolID),
            input: input,
            cwd: rootURL.path,
            focusedPaneID: focusedPaneID
        )
        let requestData = try JSONEncoder().encode(request)

        let process = Process()
        process.executableURL = tool.executableURL
        process.arguments = [tool.callback] + tool.arguments
        process.currentDirectoryURL = rootURL
        process.environment = externalToolEnvironment(for: tool)

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()

        stdin.fileHandleForWriting.writeabilityHandler = { handle in
            handle.writeabilityHandler = nil
            do {
                try handle.write(contentsOf: requestData)
            } catch {
            }
            try? handle.close()
        }

        let stdoutHandle = stdout.fileHandleForReading
        let stderrHandle = stderr.fileHandleForReading
        let stdoutTask = Task.detached { stdoutHandle.readDataToEndOfFile() }
        let stderrTask = Task.detached { stderrHandle.readDataToEndOfFile() }

        let startedAt = DispatchTime.now().uptimeNanoseconds
        while process.isRunning {
            let elapsed = DispatchTime.now().uptimeNanoseconds - startedAt
            if elapsed >= externalToolTimeoutNanoseconds {
                process.terminate()
                try? await Task.sleep(nanoseconds: 200_000_000)
                if process.isRunning {
                    process.interrupt()
                }
                if await Self.waitForExit(process, timeoutNanoseconds: 500_000_000) == false, process.processIdentifier > 0 {
                    _ = kill(process.processIdentifier, SIGKILL)
                    _ = await Self.waitForExit(process, timeoutNanoseconds: 1_000_000_000)
                }
                let stderrOutput = String(decoding: await stderrTask.value, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let detail = "timed out after \(externalToolTimeoutNanoseconds / 1_000_000_000)s"
                logger?("tool failed: \(tool.toolName) error=\(detail)")
                emitToolEvent(toolName: tool.toolName, phase: .failed, detail: detail)
                throw NSError(
                    domain: "OmuxExternalAgentTool",
                    code: 124,
                    userInfo: [NSLocalizedDescriptionKey: stderrOutput.isEmpty ? detail : "\(detail): \(stderrOutput)"]
                )
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        let stdoutData = await stdoutTask.value
        let stderrText = String(decoding: await stderrTask.value, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            let detail = "plugin exited with status \(process.terminationStatus)"
            logger?("tool failed: \(tool.toolName) error=\(detail)")
            emitToolEvent(toolName: tool.toolName, phase: .failed, detail: detail)
            throw NSError(
                domain: "OmuxExternalAgentTool",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: stderrText.isEmpty ? detail : stderrText]
            )
        }

        let response = try JSONDecoder().decode(OmuxExternalAgentToolResponse.self, from: stdoutData)
        if response.ok == false {
            let detail = response.error?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? "plugin returned an error"
            logger?("tool failed: \(tool.toolName) error=\(detail)")
            emitToolEvent(toolName: tool.toolName, phase: .failed, detail: detail)
            throw NSError(domain: "OmuxExternalAgentTool", code: 1, userInfo: [NSLocalizedDescriptionKey: detail])
        }

        let output = response.output ?? ""
        logger?("completed tool: \(tool.toolName) bytes=\(output.utf8.count)")
        emitToolEvent(toolName: tool.toolName, phase: .completed, detail: "plugin=\(tool.pluginCommand)", outputBytes: output.utf8.count, outputText: output)
        return output
    }

    private func validatedFileURL(path: String) -> (url: URL?, error: String?) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return (nil, "ERROR: path must not be empty")
        }

        let candidate = URL(fileURLWithPath: trimmed, relativeTo: rootURL).standardizedFileURL
        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard allowReadAnywhere || Self.isWithinRoot(resolved, root: rootURL) else {
            return (nil, "ERROR: path escapes the current working directory")
        }
        return (resolved, nil)
    }

    private func relativePath(for fileURL: URL) -> String {
        let rootPath = rootURL.path
        let filePath = fileURL.path
        if filePath == rootPath {
            return "."
        }
        if filePath.hasPrefix(rootPath + "/") {
            return String(filePath.dropFirst(rootPath.count + 1))
        }
        return filePath
    }

    private func emitToolEvent(
        toolName: String,
        phase: OmuxAgentToolEvent.Phase,
        detail: String,
        outputBytes: Int? = nil,
        outputText: String? = nil
    ) {
        toolEventHandler?(OmuxAgentToolEvent(
            toolName: toolName,
            phase: phase,
            detail: detail,
            outputBytes: outputBytes,
            outputText: outputText
        ))
    }

    private func externalToolEnvironment(for tool: OmuxExternalAgentTool) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["OMUX_PLUGIN_COMMAND"] = tool.pluginCommand
        environment["OMUX_PLUGIN_EXECUTABLE"] = tool.executableURL.path
        environment["OMUX_PLUGINS_DIR"] = tool.pluginDirectoryURL.deletingLastPathComponent().path
        environment["OMUX_AGENT_TOOL_NAME"] = tool.toolName
        if environment["OMUX_CLI"] == nil,
           let executableURL = Bundle.main.executableURL,
           FileManager.default.isExecutableFile(atPath: executableURL.path) {
            environment["OMUX_CLI"] = executableURL.lastPathComponent == "omux" ? executableURL.path : "omux"
        }
        return environment
    }

    private static func isWithinRoot(_ fileURL: URL, root: URL) -> Bool {
        let filePath = fileURL.path
        let rootPath = root.path
        return filePath == rootPath || filePath.hasPrefix(rootPath + "/")
    }

    private static func prefix(_ value: String, maxUTF8Bytes: Int) -> (text: String, truncated: Bool) {
        guard value.utf8.count > maxUTF8Bytes else {
            return (value, false)
        }

        var result = ""
        var usedBytes = 0
        for character in value {
            let encodedLength = String(character).utf8.count
            if usedBytes + encodedLength > maxUTF8Bytes {
                break
            }
            result.append(character)
            usedBytes += encodedLength
        }
        return (result, true)
    }

    private static func countLines(in fileURL: URL) throws -> Int {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var newlineCount = 0
        var sawBytes = false
        while true {
            let chunk = try handle.read(upToCount: 8_192) ?? Data()
            if chunk.isEmpty {
                break
            }
            sawBytes = true
            newlineCount += chunk.reduce(into: 0) { partialResult, byte in
                if byte == 0x0A {
                    partialResult += 1
                }
            }
        }

        return sawBytes ? max(newlineCount + 1, 1) : 1
    }

    private static func readExcerpt(
        from fileURL: URL,
        startLine: Int,
        endLine: Int
    ) throws -> (lines: [String], actualEnd: Int) {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var currentLine = Data()
        var currentLineNumber = 1
        var selectedLines: [String] = []

        func finishCurrentLine(finalLine: Bool = false) {
            if currentLineNumber >= startLine && currentLineNumber <= endLine {
                selectedLines.append(String(decoding: currentLine, as: UTF8.self))
            }
            if finalLine == false || currentLine.isEmpty == false {
                currentLineNumber += 1
            }
            currentLine.removeAll(keepingCapacity: true)
        }

        while currentLineNumber <= endLine {
            let chunk = try handle.read(upToCount: 8_192) ?? Data()
            if chunk.isEmpty {
                finishCurrentLine(finalLine: true)
                break
            }

            for byte in chunk {
                if byte == 0x0A {
                    finishCurrentLine()
                    if currentLineNumber > endLine {
                        break
                    }
                } else {
                    currentLine.append(byte)
                }
            }
        }

        if selectedLines.isEmpty && startLine == 1 && endLine == 1 && currentLineNumber == 1 {
            return ([], 1)
        }
        return (selectedLines, startLine + max(selectedLines.count - 1, 0))
    }

    private static func blockedOmuxInvocationReason(for invocation: [String]) -> String? {
        guard let command = invocation.first else {
            return "command must not be empty"
        }

        let interactiveCommands: Set<String> = [
            "install",
            "install-cli",
            "self-update",
            "uninstall",
            "update",
            "upgrade",
        ]
        if interactiveCommands.contains(command) {
            return "omux \(command) is not allowed from the agent tool because it installs, updates, or removes state"
        }

        if invocation.count >= 2, command == "config", invocation[1] == "open" {
            return "omux config open is not allowed from the agent tool because it launches an external editor"
        }

        return nil
    }

    private static func waitForExit(_ process: Process, timeoutNanoseconds: UInt64) async -> Bool {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        while process.isRunning {
            if DispatchTime.now().uptimeNanoseconds - startedAt >= timeoutNanoseconds {
                return false
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return true
    }

    private static func defaultRGRunner(
        request: OmuxAgentGrepRequest,
        rootURL: URL,
        limits: OmuxAgentWorkspaceLimits
    ) throws -> OmuxAgentGrepResult {
        final class PipeBuffer: @unchecked Sendable {
            private let lock = NSLock()
            private var data = Data()

            func append(_ chunk: Data) {
                lock.lock()
                data.append(chunk)
                lock.unlock()
            }

            func snapshot() -> Data {
                lock.lock()
                defer { lock.unlock() }
                return data
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.currentDirectoryURL = rootURL

        let maxResults = min(max(request.maxResults ?? limits.maxGrepResults, 1), limits.maxGrepResults)
        var arguments = [
            "rg",
            "--line-number",
            "--no-heading",
            "--color", "never",
            "--max-count", "\(maxResults)",
        ]

        switch request.caseMode {
        case .smart:
            break
        case .sensitive:
            arguments.append("--case-sensitive")
        case .insensitive:
            arguments.append("--ignore-case")
        }

        if request.includeHidden {
            arguments.append("--hidden")
        }

        for glob in request.globs {
            arguments.append(contentsOf: ["--glob", glob])
        }

        arguments.append(contentsOf: ["--", request.pattern, "."])
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let finished = DispatchSemaphore(value: 0)
        let drainGroup = DispatchGroup()
        let outputBuffer = PipeBuffer()
        let errorBuffer = PipeBuffer()

        drainGroup.enter()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                drainGroup.leave()
                return
            }
            outputBuffer.append(chunk)
        }
        drainGroup.enter()
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                drainGroup.leave()
                return
            }
            errorBuffer.append(chunk)
        }
        process.terminationHandler = { _ in
            finished.signal()
        }
        try process.run()
        finished.wait()
        drainGroup.wait()
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil

        let status = process.terminationStatus
        let output = String(decoding: outputBuffer.snapshot(), as: UTF8.self)
        let errorOutput = String(decoding: errorBuffer.snapshot(), as: UTF8.self)

        if status != 0 && status != 1 {
            throw NSError(
                domain: "OmuxAgentRGRunner",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: errorOutput]
            )
        }

        let rawLines = output.split(separator: "\n", omittingEmptySubsequences: true)
        let parsedMatches = rawLines.prefix(maxResults).compactMap { line -> OmuxAgentGrepMatch? in
            let parts = line.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3, let lineNumber = Int(parts[1]) else {
                return nil
            }

            let clipped = prefix(String(parts[2]), maxUTF8Bytes: limits.maxMatchLineBytes).text
            let rawPath = String(parts[0])
            let normalizedPath = rawPath.hasPrefix("./") ? String(rawPath.dropFirst(2)) : rawPath
            return OmuxAgentGrepMatch(path: normalizedPath, line: lineNumber, text: clipped)
        }

        let truncated = parsedMatches.count >= maxResults && rawLines.count >= maxResults
        return OmuxAgentGrepResult(matches: parsedMatches, truncated: truncated)
    }

    private static func rpcString(_ value: RPCValue?) -> String? {
        guard let value else { return nil }
        if case .string(let string) = value {
            return string
        }
        return nil
    }

    private static func rpcNullableString(_ value: RPCValue?) -> String? {
        guard let value else { return nil }
        if case .null = value {
            return nil
        }
        return rpcString(value)
    }

    private static func rpcInt(_ value: RPCValue?) -> Int? {
        guard let value else { return nil }
        if case .number(let number) = value, number.isFinite {
            return Int(number)
        }
        return nil
    }

    private static func rpcBool(_ value: RPCValue?) -> Bool? {
        guard let value else { return nil }
        if case .bool(let bool) = value {
            return bool
        }
        return nil
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct OmuxSystemAgentGenerator: OmuxAgentGenerating {
    let omuxCommandRunner: OmuxAgentCLIRunner?
    let historyFetcher: OmuxAgentHistoryFetcher?

    init(
        omuxCommandRunner: OmuxAgentCLIRunner? = nil,
        historyFetcher: OmuxAgentHistoryFetcher? = nil
    ) {
        self.omuxCommandRunner = omuxCommandRunner
        self.historyFetcher = historyFetcher
    }

    static let previousDefaultSystemInstruction = """
    You are a concise helpful local assistant.
    Prefer short, practical plain-text answers.
    Treat host context as metadata, not as a task list.
    You may control OpenMUX only by using the run_omux_cli tool.
    You may inspect recent terminal scrollback only by using the read_terminal_history tool.
    You may inspect directory contents only by using the list_directory tool.
    You may inspect local files only by using the provided tools.
    Unless host context says otherwise, file reads and searches are limited to the current working directory.
    Do not read the OpenMUX config file unless the user explicitly asks about OpenMUX configuration or that file.
    Do not infer or construct file paths from OpenMUX workspace, tab, pane, or session identifiers.
    If asked about your instructions, role, or capabilities, answer from this session's instructions and available tools, not by searching local files.
    If the user asks about recent terminal steps, command output, or the focused pane session, prefer read_terminal_history before other tools.
    If the user asks what files or directories exist, prefer list_directory before other file tools.
    If the user asks where code is implemented, prefer grep_files in the current working directory before trying ad hoc file paths.
    If the prompt depends on terminal history or other unavailable context, say that plainly instead of guessing or searching unrelated files.
    Use tools only when they materially help answer the prompt.
    Cite file paths when you rely on tool output.
    """

    static let defaultSystemInstruction = """
    Role:
    Quick local OpenMUX assistant for small tasks and lightweight automation.

    Response style:
    Be concise, practical, and plain text.

    Tool discipline:
    Use tools only when needed.
    Prefer the cheapest relevant tool first.

    Host and path safety:
    Host context is metadata only.
    Never derive filesystem paths from OpenMUX IDs.
    Do not read the OpenMUX config file unless the user explicitly asks about OpenMUX configuration or that file.

    Retrieval order:
    Recent terminal or session questions -> read_terminal_history
    What exists here -> list_directory
    Where is this implemented -> grep_files
    File-content questions -> read_file
    OpenMUX control -> run_omux_cli
    Reusable workflow guidance -> skills tools
    Specialized local workflows -> plugin tools when one clearly matches

    If required context is unavailable, say so plainly instead of guessing.
    Cite file paths when tool output informs the answer.
    """

    func generate(
        prompt: String,
        systemInstruction: String?,
        hostContext: String,
        agentConfiguration: OmuxConfigAgent,
        workingDirectoryURL: URL,
        allowReadAnywhere: Bool,
        onVerbose: (@Sendable (String) -> Void)?,
        onPartial: @escaping (String) -> Void
    ) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = try Self.requireAvailableModel(onVerbose: onVerbose)
            let effectiveInstruction = Self.effectiveSystemInstruction(systemInstruction)
            let access = Self.makeWorkspaceAccess(
                workingDirectoryURL: workingDirectoryURL,
                hostContext: hostContext,
                configuration: agentConfiguration,
                allowReadAnywhere: allowReadAnywhere,
                omuxCommandRunner: omuxCommandRunner,
                historyFetcher: historyFetcher,
                onVerbose: onVerbose
            )
            let tools = Self.makeTools(access: access, configuration: agentConfiguration)

            let toolNames = tools.map(\.name).joined(separator: ", ")
            onVerbose?("registered tools: \(toolNames)")
            let session = LanguageModelSession(model: model, tools: tools) {
                effectiveInstruction
            }

            onVerbose?("streaming model response")
            let fullPrompt = """
            \(hostContext)

            User request:
            \(prompt)
            """
            let stream = session.streamResponse(to: fullPrompt)
            var emitted = ""
            var sawFirstChunk = false

            for try await snapshot in stream {
                let content = snapshot.content
                guard content.count >= emitted.count else {
                    emitted = content
                    onPartial(content)
                    continue
                }

                let delta = String(content.dropFirst(emitted.count))
                if delta.isEmpty == false {
                    if sawFirstChunk == false {
                        onVerbose?("received first response chunk")
                        sawFirstChunk = true
                    }
                    onPartial(delta)
                    emitted = content
                }
            }

            let final = try await stream.collect()
            if final.content.count > emitted.count {
                onPartial(String(final.content.dropFirst(emitted.count)))
            }
            onVerbose?("response complete")
            return final.content
        } else {
            onVerbose?("Foundation Models unsupported on this platform")
            throw OmuxAgentError.unsupportedPlatform
        }
        #else
        onVerbose?("Foundation Models framework unavailable at build/runtime")
        throw OmuxAgentError.unsupportedPlatform
        #endif
    }

    static func effectiveSystemInstruction(_ systemInstruction: String?) -> String {
        (systemInstruction?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? systemInstruction!
            : defaultSystemInstruction
    }

    static func defaultPromptAnalysis(
        tokenCounter: ((String) -> Int?)? = nil
    ) -> OmuxAgentDefaultPromptAnalysis {
        let currentLength = defaultSystemInstruction.utf8.count
        let previousLength = previousDefaultSystemInstruction.utf8.count
        return OmuxAgentDefaultPromptAnalysis(
            currentLength: currentLength,
            previousLength: previousLength,
            currentTokenCount: tokenCounter?(defaultSystemInstruction),
            previousTokenCount: tokenCounter?(previousDefaultSystemInstruction)
        )
    }

    static func makeWorkspaceAccess(
        workingDirectoryURL: URL,
        hostContext: String,
        configuration: OmuxConfigAgent,
        allowReadAnywhere: Bool,
        omuxCommandRunner: OmuxAgentCLIRunner?,
        historyFetcher: OmuxAgentHistoryFetcher?,
        onVerbose: (@Sendable (String) -> Void)?,
        onToolEvent: (@Sendable (OmuxAgentToolEvent) -> Void)? = nil
    ) -> OmuxAgentWorkspaceAccess {
        onVerbose?("creating agent session for cwd=\(workingDirectoryURL.path)")
        return OmuxAgentWorkspaceAccess(
            rootURL: workingDirectoryURL,
            allowReadAnywhere: allowReadAnywhere,
            focusedPaneID: hostContext
                .split(separator: "\n")
                .first(where: { $0.hasPrefix("openmux.focused.paneID: ") })
                .map { String($0.dropFirst("openmux.focused.paneID: ".count)) },
            omuxCommandRunner: omuxCommandRunner,
            historyFetcher: historyFetcher,
            logger: onVerbose,
            toolEventHandler: onToolEvent,
            externalToolTimeoutNanoseconds: UInt64(configuration.externalToolTimeoutSeconds) * 1_000_000_000
        )
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    static func requireAvailableModel(
        onVerbose: (@Sendable (String) -> Void)?
    ) throws -> SystemLanguageModel {
        onVerbose?("checking Apple Foundation Models availability")
        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            onVerbose?("Apple Foundation Models unavailable on this host")
            throw OmuxAgentError.unavailable
        }
        return model
    }

    @available(macOS 26.0, *)
    static func makeTools(
        access: OmuxAgentWorkspaceAccess,
        configuration: OmuxConfigAgent
    ) -> [any Tool] {
        var tools: [any Tool] = []
        if configuration.tools.readTerminalHistory {
            tools.append(OmuxReadTerminalHistoryTool(access: access))
        }
        if configuration.tools.listDirectory {
            tools.append(OmuxListDirectoryTool(access: access))
        }
        if configuration.tools.runOmuxCLI {
            tools.append(OmuxRunCLICommandTool(access: access))
        }
        if configuration.tools.readFile {
            tools.append(OmuxReadFileTool(access: access))
        }
        if configuration.tools.grepFiles {
            tools.append(OmuxGrepTool(access: access))
        }
        if configuration.skillsEnabled && configuration.tools.listSkills {
            tools.append(OmuxListSkillsTool(access: access))
        }
        if configuration.skillsEnabled && configuration.tools.readSkill {
            tools.append(OmuxReadSkillTool(access: access))
        }
        let externalTools = OmuxExternalAgentToolCatalog.discover(configuration: configuration, fileManager: access.fileManager)
        tools.append(contentsOf: externalTools.map { OmuxExternalAgentPluginTool(access: access, tool: $0) })
        return tools
    }
    #endif
}

struct OmuxSystemAgentChatSessionFactory: OmuxAgentChatSessionFactorying {
    let omuxCommandRunner: OmuxAgentCLIRunner?
    let historyFetcher: OmuxAgentHistoryFetcher?

    init(
        omuxCommandRunner: OmuxAgentCLIRunner? = nil,
        historyFetcher: OmuxAgentHistoryFetcher? = nil
    ) {
        self.omuxCommandRunner = omuxCommandRunner
        self.historyFetcher = historyFetcher
    }

    func makeSession(
        systemInstruction: String?,
        hostContext: String,
        agentConfiguration: OmuxConfigAgent,
        workingDirectoryURL: URL,
        allowReadAnywhere: Bool,
        onVerbose: (@Sendable (String) -> Void)?,
        onToolEvent: (@Sendable (OmuxAgentToolEvent) -> Void)?
    ) throws -> AnyOmuxAgentChatSession {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = try OmuxSystemAgentGenerator.requireAvailableModel(onVerbose: onVerbose)
            let effectiveInstruction = OmuxSystemAgentGenerator.effectiveSystemInstruction(systemInstruction)
            let access = OmuxSystemAgentGenerator.makeWorkspaceAccess(
                workingDirectoryURL: workingDirectoryURL,
                hostContext: hostContext,
                configuration: agentConfiguration,
                allowReadAnywhere: allowReadAnywhere,
                omuxCommandRunner: omuxCommandRunner,
                historyFetcher: historyFetcher,
                onVerbose: onVerbose,
                onToolEvent: onToolEvent
            )
            let tools = OmuxSystemAgentGenerator.makeTools(access: access, configuration: agentConfiguration)
            onVerbose?("registered tools: \(tools.map(\.name).joined(separator: ", "))")
            return AnyOmuxAgentChatSession(OmuxFoundationModelChatSession(
                model: model,
                tools: tools,
                systemInstruction: effectiveInstruction,
                hostContext: hostContext,
                logger: onVerbose
            ))
        } else {
            onVerbose?("Foundation Models unsupported on this platform")
            throw OmuxAgentError.unsupportedPlatform
        }
        #else
        onVerbose?("Foundation Models framework unavailable at build/runtime")
        throw OmuxAgentError.unsupportedPlatform
        #endif
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
private final class OmuxFoundationModelChatSession: @unchecked Sendable, OmuxAgentChatSessioning {
    private final class TokenCountBox: @unchecked Sendable {
        var value: Int?
    }

    let toolNames: [String]
    let contextWindowSize: Int?
    private let model: SystemLanguageModel
    private let session: LanguageModelSession
    private let logger: (@Sendable (String) -> Void)?

    init(
        model: SystemLanguageModel,
        tools: [any Tool],
        systemInstruction: String,
        hostContext: String,
        logger: (@Sendable (String) -> Void)?
    ) {
        self.model = model
        self.toolNames = tools.map(\.name)
        self.contextWindowSize = model.contextSize
        self.logger = logger
        self.session = LanguageModelSession(model: model, tools: tools) {
            """
            \(systemInstruction)

            \(hostContext)
            """
        }
    }

    func send(
        prompt: String,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        logger?("streaming REPL model response")
        let stream = session.streamResponse(to: prompt)
        var emitted = ""
        var sawFirstChunk = false

        for try await snapshot in stream {
            let content = snapshot.content
            guard content.count >= emitted.count else {
                emitted = content
                onPartial(content)
                continue
            }

            let delta = String(content.dropFirst(emitted.count))
            if delta.isEmpty == false {
                if sawFirstChunk == false {
                    logger?("received first REPL response chunk")
                    sawFirstChunk = true
                }
                onPartial(delta)
                emitted = content
            }
        }

        let final = try await stream.collect()
        if final.content.count > emitted.count {
            onPartial(String(final.content.dropFirst(emitted.count)))
        }
        logger?("REPL response complete")
        return final.content
    }

    func summarizeForCompaction(transcript: String) async throws -> String {
        let compactSession = LanguageModelSession(model: model) {
            """
            You are compacting a local CLI chat transcript.
            Summarize the important user goals, concrete facts learned, files or commands referenced, and any unfinished work.
            Keep it concise and preserve only information that will help continue the session accurately.
            """
        }
        let response = try await compactSession.respond(
            to: """
            Summarize this OpenMUX agent session transcript for continuation after context compaction:

            \(transcript)
            """
        )
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func summarizeForHandoff(transcript: String) async throws -> String {
        let handoffSession = LanguageModelSession(model: model) {
            """
            You write compact markdown continuation briefs for a local CLI agent session.
            Produce exactly these sections:
            # Title
            ## Current Goal
            ## Key Facts Learned
            ## Files, Paths, and Commands
            ## Tool Activity Summary
            ## Open Issues or Questions
            ## Suggested Next Prompt
            Keep it concise, factual, and continuation-oriented.
            """
        }
        let response = try await handoffSession.respond(
            to: """
            Write a continuation handoff for this OpenMUX agent session transcript:

            \(transcript)
            """
        )
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func tokenCount(for text: String) -> Int? {
        guard #available(macOS 26.4, *) else {
            return nil
        }

        let semaphore = DispatchSemaphore(value: 0)
        let box = TokenCountBox()
        Task {
            box.value = try? await model.tokenCount(for: text)
            semaphore.signal()
        }
        semaphore.wait()
        return box.value
    }
}

@available(macOS 26.0, *)
@Generable
struct OmuxListDirectoryArguments {
    @Guide(description: "Optional directory path relative to the current working directory. Defaults to the current working directory.")
    let path: String?
}

@available(macOS 26.0, *)
struct OmuxListDirectoryTool: Tool {
    let name = "list_directory"
    let description = "List files and directories in a local directory. Use this when the user asks what files exist or wants to browse the current working directory."

    let access: OmuxAgentWorkspaceAccess

    func call(arguments: OmuxListDirectoryArguments) async throws -> String {
        access.listDirectory(path: arguments.path)
    }
}

@available(macOS 26.0, *)
@Generable
struct OmuxReadTerminalHistoryArguments {
    @Guide(description: "Optional pane ID. When omitted, reads history from the focused pane.")
    let paneID: String?

    @Guide(description: "Optional maximum number of lines to return.")
    let maxLines: Int?

    @Guide(description: "Optional maximum number of bytes to return.")
    let maxBytes: Int?
}

@available(macOS 26.0, *)
struct OmuxReadTerminalHistoryTool: Tool {
    let name = "read_terminal_history"
    let description = "Read recent terminal scrollback from OpenMUX. Use this for prompts about recent terminal steps, command output, or the focused pane session."

    let access: OmuxAgentWorkspaceAccess

    func call(arguments: OmuxReadTerminalHistoryArguments) async throws -> String {
        access.readTerminalHistory(
            paneID: arguments.paneID,
            maxLines: arguments.maxLines,
            maxBytes: arguments.maxBytes
        )
    }
}

@available(macOS 26.0, *)
@Generable
struct OmuxCLICommandArguments {
    @Guide(description: "The omux subcommand to run, such as split, list, open, history, or run.")
    let command: String

    @Guide(description: "Arguments for the omux subcommand, without the leading omux binary name.")
    let arguments: [String]
}

@available(macOS 26.0, *)
struct OmuxRunCLICommandTool: Tool {
    let name = "run_omux_cli"
    let description = "Run a non-interactive omux CLI subcommand through the local OpenMUX host. Use this to control panes, tabs, workspaces, history, and other OpenMUX actions."

    let access: OmuxAgentWorkspaceAccess

    func call(arguments: OmuxCLICommandArguments) async throws -> String {
        access.runOmuxCLI(command: arguments.command, arguments: arguments.arguments)
    }
}

@available(macOS 26.0, *)
@Generable
struct OmuxReadFileArguments {
    @Guide(description: "File path relative to the current working directory.")
    let path: String

    @Guide(description: "Optional starting line number, beginning at 1.")
    let startLine: Int?

    @Guide(description: "Optional ending line number, inclusive.")
    let endLine: Int?
}

@available(macOS 26.0, *)
struct OmuxReadFileTool: Tool {
    let name = "read_file"
    let description = "Read a local text file. By default reads are limited to the current working directory unless host context says fileReadScope is any-readable-path. Use this only when the user asks about file contents or a specific file is clearly relevant."

    let access: OmuxAgentWorkspaceAccess

    func call(arguments: OmuxReadFileArguments) async throws -> String {
        access.readFile(path: arguments.path, startLine: arguments.startLine, endLine: arguments.endLine)
    }
}

@available(macOS 26.0, *)
@Generable
enum OmuxGrepCaseMode {
    case smart
    case sensitive
    case insensitive
}

@available(macOS 26.0, *)
@Generable
struct OmuxGrepArguments {
    @Guide(description: "Search pattern for ripgrep to find in file contents.")
    let pattern: String

    @Guide(description: "Optional file globs like '*.swift' or 'docs/**'.")
    let globs: [String]

    @Guide(description: "Case sensitivity mode for the search.")
    let caseMode: OmuxGrepCaseMode

    @Guide(description: "Whether hidden files should be included.")
    let includeHidden: Bool

    @Guide(description: "Maximum number of matches to return.")
    let maxResults: Int?
}

@available(macOS 26.0, *)
struct OmuxGrepTool: Tool {
    let name = "grep_files"
    let description = "Search file contents under the current working directory with ripgrep. Use this to find relevant files or references when the user's request is about local code or files."

    let access: OmuxAgentWorkspaceAccess

    func call(arguments: OmuxGrepArguments) async throws -> String {
        access.grep(
            OmuxAgentGrepRequest(
                pattern: arguments.pattern,
                globs: arguments.globs,
                caseMode: {
                    switch arguments.caseMode {
                    case .smart:
                        return .smart
                    case .sensitive:
                        return .sensitive
                    case .insensitive:
                        return .insensitive
                    }
                }(),
                includeHidden: arguments.includeHidden,
                maxResults: arguments.maxResults
            )
        )
    }
}

@available(macOS 26.0, *)
@Generable
struct OmuxListSkillsArguments {}

@available(macOS 26.0, *)
struct OmuxListSkillsTool: Tool {
    let name = "list_skills"
    let description = "List local read-only skill bundles from the repo and user skill directories."

    let access: OmuxAgentWorkspaceAccess

    func call(arguments: OmuxListSkillsArguments) async throws -> String {
        access.listSkills()
    }
}

@available(macOS 26.0, *)
@Generable
struct OmuxReadSkillArguments {
    @Guide(description: "Skill name from list_skills.")
    let name: String

    @Guide(description: "Optional relative files under the same skill root to include alongside SKILL.md.")
    let includePaths: [String]
}

@available(macOS 26.0, *)
struct OmuxReadSkillTool: Tool {
    let name = "read_skill"
    let description = "Read one local skill bundle. Returns the SKILL.md body and any explicitly requested relative files under the same skill root."

    let access: OmuxAgentWorkspaceAccess

    func call(arguments: OmuxReadSkillArguments) async throws -> String {
        access.readSkill(name: arguments.name, includePaths: arguments.includePaths)
    }
}

@available(macOS 26.0, *)
@Generable
struct OmuxExternalAgentPluginToolArguments {
    @Guide(description: "Single text input for the plugin tool. Include the concrete query or payload the tool needs.")
    let input: String
}

@available(macOS 26.0, *)
struct OmuxExternalAgentPluginTool: Tool {
    var name: String { tool.toolName }
    var description: String {
        if let inputHint = tool.inputHint, inputHint.isEmpty == false {
            return "\(tool.description) Input hint: \(inputHint)"
        }
        return tool.description
    }

    let access: OmuxAgentWorkspaceAccess
    let tool: OmuxExternalAgentTool

    func call(arguments: OmuxExternalAgentPluginToolArguments) async throws -> String {
        try await access.callExternalTool(tool, input: arguments.input)
    }
}
#endif
