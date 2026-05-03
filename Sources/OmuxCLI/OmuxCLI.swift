import Foundation
import Darwin
import OmuxControlPlane
import OmuxConfig
import OmuxCore
import OmuxTheme

public struct OmuxCLICommand {
    private let client: OmuxControlClient
    private let writeLine: (String) -> Void
    private let readInputLine: () -> String?
    private let isInteractiveThemePickerAvailable: () -> Bool
    private let selectThemeInteractively: ([OmuxTheme], String?) throws -> OmuxTheme?
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
            installer: OmuxCLIInstaller(),
            isInteractiveThemePickerAvailable: TerminalThemePicker.isAvailable,
            selectThemeInteractively: { try TerminalThemePicker().selectTheme(themes: $0, currentThemeName: $1) }
        )
    }

    init(
        client: OmuxControlClient,
        writeLine: @escaping (String) -> Void,
        readInputLine: @escaping () -> String?,
        configLoader: OmuxConfigLoader,
        themeRegistry: OmuxThemeRegistry,
        installer: OmuxCLIInstaller,
        isInteractiveThemePickerAvailable: @escaping () -> Bool = TerminalThemePicker.isAvailable,
        selectThemeInteractively: @escaping ([OmuxTheme], String?) throws -> OmuxTheme? = {
            try TerminalThemePicker().selectTheme(themes: $0, currentThemeName: $1)
        }
    ) {
        self.client = client
        self.writeLine = writeLine
        self.readInputLine = readInputLine
        self.isInteractiveThemePickerAvailable = isInteractiveThemePickerAvailable
        self.selectThemeInteractively = selectThemeInteractively
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
                let params: RPCValue? = commandArguments.dropFirst().contains("--full")
                    ? .object(["full": .bool(true)])
                    : nil
                let response = try client.request(method: .listWorkspaces, params: params)
                writeLine(response.result?.prettyPrinted ?? "[]")
            case "session", "sessions":
                let response = try client.request(method: .listSessions)
                writeLine(response.result?.prettyPrinted ?? "[]")
            case "pane", "panes":
                let response = try client.request(method: .listPanes)
                writeLine(response.result?.prettyPrinted ?? "[]")
            case "events":
                try client.streamTerminalEvents { event in
                    writeLine(event.prettyPrinted)
                }
            case "history":
                return try runHistoryCommand(arguments: Array(commandArguments.dropFirst()))
            case "tab":
                let response = try client.request(method: .createTab)
                writeLine(response.result?.prettyPrinted ?? "")
            case "split":
                guard let splitRequest = parseSplitRequest(Array(commandArguments.dropFirst())) else {
                    writeLine("usage: omux split [--session <id>|--pane <id>|--tab <id>|--workspace <id>|--focused] [left|right|up|down]")
                    return 1
                }
                var params = targetParams(splitRequest.target)
                params["axis"] = .string(splitRequest.axis.rawValue)
                let response = try client.request(
                    method: .splitPane,
                    params: .object(params)
                )
                writeLine(response.result?.prettyPrinted ?? "")
            case "pane-tab":
                let response = try client.request(method: .createPaneTab)
                writeLine(response.result?.prettyPrinted ?? "")
            case "pane-tab-next":
                let response = try client.request(method: .focusNextPaneTab)
                writeLine(response.result?.prettyPrinted ?? "")
            case "pane-tab-prev":
                let response = try client.request(method: .focusPreviousPaneTab)
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
            case "pane-next":
                let response = try client.request(method: .focusNextPane)
                writeLine(response.result?.prettyPrinted ?? "")
            case "pane-prev":
                let response = try client.request(method: .focusPreviousPane)
                writeLine(response.result?.prettyPrinted ?? "")
            case "open":
                guard commandArguments.count <= 2 else {
                    writeLine("usage: omux open [path]")
                    return 1
                }

                let params: RPCValue?
                if commandArguments.count == 2 {
                    params = .object(["path": .string(resolveCLIPath(commandArguments[1]))])
                } else {
                    params = nil
                }
                let response = try client.request(
                    method: .openWorkspace,
                    params: params
                )
                writeLine(response.result?.prettyPrinted ?? "")
            case "focus":
                guard let target = parseFocusTarget(Array(commandArguments.dropFirst())) else {
                    writeLine("usage: omux focus <session-id>|--session <id>|--pane <id>|--tab <id>|--workspace <id>|--focused")
                    return 1
                }

                let response = try client.request(
                    method: .focusSession,
                    params: .object(["target": target.rpcValue])
                )
                writeLine(response.result?.prettyPrinted ?? "")
            case "run":
                guard let runRequest = parseRunRequest(Array(commandArguments.dropFirst())) else {
                    writeLine("usage: omux run <session-id> <command> | omux run --session <id>|--pane <id>|--tab <id>|--workspace <id>|--focused -- <command>")
                    return 1
                }

                let response = try client.request(
                    method: .runCommand,
                    params: .object([
                        "target": runRequest.target.rpcValue,
                        "command": .string(runRequest.command),
                    ])
                )
                writeLine(response.result?.prettyPrinted ?? "")
            case "send-text":
                let parsed = parseTargetPrefix(Array(commandArguments.dropFirst()))
                guard let target = parsed.target, parsed.remaining.isEmpty == false else {
                    writeLine("usage: omux send-text --session <id>|--pane <id>|--tab <id>|--workspace <id>|--focused -- <text>")
                    return 1
                }

                let response = try client.request(
                    method: .sendText,
                    params: .object([
                        "target": target.rpcValue,
                        "text": .string(parsed.remaining.joined(separator: " ")),
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
            writeLine(Self.errorMessage(for: error))
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
      omux list [--full]
      omux sessions
      omux panes
      omux events
      omux history [--json] [--max-lines <count>] [--max-bytes <count>] [<pane-id>|all]
      omux open [path]
      omux tab
      omux split [--session <id>|--pane <id>|--tab <id>|--workspace <id>|--focused] [left|right|up|down]
      omux pane-tab
      omux pane-tab-next
      omux pane-tab-prev
      omux pane-tab-focus <pane-id>
      omux pane-tab-close [pane-id]
      omux pane-next
      omux pane-prev
      omux focus <session-id>|--session <id>|--pane <id>|--tab <id>|--workspace <id>|--focused
      omux run <session-id> <command>
      omux run --session <id>|--pane <id>|--tab <id>|--workspace <id>|--focused -- <command>
      omux send-text --session <id>|--pane <id>|--tab <id>|--workspace <id>|--focused -- <text>
      omux notify <title> [body]
      omux restore <workspace-id>
      omux install-cli [destination]
    """

    private func resolveCLIPath(_ path: String) -> String {
        if let resolved = OmuxWorkspacePathResolver.resolve(path) {
            return resolved
        }

        return URL(
            fileURLWithPath: path,
            relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        )
        .standardizedFileURL
        .path
    }

    private func parseSplitRequest(_ arguments: [String]) -> (target: ControlPlaneTerminalTarget?, axis: PaneSplitAxis)? {
        var remaining = arguments
        let leading = parseTargetPrefix(remaining)
        var target = leading.target
        remaining = leading.remaining

        let axis: PaneSplitAxis
        if let direction = remaining.first {
            guard let parsedAxis = splitAxis(from: direction) else {
                return nil
            }
            axis = parsedAxis
            remaining.removeFirst()
        } else {
            axis = .columns
        }

        let trailing = parseTargetPrefix(remaining)
        if let trailingTarget = trailing.target {
            target = trailingTarget
        }
        guard trailing.remaining.isEmpty else {
            return nil
        }

        return (target, axis)
    }

    private func splitAxis(from direction: String) -> PaneSplitAxis? {
        switch direction.lowercased() {
        case "left", "right", "horizontal":
            return .columns
        case "up", "down", "vertical":
            return .rows
        default:
            return nil
        }
    }

    private func parseFocusTarget(_ arguments: [String]) -> ControlPlaneTerminalTarget? {
        let parsed = parseTargetPrefix(arguments)
        if let target = parsed.target, parsed.remaining.isEmpty {
            return target
        }

        guard arguments.count == 1 else {
            return nil
        }

        return .session(SessionID(rawValue: arguments[0]))
    }

    private func parseRunRequest(_ arguments: [String]) -> (target: ControlPlaneTerminalTarget, command: String)? {
        guard arguments.isEmpty == false else {
            return nil
        }

        if arguments[0].hasPrefix("--") {
            let parsed = parseTargetPrefix(arguments)
            guard let target = parsed.target, parsed.remaining.isEmpty == false else {
                return nil
            }
            return (target, parsed.remaining.joined(separator: " "))
        }

        guard arguments.count >= 2 else {
            return nil
        }

        return (
            .session(SessionID(rawValue: arguments[0])),
            arguments.dropFirst().joined(separator: " ")
        )
    }

    private func parseTargetPrefix(_ arguments: [String]) -> (target: ControlPlaneTerminalTarget?, remaining: [String]) {
        var index = 0
        var target: ControlPlaneTerminalTarget?

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--" {
                return (target, Array(arguments.dropFirst(index + 1)))
            }

            switch argument {
            case "--session":
                guard index + 1 < arguments.count else { return (target, Array(arguments.dropFirst(index))) }
                target = .session(SessionID(rawValue: arguments[index + 1]))
                index += 2
            case "--pane":
                guard index + 1 < arguments.count else { return (target, Array(arguments.dropFirst(index))) }
                target = .pane(PaneID(rawValue: arguments[index + 1]))
                index += 2
            case "--tab":
                guard index + 1 < arguments.count else { return (target, Array(arguments.dropFirst(index))) }
                target = .tab(TabID(rawValue: arguments[index + 1]))
                index += 2
            case "--workspace":
                guard index + 1 < arguments.count else { return (target, Array(arguments.dropFirst(index))) }
                target = .workspace(WorkspaceID(rawValue: arguments[index + 1]))
                index += 2
            case "--focused":
                target = .focused
                index += 1
            default:
                return (target, Array(arguments.dropFirst(index)))
            }
        }

        return (target, [])
    }

    private func targetParams(_ target: ControlPlaneTerminalTarget?) -> [String: RPCValue] {
        guard let target else {
            return [:]
        }

        return ["target": target.rpcValue]
    }

    private func runHistoryCommand(arguments: [String]) throws -> Int32 {
        guard let parsed = parseHistoryRequest(arguments) else {
            writeLine("usage: omux history [--json] [--max-lines <count>] [--max-bytes <count>] [<pane-id>|all]")
            return 1
        }

        let response = try client.request(
            method: .terminalHistory,
            params: parsed.request.rpcValue
        )
        if let error = response.error {
            writeLine("omux error: \(error.message)")
            return 1
        }

        guard let result = response.result else {
            writeLine(parsed.json ? "{}" : "No history.")
            return 0
        }

        if parsed.json {
            writeLine(result.prettyPrinted)
        } else {
            printHistory(result)
        }
        return 0
    }

    private func parseHistoryRequest(
        _ arguments: [String]
    ) -> (request: ControlPlaneHistoryRequest, json: Bool)? {
        var json = false
        var maxLines = PaneScrollbackSnapshot.defaultMaxLines
        var maxBytes = PaneScrollbackSnapshot.defaultMaxBytes
        var positional: [String] = []
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--json":
                json = true
                index += 1
            case "--max-lines":
                guard index + 1 < arguments.count, let value = Int(arguments[index + 1]), value >= 0 else {
                    return nil
                }
                maxLines = value
                index += 2
            case "--max-bytes":
                guard index + 1 < arguments.count, let value = Int(arguments[index + 1]), value >= 0 else {
                    return nil
                }
                maxBytes = value
                index += 2
            default:
                guard arguments[index].hasPrefix("--") == false else {
                    return nil
                }
                positional.append(arguments[index])
                index += 1
            }
        }

        guard positional.count <= 1 else {
            return nil
        }

        let scope: ControlPlaneHistoryScope
        if let target = positional.first {
            scope = target == "all" ? .all : .pane(PaneID(rawValue: target))
        } else {
            scope = .activeWorkspace
        }

        return (
            ControlPlaneHistoryRequest(scope: scope, maxBytes: maxBytes, maxLines: maxLines),
            json
        )
    }

    private func printHistory(_ result: RPCValue) {
        guard case .object(let object) = result,
              case .array(let items)? = object["items"]
        else {
            writeLine(result.prettyPrinted)
            return
        }

        guard items.isEmpty == false else {
            writeLine("No history.")
            return
        }

        for (index, item) in items.enumerated() {
            guard case .object(let history) = item else {
                continue
            }

            if index > 0 {
                writeLine("")
            }

            let workspaceName = history["workspaceName"]?.stringValue ?? "workspace"
            let workspaceID = history["workspaceID"]?.stringValue ?? "unknown"
            let tabTitle = history["tabTitle"]?.stringValue ?? "tab"
            let tabID = history["tabID"]?.stringValue ?? "unknown"
            let paneTitle = history["paneTitle"]?.stringValue ?? "pane"
            let paneID = history["paneID"]?.stringValue ?? "unknown"
            let sessionID = history["sessionID"]?.stringValue ?? "unknown"
            let cwd = history["workingDirectory"]?.nullableStringValue
            let lineCount = history["lineCount"]?.integerValue ?? 0
            let byteCount = history["byteCount"]?.integerValue ?? 0
            let truncated = history["truncated"]?.boolValue ?? false
            let unavailable = history["unavailable"]?.nullableStringValue
            let text = history["text"]?.stringValue ?? ""

            writeLine("== \(workspaceName) (\(workspaceID)) / \(tabTitle) (\(tabID)) / \(paneTitle) (\(paneID))")
            writeLine("session: \(sessionID)")
            if let cwd {
                writeLine("cwd: \(cwd)")
            }
            writeLine("lines: \(lineCount), bytes: \(byteCount), truncated: \(truncated)")
            if let unavailable {
                writeLine("unavailable: \(unavailable)")
            }
            writeLine("--")
            writeLine(text.isEmpty ? "(no history)" : text)
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

                if isInteractiveThemePickerAvailable() {
                    guard let theme = try selectThemeInteractively(themes, currentThemeName) else {
                        writeLine("Cancelled.")
                        return 0
                    }
                    selectedTheme = theme
                } else {
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
            workspace: current.workspace,
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
        lines.append("[workspace]")
        lines.append("default_root_path = \(render(.string(config.workspace.defaultRootPath)))")

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

    private static func errorMessage(for error: Error) -> String {
        if case UnixSocketError.connectFailed(let code) = error,
           code == ENOENT || code == ECONNREFUSED {
            return "omux error: OpenMUX is not reachable on the local control socket. Start or restart the current app build, for example with `make app`."
        }
        return "omux error: \(error)"
    }
}

struct ThemePickerViewport: Equatable {
    let startIndex: Int
    let endIndex: Int
    let visibleCount: Int

    static func make(itemCount: Int, selectedIndex: Int, terminalRows: Int) -> ThemePickerViewport {
        guard itemCount > 0 else {
            return ThemePickerViewport(startIndex: 0, endIndex: 0, visibleCount: 0)
        }

        let reservedRows = 2
        let visibleCount = min(itemCount, max(1, terminalRows - reservedRows))
        let clampedSelectedIndex = min(max(0, selectedIndex), itemCount - 1)
        let preferredStart = clampedSelectedIndex - (visibleCount / 2)
        let maxStart = max(0, itemCount - visibleCount)
        let startIndex = min(max(0, preferredStart), maxStart)

        return ThemePickerViewport(
            startIndex: startIndex,
            endIndex: startIndex + visibleCount,
            visibleCount: visibleCount
        )
    }
}

private struct TerminalThemePicker {
    enum PickerError: Error, LocalizedError {
        case terminalUnavailable
        case unableToReadTerminalAttributes
        case unableToEnterRawMode
        case unableToRestoreTerminalMode

        var errorDescription: String? {
            switch self {
            case .terminalUnavailable:
                return "interactive terminal is not available"
            case .unableToReadTerminalAttributes:
                return "unable to read terminal attributes"
            case .unableToEnterRawMode:
                return "unable to enter raw terminal mode"
            case .unableToRestoreTerminalMode:
                return "unable to restore terminal mode"
            }
        }
    }

    private enum Key {
        case up
        case down
        case enter
        case cancel
        case other
    }

    static func isAvailable() -> Bool {
        isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1
    }

    func selectTheme(themes: [OmuxTheme], currentThemeName: String?) throws -> OmuxTheme? {
        guard Self.isAvailable() else {
            throw PickerError.terminalUnavailable
        }
        guard themes.isEmpty == false else {
            return nil
        }

        var selectedIndex = themes.firstIndex(where: { $0.name == currentThemeName }) ?? 0
        var renderedLineCount = 0

        return try withRawTerminalMode {
            write("\u{1B}[?25l")
            defer {
                clearRenderedLines(renderedLineCount)
                write("\u{1B}[?25h")
            }

            render(
                themes: themes,
                selectedIndex: selectedIndex,
                currentThemeName: currentThemeName,
                previousLineCount: &renderedLineCount
            )

            while true {
                switch readKey() {
                case .up:
                    selectedIndex = selectedIndex == 0 ? themes.count - 1 : selectedIndex - 1
                    render(
                        themes: themes,
                        selectedIndex: selectedIndex,
                        currentThemeName: currentThemeName,
                        previousLineCount: &renderedLineCount
                    )
                case .down:
                    selectedIndex = selectedIndex == themes.count - 1 ? 0 : selectedIndex + 1
                    render(
                        themes: themes,
                        selectedIndex: selectedIndex,
                        currentThemeName: currentThemeName,
                        previousLineCount: &renderedLineCount
                    )
                case .enter:
                    return themes[selectedIndex]
                case .cancel:
                    return nil
                case .other:
                    continue
                }
            }
        }
    }

    private func withRawTerminalMode<Result>(_ body: () throws -> Result) throws -> Result {
        var original = termios()
        guard tcgetattr(STDIN_FILENO, &original) == 0 else {
            throw PickerError.unableToReadTerminalAttributes
        }

        var raw = original
        cfmakeraw(&raw)
        guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == 0 else {
            throw PickerError.unableToEnterRawMode
        }

        do {
            let result = try body()
            guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &original) == 0 else {
                throw PickerError.unableToRestoreTerminalMode
            }
            return result
        } catch {
            _ = tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
            throw error
        }
    }

    private func render(
        themes: [OmuxTheme],
        selectedIndex: Int,
        currentThemeName: String?,
        previousLineCount: inout Int
    ) {
        clearRenderedLines(previousLineCount)

        let viewport = ThemePickerViewport.make(
            itemCount: themes.count,
            selectedIndex: selectedIndex,
            terminalRows: terminalRowCount()
        )
        let selectedOrdinal = min(max(0, selectedIndex), themes.count - 1) + 1
        var lines = ["Available themes \(selectedOrdinal)/\(themes.count) (Up/Down, Enter, q):"]

        for index in viewport.startIndex..<viewport.endIndex {
            let theme = themes[index]
            let currentMarker = theme.name == currentThemeName ? "*" : " "
            let pointer = index == selectedIndex ? ">" : " "
            let line = "\(pointer)\(currentMarker) \(theme.name) — \(theme.displayName)"
            lines.append(index == selectedIndex ? "\u{1B}[7m\(line)\u{1B}[0m" : line)
        }

        if viewport.visibleCount < themes.count {
            lines.append("Showing \(viewport.startIndex + 1)-\(viewport.endIndex) of \(themes.count)")
        }

        write(lines.map { "\u{1B}[2K\r\($0)" }.joined(separator: "\n") + "\n")
        previousLineCount = lines.count
    }

    private func terminalRowCount() -> Int {
        var size = winsize()
        guard ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0, size.ws_row > 0 else {
            return 24
        }
        return Int(size.ws_row)
    }

    private func clearRenderedLines(_ lineCount: Int) {
        guard lineCount > 0 else {
            return
        }

        write("\u{1B}[\(lineCount)A")
        for index in 0..<lineCount {
            write("\u{1B}[2K\r")
            if index < lineCount - 1 {
                write("\u{1B}[1B")
            }
        }
        write("\u{1B}[\(lineCount - 1)A")
    }

    private func readKey() -> Key {
        guard let byte = readByte() else {
            return .cancel
        }

        switch byte {
        case 0x03:
            return .cancel
        case 0x0A, 0x0D:
            return .enter
        case 0x1B:
            guard let second = readByte(timeoutMicroseconds: 50_000) else {
                return .cancel
            }
            guard second == 0x5B, let third = readByte(timeoutMicroseconds: 50_000) else {
                return .cancel
            }
            if third == 0x41 {
                return .up
            }
            if third == 0x42 {
                return .down
            }
            return .other
        case 0x6A:
            return .down
        case 0x6B:
            return .up
        case 0x71, 0x51:
            return .cancel
        default:
            return .other
        }
    }

    private func readByte(timeoutMicroseconds: Int? = nil) -> UInt8? {
        if let timeoutMicroseconds {
            let flags = fcntl(STDIN_FILENO, F_GETFL, 0)
            guard flags >= 0 else {
                return nil
            }
            guard fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK) >= 0 else {
                return nil
            }
            defer {
                _ = fcntl(STDIN_FILENO, F_SETFL, flags)
            }

            let deadline = Date().addingTimeInterval(Double(timeoutMicroseconds) / 1_000_000)
            while Date() < deadline {
                var byte: UInt8 = 0
                let count = Darwin.read(STDIN_FILENO, &byte, 1)
                if count == 1 {
                    return byte
                }
                if errno != EAGAIN && errno != EWOULDBLOCK {
                    return nil
                }
                usleep(1_000)
            }
            return nil
        }

        var byte: UInt8 = 0
        let count = Darwin.read(STDIN_FILENO, &byte, 1)
        return count == 1 ? byte : nil
    }

    private func write(_ text: String) {
        FileHandle.standardOutput.write(Data(text.utf8))
    }
}

private extension RPCValue {
    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }

    var nullableStringValue: String? {
        if case .null = self {
            return nil
        }
        return stringValue
    }

    var intValue: Int? {
        if case .number(let value) = self {
            return Int(exactly: value)
        }
        return nil
    }

    var integerValue: Int? {
        if case .number(let value) = self, value.isFinite {
            return Int(value)
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
