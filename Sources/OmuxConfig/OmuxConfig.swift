import Foundation
import OmuxCore

public let OmuxConfigSchemaVersion = 1

public enum OmuxConfigDiagnosticSeverity: String, Codable, Sendable {
    case warning
    case error

    public var isError: Bool {
        self == .error
    }
}

public struct OmuxConfigDiagnostic: Error, Codable, Equatable, Sendable {
    public let severity: OmuxConfigDiagnosticSeverity
    public let message: String
    public let filePath: String?
    public let line: Int?

    public init(
        severity: OmuxConfigDiagnosticSeverity,
        message: String,
        filePath: String? = nil,
        line: Int? = nil
    ) {
        self.severity = severity
        self.message = message
        self.filePath = filePath
        self.line = line
    }
}

public enum OmuxTOMLValue: Equatable, Sendable {
    case string(String)
    case integer(Int)
    case double(Double)
    case bool(Bool)
    case array([OmuxTOMLValue])

    public var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    public var intValue: Int? {
        guard case .integer(let value) = self else { return nil }
        return value
    }

    public var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    public var doubleValue: Double? {
        switch self {
        case .double(let value):
            return value
        case .integer(let value):
            return Double(value)
        default:
            return nil
        }
    }

    public func serialized() -> String {
        switch self {
        case .string(let value):
            return "\"\(Self.escape(value))\""
        case .integer(let value):
            return String(value)
        case .double(let value):
            return String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .array(let values):
            return "[\(values.map { $0.serialized() }.joined(separator: ", "))]"
        }
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}

public struct OmuxTOMLEntry: Equatable, Sendable {
    public let key: String
    public let value: OmuxTOMLValue
    public let line: Int

    public init(key: String, value: OmuxTOMLValue, line: Int) {
        self.key = key
        self.value = value
        self.line = line
    }
}

public struct OmuxTOMLDocument: Equatable, Sendable {
    private let rootEntries: [OmuxTOMLEntry]
    private let tableEntries: [String: [OmuxTOMLEntry]]

    public init(
        rootEntries: [OmuxTOMLEntry] = [],
        tableEntries: [String: [OmuxTOMLEntry]] = [:]
    ) {
        self.rootEntries = rootEntries
        self.tableEntries = tableEntries
    }

    public var tableNames: [String] {
        tableEntries.keys.sorted()
    }

    public func entries(in tableName: String? = nil) -> [OmuxTOMLEntry] {
        if let tableName {
            return tableEntries[tableName] ?? []
        }

        return rootEntries
    }

    public func value(in tableName: String? = nil, for key: String) -> OmuxTOMLValue? {
        entries(in: tableName).last(where: { $0.key == key })?.value
    }

    public func value(for key: String) -> OmuxTOMLValue? {
        value(in: nil, for: key)
    }

    public func line(in tableName: String? = nil, for key: String) -> Int? {
        entries(in: tableName).last(where: { $0.key == key })?.line
    }

    public func line(for key: String) -> Int? {
        line(in: nil, for: key)
    }
}

public struct OmuxConfigTheme: Equatable, Sendable {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

public struct OmuxConfigTerminal: Equatable, Sendable {
    public enum OptionAsAlt: Equatable, Sendable {
        case disabled
        case both
        case left
        case right

        public var ghosttyValue: String {
            switch self {
            case .disabled:
                return "false"
            case .both:
                return "true"
            case .left:
                return "left"
            case .right:
                return "right"
            }
        }
    }

    public struct PersistedScrollback: Equatable, Sendable {
        public static let defaultEnabled = true
        public static let defaultMaxLines = PaneScrollbackSnapshot.defaultMaxLines
        public static let defaultMaxBytes = PaneScrollbackSnapshot.defaultMaxBytes

        public let enabled: Bool
        public let maxLines: Int
        public let maxBytes: Int

        public init(
            enabled: Bool = defaultEnabled,
            maxLines: Int = defaultMaxLines,
            maxBytes: Int = defaultMaxBytes
        ) {
            self.enabled = enabled
            self.maxLines = maxLines
            self.maxBytes = maxBytes
        }
    }

    public let fontFamily: String?
    public let fontSize: Int?
    public let scrollbackLines: Int?
    public let optionAsAlt: OptionAsAlt?
    public let persistedScrollback: PersistedScrollback

    public init(
        fontFamily: String? = nil,
        fontSize: Int? = nil,
        scrollbackLines: Int? = nil,
        optionAsAlt: OptionAsAlt? = nil,
        persistedScrollback: PersistedScrollback = PersistedScrollback()
    ) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.scrollbackLines = scrollbackLines
        self.optionAsAlt = optionAsAlt
        self.persistedScrollback = persistedScrollback
    }
}

public struct OmuxConfigWorkspace: Equatable, Sendable {
    public static let defaultIsolateShellHistory = true

    public let defaultRootPath: String
    public let isolateShellHistory: Bool

    public init(
        defaultRootPath: String = OmuxWorkspacePathResolver.defaultRootPath,
        isolateShellHistory: Bool = Self.defaultIsolateShellHistory
    ) {
        self.defaultRootPath = defaultRootPath
        self.isolateShellHistory = isolateShellHistory
    }
}

public struct OmuxConfigUI: Equatable, Sendable {
    public struct Panes: Equatable, Sendable {
        public enum IdleStatusClear: String, Equatable, Sendable {
            case onFocus = "on-focus"
            case afterDelay = "after-delay"
            case never
        }

        public static let defaultInactiveOpacity = 0.5
        public static let defaultIdleStatusClear = IdleStatusClear.onFocus

        public let inactiveOpacity: Double
        public let idleStatusClear: IdleStatusClear

        public init(
            inactiveOpacity: Double = Self.defaultInactiveOpacity,
            idleStatusClear: IdleStatusClear = Self.defaultIdleStatusClear
        ) {
            self.inactiveOpacity = inactiveOpacity
            self.idleStatusClear = idleStatusClear
        }
    }

    public struct Icons: Equatable, Sendable {
        public enum Provider: String, Equatable, Sendable {
            case nerdFont = "nerd-font"
            case text
            case sfSymbols = "sf-symbols"
        }

        public let enabled: Bool
        public let provider: Provider
        public let fontFamily: String?
        public let colorsEnabled: Bool

        public init(
            enabled: Bool = true,
            provider: Provider = .nerdFont,
            fontFamily: String? = nil,
            colorsEnabled: Bool = true
        ) {
            self.enabled = enabled
            self.provider = provider
            self.fontFamily = fontFamily
            self.colorsEnabled = colorsEnabled
        }
    }

    public let panes: Panes
    public let icons: Icons

    public init(panes: Panes = Panes(), icons: Icons = Icons()) {
        self.panes = panes
        self.icons = icons
    }
}

public struct OmuxGhosttyConfigEntry: Equatable, Sendable {
    public let key: String
    public let value: OmuxTOMLValue
    public let line: Int?

    public init(key: String, value: OmuxTOMLValue, line: Int? = nil) {
        self.key = key
        self.value = value
        self.line = line
    }
}

public struct OmuxConfigPlugins: Equatable, Sendable {
    public struct MarkdownPreview: Equatable, Sendable {
        public let enabled: Bool
        public let renderer: String
        public let theme: String
        public let presentation: String

        public init(
            enabled: Bool = true,
            renderer: String = "builtin",
            theme: String = "auto",
            presentation: String = "pane-tab"
        ) {
            self.enabled = enabled
            self.renderer = renderer
            self.theme = theme
            self.presentation = presentation
        }
    }

    public struct AIStatus: Equatable, Sendable {
        public let enabled: Bool

        public init(enabled: Bool = true) {
            self.enabled = enabled
        }
    }

    public let markdownPreview: MarkdownPreview
    public let aiStatus: AIStatus

    public init(
        markdownPreview: MarkdownPreview = MarkdownPreview(),
        aiStatus: AIStatus = AIStatus()
    ) {
        self.markdownPreview = markdownPreview
        self.aiStatus = aiStatus
    }
}

public struct OmuxConfigRegistries: Equatable, Sendable {
    public static let defaultHooks = ["https://github.com/finger-gun/omux-hooks"]
    public static let defaultPlugins = ["https://github.com/finger-gun/omux-plugins"]

    public let hooks: [String]
    public let plugins: [String]

    public init(
        hooks: [String] = Self.defaultHooks,
        plugins: [String] = Self.defaultPlugins
    ) {
        self.hooks = hooks
        self.plugins = plugins
    }
}

public struct OmuxConfigAgentSessions: Equatable, Sendable {
    public struct Agent: Equatable, Sendable {
        public let enabled: Bool?
        public let home: String?
        public let resumeCommand: String?

        public init(enabled: Bool? = nil, home: String? = nil, resumeCommand: String? = nil) {
            self.enabled = enabled
            self.home = home
            self.resumeCommand = resumeCommand
        }

    }

    public struct ExternalAdapter: Equatable, Sendable {
        public let enabled: Bool?
        public let resumeCommand: String?

        public init(
            enabled: Bool? = nil,
            resumeCommand: String? = nil
        ) {
            self.enabled = enabled
            self.resumeCommand = resumeCommand
        }
    }

    public static let defaultIncludedAgents = ["codex", "copilot", "gemini"]

    public let enabled: Bool
    public let previewEnabled: Bool
    public let indexOnLaunch: Bool
    public let collapsedToggleVisible: Bool
    public let includedAgents: [String]
    public let excludedPaths: [String]
    public let maxPreviewBytes: Int
    public let sidebarRowsPerAgent: Int
    public let externalAdaptersEnabled: Bool
    public let agents: [String: Agent]
    public let externalAdapters: [String: ExternalAdapter]

    public init(
        enabled: Bool = true,
        previewEnabled: Bool = true,
        indexOnLaunch: Bool = true,
        collapsedToggleVisible: Bool = true,
        includedAgents: [String] = Self.defaultIncludedAgents,
        excludedPaths: [String] = [],
        maxPreviewBytes: Int = 1_048_576,
        sidebarRowsPerAgent: Int = 10,
        externalAdaptersEnabled: Bool = true,
        agents: [String: Agent] = [:],
        externalAdapters: [String: ExternalAdapter] = [:]
    ) {
        self.enabled = enabled
        self.previewEnabled = previewEnabled
        self.indexOnLaunch = indexOnLaunch
        self.collapsedToggleVisible = collapsedToggleVisible
        self.includedAgents = includedAgents
        self.excludedPaths = excludedPaths
        self.maxPreviewBytes = maxPreviewBytes
        self.sidebarRowsPerAgent = sidebarRowsPerAgent
        self.externalAdaptersEnabled = externalAdaptersEnabled
        self.agents = agents
        self.externalAdapters = externalAdapters
    }
}

public struct OmuxConfig: Equatable, Sendable {
    public let schema: Int
    public let autoCheckUpdate: Bool
    public let theme: OmuxConfigTheme
    public let terminal: OmuxConfigTerminal
    public let workspace: OmuxConfigWorkspace
    public let ui: OmuxConfigUI
    public let agentSessions: OmuxConfigAgentSessions
    public let plugins: OmuxConfigPlugins
    public let registries: OmuxConfigRegistries
    public let keyBindings: [OpenMUXKeyBindingOverride]
    public let ghostty: [OmuxGhosttyConfigEntry]
    public let sourceURL: URL?

    public init(
        schema: Int,
        autoCheckUpdate: Bool = true,
        theme: OmuxConfigTheme,
        terminal: OmuxConfigTerminal,
        workspace: OmuxConfigWorkspace = OmuxConfigWorkspace(),
        ui: OmuxConfigUI = OmuxConfigUI(),
        agentSessions: OmuxConfigAgentSessions = OmuxConfigAgentSessions(),
        plugins: OmuxConfigPlugins = OmuxConfigPlugins(),
        registries: OmuxConfigRegistries = OmuxConfigRegistries(),
        keyBindings: [OpenMUXKeyBindingOverride] = [],
        ghostty: [OmuxGhosttyConfigEntry],
        sourceURL: URL? = nil
    ) {
        self.schema = schema
        self.autoCheckUpdate = autoCheckUpdate
        self.theme = theme
        self.terminal = terminal
        self.workspace = workspace
        self.ui = ui
        self.agentSessions = agentSessions
        self.plugins = plugins
        self.registries = registries
        self.keyBindings = keyBindings
        self.ghostty = ghostty
        self.sourceURL = sourceURL
    }

    public static let defaults = OmuxConfig(
        schema: OmuxConfigSchemaVersion,
        autoCheckUpdate: true,
        theme: OmuxConfigTheme(name: "monokai-soda"),
        terminal: OmuxConfigTerminal(),
        workspace: OmuxConfigWorkspace(),
        ui: OmuxConfigUI(),
        agentSessions: OmuxConfigAgentSessions(),
        plugins: OmuxConfigPlugins(),
        registries: OmuxConfigRegistries(),
        keyBindings: [],
        ghostty: []
    )

}

public enum OmuxWorkspacePathResolver {
    public static var defaultRootPath: String {
        FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
    }

    public static func resolve(_ rawPath: String) -> String? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }

        let expanded = expandHome(in: trimmed)
        guard expanded.hasPrefix("/") else {
            return nil
        }

        return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL.path
    }

    private static func expandHome(in path: String) -> String {
        if path == "~" {
            return defaultRootPath
        }
        if path.hasPrefix("~/") {
            return defaultRootPath + String(path.dropFirst())
        }
        return path
    }
}

public struct OmuxConfigLoadResult: Equatable, Sendable {
    public let config: OmuxConfig
    public let diagnostics: [OmuxConfigDiagnostic]

    public init(config: OmuxConfig, diagnostics: [OmuxConfigDiagnostic]) {
        self.config = config
        self.diagnostics = diagnostics
    }

    public var hasErrors: Bool {
        diagnostics.contains(where: { $0.severity.isError })
    }
}

public enum OmuxConfigPaths {
    public static var homeDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    public static var baseDirectoryURL: URL {
        if let override = ProcessInfo.processInfo.environment["OMUX_HOME"], override.isEmpty == false {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return homeDirectoryURL.appendingPathComponent(".omux", isDirectory: true)
    }

    public static var configFileURL: URL {
        baseDirectoryURL.appendingPathComponent("config.toml")
    }

    public static var themesDirectoryURL: URL {
        baseDirectoryURL.appendingPathComponent("themes", isDirectory: true)
    }

    public static var hooksDirectoryURL: URL {
        baseDirectoryURL.appendingPathComponent("hooks", isDirectory: true)
    }

    public static var pluginsDirectoryURL: URL {
        baseDirectoryURL.appendingPathComponent("plugins", isDirectory: true)
    }

    public static var generatedDirectoryURL: URL {
        baseDirectoryURL.appendingPathComponent("generated", isDirectory: true)
    }

    public static var generatedGhosttyDirectoryURL: URL {
        generatedDirectoryURL.appendingPathComponent("ghostty", isDirectory: true)
    }

    public static var agentSessionsDatabaseURL: URL {
        baseDirectoryURL.appendingPathComponent("agent-sessions.sqlite", isDirectory: false)
    }

    public static var vaultDatabaseURL: URL {
        agentSessionsDatabaseURL
    }
}

public enum OmuxConfigTemplate {
    public static func starter(themeName: String = OmuxConfig.defaults.theme.name) -> String {
        """
        schema = \(OmuxConfigSchemaVersion)
        # auto_check_update = true

        [theme]
        name = "\(themeName)"

        [terminal]
        # font_family = "Berkeley Mono"
        # font_size = 13
        # scrollback_lines = 100000
        # option_as_alt = "right"
        # persist_scrollback = true
        # persist_scrollback_lines = 4000
        # persist_scrollback_bytes = 1048576

        [workspace]
        default_root_path = "~"
        isolate_shell_history = true

        [ui.panes]
        # inactive_opacity = 0.5
        # idle_status_clear = "on-focus" # "on-focus", "after-delay", or "never"

        [ui.icons]
        # enabled = true
        # provider = "nerd-font"
        # colors_enabled = true
        # font_family = "JetBrainsMono Nerd Font" # optional override; OpenMUX bundles Symbols Nerd Font Mono

        [agent-sessions]
        enabled = true
        preview_enabled = true
        index_on_launch = true
        collapsed_toggle_visible = true
        external_adapters_enabled = true
        included_agents = ["codex", "copilot", "gemini"]
        excluded_paths = []
        max_preview_bytes = 1048576
        sidebar_rows_per_agent = 10

        [plugins.markdown-preview]
        enabled = true
        renderer = "builtin"
        theme = "auto"
        presentation = "pane-tab"

        [plugins.ai-status]
        enabled = true

        [registries]
        hooks = ["https://github.com/finger-gun/omux-hooks"]
        plugins = ["https://github.com/finger-gun/omux-plugins"]

        [keys]
        \(OpenMUXKeyBindingRegistry.defaultBindingPairs.map { "\"\($0.0.description)\" = \"\($0.1.rawValue)\"" }.joined(separator: "\n"))

        [ghostty]
        # "copy-on-select" = false
        """
    }
}

public enum OmuxTOMLParser {
    public static func parse(fileAt url: URL) -> (document: OmuxTOMLDocument?, diagnostics: [OmuxConfigDiagnostic]) {
        do {
            let contents = try String(contentsOf: url, encoding: .utf8)
            return parse(contents: contents, sourceURL: url)
        } catch {
            return (
                nil,
                [
                    OmuxConfigDiagnostic(
                        severity: .error,
                        message: "Unable to read TOML file: \(error.localizedDescription)",
                        filePath: url.path
                    ),
                ]
            )
        }
    }

    public static func parse(
        contents: String,
        sourceURL: URL? = nil
    ) -> (document: OmuxTOMLDocument?, diagnostics: [OmuxConfigDiagnostic]) {
        var diagnostics: [OmuxConfigDiagnostic] = []
        var rootEntries: [OmuxTOMLEntry] = []
        var tableEntries: [String: [OmuxTOMLEntry]] = [:]
        var currentTable: String?

        for (index, rawLine) in contents.components(separatedBy: .newlines).enumerated() {
            let lineNumber = index + 1
            let trimmed = stripComment(from: rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else {
                continue
            }

            if trimmed.hasPrefix("[") {
                guard trimmed.hasSuffix("]") else {
                    diagnostics.append(
                        diagnostic(
                            message: "Unterminated table declaration.",
                            sourceURL: sourceURL,
                            line: lineNumber
                        )
                    )
                    continue
                }

                let tableName = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                guard tableName.isEmpty == false else {
                    diagnostics.append(
                        diagnostic(
                            message: "Empty table declaration is not allowed.",
                            sourceURL: sourceURL,
                            line: lineNumber
                        )
                    )
                    continue
                }

                currentTable = tableName
                if tableEntries[tableName] == nil {
                    tableEntries[tableName] = []
                }
                continue
            }

            guard let separatorIndex = separatorIndex(in: trimmed) else {
                diagnostics.append(
                    diagnostic(
                        message: "Expected key/value assignment.",
                        sourceURL: sourceURL,
                        line: lineNumber
                    )
                )
                continue
            }

            let rawKey = String(trimmed[..<separatorIndex]).trimmingCharacters(in: .whitespaces)
            let rawValue = String(trimmed[trimmed.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespaces)

            guard let key = parseKey(rawKey) else {
                diagnostics.append(
                    diagnostic(
                        message: "Invalid TOML key '\(rawKey)'.",
                        sourceURL: sourceURL,
                        line: lineNumber
                    )
                )
                continue
            }

            guard let value = parseValue(rawValue) else {
                diagnostics.append(
                    diagnostic(
                        message: "Unsupported TOML value for key '\(key)'.",
                        sourceURL: sourceURL,
                        line: lineNumber
                    )
                )
                continue
            }

            let entry = OmuxTOMLEntry(key: key, value: value, line: lineNumber)
            if let currentTable {
                tableEntries[currentTable, default: []].append(entry)
            } else {
                rootEntries.append(entry)
            }
        }

        guard diagnostics.isEmpty else {
            return (nil, diagnostics)
        }

        return (OmuxTOMLDocument(rootEntries: rootEntries, tableEntries: tableEntries), [])
    }

    private static func diagnostic(message: String, sourceURL: URL?, line: Int) -> OmuxConfigDiagnostic {
        OmuxConfigDiagnostic(
            severity: .error,
            message: message,
            filePath: sourceURL?.path,
            line: line
        )
    }

    private static func stripComment(from line: String) -> String {
        var isInsideString = false
        var bracketDepth = 0
        var previous: Character?

        for (offset, character) in line.enumerated() {
            if character == "\"" && previous != "\\" {
                isInsideString.toggle()
            } else if isInsideString == false {
                if character == "[" {
                    bracketDepth += 1
                } else if character == "]" {
                    bracketDepth = max(0, bracketDepth - 1)
                } else if character == "#" && bracketDepth == 0 {
                    return String(line.prefix(offset))
                }
            }
            previous = character
        }

        return line
    }

    private static func separatorIndex(in line: String) -> String.Index? {
        var isInsideString = false
        var bracketDepth = 0
        var previous: Character?

        for index in line.indices {
            let character = line[index]
            if character == "\"" && previous != "\\" {
                isInsideString.toggle()
            } else if isInsideString == false {
                if character == "[" {
                    bracketDepth += 1
                } else if character == "]" {
                    bracketDepth = max(0, bracketDepth - 1)
                } else if character == "=" && bracketDepth == 0 {
                    return index
                }
            }
            previous = character
        }

        return nil
    }

    private static func parseKey(_ rawKey: String) -> String? {
        if rawKey.hasPrefix("\""), rawKey.hasSuffix("\"") {
            return parseQuotedString(rawKey)
        }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        guard rawKey.unicodeScalars.allSatisfy(allowed.contains) else {
            return nil
        }

        return rawKey
    }

    private static func parseValue(_ rawValue: String) -> OmuxTOMLValue? {
        if rawValue.hasPrefix("\""), rawValue.hasSuffix("\"") {
            return parseQuotedString(rawValue).map(OmuxTOMLValue.string)
        }

        if rawValue == "true" {
            return .bool(true)
        }

        if rawValue == "false" {
            return .bool(false)
        }

        if rawValue.hasPrefix("["), rawValue.hasSuffix("]") {
            let inner = String(rawValue.dropFirst().dropLast())
            if inner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .array([])
            }

            let parts = splitArray(inner)
            var values: [OmuxTOMLValue] = []
            values.reserveCapacity(parts.count)
            for part in parts {
                guard let value = parseValue(part.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    return nil
                }
                values.append(value)
            }
            return .array(values)
        }

        if rawValue.contains("."), let value = Double(rawValue) {
            return .double(value)
        }

        if let value = Int(rawValue) {
            return .integer(value)
        }

        return nil
    }

    private static func splitArray(_ value: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var isInsideString = false
        var bracketDepth = 0
        var previous: Character?

        for character in value {
            if character == "\"" && previous != "\\" {
                isInsideString.toggle()
            } else if isInsideString == false {
                if character == "[" {
                    bracketDepth += 1
                } else if character == "]" {
                    bracketDepth = max(0, bracketDepth - 1)
                } else if character == "," && bracketDepth == 0 {
                    parts.append(current)
                    current = ""
                    previous = character
                    continue
                }
            }

            current.append(character)
            previous = character
        }

        if current.isEmpty == false {
            parts.append(current)
        }

        return parts
    }

    private static func parseQuotedString(_ rawValue: String) -> String? {
        guard rawValue.count >= 2 else {
            return nil
        }

        let inner = rawValue.dropFirst().dropLast()
        var result = ""
        var escaping = false

        for character in inner {
            if escaping {
                switch character {
                case "\"":
                    result.append("\"")
                case "\\":
                    result.append("\\")
                case "n":
                    result.append("\n")
                case "t":
                    result.append("\t")
                case "r":
                    result.append("\r")
                default:
                    result.append(character)
                }
                escaping = false
                continue
            }

            if character == "\\" {
                escaping = true
            } else {
                result.append(character)
            }
        }

        guard escaping == false else {
            return nil
        }

        return result
    }
}

public struct OmuxConfigLoader {
    private let fileManager: FileManager
    private let configURL: URL

    public init(
        fileManager: FileManager = .default,
        configURL: URL = OmuxConfigPaths.configFileURL
    ) {
        self.fileManager = fileManager
        self.configURL = configURL
    }

    public func load(url: URL? = nil) -> OmuxConfigLoadResult {
        let url = url ?? configURL
        guard fileManager.fileExists(atPath: url.path) else {
            return OmuxConfigLoadResult(config: OmuxConfig.defaults, diagnostics: [])
        }

        let parseResult = OmuxTOMLParser.parse(fileAt: url)
        guard let document = parseResult.document else {
            return OmuxConfigLoadResult(config: OmuxConfig.defaults, diagnostics: parseResult.diagnostics)
        }

        let decodeResult = decode(document: document, sourceURL: url)
        return OmuxConfigLoadResult(config: decodeResult.config, diagnostics: parseResult.diagnostics + decodeResult.diagnostics)
    }

    private func decode(document: OmuxTOMLDocument, sourceURL: URL) -> OmuxConfigLoadResult {
        var diagnostics: [OmuxConfigDiagnostic] = []

        let allowedRootKeys: Set<String> = ["schema", "auto_check_update"]
        for entry in document.entries() where allowedRootKeys.contains(entry.key) == false {
            diagnostics.append(
                OmuxConfigDiagnostic(
                    severity: .error,
                    message: "Unknown top-level config key '\(entry.key)'.",
                    filePath: sourceURL.path,
                    line: entry.line
                )
            )
        }

        let agentSessionsTableNames = ["agent-sessions"]
        let agentSessionsAgentTablePrefixes = agentSessionsTableNames.map { "\($0).agents." }
        let agentSessionsExternalTablePrefixes = agentSessionsTableNames.map { "\($0).external." }
        let allowedTables: Set<String> = [
            "theme",
            "terminal",
            "workspace",
            "ui.panes",
            "ui.icons",
            "agent-sessions",
            "plugins.markdown-preview",
            "plugins.ai-status",
            "registries",
            "keys",
            "ghostty",
        ]
        for tableName in document.tableNames
        where allowedTables.contains(tableName) == false
            && agentSessionsAgentTablePrefixes.contains(where: { tableName.hasPrefix($0) }) == false
            && agentSessionsExternalTablePrefixes.contains(where: { tableName.hasPrefix($0) }) == false {
            diagnostics.append(
                OmuxConfigDiagnostic(
                    severity: .error,
                    message: "Unknown config table [\(tableName)].",
                    filePath: sourceURL.path
                )
            )
        }

        guard let schemaValue = document.value(for: "schema") else {
            diagnostics.append(
                OmuxConfigDiagnostic(
                    severity: .error,
                    message: "Missing required schema field. Add 'schema = \(OmuxConfigSchemaVersion)'.",
                    filePath: sourceURL.path
                )
            )
            return OmuxConfigLoadResult(config: OmuxConfig.defaults, diagnostics: diagnostics)
        }

        guard let schema = schemaValue.intValue else {
            diagnostics.append(
                OmuxConfigDiagnostic(
                    severity: .error,
                    message: "Schema must be an integer.",
                    filePath: sourceURL.path,
                    line: document.line(for: "schema")
                )
            )
            return OmuxConfigLoadResult(config: OmuxConfig.defaults, diagnostics: diagnostics)
        }

        guard schema == OmuxConfigSchemaVersion else {
            diagnostics.append(
                OmuxConfigDiagnostic(
                    severity: .error,
                    message: "Unsupported config schema \(schema). This build supports schema \(OmuxConfigSchemaVersion).",
                    filePath: sourceURL.path,
                    line: document.line(for: "schema")
                )
            )
            return OmuxConfigLoadResult(config: OmuxConfig.defaults, diagnostics: diagnostics)
        }

        var config = OmuxConfig.defaults
        var autoCheckUpdate = config.autoCheckUpdate

        if let autoCheckUpdateValue = document.value(for: "auto_check_update") {
            if let value = autoCheckUpdateValue.boolValue {
                autoCheckUpdate = value
            } else {
                diagnostics.append(
                    OmuxConfigDiagnostic(
                        severity: .error,
                        message: "auto_check_update must be a boolean.",
                        filePath: sourceURL.path,
                        line: document.line(for: "auto_check_update")
                    )
                )
            }
        }

        if let themeNameValue = document.value(in: "theme", for: "name") {
            guard let themeName = themeNameValue.stringValue else {
                diagnostics.append(
                    OmuxConfigDiagnostic(
                        severity: .error,
                        message: "theme.name must be a string.",
                        filePath: sourceURL.path,
                        line: document.line(in: "theme", for: "name")
                    )
                )
                return OmuxConfigLoadResult(config: OmuxConfig.defaults, diagnostics: diagnostics)
            }
            config = OmuxConfig(
                schema: config.schema,
                autoCheckUpdate: autoCheckUpdate,
                theme: OmuxConfigTheme(name: themeName),
                terminal: config.terminal,
                workspace: config.workspace,
                ui: config.ui,
                agentSessions: config.agentSessions,
                plugins: config.plugins,
                registries: config.registries,
                keyBindings: config.keyBindings,
                ghostty: config.ghostty,
                sourceURL: sourceURL
            )
        } else {
            config = OmuxConfig(
                schema: config.schema,
                autoCheckUpdate: autoCheckUpdate,
                theme: config.theme,
                terminal: config.terminal,
                workspace: config.workspace,
                ui: config.ui,
                agentSessions: config.agentSessions,
                plugins: config.plugins,
                registries: config.registries,
                keyBindings: config.keyBindings,
                ghostty: config.ghostty,
                sourceURL: sourceURL
            )
        }

        let themeAllowedKeys: Set<String> = ["name"]
        for entry in document.entries(in: "theme") where themeAllowedKeys.contains(entry.key) == false {
            diagnostics.append(
                OmuxConfigDiagnostic(
                    severity: .error,
                    message: "Unknown [theme] key '\(entry.key)'.",
                    filePath: sourceURL.path,
                    line: entry.line
                )
            )
        }

        let terminalAllowedKeys: Set<String> = [
            "font_family",
            "font_size",
            "scrollback_lines",
            "option_as_alt",
            "persist_scrollback",
            "persist_scrollback_lines",
            "persist_scrollback_bytes",
            "keyboard_selection",
        ]
        var fontFamily = config.terminal.fontFamily
        var fontSize = config.terminal.fontSize
        var scrollbackLines = config.terminal.scrollbackLines
        var optionAsAlt = config.terminal.optionAsAlt
        var persistedScrollbackEnabled = config.terminal.persistedScrollback.enabled
        var persistedScrollbackMaxLines = config.terminal.persistedScrollback.maxLines
        var persistedScrollbackMaxBytes = config.terminal.persistedScrollback.maxBytes

        for entry in document.entries(in: "terminal") {
            guard terminalAllowedKeys.contains(entry.key) else {
                diagnostics.append(
                    OmuxConfigDiagnostic(
                        severity: .error,
                        message: "Unknown [terminal] key '\(entry.key)'.",
                        filePath: sourceURL.path,
                        line: entry.line
                    )
                )
                continue
            }

            switch entry.key {
            case "keyboard_selection":
                diagnostics.append(
                    OmuxConfigDiagnostic(
                        severity: .warning,
                        message: "terminal.keyboard_selection is deprecated and ignored.",
                        filePath: sourceURL.path,
                        line: entry.line
                    )
                )
            case "font_family":
                guard let value = entry.value.stringValue else {
                    diagnostics.append(
                        OmuxConfigDiagnostic(
                            severity: .error,
                            message: "terminal.font_family must be a string.",
                            filePath: sourceURL.path,
                            line: entry.line
                        )
                    )
                    continue
                }
                fontFamily = value
            case "font_size":
                guard let value = entry.value.intValue else {
                    diagnostics.append(
                        OmuxConfigDiagnostic(
                            severity: .error,
                            message: "terminal.font_size must be an integer.",
                            filePath: sourceURL.path,
                            line: entry.line
                        )
                    )
                    continue
                }
                fontSize = value
            case "scrollback_lines":
                guard let value = entry.value.intValue else {
                    diagnostics.append(
                        OmuxConfigDiagnostic(
                            severity: .error,
                            message: "terminal.scrollback_lines must be an integer.",
                            filePath: sourceURL.path,
                            line: entry.line
                        )
                    )
                    continue
                }
                scrollbackLines = value
            case "persist_scrollback":
                guard let value = entry.value.boolValue else {
                    diagnostics.append(
                        OmuxConfigDiagnostic(
                            severity: .error,
                            message: "terminal.persist_scrollback must be a boolean.",
                            filePath: sourceURL.path,
                            line: entry.line
                        )
                    )
                    continue
                }
                persistedScrollbackEnabled = value
            case "persist_scrollback_lines":
                guard let value = entry.value.intValue else {
                    diagnostics.append(
                        OmuxConfigDiagnostic(
                            severity: .error,
                            message: "terminal.persist_scrollback_lines must be an integer.",
                            filePath: sourceURL.path,
                            line: entry.line
                        )
                    )
                    continue
                }
                guard value > 0 else {
                    diagnostics.append(
                        OmuxConfigDiagnostic(
                            severity: .error,
                            message: "terminal.persist_scrollback_lines must be greater than zero.",
                            filePath: sourceURL.path,
                            line: entry.line
                        )
                    )
                    continue
                }
                persistedScrollbackMaxLines = value
            case "persist_scrollback_bytes":
                guard let value = entry.value.intValue else {
                    diagnostics.append(
                        OmuxConfigDiagnostic(
                            severity: .error,
                            message: "terminal.persist_scrollback_bytes must be an integer.",
                            filePath: sourceURL.path,
                            line: entry.line
                        )
                    )
                    continue
                }
                guard value > 0 else {
                    diagnostics.append(
                        OmuxConfigDiagnostic(
                            severity: .error,
                            message: "terminal.persist_scrollback_bytes must be greater than zero.",
                            filePath: sourceURL.path,
                            line: entry.line
                        )
                    )
                    continue
                }
                persistedScrollbackMaxBytes = value
            case "option_as_alt":
                switch entry.value {
                case .bool(false):
                    optionAsAlt = .disabled
                case .bool(true):
                    optionAsAlt = .both
                case .string("left"):
                    optionAsAlt = .left
                case .string("right"):
                    optionAsAlt = .right
                default:
                    diagnostics.append(
                        OmuxConfigDiagnostic(
                            severity: .error,
                            message: "terminal.option_as_alt must be true, false, \"left\", or \"right\".",
                            filePath: sourceURL.path,
                            line: entry.line
                        )
                    )
                    continue
                }
            default:
                break
            }
        }

        let workspaceAllowedKeys: Set<String> = ["default_root_path", "isolate_shell_history"]
        var defaultRootPath = config.workspace.defaultRootPath
        var isolateShellHistory = config.workspace.isolateShellHistory
        for entry in document.entries(in: "workspace") {
            guard workspaceAllowedKeys.contains(entry.key) else {
                diagnostics.append(
                    OmuxConfigDiagnostic(
                        severity: .error,
                        message: "Unknown [workspace] key '\(entry.key)'.",
                        filePath: sourceURL.path,
                        line: entry.line
                    )
                )
                continue
            }

            switch entry.key {
            case "default_root_path":
                guard let value = entry.value.stringValue else {
                    diagnostics.append(
                        OmuxConfigDiagnostic(
                            severity: .error,
                            message: "workspace.default_root_path must be a string.",
                            filePath: sourceURL.path,
                            line: entry.line
                        )
                    )
                    continue
                }
                guard let resolvedPath = OmuxWorkspacePathResolver.resolve(value) else {
                    diagnostics.append(
                        OmuxConfigDiagnostic(
                            severity: .error,
                            message: "workspace.default_root_path must be an absolute path or start with '~'.",
                            filePath: sourceURL.path,
                            line: entry.line
                        )
                    )
                    continue
                }
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: resolvedPath, isDirectory: &isDirectory), isDirectory.boolValue else {
                    diagnostics.append(
                        OmuxConfigDiagnostic(
                            severity: .error,
                            message: "workspace.default_root_path must point to an existing directory.",
                            filePath: sourceURL.path,
                            line: entry.line
                        )
                    )
                    continue
                }
                defaultRootPath = resolvedPath
            case "isolate_shell_history":
                guard let value = entry.value.boolValue else {
                    diagnostics.append(
                        OmuxConfigDiagnostic(
                            severity: .error,
                            message: "workspace.isolate_shell_history must be a boolean.",
                            filePath: sourceURL.path,
                            line: entry.line
                        )
                    )
                    continue
                }
                isolateShellHistory = value
            default:
                break
            }
        }

        let paneUIAllowedKeys: Set<String> = ["inactive_opacity", "idle_status_clear"]
        var paneInactiveOpacity = config.ui.panes.inactiveOpacity
        var paneIdleStatusClear = config.ui.panes.idleStatusClear
        for entry in document.entries(in: "ui.panes") {
            guard paneUIAllowedKeys.contains(entry.key) else {
                diagnostics.append(
                    OmuxConfigDiagnostic(
                        severity: .error,
                        message: "Unknown [ui.panes] key '\(entry.key)'.",
                        filePath: sourceURL.path,
                        line: entry.line
                    )
                )
                continue
            }

            switch entry.key {
            case "inactive_opacity":
                guard let value = entry.value.doubleValue else {
                    diagnostics.append(
                        OmuxConfigDiagnostic(
                            severity: .error,
                            message: "ui.panes.inactive_opacity must be a number between 0.0 and 1.0.",
                            filePath: sourceURL.path,
                            line: entry.line
                        )
                    )
                    continue
                }
                guard (0.0...1.0).contains(value) else {
                    diagnostics.append(
                        OmuxConfigDiagnostic(
                            severity: .error,
                            message: "ui.panes.inactive_opacity must be between 0.0 and 1.0.",
                            filePath: sourceURL.path,
                            line: entry.line
                        )
                    )
                    continue
                }
                paneInactiveOpacity = value
            case "idle_status_clear":
                guard case .string(let rawValue) = entry.value,
                      let value = OmuxConfigUI.Panes.IdleStatusClear(rawValue: rawValue)
                else {
                    diagnostics.append(
                        OmuxConfigDiagnostic(
                            severity: .error,
                            message: "ui.panes.idle_status_clear must be \"on-focus\", \"after-delay\", or \"never\".",
                            filePath: sourceURL.path,
                            line: entry.line
                        )
                    )
                    continue
                }
                paneIdleStatusClear = value
            default:
                break
            }
        }

        let iconAllowedKeys: Set<String> = ["enabled", "provider", "colors_enabled", "font_family"]
        var iconsEnabled = config.ui.icons.enabled
        var iconsProvider = config.ui.icons.provider
        var iconsFontFamily = config.ui.icons.fontFamily
        var iconsColorsEnabled = config.ui.icons.colorsEnabled
        for entry in document.entries(in: "ui.icons") {
            guard iconAllowedKeys.contains(entry.key) else {
                diagnostics.append(
                    OmuxConfigDiagnostic(
                        severity: .error,
                        message: "Unknown [ui.icons] key '\(entry.key)'.",
                        filePath: sourceURL.path,
                        line: entry.line
                    )
                )
                continue
            }

            switch entry.key {
            case "enabled":
                guard let value = entry.value.boolValue else {
                    diagnostics.append(
                        OmuxConfigDiagnostic(
                            severity: .error,
                            message: "ui.icons.enabled must be a boolean.",
                            filePath: sourceURL.path,
                            line: entry.line
                        )
                    )
                    continue
                }
                iconsEnabled = value
            case "provider":
                guard let rawValue = entry.value.stringValue,
                      let value = OmuxConfigUI.Icons.Provider(rawValue: rawValue)
                else {
                    diagnostics.append(
                        OmuxConfigDiagnostic(
                            severity: .error,
                            message: "ui.icons.provider must be \"nerd-font\", \"sf-symbols\", or \"text\".",
                            filePath: sourceURL.path,
                            line: entry.line
                        )
                    )
                    continue
                }
                iconsProvider = value
            case "colors_enabled":
                guard let value = entry.value.boolValue else {
                    diagnostics.append(
                        OmuxConfigDiagnostic(
                            severity: .error,
                            message: "ui.icons.colors_enabled must be a boolean.",
                            filePath: sourceURL.path,
                            line: entry.line
                        )
                    )
                    continue
                }
                iconsColorsEnabled = value
            case "font_family":
                guard let value = entry.value.stringValue else {
                    diagnostics.append(
                        OmuxConfigDiagnostic(
                            severity: .error,
                            message: "ui.icons.font_family must be a string.",
                            filePath: sourceURL.path,
                            line: entry.line
                        )
                    )
                    continue
                }
                iconsFontFamily = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
            default:
                break
            }
        }

        let markdownPreviewAllowedKeys: Set<String> = ["enabled", "renderer", "theme", "presentation"]
        var markdownPreviewEnabled = config.plugins.markdownPreview.enabled
        var markdownPreviewRenderer = config.plugins.markdownPreview.renderer
        var markdownPreviewTheme = config.plugins.markdownPreview.theme
        var markdownPreviewPresentation = config.plugins.markdownPreview.presentation
        for entry in document.entries(in: "plugins.markdown-preview") {
            guard markdownPreviewAllowedKeys.contains(entry.key) else {
                diagnostics.append(
                    OmuxConfigDiagnostic(
                        severity: .error,
                        message: "Unknown [plugins.markdown-preview] key '\(entry.key)'.",
                        filePath: sourceURL.path,
                        line: entry.line
                    )
                )
                continue
            }

            switch entry.key {
            case "enabled":
                guard let value = entry.value.boolValue else {
                    diagnostics.append(
                        OmuxConfigDiagnostic(
                            severity: .error,
                            message: "plugins.markdown-preview.enabled must be a boolean.",
                            filePath: sourceURL.path,
                            line: entry.line
                        )
                    )
                    continue
                }
                markdownPreviewEnabled = value
            case "renderer":
                guard let value = entry.value.stringValue, value == "builtin" else {
                    diagnostics.append(
                        OmuxConfigDiagnostic(
                            severity: .error,
                            message: "plugins.markdown-preview.renderer must be \"builtin\".",
                            filePath: sourceURL.path,
                            line: entry.line
                        )
                    )
                    continue
                }
                markdownPreviewRenderer = value
            case "theme":
                guard let value = entry.value.stringValue, ["auto", "light", "dark"].contains(value) else {
                    diagnostics.append(
                        OmuxConfigDiagnostic(
                            severity: .error,
                            message: "plugins.markdown-preview.theme must be \"auto\", \"light\", or \"dark\".",
                            filePath: sourceURL.path,
                            line: entry.line
                        )
                    )
                    continue
                }
                markdownPreviewTheme = value
            case "presentation":
                guard let value = entry.value.stringValue, ["pane-tab", "modal"].contains(value) else {
                    diagnostics.append(
                        OmuxConfigDiagnostic(
                            severity: .error,
                            message: "plugins.markdown-preview.presentation must be \"pane-tab\" or \"modal\".",
                            filePath: sourceURL.path,
                            line: entry.line
                        )
                    )
                    continue
                }
                markdownPreviewPresentation = value
            default:
                break
            }
        }

        let aiStatusAllowedKeys: Set<String> = ["enabled"]
        var aiStatusEnabled = config.plugins.aiStatus.enabled
        for entry in document.entries(in: "plugins.ai-status") {
            guard aiStatusAllowedKeys.contains(entry.key) else {
                diagnostics.append(
                    OmuxConfigDiagnostic(
                        severity: .error,
                        message: "Unknown [plugins.ai-status] key '\(entry.key)'.",
                        filePath: sourceURL.path,
                        line: entry.line
                    )
                )
                continue
            }

            switch entry.key {
            case "enabled":
                guard let value = entry.value.boolValue else {
                    diagnostics.append(
                        OmuxConfigDiagnostic(
                            severity: .error,
                            message: "plugins.ai-status.enabled must be a boolean.",
                            filePath: sourceURL.path,
                            line: entry.line
                        )
                    )
                    continue
                }
                aiStatusEnabled = value
            default:
                break
            }
        }

        let registriesAllowedKeys: Set<String> = ["hooks", "plugins"]
        var hookRegistries = config.registries.hooks
        var pluginRegistries = config.registries.plugins
        for entry in document.entries(in: "registries") {
            guard registriesAllowedKeys.contains(entry.key) else {
                diagnostics.append(
                    OmuxConfigDiagnostic(
                        severity: .error,
                        message: "Unknown [registries] key '\(entry.key)'.",
                        filePath: sourceURL.path,
                        line: entry.line
                    )
                )
                continue
            }

            guard let values = registryURLStrings(from: entry.value) else {
                diagnostics.append(
                    OmuxConfigDiagnostic(
                        severity: .error,
                        message: "registries.\(entry.key) must be an array of URL strings.",
                        filePath: sourceURL.path,
                        line: entry.line
                    )
                )
                continue
            }
            guard values.allSatisfy(Self.isSupportedRegistryURLString) else {
                diagnostics.append(
                    OmuxConfigDiagnostic(
                        severity: .error,
                        message: "registries.\(entry.key) contains an unsupported registry URL.",
                        filePath: sourceURL.path,
                        line: entry.line
                    )
                )
                continue
            }

            switch entry.key {
            case "hooks":
                hookRegistries = values
            case "plugins":
                pluginRegistries = values
            default:
                break
            }
        }

        let supportedAgentSessionAgents: Set<String> = ["codex", "copilot", "gemini"]
        let agentSessionsAllowedKeys: Set<String> = [
            "enabled",
            "preview_enabled",
            "index_on_launch",
            "collapsed_toggle_visible",
            "external_adapters_enabled",
            "included_agents",
            "excluded_paths",
            "max_preview_bytes",
            "sidebar_rows_per_agent",
        ]
        var agentSessionsEnabled = config.agentSessions.enabled
        var agentSessionsPreviewEnabled = config.agentSessions.previewEnabled
        var agentSessionsIndexOnLaunch = config.agentSessions.indexOnLaunch
        var agentSessionsCollapsedToggleVisible = config.agentSessions.collapsedToggleVisible
        var agentSessionsIncludedAgents = config.agentSessions.includedAgents
        var agentSessionsExcludedPaths = config.agentSessions.excludedPaths
        var agentSessionsMaxPreviewBytes = config.agentSessions.maxPreviewBytes
        var agentSessionsSidebarRowsPerAgent = config.agentSessions.sidebarRowsPerAgent
        var agentSessionsExternalAdaptersEnabled = config.agentSessions.externalAdaptersEnabled
        for tableName in agentSessionsTableNames {
            for entry in document.entries(in: tableName) {
                guard agentSessionsAllowedKeys.contains(entry.key) else {
                    diagnostics.append(
                        OmuxConfigDiagnostic(
                            severity: .error,
                            message: "Unknown [\(tableName)] key '\(entry.key)'.",
                            filePath: sourceURL.path,
                            line: entry.line
                        )
                    )
                    continue
                }

                switch entry.key {
                case "enabled":
                    guard let value = entry.value.boolValue else {
                        diagnostics.append(OmuxConfigDiagnostic(severity: .error, message: "\(tableName).enabled must be a boolean.", filePath: sourceURL.path, line: entry.line))
                        continue
                    }
                    agentSessionsEnabled = value
                case "preview_enabled":
                    guard let value = entry.value.boolValue else {
                        diagnostics.append(OmuxConfigDiagnostic(severity: .error, message: "\(tableName).preview_enabled must be a boolean.", filePath: sourceURL.path, line: entry.line))
                        continue
                    }
                    agentSessionsPreviewEnabled = value
                case "index_on_launch":
                    guard let value = entry.value.boolValue else {
                        diagnostics.append(OmuxConfigDiagnostic(severity: .error, message: "\(tableName).index_on_launch must be a boolean.", filePath: sourceURL.path, line: entry.line))
                        continue
                    }
                    agentSessionsIndexOnLaunch = value
                case "collapsed_toggle_visible":
                    guard let value = entry.value.boolValue else {
                        diagnostics.append(OmuxConfigDiagnostic(severity: .error, message: "\(tableName).collapsed_toggle_visible must be a boolean.", filePath: sourceURL.path, line: entry.line))
                        continue
                    }
                    agentSessionsCollapsedToggleVisible = value
                case "external_adapters_enabled":
                    guard let value = entry.value.boolValue else {
                        diagnostics.append(OmuxConfigDiagnostic(severity: .error, message: "\(tableName).external_adapters_enabled must be a boolean.", filePath: sourceURL.path, line: entry.line))
                        continue
                    }
                    agentSessionsExternalAdaptersEnabled = value
                case "included_agents":
                    guard let values = stringArray(from: entry.value) else {
                        diagnostics.append(OmuxConfigDiagnostic(severity: .error, message: "\(tableName).included_agents must be an array of strings.", filePath: sourceURL.path, line: entry.line))
                        continue
                    }
                    let unsupported = values.filter { supportedAgentSessionAgents.contains($0) == false }
                    guard unsupported.isEmpty else {
                        diagnostics.append(
                            OmuxConfigDiagnostic(
                                severity: .error,
                                message: "\(tableName).included_agents contains unsupported built-in agent '\(unsupported[0])'. Plugin adapters are configured under [agent-sessions.external.<name>].",
                                filePath: sourceURL.path,
                                line: entry.line
                            )
                        )
                        continue
                    }
                    agentSessionsIncludedAgents = values
                case "excluded_paths":
                    guard let values = stringArray(from: entry.value) else {
                        diagnostics.append(OmuxConfigDiagnostic(severity: .error, message: "\(tableName).excluded_paths must be an array of strings.", filePath: sourceURL.path, line: entry.line))
                        continue
                    }
                    agentSessionsExcludedPaths = values
                case "max_preview_bytes":
                    guard let value = entry.value.intValue, value >= 1024 else {
                        diagnostics.append(OmuxConfigDiagnostic(severity: .error, message: "\(tableName).max_preview_bytes must be an integer greater than or equal to 1024.", filePath: sourceURL.path, line: entry.line))
                        continue
                    }
                    agentSessionsMaxPreviewBytes = value
                case "sidebar_rows_per_agent":
                    guard let value = entry.value.intValue, value >= 1 else {
                        diagnostics.append(OmuxConfigDiagnostic(severity: .error, message: "\(tableName).sidebar_rows_per_agent must be an integer greater than or equal to 1.", filePath: sourceURL.path, line: entry.line))
                        continue
                    }
                    agentSessionsSidebarRowsPerAgent = value
                default:
                    break
                }
            }
        }

        var agentSessionsAgents = config.agentSessions.agents
        let orderedAgentTablePrefixes = ["agent-sessions.agents."]
        for tablePrefix in orderedAgentTablePrefixes {
            let tableNames = document.tableNames
                .filter { $0.hasPrefix(tablePrefix) }
                .sorted()
            for tableName in tableNames {
            let agentName = String(tableName.dropFirst(tablePrefix.count))
            guard supportedAgentSessionAgents.contains(agentName) else {
                diagnostics.append(
                    OmuxConfigDiagnostic(
                        severity: .error,
                        message: "Unsupported Agent Sessions agent '\(agentName)'.",
                        filePath: sourceURL.path
                    )
                )
                continue
            }
            let allowedAgentKeys: Set<String> = ["enabled", "home", "resume_command"]
            var enabled: Bool?
            var home: String?
            var resumeCommand: String?
            for entry in document.entries(in: tableName) {
                guard allowedAgentKeys.contains(entry.key) else {
                    diagnostics.append(
                        OmuxConfigDiagnostic(
                            severity: .error,
                            message: "Unknown [\(tableName)] key '\(entry.key)'.",
                            filePath: sourceURL.path,
                            line: entry.line
                        )
                    )
                    continue
                }
                switch entry.key {
                case "enabled":
                    guard let value = entry.value.boolValue else {
                        diagnostics.append(OmuxConfigDiagnostic(severity: .error, message: "\(tableName).enabled must be a boolean.", filePath: sourceURL.path, line: entry.line))
                        continue
                    }
                    enabled = value
                case "home":
                    guard let value = entry.value.stringValue else {
                        diagnostics.append(OmuxConfigDiagnostic(severity: .error, message: "\(tableName).home must be a string.", filePath: sourceURL.path, line: entry.line))
                        continue
                    }
                    guard value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                        diagnostics.append(OmuxConfigDiagnostic(severity: .error, message: "\(tableName).home must be a non-empty string.", filePath: sourceURL.path, line: entry.line))
                        continue
                    }
                    home = value
                case "resume_command":
                    guard let value = entry.value.stringValue else {
                        diagnostics.append(OmuxConfigDiagnostic(severity: .error, message: "\(tableName).resume_command must be a string.", filePath: sourceURL.path, line: entry.line))
                        continue
                    }
                    guard value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                        diagnostics.append(OmuxConfigDiagnostic(severity: .error, message: "\(tableName).resume_command must be a non-empty string.", filePath: sourceURL.path, line: entry.line))
                        continue
                    }
                    resumeCommand = value
                default:
                    break
                }
            }
            agentSessionsAgents[agentName] = OmuxConfigAgentSessions.Agent(enabled: enabled, home: home, resumeCommand: resumeCommand)
            }
        }

        var agentSessionsExternalAdapters = config.agentSessions.externalAdapters
        let orderedExternalTablePrefixes = ["agent-sessions.external."]
        for tablePrefix in orderedExternalTablePrefixes {
            let tableNames = document.tableNames
                .filter { $0.hasPrefix(tablePrefix) }
                .sorted()
            for tableName in tableNames {
                let adapterName = String(tableName.dropFirst(tablePrefix.count))
                let trimmedAdapterName = adapterName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmedAdapterName.isEmpty == false,
                      trimmedAdapterName.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ $0.isEmpty == false }) else {
                    diagnostics.append(
                        OmuxConfigDiagnostic(
                            severity: .error,
                            message: "Malformed Agent Sessions external adapter table [\(tableName)].",
                            filePath: sourceURL.path
                        )
                    )
                    continue
                }
                let allowedExternalKeys: Set<String> = ["enabled", "resume_command"]
                var enabled: Bool?
                var resumeCommand: String?
                for entry in document.entries(in: tableName) {
                    guard allowedExternalKeys.contains(entry.key) else {
                        diagnostics.append(
                            OmuxConfigDiagnostic(
                                severity: .error,
                                message: "Unknown [\(tableName)] key '\(entry.key)'.",
                                filePath: sourceURL.path,
                                line: entry.line
                            )
                        )
                        continue
                    }
                    switch entry.key {
                    case "enabled":
                        guard let value = entry.value.boolValue else {
                            diagnostics.append(OmuxConfigDiagnostic(severity: .error, message: "\(tableName).enabled must be a boolean.", filePath: sourceURL.path, line: entry.line))
                            continue
                        }
                        enabled = value
                    case "resume_command":
                        guard let value = entry.value.stringValue else {
                            diagnostics.append(OmuxConfigDiagnostic(severity: .error, message: "\(tableName).resume_command must be a string.", filePath: sourceURL.path, line: entry.line))
                            continue
                        }
                        guard value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                            diagnostics.append(OmuxConfigDiagnostic(severity: .error, message: "\(tableName).resume_command must be a non-empty string.", filePath: sourceURL.path, line: entry.line))
                            continue
                        }
                        resumeCommand = value
                    default:
                        break
                    }
                }
                agentSessionsExternalAdapters[trimmedAdapterName] = OmuxConfigAgentSessions.ExternalAdapter(
                    enabled: enabled,
                    resumeCommand: resumeCommand
                )
            }
        }

        var keyBindings: [OpenMUXKeyBindingOverride] = []
        var seenKeyChords = Set<OpenMUXKeyChord>()
        for entry in document.entries(in: "keys") {
            let chord: OpenMUXKeyChord
            do {
                chord = try OpenMUXKeyChord(parsing: entry.key)
            } catch {
                diagnostics.append(
                    OmuxConfigDiagnostic(
                        severity: .error,
                        message: keyChordDiagnosticMessage(for: entry.key, error: error),
                        filePath: sourceURL.path,
                        line: entry.line
                    )
                )
                continue
            }

            guard seenKeyChords.insert(chord).inserted else {
                diagnostics.append(
                    OmuxConfigDiagnostic(
                        severity: .error,
                        message: "Duplicate [keys] chord '\(entry.key)'.",
                        filePath: sourceURL.path,
                        line: entry.line
                    )
                )
                continue
            }

            guard let actionName = entry.value.stringValue else {
                diagnostics.append(
                    OmuxConfigDiagnostic(
                        severity: .error,
                        message: "[keys] value for '\(entry.key)' must be an action string or \"none\".",
                        filePath: sourceURL.path,
                        line: entry.line
                    )
                )
                continue
            }

            if actionName == "none" {
                keyBindings.append(OpenMUXKeyBindingOverride(chord: chord, action: nil))
            } else if let action = OpenMUXKeyBindingAction(rawValue: actionName) {
                keyBindings.append(OpenMUXKeyBindingOverride(chord: chord, action: action))
            } else {
                diagnostics.append(
                    OmuxConfigDiagnostic(
                        severity: .error,
                        message: "Unsupported [keys] action '\(actionName)' for chord '\(entry.key)'.",
                        filePath: sourceURL.path,
                        line: entry.line
                    )
                )
            }
        }

        let ghosttyEntries = document.entries(in: "ghostty").map {
            OmuxGhosttyConfigEntry(key: $0.key, value: $0.value, line: $0.line)
        }

        config = OmuxConfig(
            schema: schema,
            autoCheckUpdate: autoCheckUpdate,
            theme: config.theme,
            terminal: OmuxConfigTerminal(
                fontFamily: fontFamily,
                fontSize: fontSize,
                scrollbackLines: scrollbackLines,
                optionAsAlt: optionAsAlt,
                persistedScrollback: OmuxConfigTerminal.PersistedScrollback(
                    enabled: persistedScrollbackEnabled,
                    maxLines: persistedScrollbackMaxLines,
                    maxBytes: persistedScrollbackMaxBytes
                )
            ),
            workspace: OmuxConfigWorkspace(
                defaultRootPath: defaultRootPath,
                isolateShellHistory: isolateShellHistory
            ),
            ui: OmuxConfigUI(
                panes: OmuxConfigUI.Panes(
                    inactiveOpacity: paneInactiveOpacity,
                    idleStatusClear: paneIdleStatusClear
                ),
                icons: OmuxConfigUI.Icons(
                    enabled: iconsEnabled,
                    provider: iconsProvider,
                    fontFamily: iconsFontFamily,
                    colorsEnabled: iconsColorsEnabled
                )
            ),
            agentSessions: OmuxConfigAgentSessions(
                enabled: agentSessionsEnabled,
                previewEnabled: agentSessionsPreviewEnabled,
                indexOnLaunch: agentSessionsIndexOnLaunch,
                collapsedToggleVisible: agentSessionsCollapsedToggleVisible,
                includedAgents: agentSessionsIncludedAgents,
                excludedPaths: agentSessionsExcludedPaths,
                maxPreviewBytes: agentSessionsMaxPreviewBytes,
                sidebarRowsPerAgent: agentSessionsSidebarRowsPerAgent,
                externalAdaptersEnabled: agentSessionsExternalAdaptersEnabled,
                agents: agentSessionsAgents,
                externalAdapters: agentSessionsExternalAdapters
            ),
            plugins: OmuxConfigPlugins(
                markdownPreview: OmuxConfigPlugins.MarkdownPreview(
                    enabled: markdownPreviewEnabled,
                    renderer: markdownPreviewRenderer,
                    theme: markdownPreviewTheme,
                    presentation: markdownPreviewPresentation
                ),
                aiStatus: OmuxConfigPlugins.AIStatus(enabled: aiStatusEnabled)
            ),
            registries: OmuxConfigRegistries(
                hooks: hookRegistries,
                plugins: pluginRegistries
            ),
            keyBindings: keyBindings,
            ghostty: ghosttyEntries,
            sourceURL: sourceURL
        )

        return OmuxConfigLoadResult(config: config, diagnostics: diagnostics)
    }

    private func keyChordDiagnosticMessage(for rawChord: String, error: Error) -> String {
        guard let parseError = error as? OpenMUXKeyChord.ParseError else {
            return "Malformed [keys] chord '\(rawChord)'."
        }

        switch parseError {
        case .unsupportedOptionModifier:
            return "Unsupported [keys] chord '\(rawChord)': Option/Alt bindings are not supported because they conflict with international text input."
        default:
            return "Malformed [keys] chord '\(rawChord)'."
        }
    }

    private func registryURLStrings(from value: OmuxTOMLValue) -> [String]? {
        stringArray(from: value)
    }

    private func stringArray(from value: OmuxTOMLValue) -> [String]? {
        guard case .array(let values) = value else {
            return nil
        }

        var strings: [String] = []
        strings.reserveCapacity(values.count)
        for value in values {
            guard let string = value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  string.isEmpty == false
            else {
                return nil
            }
            strings.append(string)
        }
        return strings
    }

    private static func isSupportedRegistryURLString(_ value: String) -> Bool {
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased()
        else {
            return false
        }
        return ["https", "file"].contains(scheme)
    }
}
