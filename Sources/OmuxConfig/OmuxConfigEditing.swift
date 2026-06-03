import Foundation
import OmuxCore

public struct OmuxConfigExport: Codable, Equatable, Sendable {
    public struct Defaults: Codable, Equatable, Sendable {
        public let schema: Int
        public let autoCheckUpdate: Bool
        public let themeName: String
        public let workspaceDefaultRootPath: String
        public let workspaceIsolateShellHistory: Bool
        public let agentEnabled: Bool
        public let agentSkillsEnabled: Bool
        public let agentExternalToolTimeoutSeconds: Int
        public let agentTools: AgentTools
        public let inactivePaneOpacity: Double
        public let idleStatusClear: String
        public let iconsEnabled: Bool
        public let iconProvider: String
        public let iconColorsEnabled: Bool
        public let sidebarTerminalRow1: String
        public let sidebarTerminalRow2: String
        public let sidebarTerminalRow3: String
        public let markdownPreviewEnabled: Bool
        public let markdownPreviewRenderer: String
        public let markdownPreviewTheme: String
        public let markdownPreviewPresentation: String
        public let aiStatusEnabled: Bool
        public let hookRegistries: [String]
        public let pluginRegistries: [String]
        public let persistedScrollbackEnabled: Bool
        public let persistedScrollbackLines: Int
        public let persistedScrollbackBytes: Int
    }

    public struct Values: Codable, Equatable, Sendable {
        public let schema: Int
        public let autoCheckUpdate: Bool
        public let themeName: String
        public let terminal: Terminal
        public let workspace: Workspace
        public let ui: UI
        public let agent: Agent
        public let plugins: Plugins
        public let registries: Registries
    }

    public struct AgentTools: Codable, Equatable, Sendable {
        public let readTerminalHistory: Bool
        public let listDirectory: Bool
        public let runOmuxCLI: Bool
        public let readFile: Bool
        public let grepFiles: Bool
        public let listSkills: Bool
        public let readSkill: Bool
    }

    public struct Agent: Codable, Equatable, Sendable {
        public let externalPlugins: [String: AgentExternalPlugin]
        public let enabled: Bool
        public let skillsEnabled: Bool
        public let externalToolTimeoutSeconds: Int
        public let tools: AgentTools
    }

    public struct AgentExternalPlugin: Codable, Equatable, Sendable {
        public let enabled: Bool?
    }

    public struct Terminal: Codable, Equatable, Sendable {
        public let fontFamily: String?
        public let fontSize: Int?
        public let scrollbackLines: Int?
        public let optionAsAlt: String?
        public let persistedScrollback: PersistedScrollback
    }

    public struct PersistedScrollback: Codable, Equatable, Sendable {
        public let enabled: Bool
        public let maxLines: Int
        public let maxBytes: Int
    }

    public struct Workspace: Codable, Equatable, Sendable {
        public let defaultRootPath: String
        public let isolateShellHistory: Bool
    }

    public struct UI: Codable, Equatable, Sendable {
        public let panes: Panes
        public let icons: Icons
        public let sidebar: Sidebar
    }

    public struct Panes: Codable, Equatable, Sendable {
        public let inactiveOpacity: Double
        public let idleStatusClear: String
    }

    public struct Icons: Codable, Equatable, Sendable {
        public let enabled: Bool
        public let provider: String
        public let fontFamily: String?
        public let colorsEnabled: Bool
    }

    public struct Sidebar: Codable, Equatable, Sendable {
        public let terminalRow1: String
        public let terminalRow2: String
        public let terminalRow3: String
    }

    public struct Plugins: Codable, Equatable, Sendable {
        public let markdownPreview: MarkdownPreview
        public let aiStatus: AIStatus
    }

    public struct MarkdownPreview: Codable, Equatable, Sendable {
        public let enabled: Bool
        public let renderer: String
        public let theme: String
        public let presentation: String
    }

    public struct AIStatus: Codable, Equatable, Sendable {
        public let enabled: Bool
    }

    public struct Registries: Codable, Equatable, Sendable {
        public let hooks: [String]
        public let plugins: [String]
    }

    public let sourcePath: String
    public let values: Values
    public let defaults: Defaults
    public let diagnostics: [OmuxConfigDiagnostic]
}

public struct OmuxConfigApplyPayload: Codable, Equatable, Sendable {
    public struct Terminal: Codable, Equatable, Sendable {
        public var fontFamily: String?
        public var fontSize: Int?
        public var scrollbackLines: Int?
        public var optionAsAlt: String?
        public var persistedScrollback: PersistedScrollback?
    }

    public struct PersistedScrollback: Codable, Equatable, Sendable {
        public var enabled: Bool?
        public var maxLines: Int?
        public var maxBytes: Int?
    }

    public struct Workspace: Codable, Equatable, Sendable {
        public var defaultRootPath: String?
        public var isolateShellHistory: Bool?
    }

    public struct Agent: Codable, Equatable, Sendable {
        public var enabled: Bool?
        public var skillsEnabled: Bool?
        public var externalToolTimeoutSeconds: Int?
        public var tools: AgentTools?
        public var externalPlugins: [String: AgentExternalPlugin]?
    }

    public struct AgentTools: Codable, Equatable, Sendable {
        public var readTerminalHistory: Bool?
        public var listDirectory: Bool?
        public var runOmuxCLI: Bool?
        public var readFile: Bool?
        public var grepFiles: Bool?
        public var listSkills: Bool?
        public var readSkill: Bool?
    }

    public struct AgentExternalPlugin: Codable, Equatable, Sendable {
        public var enabled: Bool?
    }

    public struct UI: Codable, Equatable, Sendable {
        public var panes: Panes?
        public var icons: Icons?
        public var sidebar: Sidebar?
    }

    public struct Panes: Codable, Equatable, Sendable {
        public var inactiveOpacity: Double?
        public var idleStatusClear: String?
    }

    public struct Icons: Codable, Equatable, Sendable {
        public var enabled: Bool?
        public var provider: String?
        public var fontFamily: String?
        public var colorsEnabled: Bool?
    }

    public struct Sidebar: Codable, Equatable, Sendable {
        public var terminalRow1: String?
        public var terminalRow2: String?
        public var terminalRow3: String?
    }

    public struct Plugins: Codable, Equatable, Sendable {
        public var markdownPreview: MarkdownPreview?
        public var aiStatus: AIStatus?
    }

    public struct MarkdownPreview: Codable, Equatable, Sendable {
        public var enabled: Bool?
        public var renderer: String?
        public var theme: String?
        public var presentation: String?
    }

    public struct AIStatus: Codable, Equatable, Sendable {
        public var enabled: Bool?
    }

    public struct Registries: Codable, Equatable, Sendable {
        public var hooks: [String]?
        public var plugins: [String]?
    }

    public var autoCheckUpdate: Bool?
    public var themeName: String?
    public var terminal: Terminal?
    public var workspace: Workspace?
    public var ui: UI?
    public var agent: Agent?
    public var plugins: Plugins?
    public var registries: Registries?
}

public struct OmuxConfigApplyResult: Codable, Equatable, Sendable {
    public let applied: Bool
    public let path: String
    public let backupPath: String?
    public let diagnostics: [OmuxConfigDiagnostic]
}

public struct OmuxConfigExporter {
    public let loader: OmuxConfigLoader

    public init(loader: OmuxConfigLoader = OmuxConfigLoader()) {
        self.loader = loader
    }

    public func export() -> OmuxConfigExport {
        let result = loader.load()
        let config = result.config
        return OmuxConfigExport(
            sourcePath: (config.sourceURL ?? OmuxConfigPaths.configFileURL).path,
            values: .init(config: config),
            defaults: .init(config: .defaults),
            diagnostics: result.diagnostics
        )
    }
}

public struct OmuxConfigEditor {
    public let loader: OmuxConfigLoader
    public var fileManager: FileManager

    public init(loader: OmuxConfigLoader = OmuxConfigLoader(), fileManager: FileManager = .default) {
        self.loader = loader
        self.fileManager = fileManager
    }

    public func apply(jsonFileURL: URL) throws -> OmuxConfigApplyResult {
        let data = try Data(contentsOf: jsonFileURL)
        let unsupportedDiagnostics = try unsupportedKeyDiagnostics(in: data, filePath: jsonFileURL.path)
        guard unsupportedDiagnostics.isEmpty else {
            return OmuxConfigApplyResult(
                applied: false,
                path: OmuxConfigPaths.configFileURL.path,
                backupPath: nil,
                diagnostics: unsupportedDiagnostics
            )
        }

        let payload: OmuxConfigApplyPayload
        do {
            payload = try JSONDecoder().decode(OmuxConfigApplyPayload.self, from: data)
        } catch {
            return OmuxConfigApplyResult(
                applied: false,
                path: OmuxConfigPaths.configFileURL.path,
                backupPath: nil,
                diagnostics: [
                    OmuxConfigDiagnostic(
                        severity: .error,
                        message: "Invalid config apply JSON: \(error.localizedDescription)",
                        filePath: jsonFileURL.path
                    ),
                ]
            )
        }

        let currentResult = loader.load()
        guard currentResult.hasErrors == false else {
            return OmuxConfigApplyResult(
                applied: false,
                path: (currentResult.config.sourceURL ?? OmuxConfigPaths.configFileURL).path,
                backupPath: nil,
                diagnostics: currentResult.diagnostics
            )
        }

        let current = currentResult.config
        if let externalToolTimeout = payload.agent?.externalToolTimeoutSeconds, externalToolTimeout <= 0 {
            return OmuxConfigApplyResult(
                applied: false,
                path: (current.sourceURL ?? OmuxConfigPaths.configFileURL).path,
                backupPath: nil,
                diagnostics: [
                    OmuxConfigDiagnostic(
                        severity: .error,
                        message: "agent.external_tool_timeout_seconds must be greater than 0.",
                        filePath: jsonFileURL.path
                    ),
                ]
            )
        }
        let configURL = current.sourceURL ?? OmuxConfigPaths.configFileURL
        let updated = updatedConfig(from: current, applying: payload, sourceURL: configURL)
        let rendered = OmuxConfigRenderer.render(config: updated)
        let validationURL = fileManager.temporaryDirectory
            .appendingPathComponent("omux-config-apply-\(UUID().uuidString).toml")
        try rendered.write(to: validationURL, atomically: true, encoding: .utf8)
        defer { try? fileManager.removeItem(at: validationURL) }

        let validationResult = loader.load(url: validationURL)
        guard validationResult.hasErrors == false else {
            return OmuxConfigApplyResult(
                applied: false,
                path: configURL.path,
                backupPath: nil,
                diagnostics: validationResult.diagnostics
            )
        }

        try fileManager.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let backupURL = try backupExistingConfig(configURL)
        try rendered.write(to: configURL, atomically: true, encoding: .utf8)
        return OmuxConfigApplyResult(applied: true, path: configURL.path, backupPath: backupURL?.path, diagnostics: [])
    }

    private func backupExistingConfig(_ configURL: URL) throws -> URL? {
        guard fileManager.fileExists(atPath: configURL.path) else {
            return nil
        }
        let backupDirectory = OmuxConfigPaths.baseDirectoryURL.appendingPathComponent("backups", isDirectory: true)
        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let backupURL = backupDirectory.appendingPathComponent("config-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString).toml")
        try fileManager.copyItem(at: configURL, to: backupURL)
        return backupURL
    }

    private func updatedConfig(from current: OmuxConfig, applying payload: OmuxConfigApplyPayload, sourceURL: URL) -> OmuxConfig {
        let terminalPayload = payload.terminal
        let persistedPayload = terminalPayload?.persistedScrollback
        let persistedScrollback = OmuxConfigTerminal.PersistedScrollback(
            enabled: persistedPayload?.enabled ?? current.terminal.persistedScrollback.enabled,
            maxLines: persistedPayload?.maxLines ?? current.terminal.persistedScrollback.maxLines,
            maxBytes: persistedPayload?.maxBytes ?? current.terminal.persistedScrollback.maxBytes
        )

        let optionAsAlt: OmuxConfigTerminal.OptionAsAlt?
        if let rawOptionAsAlt = terminalPayload?.optionAsAlt {
            switch rawOptionAsAlt {
            case "disabled", "false":
                optionAsAlt = .disabled
            case "both", "true":
                optionAsAlt = .both
            case "left":
                optionAsAlt = .left
            case "right":
                optionAsAlt = .right
            default:
                optionAsAlt = current.terminal.optionAsAlt
            }
        } else {
            optionAsAlt = current.terminal.optionAsAlt
        }

        let panesPayload = payload.ui?.panes
        let iconsPayload = payload.ui?.icons
        let sidebarPayload = payload.ui?.sidebar
        let agentPayload = payload.agent
        let agentToolsPayload = agentPayload?.tools
        let markdownPreviewPayload = payload.plugins?.markdownPreview
        let aiStatusPayload = payload.plugins?.aiStatus
        return OmuxConfig(
            schema: current.schema,
            autoCheckUpdate: payload.autoCheckUpdate ?? current.autoCheckUpdate,
            theme: OmuxConfigTheme(name: payload.themeName ?? current.theme.name),
            terminal: OmuxConfigTerminal(
                fontFamily: terminalPayload?.fontFamily ?? current.terminal.fontFamily,
                fontSize: terminalPayload?.fontSize ?? current.terminal.fontSize,
                scrollbackLines: terminalPayload?.scrollbackLines ?? current.terminal.scrollbackLines,
                optionAsAlt: optionAsAlt,
                persistedScrollback: persistedScrollback
            ),
            workspace: OmuxConfigWorkspace(
                defaultRootPath: payload.workspace?.defaultRootPath ?? current.workspace.defaultRootPath,
                isolateShellHistory: payload.workspace?.isolateShellHistory ?? current.workspace.isolateShellHistory
            ),
            ui: OmuxConfigUI(
                panes: OmuxConfigUI.Panes(
                    inactiveOpacity: panesPayload?.inactiveOpacity ?? current.ui.panes.inactiveOpacity,
                    idleStatusClear: panesPayload?.idleStatusClear.flatMap(OmuxConfigUI.Panes.IdleStatusClear.init(rawValue:)) ?? current.ui.panes.idleStatusClear
                ),
                icons: OmuxConfigUI.Icons(
                    enabled: iconsPayload?.enabled ?? current.ui.icons.enabled,
                    provider: iconsPayload?.provider.flatMap(OmuxConfigUI.Icons.Provider.init(rawValue:)) ?? current.ui.icons.provider,
                    fontFamily: iconsPayload?.fontFamily ?? current.ui.icons.fontFamily,
                    colorsEnabled: iconsPayload?.colorsEnabled ?? current.ui.icons.colorsEnabled
                ),
                sidebar: OmuxConfigUI.Sidebar(
                    terminalRows: OmuxConfigUI.Sidebar.TerminalRows(
                        row1: sidebarPayload?.terminalRow1.flatMap(OmuxConfigUI.Sidebar.TerminalRowSource.init(rawValue:)) ?? current.ui.sidebar.terminalRows.row1,
                        row2: sidebarPayload?.terminalRow2.flatMap(OmuxConfigUI.Sidebar.TerminalRowSource.init(rawValue:)) ?? current.ui.sidebar.terminalRows.row2,
                        row3: sidebarPayload?.terminalRow3.flatMap(OmuxConfigUI.Sidebar.TerminalRowSource.init(rawValue:)) ?? current.ui.sidebar.terminalRows.row3
                    )
                )
            ),
            agent: OmuxConfigAgent(
                enabled: agentPayload?.enabled ?? current.agent.enabled,
                skillsEnabled: agentPayload?.skillsEnabled ?? current.agent.skillsEnabled,
                externalToolTimeoutSeconds: agentPayload?.externalToolTimeoutSeconds ?? current.agent.externalToolTimeoutSeconds,
                tools: OmuxConfigAgent.Tools(
                    readTerminalHistory: agentToolsPayload?.readTerminalHistory ?? current.agent.tools.readTerminalHistory,
                    listDirectory: agentToolsPayload?.listDirectory ?? current.agent.tools.listDirectory,
                    runOmuxCLI: agentToolsPayload?.runOmuxCLI ?? current.agent.tools.runOmuxCLI,
                    readFile: agentToolsPayload?.readFile ?? current.agent.tools.readFile,
                    grepFiles: agentToolsPayload?.grepFiles ?? current.agent.tools.grepFiles,
                    listSkills: agentToolsPayload?.listSkills ?? current.agent.tools.listSkills,
                    readSkill: agentToolsPayload?.readSkill ?? current.agent.tools.readSkill
                ),
                externalPlugins: agentPayload?.externalPlugins.map { extPlugins in
                    var merged = current.agent.externalPlugins
                    for (key, value) in extPlugins {
                        merged[key] = OmuxConfigAgent.ExternalPlugin(enabled: value.enabled ?? merged[key]?.enabled)
                    }
                    return merged
                } ?? current.agent.externalPlugins
            ),
            plugins: OmuxConfigPlugins(
                markdownPreview: OmuxConfigPlugins.MarkdownPreview(
                    enabled: markdownPreviewPayload?.enabled ?? current.plugins.markdownPreview.enabled,
                    renderer: markdownPreviewPayload?.renderer ?? current.plugins.markdownPreview.renderer,
                    theme: markdownPreviewPayload?.theme ?? current.plugins.markdownPreview.theme,
                    presentation: markdownPreviewPayload?.presentation ?? current.plugins.markdownPreview.presentation
                ),
                aiStatus: OmuxConfigPlugins.AIStatus(
                    enabled: aiStatusPayload?.enabled ?? current.plugins.aiStatus.enabled
                )
            ),
            registries: OmuxConfigRegistries(
                hooks: payload.registries?.hooks ?? current.registries.hooks,
                plugins: payload.registries?.plugins ?? current.registries.plugins
            ),
            keyBindings: current.keyBindings,
            ghostty: current.ghostty,
            sourceURL: sourceURL
        )
    }

    private func unsupportedKeyDiagnostics(in data: Data, filePath: String) throws -> [OmuxConfigDiagnostic] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            return [
                OmuxConfigDiagnostic(
                    severity: .error,
                    message: "Config apply JSON must be an object.",
                    filePath: filePath
                ),
            ]
        }
        return unsupportedKeys(in: dictionary, allowed: Self.allowedKeys, prefix: "", filePath: filePath)
    }

    private func unsupportedKeys(
        in dictionary: [String: Any],
        allowed: [String: Any],
        prefix: String,
        filePath: String
    ) -> [OmuxConfigDiagnostic] {
        var diagnostics: [OmuxConfigDiagnostic] = []
        for key in dictionary.keys.sorted() {
            guard let rule = allowed[key] else {
                diagnostics.append(
                    OmuxConfigDiagnostic(
                        severity: .error,
                        message: "Unsupported config apply key '\(prefix + key)'.",
                        filePath: filePath
                    )
                )
                continue
            }
            if let childDictionary = dictionary[key] as? [String: Any],
               let childAllowed = rule as? [String: Any] {
                diagnostics += unsupportedKeys(
                    in: childDictionary,
                    allowed: childAllowed,
                    prefix: prefix + key + ".",
                    filePath: filePath
                )
            }
        }
        return diagnostics
    }

    private static var allowedKeys: [String: Any] {
        [
            "autoCheckUpdate": true,
            "themeName": true,
            "terminal": [
                "fontFamily": true,
                "fontSize": true,
                "scrollbackLines": true,
                "optionAsAlt": true,
                "persistedScrollback": [
                    "enabled": true,
                    "maxLines": true,
                    "maxBytes": true,
                ],
            ],
            "workspace": ["defaultRootPath": true, "isolateShellHistory": true],
            "ui": [
                "panes": [
                    "inactiveOpacity": true,
                    "idleStatusClear": true,
                ],
                "icons": [
                    "enabled": true,
                    "provider": true,
                    "fontFamily": true,
                    "colorsEnabled": true,
                ],
                "sidebar": [
                    "terminalRow1": true,
                    "terminalRow2": true,
                    "terminalRow3": true,
                ],
            ],
            "agent": [
                "enabled": true,
                "skillsEnabled": true,
                "externalToolTimeoutSeconds": true,
                "tools": [
                    "readTerminalHistory": true,
                    "listDirectory": true,
                    "runOmuxCLI": true,
                    "readFile": true,
                    "grepFiles": true,
                    "listSkills": true,
                    "readSkill": true,
                ],
                "externalPlugins": true,
            ],
            "plugins": [
                "markdownPreview": [
                    "enabled": true,
                    "renderer": true,
                    "theme": true,
                    "presentation": true,
                ],
                "aiStatus": [
                    "enabled": true,
                ],
            ],
            "registries": [
                "hooks": true,
                "plugins": true,
            ],
        ]
    }
}

public enum OmuxConfigRenderer {
    public static func render(config: OmuxConfig) -> String {
        var lines: [String] = ["schema = \(config.schema)"]
        if config.autoCheckUpdate == false {
            lines.append("auto_check_update = false")
        }
        lines.append("")
        lines.append("[theme]")
        lines.append("name = \(render(.string(config.theme.name)))")
        lines.append("")
        lines.append("[terminal]")

        if let fontFamily = config.terminal.fontFamily {
            lines.append("font_family = \(render(.string(fontFamily)))")
        }
        if let fontSize = config.terminal.fontSize {
            lines.append("font_size = \(fontSize)")
        }
        if let scrollbackLines = config.terminal.scrollbackLines {
            lines.append("scrollback_lines = \(scrollbackLines)")
        }
        if let optionAsAlt = config.terminal.optionAsAlt {
            switch optionAsAlt {
            case .disabled:
                lines.append("option_as_alt = false")
            case .both:
                lines.append("option_as_alt = true")
            case .left:
                lines.append("option_as_alt = \"left\"")
            case .right:
                lines.append("option_as_alt = \"right\"")
            }
        }
        let persistedScrollback = config.terminal.persistedScrollback
        if persistedScrollback.enabled != OmuxConfigTerminal.PersistedScrollback.defaultEnabled {
            lines.append("persist_scrollback = \(persistedScrollback.enabled ? "true" : "false")")
        }
        if persistedScrollback.maxLines != OmuxConfigTerminal.PersistedScrollback.defaultMaxLines {
            lines.append("persist_scrollback_lines = \(persistedScrollback.maxLines)")
        }
        if persistedScrollback.maxBytes != OmuxConfigTerminal.PersistedScrollback.defaultMaxBytes {
            lines.append("persist_scrollback_bytes = \(persistedScrollback.maxBytes)")
        }

        lines.append("")
        lines.append("[workspace]")
        lines.append("default_root_path = \(render(.string(config.workspace.defaultRootPath)))")
        lines.append("isolate_shell_history = \(config.workspace.isolateShellHistory ? "true" : "false")")
        lines.append("")
        lines.append("[ui.icons]")
        lines.append("enabled = \(config.ui.icons.enabled ? "true" : "false")")
        lines.append("provider = \(render(.string(config.ui.icons.provider.rawValue)))")
        if let fontFamily = config.ui.icons.fontFamily {
            lines.append("font_family = \(render(.string(fontFamily)))")
        }
        lines.append("colors_enabled = \(config.ui.icons.colorsEnabled ? "true" : "false")")
        lines.append("")
        lines.append("[ui.sidebar]")
        lines.append("terminal_row_1 = \(render(.string(config.ui.sidebar.terminalRows.row1.rawValue)))")
        lines.append("terminal_row_2 = \(render(.string(config.ui.sidebar.terminalRows.row2.rawValue)))")
        lines.append("terminal_row_3 = \(render(.string(config.ui.sidebar.terminalRows.row3.rawValue)))")
        lines.append("")
        lines.append("[ui.panes]")
        lines.append("inactive_opacity = \(renderOpacity(config.ui.panes.inactiveOpacity))")
        lines.append("idle_status_clear = \(render(.string(config.ui.panes.idleStatusClear.rawValue)))")
        lines.append("")
        lines.append("[agent]")
        lines.append("enabled = \(config.agent.enabled ? "true" : "false")")
        lines.append("skills_enabled = \(config.agent.skillsEnabled ? "true" : "false")")
        lines.append("external_tool_timeout_seconds = \(config.agent.externalToolTimeoutSeconds)")
        lines.append("")
        lines.append("[agent.tools]")
        lines.append("read_terminal_history = \(config.agent.tools.readTerminalHistory ? "true" : "false")")
        lines.append("list_directory = \(config.agent.tools.listDirectory ? "true" : "false")")
        lines.append("run_omux_cli = \(config.agent.tools.runOmuxCLI ? "true" : "false")")
        lines.append("read_file = \(config.agent.tools.readFile ? "true" : "false")")
        lines.append("grep_files = \(config.agent.tools.grepFiles ? "true" : "false")")
        lines.append("list_skills = \(config.agent.tools.listSkills ? "true" : "false")")
        lines.append("read_skill = \(config.agent.tools.readSkill ? "true" : "false")")
        for pluginName in config.agent.externalPlugins.keys.sorted() {
            guard let setting = config.agent.externalPlugins[pluginName],
                  let enabled = setting.enabled else {
                continue
            }
            lines.append("")
            lines.append("[\(render(.string("agent.external.\(pluginName)")))]")
            lines.append("enabled = \(enabled ? "true" : "false")")
        }
        lines.append("")
        lines.append("[plugins.markdown-preview]")
        let markdownPreview = config.plugins.markdownPreview
        lines.append("enabled = \(markdownPreview.enabled ? "true" : "false")")
        lines.append("renderer = \(render(.string(markdownPreview.renderer)))")
        lines.append("theme = \(render(.string(markdownPreview.theme)))")
        lines.append("presentation = \(render(.string(markdownPreview.presentation)))")
        lines.append("")
        lines.append("[plugins.ai-status]")
        lines.append("enabled = \(config.plugins.aiStatus.enabled ? "true" : "false")")
        lines.append("")
        lines.append("[registries]")
        lines.append("hooks = \(render(.array(config.registries.hooks.map(OmuxTOMLValue.string))))")
        lines.append("plugins = \(render(.array(config.registries.plugins.map(OmuxTOMLValue.string))))")
        lines.append("")
        lines.append("[keys]")
        for entry in config.keyBindings {
            let value = entry.action?.rawValue ?? "none"
            lines.append("\"\(entry.chord.description)\" = \(render(.string(value)))")
        }
        lines.append("")
        lines.append("[ghostty]")
        for entry in config.ghostty {
            lines.append("\"\(escape(entry.key))\" = \(render(entry.value))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func render(_ value: OmuxTOMLValue) -> String {
        switch value {
        case .string(let string):
            return "\"\(escape(string))\""
        case .integer(let integer):
            return String(integer)
        case .double(let double):
            return String(double)
        case .bool(let bool):
            return bool ? "true" : "false"
        case .array(let values):
            return "[\(values.map(render).joined(separator: ", "))]"
        }
    }

    private static func renderOpacity(_ opacity: Double) -> String {
        let rounded = (opacity * 1000).rounded() / 1000
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(rounded)
    }

    private static func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}

private extension OmuxConfigExport.Values {
    init(config: OmuxConfig) {
        self.init(
            schema: config.schema,
            autoCheckUpdate: config.autoCheckUpdate,
            themeName: config.theme.name,
            terminal: .init(config: config.terminal),
            workspace: .init(
                defaultRootPath: config.workspace.defaultRootPath,
                isolateShellHistory: config.workspace.isolateShellHistory
            ),
            ui: .init(config: config.ui),
            agent: .init(config: config.agent),
            plugins: .init(config: config.plugins),
            registries: .init(hooks: config.registries.hooks, plugins: config.registries.plugins)
        )
    }
}

private extension OmuxConfigExport.Defaults {
    init(config: OmuxConfig) {
        self.init(
            schema: config.schema,
            autoCheckUpdate: config.autoCheckUpdate,
            themeName: config.theme.name,
            workspaceDefaultRootPath: config.workspace.defaultRootPath,
            workspaceIsolateShellHistory: config.workspace.isolateShellHistory,
            agentEnabled: config.agent.enabled,
            agentSkillsEnabled: config.agent.skillsEnabled,
            agentExternalToolTimeoutSeconds: config.agent.externalToolTimeoutSeconds,
            agentTools: .init(config: config.agent.tools),
            inactivePaneOpacity: config.ui.panes.inactiveOpacity,
            idleStatusClear: config.ui.panes.idleStatusClear.rawValue,
            iconsEnabled: config.ui.icons.enabled,
            iconProvider: config.ui.icons.provider.rawValue,
            iconColorsEnabled: config.ui.icons.colorsEnabled,
            sidebarTerminalRow1: config.ui.sidebar.terminalRows.row1.rawValue,
            sidebarTerminalRow2: config.ui.sidebar.terminalRows.row2.rawValue,
            sidebarTerminalRow3: config.ui.sidebar.terminalRows.row3.rawValue,
            markdownPreviewEnabled: config.plugins.markdownPreview.enabled,
            markdownPreviewRenderer: config.plugins.markdownPreview.renderer,
            markdownPreviewTheme: config.plugins.markdownPreview.theme,
            markdownPreviewPresentation: config.plugins.markdownPreview.presentation,
            aiStatusEnabled: config.plugins.aiStatus.enabled,
            hookRegistries: config.registries.hooks,
            pluginRegistries: config.registries.plugins,
            persistedScrollbackEnabled: config.terminal.persistedScrollback.enabled,
            persistedScrollbackLines: config.terminal.persistedScrollback.maxLines,
            persistedScrollbackBytes: config.terminal.persistedScrollback.maxBytes
        )
    }
}

private extension OmuxConfigExport.Terminal {
    init(config: OmuxConfigTerminal) {
        let optionAsAlt: String?
        switch config.optionAsAlt {
        case .disabled:
            optionAsAlt = "disabled"
        case .both:
            optionAsAlt = "both"
        case .left:
            optionAsAlt = "left"
        case .right:
            optionAsAlt = "right"
        case nil:
            optionAsAlt = nil
        }
        self.init(
            fontFamily: config.fontFamily,
            fontSize: config.fontSize,
            scrollbackLines: config.scrollbackLines,
            optionAsAlt: optionAsAlt,
            persistedScrollback: .init(
                enabled: config.persistedScrollback.enabled,
                maxLines: config.persistedScrollback.maxLines,
                maxBytes: config.persistedScrollback.maxBytes
            )
        )
    }
}

private extension OmuxConfigExport.UI {
    init(config: OmuxConfigUI) {
        self.init(
            panes: .init(
                inactiveOpacity: config.panes.inactiveOpacity,
                idleStatusClear: config.panes.idleStatusClear.rawValue
            ),
            icons: .init(
                enabled: config.icons.enabled,
                provider: config.icons.provider.rawValue,
                fontFamily: config.icons.fontFamily,
                colorsEnabled: config.icons.colorsEnabled
            ),
            sidebar: .init(
                terminalRow1: config.sidebar.terminalRows.row1.rawValue,
                terminalRow2: config.sidebar.terminalRows.row2.rawValue,
                terminalRow3: config.sidebar.terminalRows.row3.rawValue
            )
        )
    }
}

private extension OmuxConfigExport.Agent {
    init(config: OmuxConfigAgent) {
        self.init(
            externalPlugins: config.externalPlugins.mapValues { .init(enabled: $0.enabled) },
            enabled: config.enabled,
            skillsEnabled: config.skillsEnabled,
            externalToolTimeoutSeconds: config.externalToolTimeoutSeconds,
            tools: .init(config: config.tools)
        )
    }
}

private extension OmuxConfigExport.AgentTools {
    init(config: OmuxConfigAgent.Tools) {
        self.init(
            readTerminalHistory: config.readTerminalHistory,
            listDirectory: config.listDirectory,
            runOmuxCLI: config.runOmuxCLI,
            readFile: config.readFile,
            grepFiles: config.grepFiles,
            listSkills: config.listSkills,
            readSkill: config.readSkill
        )
    }
}

private extension OmuxConfigExport.Plugins {
    init(config: OmuxConfigPlugins) {
        self.init(
            markdownPreview: .init(
                enabled: config.markdownPreview.enabled,
                renderer: config.markdownPreview.renderer,
                theme: config.markdownPreview.theme,
                presentation: config.markdownPreview.presentation
            ),
            aiStatus: .init(enabled: config.aiStatus.enabled)
        )
    }
}
