import Foundation
import OmuxControlPlane
import OmuxConfig
import OmuxCore
import OmuxTheme

public struct OmuxCLICommand {
    private let client: OmuxControlClient
    private let writeLine: (String) -> Void
    private let readInputLine: () -> String?
    private let configLoader: OmuxConfigLoader
    private let themeRegistry: OmuxThemeRegistry
    private let installer: OmuxCLIInstaller

    public init(
        client: OmuxControlClient = OmuxControlClient(),
        writeLine: @escaping (String) -> Void = { print($0) },
        readInputLine: @escaping () -> String? = { Swift.readLine(strippingNewline: true) },
        configLoader: OmuxConfigLoader = OmuxConfigLoader(),
        themeRegistry: OmuxThemeRegistry = OmuxThemeRegistry()
    ) {
        self.init(
            client: client,
            writeLine: writeLine,
            readInputLine: readInputLine,
            configLoader: configLoader,
            themeRegistry: themeRegistry,
            installer: OmuxCLIInstaller()
        )
    }

    init(
        client: OmuxControlClient,
        writeLine: @escaping (String) -> Void,
        readInputLine: @escaping () -> String?,
        configLoader: OmuxConfigLoader,
        themeRegistry: OmuxThemeRegistry,
        installer: OmuxCLIInstaller
    ) {
        self.client = client
        self.writeLine = writeLine
        self.readInputLine = readInputLine
        self.configLoader = configLoader
        self.themeRegistry = themeRegistry
        self.installer = installer
    }

    @discardableResult
    public func run(arguments: [String]) -> Int32 {
        let commandArguments = Array(arguments.dropFirst())
        guard let command = commandArguments.first else {
            writeLine(Self.usage)
            return 1
        }

        do {
            switch command {
            case "config":
                return runConfigCommand(arguments: Array(commandArguments.dropFirst()))
            case "theme":
                return runThemeCommand(arguments: Array(commandArguments.dropFirst()))
            case "list":
                let response = try client.request(method: .listWorkspaces)
                writeLine(response.result?.prettyPrinted ?? "[]")
            case "events":
                try client.streamTerminalEvents { event in
                    writeLine(event.prettyPrinted)
                }
            case "tab":
                let response = try client.request(method: .createTab)
                writeLine(response.result?.prettyPrinted ?? "")
            case "split":
                let axis = splitAxis(from: commandArguments.dropFirst())
                let response = try client.request(
                    method: .splitPane,
                    params: .object(["axis": .string(axis.rawValue)])
                )
                writeLine(response.result?.prettyPrinted ?? "")
            case "pane-tab":
                let response = try client.request(method: .createPaneTab)
                writeLine(response.result?.prettyPrinted ?? "")
            case "pane-tab-focus":
                guard commandArguments.count >= 2 else {
                    writeLine("usage: omux pane-tab-focus <pane-id>")
                    return 1
                }

                let response = try client.request(
                    method: .focusPaneTab,
                    params: .object(["paneID": .string(commandArguments[1])])
                )
                writeLine(response.result?.prettyPrinted ?? "")
            case "pane-tab-close":
                let params: RPCValue?
                if commandArguments.count >= 2 {
                    params = .object(["paneID": .string(commandArguments[1])])
                } else {
                    params = nil
                }

                let response = try client.request(method: .closePaneTab, params: params)
                writeLine(response.result?.prettyPrinted ?? "")
            case "open":
                guard commandArguments.count >= 2 else {
                    writeLine("usage: omux open <path>")
                    return 1
                }

                let path = commandArguments[1]
                let response = try client.request(
                    method: .openWorkspace,
                    params: .object(["path": .string(path)])
                )
                writeLine(response.result?.prettyPrinted ?? "")
            case "focus":
                guard commandArguments.count >= 2 else {
                    writeLine("usage: omux focus <session-id>")
                    return 1
                }

                let response = try client.request(
                    method: .focusSession,
                    params: .object(["sessionID": .string(commandArguments[1])])
                )
                writeLine(response.result?.prettyPrinted ?? "")
            case "run":
                guard commandArguments.count >= 3 else {
                    writeLine("usage: omux run <session-id> <command>")
                    return 1
                }

                let sessionID = commandArguments[1]
                let command = commandArguments.dropFirst(2).joined(separator: " ")
                let response = try client.request(
                    method: .runCommand,
                    params: .object([
                        "sessionID": .string(sessionID),
                        "command": .string(command),
                    ])
                )
                writeLine(response.result?.prettyPrinted ?? "")
            case "notify":
                guard commandArguments.count >= 2 else {
                    writeLine("usage: omux notify <title> [body]")
                    return 1
                }

                let body = commandArguments.dropFirst(2).joined(separator: " ")
                let response = try client.request(
                    method: .sendNotification,
                    params: .object([
                        "title": .string(commandArguments[1]),
                        "body": .string(body),
                    ])
                )
                writeLine(response.result?.prettyPrinted ?? "")
            case "restore":
                guard commandArguments.count >= 2 else {
                    writeLine("usage: omux restore <workspace-id>")
                    return 1
                }

                let response = try client.request(
                    method: .restoreLayout,
                    params: .object(["workspaceID": .string(commandArguments[1])])
                )
                writeLine(response.result?.prettyPrinted ?? "")
            case "help", "--help", "-h":
                writeLine(Self.usage)
            case "install-cli":
                return runInstallCLI(arguments: Array(commandArguments.dropFirst()))
            default:
                writeLine(Self.usage)
                return 1
            }
        } catch {
            writeLine("omux error: \(error)")
            return 1
        }

        return 0
    }

    public static let usage = """
    OpenMUX CLI

    Commands:
      omux config doctor
      omux config reload
      omux config init
      omux theme
      omux theme <name>
      omux theme list
      omux list
      omux events
      omux open <path>
      omux tab
      omux split [right|down]
      omux pane-tab
      omux pane-tab-focus <pane-id>
      omux pane-tab-close [pane-id]
      omux focus <session-id>
      omux run <session-id> <command>
      omux notify <title> [body]
      omux restore <workspace-id>
      omux install-cli [destination]
    """

    private func splitAxis(from arguments: ArraySlice<String>) -> PaneSplitAxis {
        guard let value = arguments.first?.lowercased() else {
            return .columns
        }

        switch value {
        case "down", "vertical":
            return .rows
        default:
            return .columns
        }
    }

    private func runConfigCommand(arguments: [String]) -> Int32 {
        guard let subcommand = arguments.first else {
            writeLine("usage: omux config <doctor|reload|init>")
            return 1
        }

        do {
            switch subcommand {
            case "doctor":
                return try runConfigDoctor()
            case "reload":
                return try runConfigReload()
            case "init":
                let configURL = OmuxConfigPaths.configFileURL
                if FileManager.default.fileExists(atPath: configURL.path) {
                    writeLine("omux error: \(configURL.path) already exists")
                    return 1
                }

                try FileManager.default.createDirectory(
                    at: OmuxConfigPaths.baseDirectoryURL,
                    withIntermediateDirectories: true
                )
                try OmuxConfigTemplate.starter().write(to: configURL, atomically: true, encoding: .utf8)
                writeLine("Wrote \(configURL.path)")
                return 0
            default:
                writeLine("usage: omux config <doctor|reload|init>")
                return 1
            }
        } catch {
            writeLine("omux error: \(error)")
            return 1
        }
    }

    private func runThemeCommand(arguments: [String]) -> Int32 {
        do {
            let (themes, themeDiagnostics) = themeRegistry.loadThemes()
            let configResult = configLoader.load()
            let currentThemeName = configResult.hasErrors ? nil : configResult.config.theme.name

            if arguments.first == "list" {
                guard arguments.count == 1 else {
                    writeLine("usage: omux theme [list|<name>]")
                    return 1
                }
                let exitCode = printDiagnosticsAndReturnCode(themeDiagnostics, printEmptyMessage: false)
                printThemes(themes, currentThemeName: currentThemeName)
                return exitCode
            }

            guard arguments.count <= 1 else {
                writeLine("usage: omux theme [list|<name>]")
                return 1
            }

            let selectedTheme: OmuxTheme?
            if let rawSelection = arguments.first {
                selectedTheme = resolveThemeSelection(rawSelection, themes: themes)
            } else {
                let exitCode = printDiagnosticsAndReturnCode(themeDiagnostics, printEmptyMessage: false)
                guard exitCode == 0 else {
                    return exitCode
                }
                printThemes(themes, currentThemeName: currentThemeName)
                writeLine("Select theme number or name:")
                guard let input = readInputLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
                      input.isEmpty == false else {
                    writeLine("omux error: no theme selected")
                    return 1
                }
                if ["q", "quit", "exit"].contains(input.lowercased()) {
                    writeLine("Cancelled.")
                    return 0
                }
                selectedTheme = resolveThemeSelection(input, themes: themes)
            }

            guard let selectedTheme else {
                let requested = arguments.first ?? ""
                let label = requested.isEmpty ? "selected theme" : requested
                writeLine("omux error: unknown theme '\(label)'")
                return 1
            }

            return try applyTheme(selectedTheme)
        } catch {
            writeLine("omux error: \(error)")
            return 1
        }
    }

    private func runConfigDoctor() throws -> Int32 {
        let response = try client.request(method: .configDoctor)
        guard response.error == nil else {
            writeLine("omux error: \(response.error!.message)")
            return 1
        }
        let diagnostics = response.result?.arrayValue?.compactMap(OmuxConfigDiagnostic.init(rpcValue:)) ?? []
        return printDiagnosticsAndReturnCode(diagnostics)
    }

    private func runConfigReload() throws -> Int32 {
        let response = try client.request(method: .configReload)
        guard response.error == nil else {
            writeLine("omux error: \(response.error!.message)")
            return 1
        }
        let object = response.result?.objectValue ?? [:]
        let diagnostics = object["diagnostics"]?.arrayValue?.compactMap(OmuxConfigDiagnostic.init(rpcValue:)) ?? []
        let exitCode = printDiagnosticsAndReturnCode(diagnostics)
        if let applied = object["applied"]?.boolValue {
            writeLine(applied ? "OpenMUX config reloaded." : "OpenMUX config unchanged.")
        }
        return exitCode
    }

    private func runInstallCLI(arguments: [String]) -> Int32 {
        guard arguments.count <= 1 else {
            writeLine("usage: omux install-cli [destination]")
            return 1
        }

        do {
            let result = try installer.install(destinationPath: arguments.first)
            writeLine("Installed omux at \(result.installedPath) -> \(result.sourcePath)")
            if let pathHintDirectory = result.pathHintDirectory {
                writeLine("Add this to your shell profile: export PATH=\"\(pathHintDirectory):$PATH\"")
            }
            return 0
        } catch {
            writeLine("omux error: \(error)")
            return 1
        }
    }

    private func applyTheme(_ theme: OmuxTheme) throws -> Int32 {
        let configResult = configLoader.load()
        guard configResult.hasErrors == false else {
            return printDiagnosticsAndReturnCode(configResult.diagnostics)
        }

        let current = configResult.config
        let configURL = current.sourceURL ?? OmuxConfigPaths.configFileURL
        let updated = OmuxConfig(
            schema: current.schema,
            theme: OmuxConfigTheme(name: theme.name),
            terminal: current.terminal,
            ghostty: current.ghostty,
            sourceURL: configURL
        )

        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try render(config: updated).write(to: configURL, atomically: true, encoding: .utf8)

        writeLine("Theme set to \(theme.displayName).")
        return try runConfigReload()
    }

    private func printThemes(_ themes: [OmuxTheme], currentThemeName: String?) {
        writeLine("Available themes:")
        for (index, theme) in themes.enumerated() {
            let marker = theme.name == currentThemeName ? "*" : " "
            writeLine("\(index + 1).\(marker) \(theme.name) — \(theme.displayName)")
        }
    }

    private func resolveThemeSelection(_ selection: String, themes: [OmuxTheme]) -> OmuxTheme? {
        if let index = Int(selection), themes.indices.contains(index - 1) {
            return themes[index - 1]
        }

        let normalizedSelection = selection.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return themes.first {
            $0.name.lowercased() == normalizedSelection || $0.displayName.lowercased() == normalizedSelection
        }
    }

    private func render(config: OmuxConfig) -> String {
        var lines: [String] = [
            "schema = \(config.schema)",
            "",
            "[theme]",
            "name = \(render(.string(config.theme.name)))",
            "",
            "[terminal]",
        ]

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

        lines.append("")
        lines.append("[ghostty]")
        for entry in config.ghostty {
            lines.append("\"\(escape(entry.key))\" = \(render(entry.value))")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private func render(_ value: OmuxTOMLValue) -> String {
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

    private func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    private func printDiagnosticsAndReturnCode(
        _ diagnostics: [OmuxConfigDiagnostic],
        printEmptyMessage: Bool = true
    ) -> Int32 {
        if diagnostics.isEmpty {
            guard printEmptyMessage else {
                return 0
            }
            writeLine("No diagnostics.")
            return 0
        }

        for diagnostic in diagnostics {
            let location: String
            if let filePath = diagnostic.filePath, let line = diagnostic.line {
                location = " \(filePath):\(line)"
            } else if let filePath = diagnostic.filePath {
                location = " \(filePath)"
            } else {
                location = ""
            }
            writeLine("[\(diagnostic.severity.rawValue)]\(location) \(diagnostic.message)")
        }

        return diagnostics.contains(where: { $0.severity.isError }) ? 1 : 0
    }
}

private extension RPCValue {
    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }

    var intValue: Int? {
        if case .number(let value) = self {
            return Int(exactly: value)
        }
        return nil
    }

    var objectValue: [String: RPCValue]? {
        if case .object(let value) = self {
            return value
        }
        return nil
    }

    var arrayValue: [RPCValue]? {
        if case .array(let value) = self {
            return value
        }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let value) = self {
            return value
        }
        return nil
    }
}

private extension OmuxConfigDiagnostic {
    init?(rpcValue: RPCValue) {
        guard case .object(let object) = rpcValue,
              let severityRawValue = object["severity"]?.stringValue,
              let severity = OmuxConfigDiagnosticSeverity(rawValue: severityRawValue),
              let message = object["message"]?.stringValue
        else {
            return nil
        }

        let filePath = object["filePath"]?.stringValue
        let line = object["line"]?.intValue
        self.init(severity: severity, message: message, filePath: filePath, line: line)
    }
}
