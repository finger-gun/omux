import Foundation
import Darwin
import OmuxAIStatusPlugin
import OmuxControlPlane
import OmuxConfig
import OmuxCore
import OmuxVault
import OmuxMarkdownPreviewPlugin
import OmuxTheme

public struct OmuxCLICommand {
    private let client: OmuxControlClient
    private let writeLine: (String) -> Void
    private let readInputLine: () -> String?
    private let isInteractiveThemePickerAvailable: () -> Bool
    private let selectThemeInteractively: ([OmuxTheme], String?) throws -> OmuxTheme?
    private let isInteractivePluginPickerAvailable: () -> Bool
    private let selectPluginInteractively: ([PluginPickerItem]) throws -> PluginPickerItem?
    private let isInteractiveVaultResumeChoicePickerAvailable: () -> Bool
    private let selectVaultResumeChoiceInteractively: ([VaultResumeChoiceItem], VaultResumeMismatchContext) throws -> VaultResumeChoiceItem?
    private let configLoader: OmuxConfigLoader
    private let themeRegistry: OmuxThemeRegistry
    private let installer: OmuxCLIInstaller
    private let versionProvider: OpenMUXVersionProvider
    private let pluginRegistry: OmuxCLIPluginRegistry
    private let pluginRunner: OmuxCLIPluginRunner
    private let environment: () -> [String: String]
    private let gitRunner: (GitProcessCommand) throws -> GitProcessResult

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
            versionProvider: OpenMUXVersionProvider(),
            environment: { ProcessInfo.processInfo.environment },
            gitRunner: Self.runGitProcess,
            isInteractiveThemePickerAvailable: TerminalThemePicker.isAvailable,
            selectThemeInteractively: { try TerminalThemePicker().selectTheme(themes: $0, currentThemeName: $1) },
            isInteractivePluginPickerAvailable: TerminalPluginPicker.isAvailable,
            selectPluginInteractively: { try TerminalPluginPicker().selectPlugin(items: $0) },
            isInteractiveVaultResumeChoicePickerAvailable: TerminalVaultResumeChoicePicker.isAvailable,
            selectVaultResumeChoiceInteractively: { try TerminalVaultResumeChoicePicker().selectChoice(items: $0, context: $1) }
        )
    }

    init(
        client: OmuxControlClient,
        writeLine: @escaping (String) -> Void,
        readInputLine: @escaping () -> String?,
        configLoader: OmuxConfigLoader,
        themeRegistry: OmuxThemeRegistry,
        installer: OmuxCLIInstaller,
        versionProvider: OpenMUXVersionProvider = OpenMUXVersionProvider(),
        pluginRegistry: OmuxCLIPluginRegistry = OmuxCLIPluginRegistry(),
        pluginRunner: OmuxCLIPluginRunner = OmuxCLIPluginRunner(),
        environment: @escaping () -> [String: String] = { ProcessInfo.processInfo.environment },
        gitRunner: @escaping (GitProcessCommand) throws -> GitProcessResult = OmuxCLICommand.runGitProcess,
        isInteractiveThemePickerAvailable: @escaping () -> Bool = TerminalThemePicker.isAvailable,
        selectThemeInteractively: @escaping ([OmuxTheme], String?) throws -> OmuxTheme? = {
            try TerminalThemePicker().selectTheme(themes: $0, currentThemeName: $1)
        },
        isInteractivePluginPickerAvailable: @escaping () -> Bool = TerminalPluginPicker.isAvailable,
        selectPluginInteractively: @escaping ([PluginPickerItem]) throws -> PluginPickerItem? = {
            try TerminalPluginPicker().selectPlugin(items: $0)
        },
        isInteractiveVaultResumeChoicePickerAvailable: @escaping () -> Bool = TerminalVaultResumeChoicePicker.isAvailable,
        selectVaultResumeChoiceInteractively: @escaping ([VaultResumeChoiceItem], VaultResumeMismatchContext) throws -> VaultResumeChoiceItem? = {
            try TerminalVaultResumeChoicePicker().selectChoice(items: $0, context: $1)
        }
    ) {
        self.client = client
        self.writeLine = writeLine
        self.readInputLine = readInputLine
        self.isInteractiveThemePickerAvailable = isInteractiveThemePickerAvailable
        self.selectThemeInteractively = selectThemeInteractively
        self.isInteractivePluginPickerAvailable = isInteractivePluginPickerAvailable
        self.selectPluginInteractively = selectPluginInteractively
        self.isInteractiveVaultResumeChoicePickerAvailable = isInteractiveVaultResumeChoicePickerAvailable
        self.selectVaultResumeChoiceInteractively = selectVaultResumeChoiceInteractively
        self.configLoader = configLoader
        self.themeRegistry = themeRegistry
        self.installer = installer
        self.versionProvider = versionProvider
        self.pluginRegistry = pluginRegistry
        self.pluginRunner = pluginRunner
        self.environment = environment
        self.gitRunner = gitRunner
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
            case "__update-helper":
                guard commandArguments.count == 2 else {
                    writeLine("usage: omux __update-helper <manifest-path>")
                    return 1
                }
                return OmuxSelfUpdater(writeLine: writeLine, readInputLine: readInputLine)
                    .runHelper(manifestPath: commandArguments[1])
            case "__debug-update":
                return try runUpdateCommand(
                    arguments: Array(commandArguments.dropFirst()),
                    allowReinstallLatest: true
                )
            case "config":
                return runConfigCommand(arguments: Array(commandArguments.dropFirst()))
            case "theme":
                return runThemeCommand(arguments: Array(commandArguments.dropFirst()))
            case "hook", "hooks":
                return runHookRegistryCommand(arguments: Array(commandArguments.dropFirst()))
            case "plugin", "plugins":
                return runPluginCommand(arguments: Array(commandArguments.dropFirst()))
            case "agent-sessions", "agent-session", "agents", "as":
                return try runVaultCommand(arguments: Array(commandArguments.dropFirst()), commandName: "agent-sessions")
            case "version", "--version":
                writeLine(try versionProvider.currentVersion())
            case "update":
                return try runUpdateCommand(arguments: Array(commandArguments.dropFirst()))
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
            case "extension-pane":
                return try runExtensionPaneCommand(arguments: Array(commandArguments.dropFirst()))
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
            case "worktree":
                return try runWorktreeCommand(arguments: Array(commandArguments.dropFirst()))
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
            case "pane-remove":
                let arguments = Array(commandArguments.dropFirst())
                let params: RPCValue?
                if arguments.isEmpty {
                    params = nil
                } else {
                    let parsed = parseTargetPrefix(arguments)
                    guard let target = parsed.target, parsed.remaining.isEmpty else {
                        writeLine("usage: omux pane-remove [--session <id>|--pane <id>|--tab <id>|--workspace <id>|--focused]")
                        return 1
                    }
                    params = .object(["target": target.rpcValue])
                }

                let response = try client.request(method: .removePane, params: params)
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
            case "workspace-close":
                guard commandArguments.count <= 2 else {
                    writeLine("usage: omux workspace-close [workspace-id]")
                    return 1
                }

                let params: RPCValue?
                if commandArguments.count == 2 {
                    params = .object(["workspaceID": .string(commandArguments[1])])
                } else {
                    params = nil
                }
                let response = try client.request(method: .closeWorkspace, params: params)
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
            case "pane-status":
                guard let request = parsePaneStatusRequest(Array(commandArguments.dropFirst())) else {
                    writeLine("usage: omux pane-status --session <id>|--pane <id>|--tab <id>|--workspace <id>|--focused --state working|indeterminate|error|needs-input|idle|clear [--value <0-100>] [--label <text>] [--message <text>] [--source <name>]")
                    return 1
                }

                let response = try client.request(
                    method: .paneStatus,
                    params: request.rpcValue
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
                if let registration = pluginRegistry.registration(named: command) {
                    return try runRegisteredPlugin(registration, arguments: Array(commandArguments.dropFirst()))
                }
                writeLine(Self.usage)
                return 1
            }
        } catch {
            writeLine(Self.errorMessage(for: error))
            return 1
        }

        return 0
    }

    public static let usage = OpenMUXCLICommandCatalog.usage

    private func resolveCLIPath(_ path: String) -> String {
        resolveCLIPath(path, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true))
    }

    private func resolveCLIPath(_ path: String, relativeTo baseURL: URL) -> String {
        if let resolved = OmuxWorkspacePathResolver.resolve(path) {
            return resolved
        }

        return URL(
            fileURLWithPath: path,
            relativeTo: baseURL
        )
        .standardizedFileURL
        .path
    }

    private struct WorktreeCommandRequest {
        var branch: String
        var path: String?
        var fromRef: String?
        var paneStackID: String?
        var clear: Bool = false
    }

    private func runWorktreeCommand(arguments: [String]) throws -> Int32 {
        guard var request = parseWorktreeCommand(arguments) else {
            writeLine("usage: omux worktree <branch> [path] [--from <ref>] [--pane-stack <id>] [--clear]")
            return 1
        }

        if request.clear {
            // Clear screen and prompt interactively for branch name.
            FileHandle.standardOutput.write(Data("\u{1B}[2J\u{1B}[H".utf8))
            let defaultBranch = Self.generatedWorktreeBranchName()
            FileHandle.standardOutput.write(Data("Worktree branch name [\(defaultBranch)]: ".utf8))
            let input = readInputLine() ?? ""
            let branch = input.trimmingCharacters(in: .whitespacesAndNewlines)
            request.branch = branch.isEmpty ? defaultBranch : branch
        }

        let cwd = currentWorkingDirectoryURL()
        guard let repoRoot = try successfulGitOutput(["rev-parse", "--show-toplevel"], workingDirectory: cwd) else {
            return 1
        }
        guard repoRoot.isEmpty == false else {
            writeLine("omux git error: unable to resolve repository root")
            return 1
        }

        guard let gitCommonDirectory = try successfulGitOutput(["rev-parse", "--git-common-dir"], workingDirectory: cwd) else {
            return 1
        }
        guard gitCommonDirectory.isEmpty == false else {
            writeLine("omux git error: unable to resolve git common directory")
            return 1
        }

        let repoRootURL = URL(fileURLWithPath: repoRoot, isDirectory: true).standardizedFileURL
        let gitCommonDirectoryURL = URL(
            fileURLWithPath: gitCommonDirectory,
            relativeTo: cwd
        ).standardizedFileURL
        let worktreePath = request.path.map { resolveCLIPath($0, relativeTo: cwd) }
            ?? Self.defaultWorktreePath(
                branch: request.branch,
                gitCommonDirectory: gitCommonDirectoryURL,
                repoRoot: repoRootURL
            )

        var addArguments = ["worktree", "add", "-b", request.branch, worktreePath]
        if let fromRef = request.fromRef {
            addArguments.append(fromRef)
        }
        let addResult = try runGit(arguments: addArguments, workingDirectory: cwd)
        guard addResult.terminationStatus == 0 else {
            writeLine("omux git error: \(Self.gitFailureMessage(addResult))")
            return 1
        }

        if request.clear {
            // Stay in current tab: clear screen, then cd into the worktree.
            let focusedTarget = RPCValue.object(["type": .string("focused")])
            let cdResponse = try client.request(
                method: .runCommand,
                params: .object([
                    "target": focusedTarget,
                    "command": .string("cd \(worktreePath.shellEscaped)"),
                ])
            )
            if let error = cdResponse.error {
                writeLine("omux error: cd failed: \(error.message)")
                return 1
            }
            let clearResponse = try client.request(
                method: .runCommand,
                params: .object([
                    "target": focusedTarget,
                    "command": .string("clear"),
                ])
            )
            if let error = clearResponse.error {
                writeLine("omux error: clear failed: \(error.message)")
                return 1
            }
        } else {
            // Default: open a new pane tab in the worktree directory.
            var params: [String: RPCValue] = [
                "workingDirectory": .string(worktreePath),
                "title": .string(Self.worktreePaneTitle(branch: request.branch)),
            ]
            if let paneStackID = request.paneStackID {
                params["paneStackID"] = .string(paneStackID)
            }
            let response = try client.request(method: .createPaneTab, params: .object(params))
            if let error = response.error {
                writeLine("omux error: createPaneTab failed: \(error.message)")
                return 1
            }
            writeLine(response.result?.prettyPrinted ?? "")
        }
        return 0
    }

    private func parseWorktreeCommand(_ arguments: [String]) -> WorktreeCommandRequest? {
        var positional: [String] = []
        var fromRef: String?
        var paneStackID: String?
        var clear = false
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--from":
                guard index + 1 < arguments.count else { return nil }
                fromRef = arguments[index + 1]
                index += 2
            case "--pane-stack":
                guard index + 1 < arguments.count else { return nil }
                paneStackID = arguments[index + 1]
                index += 2
            case "--clear":
                clear = true
                index += 1
            default:
                guard arguments[index].hasPrefix("--") == false else { return nil }
                positional.append(arguments[index])
                index += 1
            }
        }

        if clear {
            let branch = positional.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return WorktreeCommandRequest(
                branch: branch,
                path: positional.count >= 2 ? positional[1] : nil,
                fromRef: fromRef?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                paneStackID: paneStackID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                clear: true
            )
        }

        guard (1...2).contains(positional.count) else { return nil }
        let branch = positional[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard branch.isEmpty == false else { return nil }
        return WorktreeCommandRequest(
            branch: branch,
            path: positional.count == 2 ? positional[1] : nil,
            fromRef: fromRef?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            paneStackID: paneStackID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            clear: false
        )
    }

    private func currentWorkingDirectoryURL() -> URL {
        let path = environment()["PWD"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(
            fileURLWithPath: path?.isEmpty == false ? path! : FileManager.default.currentDirectoryPath,
            isDirectory: true
        ).standardizedFileURL
    }

    private func successfulGitOutput(_ arguments: [String], workingDirectory: URL) throws -> String? {
        let result = try runGit(arguments: arguments, workingDirectory: workingDirectory)
        guard result.terminationStatus == 0 else {
            writeLine("omux git error: \(Self.gitFailureMessage(result))")
            return nil
        }
        return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runGit(arguments: [String], workingDirectory: URL) throws -> GitProcessResult {
        try gitRunner(GitProcessCommand(arguments: arguments, workingDirectory: workingDirectory))
    }

    private static func defaultWorktreePath(
        branch: String,
        gitCommonDirectory: URL,
        repoRoot: URL
    ) -> String {
        let commonParent = gitCommonDirectory.deletingLastPathComponent()
        let parent = gitCommonDirectory.lastPathComponent == ".git"
            ? commonParent.deletingLastPathComponent()
            : (commonParent.path.isEmpty ? repoRoot.deletingLastPathComponent() : commonParent)
        return parent
            .appendingPathComponent(
                "\(repoRoot.lastPathComponent)-\(sanitizedWorktreeDirectoryName(branch))",
                isDirectory: true
            )
            .standardizedFileURL
            .path
    }

    private static func sanitizedWorktreeDirectoryName(_ branch: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        var result = ""
        var previousWasSeparator = false
        for scalar in branch.unicodeScalars {
            if allowed.contains(scalar) {
                result.unicodeScalars.append(scalar)
                previousWasSeparator = false
            } else if previousWasSeparator == false {
                result.append("-")
                previousWasSeparator = true
            }
        }
        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-._"))
        return trimmed.isEmpty ? "worktree" : trimmed
    }

    private static func worktreePaneTitle(branch: String) -> String {
        let title = branch.split(separator: "/").last.map(String.init) ?? branch
        return title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? branch
    }

    private static func generatedWorktreeBranchName() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        let date = formatter.string(from: Date())
        let suffix = UUID().uuidString.prefix(8).lowercased()
        return "worktree/\(date)-\(suffix)"
    }

    private static func gitFailureMessage(_ result: GitProcessResult) -> String {
        let message = [result.standardError, result.standardOutput]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.isEmpty == false }
        return message ?? "git exited with status \(result.terminationStatus)"
    }

    private static func runGitProcess(_ command: GitProcessCommand) throws -> GitProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = command.arguments
        process.currentDirectoryURL = command.workingDirectory

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        return GitProcessResult(
            terminationStatus: process.terminationStatus,
            standardOutput: String(decoding: stdoutData, as: UTF8.self),
            standardError: String(decoding: stderrData, as: UTF8.self)
        )
    }

    private func runPluginCommand(arguments: [String]) -> Int32 {
        guard let subcommand = arguments.first else {
            return runPluginTogglePicker()
        }

        switch subcommand {
        case "discover", "install", "uninstall", "update":
            return runExtensionRegistryCommand(kind: .plugin, arguments: arguments)
        case "list":
            guard arguments.count == 1 else {
                writeLine("usage: omux plugin list")
                return 1
            }
            let plugins = pluginRegistry.plugins()
            guard plugins.isEmpty == false else {
                writeLine("No plugins installed.")
                return 0
            }
            for plugin in plugins {
                writeLine("\(plugin.commandName)\t\(plugin.displayPath)")
            }
            return 0
        case "path":
            guard arguments.count == 1 else {
                writeLine("usage: omux plugin path")
                return 1
            }
            writeLine(pluginRegistry.pluginsDirectoryURL.path)
            return 0
        default:
            writeLine("usage: omux plugins OR omux plugin list|path")
            return 1
        }
    }

    private func runVaultCommand(arguments: [String], commandName: String) throws -> Int32 {
        let usage = "usage: omux \(commandName) list|search|preview|resume|reindex|export|import|agents|open|close|toggle|palette"
        guard let subcommand = arguments.first else {
            let response = try client.request(
                method: .agentSessionsUI,
                params: .object(["action": .string("open")])
            )
            writeLine(response.result?.prettyPrinted ?? "")
            return response.error == nil ? 0 : 1
        }
        let rest = Array(arguments.dropFirst())
        switch subcommand {
        case "list":
            guard let params = parseVaultSearchOptions(rest, commandName: commandName, subcommand: "list", requiresQuery: false) else {
                return 1
            }
            let response = try client.request(method: .agentSessionsList, params: params.isEmpty ? nil : .object(params))
            writeLine(response.result?.prettyPrinted ?? "[]")
            return 0
        case "search":
            guard let params = parseVaultSearchOptions(rest, commandName: commandName, subcommand: "search", requiresQuery: true) else {
                return 1
            }
            let response = try client.request(
                method: .agentSessionsSearch,
                params: .object(params)
            )
            writeLine(response.result?.prettyPrinted ?? "[]")
            return 0
        case "preview":
            guard let id = rest.first else {
                writeLine("usage: omux \(commandName) preview <session-id>")
                return 1
            }
            let response = try client.request(method: .agentSessionsPreview, params: .object(["sessionID": .string(id)]))
            writeLine(response.result?.prettyPrinted ?? "")
            return 0
        case "resume":
            guard let id = rest.first else {
                writeLine("usage: omux \(commandName) resume <session-id> [--focused|--new-tab|--split|--workspace]")
                return 1
            }
            let destinationFlags = ["--focused", "--new-tab", "--split", "--workspace"].filter(rest.contains)
            guard destinationFlags.count <= 1 else {
                writeLine("error: agent session resume destination flags are mutually exclusive")
                writeLine("usage: omux \(commandName) resume <session-id> [--focused|--new-tab|--split|--workspace]")
                return 1
            }
            let destination: VaultResumeDestination
            if rest.contains("--new-tab") {
                destination = .newPaneTab
            } else if rest.contains("--split") {
                destination = .split
            } else if rest.contains("--workspace") {
                destination = .workspace
            } else {
                destination = .focused
            }
            let response = try client.request(
                method: .agentSessionsResume,
                params: .object(["sessionID": .string(id), "destination": .string(destination.rawValue)])
            )
            writeLine(response.result?.prettyPrinted ?? "")
            return 0
        case "resume-choice":
            return runVaultResumeChoiceCommand(arguments: rest)
        case "reindex":
            var params: [String: RPCValue] = [:]
            if let agentIndex = rest.firstIndex(of: "--agent") {
                guard rest.indices.contains(agentIndex + 1), rest[agentIndex + 1].hasPrefix("-") == false else {
                    writeLine("error: --agent requires an agent name")
                    writeLine("usage: omux \(commandName) reindex [--agent <agent>]")
                    return 1
                }
                params["agent"] = .string(rest[agentIndex + 1])
            }
            let response = try client.request(method: .agentSessionsReindex, params: params.isEmpty ? nil : .object(params))
            writeLine(response.result?.prettyPrinted ?? "")
            return 0
        case "export":
            guard let outputIndex = rest.firstIndex(of: "--output"),
                  rest.indices.contains(outputIndex + 1)
            else {
                writeLine("usage: omux \(commandName) export <session-id>... --output <path>")
                return 1
            }
            let ids = Array(rest[..<outputIndex])
            guard ids.isEmpty == false else {
                writeLine("usage: omux \(commandName) export <session-id>... --output <path>")
                return 1
            }
            let response = try client.request(
                method: .agentSessionsExport,
                params: .object(["ids": .array(ids.map(RPCValue.string))])
            )
            guard let encoded = response.result?.objectValue?["data"]?.stringValue,
                  let data = Data(base64Encoded: encoded)
            else {
                writeLine(response.result?.prettyPrinted ?? "")
                return 1
            }
            try data.write(to: URL(fileURLWithPath: resolveCLIPath(rest[outputIndex + 1])))
            return 0
        case "import":
            guard let path = rest.first else {
                writeLine("usage: omux \(commandName) import <path>")
                return 1
            }
            let data = try Data(contentsOf: URL(fileURLWithPath: resolveCLIPath(path)))
            let response = try client.request(
                method: .agentSessionsImport,
                params: .object(["data": .string(data.base64EncodedString())])
            )
            writeLine(response.result?.prettyPrinted ?? "")
            return 0
        case "agents":
            let response = try client.request(method: .agentSessionsAgents)
            writeLine(response.result?.prettyPrinted ?? "[]")
            return 0
        case "open", "show", "close", "hide", "toggle", "palette", "command-palette":
            let response = try client.request(
                method: .agentSessionsUI,
                params: .object(["action": .string(subcommand)])
            )
            writeLine(response.result?.prettyPrinted ?? "")
            return response.error == nil ? 0 : 1
        default:
            writeLine(usage)
            return 1
        }
    }

    private func parseVaultSearchOptions(
        _ arguments: [String],
        commandName: String,
        subcommand: String,
        requiresQuery: Bool
    ) -> [String: RPCValue]? {
        var params: [String: RPCValue] = [:]
        var queryParts: [String] = []
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--agent":
                guard arguments.indices.contains(index + 1), arguments[index + 1].hasPrefix("-") == false else {
                    writeLine("error: --agent requires an agent name")
                    writeLine("usage: omux \(commandName) \(subcommand) \(requiresQuery ? "<query> " : "")[--agent <agent>] [--limit <count>] [--offset <count>] [--cwd <path>]")
                    return nil
                }
                params["agent"] = .string(arguments[index + 1])
                index += 2
            case "--limit":
                guard arguments.indices.contains(index + 1), let limit = Int(arguments[index + 1]) else {
                    writeLine("error: --limit requires a number")
                    return nil
                }
                params["limit"] = .integer(limit)
                index += 2
            case "--offset":
                guard arguments.indices.contains(index + 1), let offset = Int(arguments[index + 1]) else {
                    writeLine("error: --offset requires a number")
                    return nil
                }
                params["offset"] = .integer(offset)
                index += 2
            case "--cwd", "--working-directory":
                guard arguments.indices.contains(index + 1), arguments[index + 1].hasPrefix("-") == false else {
                    writeLine("error: \(argument) requires a path")
                    return nil
                }
                params["workingDirectory"] = .string(resolveCLIPath(arguments[index + 1]))
                index += 2
            default:
                if argument.hasPrefix("-") {
                    writeLine("error: unknown option \(argument)")
                    return nil
                }
                queryParts.append(argument)
                index += 1
            }
        }
        if queryParts.isEmpty == false {
            params["query"] = .string(queryParts.joined(separator: " "))
        } else if requiresQuery {
            writeLine("usage: omux \(commandName) search <query> [--agent <agent>] [--limit <count>] [--offset <count>] [--cwd <path>]")
            return nil
        }
        return params
    }

    private func runVaultResumeChoiceCommand(arguments: [String]) -> Int32 {
        guard let request = VaultResumeChoiceRequest(arguments: arguments) else {
            writeLine("usage: omux agent-sessions resume-choice <session-id> --resume-command <command> --output <path> [--session-path <path>] [--current-path <path>...]")
            return 1
        }

        let items = VaultResumeChoiceItem.items(
            sessionID: request.sessionID,
            resumeCommand: request.resumeCommand,
            hasWorkspacePath: request.sessionPath != nil
        )
        let context = VaultResumeMismatchContext(sessionPath: request.sessionPath, currentPaths: request.currentPaths)

        let selected: VaultResumeChoiceItem?
        do {
            if isInteractiveVaultResumeChoicePickerAvailable() {
                selected = try selectVaultResumeChoiceInteractively(items, context)
            } else {
                selected = selectVaultResumeChoiceByLine(items: items, context: context)
            }
        } catch {
            writeLine("omux error: \(error.localizedDescription)")
            return 1
        }

        guard let selected, selected.keyword != "cancel" else {
            writeLine("Cancelled.")
            try? "".write(toFile: request.outputPath, atomically: true, encoding: .utf8)
            return 0
        }

        if request.execute {
            return runSelectedVaultResumeCommand(selected.shellCommand)
        }

        do {
            try selected.shellCommand.write(toFile: request.outputPath, atomically: true, encoding: .utf8)
        } catch {
            writeLine("omux error: failed to write selected command: \(error.localizedDescription)")
            return 1
        }
        writeLine("Selected: \(selected.title)")
        return 0
    }

    private func runSelectedVaultResumeCommand(_ command: String) -> Int32 {
        guard command.isEmpty == false else {
            return 0
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-lc", command]
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            writeLine("omux error: failed to run selected command: \(error.localizedDescription)")
            return 1
        }
    }

    private func selectVaultResumeChoiceByLine(
        items: [VaultResumeChoiceItem],
        context: VaultResumeMismatchContext
    ) -> VaultResumeChoiceItem? {
        writeLine("Agent session path differs.")
        writeLine("Session path: \(context.sessionPath ?? "unknown")")
        if context.currentPaths.isEmpty == false {
            writeLine("Current workspace paths: \(context.currentPaths.joined(separator: ", "))")
        }
        for (index, item) in items.enumerated() {
            writeLine("\(index + 1). \(item.title) — \(item.subtitle)")
        }
        writeLine("Select action number or name:")
        guard let input = readInputLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
              input.isEmpty == false else {
            return nil
        }
        if ["q", "quit", "exit", "cancel"].contains(input.lowercased()) {
            return nil
        }
        if let index = Int(input), items.indices.contains(index - 1) {
            return items[index - 1]
        }
        return items.first {
            $0.title.localizedCaseInsensitiveContains(input)
                || $0.keyword.localizedCaseInsensitiveCompare(input) == .orderedSame
        }
    }

    private func runHookRegistryCommand(arguments: [String]) -> Int32 {
        guard let subcommand = arguments.first else {
            writeLine("usage: omux hooks discover|install|uninstall|update")
            return 1
        }
        switch subcommand {
        case "discover", "install", "uninstall", "update":
            return runExtensionRegistryCommand(kind: .hook, arguments: arguments)
        default:
            writeLine("usage: omux hooks discover|install|uninstall|update")
            return 1
        }
    }

    private struct ExtensionRegistryCommandOptions {
        var packageID: String?
        var registryURLs: [String] = []
        var json = false
        var yes = false
    }

    private func runExtensionRegistryCommand(kind: OmuxExtensionPackageKind, arguments: [String]) -> Int32 {
        guard let subcommand = arguments.first else {
            writeLine(extensionRegistryUsage(kind: kind))
            return 1
        }

        do {
            let options = try parseExtensionRegistryOptions(Array(arguments.dropFirst()), requiresPackageID: subcommand != "discover")
            let installer = OmuxExtensionInstaller()
            switch subcommand {
            case "discover":
                let packages = try installer.discover(kind: kind, registryURLs: registryURLs(kind: kind, overrides: options.registryURLs))
                printExtensionPackages(packages, json: options.json)
                return 0
            case "install":
                guard let packageID = options.packageID else {
                    writeLine(extensionRegistryUsage(kind: kind))
                    return 1
                }
                let registryURLs = try registryURLs(kind: kind, overrides: options.registryURLs)
                let plan = try installer.planInstall(kind: kind, id: packageID, registryURLs: registryURLs)
                try confirmExtensionInstall(package: plan.package, manifest: plan.manifest, targets: plan.plannedTargets, yes: options.yes)
                let installed = try installer.install(kind: kind, id: packageID, registryURLs: registryURLs)
                writeLine("Installed \(kind.rawValue) \(installed.package.id) \(installed.manifest.version).")
                return 0
            case "uninstall":
                guard let packageID = options.packageID else {
                    writeLine(extensionRegistryUsage(kind: kind))
                    return 1
                }
                let receipt = try installer.uninstall(kind: kind, id: packageID)
                writeLine("Uninstalled \(kind.rawValue) \(receipt.id) \(receipt.version).")
                return 0
            case "update":
                guard let packageID = options.packageID else {
                    writeLine(extensionRegistryUsage(kind: kind))
                    return 1
                }
                let receipt = try installer.readReceipt(kind: kind, id: packageID)
                let plan = try installer.planInstall(kind: kind, id: packageID, registryURLs: [receipt.registry])
                try confirmExtensionInstall(package: plan.package, manifest: plan.manifest, targets: plan.plannedTargets, yes: options.yes)
                let updated = try installer.update(kind: kind, id: packageID)
                writeLine("Updated \(kind.rawValue) \(updated.package.id) to \(updated.manifest.version).")
                return 0
            default:
                writeLine(extensionRegistryUsage(kind: kind))
                return 1
            }
        } catch let error as OmuxExtensionRegistryError {
            writeLine("omux error: \(error.description)")
            return 1
        } catch {
            writeLine("omux error: \(error)")
            return 1
        }
    }

    private func parseExtensionRegistryOptions(_ arguments: [String], requiresPackageID: Bool) throws -> ExtensionRegistryCommandOptions {
        var options = ExtensionRegistryCommandOptions()
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--registry":
                guard index + 1 < arguments.count else {
                    throw OmuxExtensionRegistryError.invalidRegistryURL("")
                }
                options.registryURLs.append(arguments[index + 1])
                index += 2
            case "--json":
                options.json = true
                index += 1
            case "--yes", "-y":
                options.yes = true
                index += 1
            default:
                guard arguments[index].hasPrefix("--") == false, options.packageID == nil else {
                    throw OmuxExtensionRegistryError.invalidManifest("unsupported arguments")
                }
                options.packageID = arguments[index]
                index += 1
            }
        }
        if requiresPackageID, options.packageID == nil {
            throw OmuxExtensionRegistryError.packageNotFound("<id>")
        }
        return options
    }

    private func registryURLs(kind: OmuxExtensionPackageKind, overrides: [String]) throws -> [String] {
        if overrides.isEmpty == false {
            return overrides
        }
        let configResult = configLoader.load()
        guard configResult.hasErrors == false else {
            _ = printDiagnosticsAndReturnCode(configResult.diagnostics)
            throw OmuxExtensionRegistryError.invalidCatalog("configuration has errors")
        }
        switch kind {
        case .hook:
            return configResult.config.registries.hooks
        case .plugin:
            return configResult.config.registries.plugins
        }
    }

    private func printExtensionPackages(_ packages: [OmuxExtensionCatalogPackage], json: Bool) {
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(packages), let output = String(data: data, encoding: .utf8) {
                writeLine(output)
            }
            return
        }
        guard packages.isEmpty == false else {
            writeLine("No packages found.")
            return
        }
        for package in packages {
            writeLine("\(package.id)\t\(package.version)\t\(package.name)\t\(package.registry)")
        }
    }

    private func confirmExtensionInstall(
        package: OmuxExtensionCatalogPackage,
        manifest: OmuxExtensionPackageManifest,
        targets: [URL],
        yes: Bool
    ) throws {
        writeLine("Package: \(package.id) \(manifest.version)")
        writeLine("Source: \(package.registry)")
        writeLine("Targets:")
        for target in targets {
            writeLine("  \(target.path)")
        }
        if yes {
            return
        }
        writeLine("Install executable \(package.kind.rawValue) package? [y/N]")
        guard let input = readInputLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              ["y", "yes"].contains(input)
        else {
            throw OmuxExtensionRegistryError.confirmationRequired
        }
    }

    private func extensionRegistryUsage(kind: OmuxExtensionPackageKind) -> String {
        switch kind {
        case .hook:
            return "usage: omux hooks discover|install|uninstall|update"
        case .plugin:
            return "usage: omux plugins discover|install|uninstall|update OR omux plugin list|path"
        }
    }

    private func runPluginTogglePicker() -> Int32 {
        do {
            let configResult = configLoader.load()
            guard configResult.hasErrors == false else {
                return printDiagnosticsAndReturnCode(configResult.diagnostics)
            }

            let items = pluginPickerItems(config: configResult.config)
            guard items.isEmpty == false else {
                writeLine("No plugins installed.")
                return 0
            }

            let selectedItem: PluginPickerItem?
            if isInteractivePluginPickerAvailable() {
                guard let item = try selectPluginInteractively(items) else {
                    writeLine("Cancelled.")
                    return 0
                }
                selectedItem = item
            } else {
                printPluginPickerItems(items)
                writeLine("Select plugin number or name to toggle:")
                guard let input = readInputLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
                      input.isEmpty == false else {
                    writeLine("omux error: no plugin selected")
                    return 1
                }
                if ["q", "quit", "exit"].contains(input.lowercased()) {
                    writeLine("Cancelled.")
                    return 0
                }
                selectedItem = resolvePluginSelection(input, items: items)
            }

            guard let selectedItem else {
                writeLine("omux error: unknown plugin")
                return 1
            }
            guard selectedItem.canToggle else {
                writeLine("Plugin \(selectedItem.commandName) is registered externally and cannot be toggled from OpenMUX config.")
                return 1
            }

            return try togglePlugin(selectedItem, current: configResult.config)
        } catch {
            writeLine("omux error: \(error)")
            return 1
        }
    }

    private func pluginPickerItems(config: OmuxConfig) -> [PluginPickerItem] {
        pluginRegistry.plugins().map { plugin in
            switch plugin {
            case .bundled(let bundledPlugin):
                let isEnabled: Bool
                let canToggle: Bool
                switch bundledPlugin.commandName {
                case OmuxMarkdownPreviewPlugin.commandName:
                    isEnabled = config.plugins.markdownPreview.enabled
                    canToggle = true
                case OmuxAIStatusPlugin.commandName:
                    isEnabled = config.plugins.aiStatus.enabled
                    canToggle = true
                default:
                    isEnabled = true
                    canToggle = false
                }
                return PluginPickerItem(
                    commandName: bundledPlugin.commandName,
                    displayPath: bundledPlugin.displayPath,
                    isEnabled: isEnabled,
                    canToggle: canToggle
                )
            case .external(let externalPlugin):
                return PluginPickerItem(
                    commandName: externalPlugin.commandName,
                    displayPath: externalPlugin.executableURL.path,
                    isEnabled: true,
                    canToggle: false
                )
            }
        }
    }

    private func printPluginPickerItems(_ items: [PluginPickerItem]) {
        writeLine("Available plugins:")
        for (index, item) in items.enumerated() {
            writeLine("\(index + 1). \(item.statusLabel) \(item.commandName) — \(item.displayPath)")
        }
    }

    private func resolvePluginSelection(_ selection: String, items: [PluginPickerItem]) -> PluginPickerItem? {
        if let index = Int(selection), items.indices.contains(index - 1) {
            return items[index - 1]
        }

        let normalizedSelection = selection.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items.first { $0.commandName.lowercased() == normalizedSelection }
    }

    private func togglePlugin(_ item: PluginPickerItem, current: OmuxConfig) throws -> Int32 {
        let configURL = current.sourceURL ?? OmuxConfigPaths.configFileURL
        let plugins: OmuxConfigPlugins
        switch item.commandName {
        case OmuxMarkdownPreviewPlugin.commandName:
            let markdownPreview = current.plugins.markdownPreview
            plugins = OmuxConfigPlugins(
                markdownPreview: OmuxConfigPlugins.MarkdownPreview(
                    enabled: !markdownPreview.enabled,
                    renderer: markdownPreview.renderer,
                    theme: markdownPreview.theme,
                    presentation: markdownPreview.presentation
                ),
                aiStatus: current.plugins.aiStatus
            )
        case OmuxAIStatusPlugin.commandName:
            plugins = OmuxConfigPlugins(
                markdownPreview: current.plugins.markdownPreview,
                aiStatus: OmuxConfigPlugins.AIStatus(enabled: !current.plugins.aiStatus.enabled)
            )
        default:
            writeLine("Plugin \(item.commandName) cannot be toggled from OpenMUX config.")
            return 1
        }

        let updated = OmuxConfig(
            schema: current.schema,
            autoCheckUpdate: current.autoCheckUpdate,
            theme: current.theme,
            terminal: current.terminal,
            workspace: current.workspace,
            ui: current.ui,
            plugins: plugins,
            registries: current.registries,
            keyBindings: current.keyBindings,
            ghostty: current.ghostty,
            sourceURL: configURL
        )

        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try render(config: updated).write(to: configURL, atomically: true, encoding: .utf8)

        let state = item.isEnabled ? "disabled" : "enabled"
        writeLine("Plugin \(item.commandName) \(state).")
        return try runConfigReload()
    }

    private func runRegisteredPlugin(_ plugin: OmuxRegisteredCLIPlugin, arguments: [String]) throws -> Int32 {
        switch plugin {
        case .bundled(let bundledPlugin):
            switch bundledPlugin.commandName {
            case OmuxMarkdownPreviewPlugin.commandName:
                return try runMarkdownPreviewCommand(arguments: arguments)
            case OmuxAIStatusPlugin.commandName:
                return try runAIStatusCommand(arguments: arguments)
            default:
                writeLine("omux error: bundled plugin '\(bundledPlugin.commandName)' is not available")
                return 1
            }
        case .external(let externalPlugin):
            return try pluginRunner.run(
                plugin: externalPlugin,
                arguments: arguments,
                environment: environment()
            )
        }
    }

    private func runMarkdownPreviewCommand(arguments: [String]) throws -> Int32 {
        guard let request = parseMarkdownPreviewRequest(arguments) else {
            writeLine("usage: omux markdown-preview <file> [--watch] [--pane <id>] [--title <title>] [--axis columns|rows] [--modal|--pane-tab|--presentation pane-tab|modal]")
            return 1
        }

        let configResult = configLoader.load()
        guard configResult.hasErrors == false else {
            return printDiagnosticsAndReturnCode(configResult.diagnostics)
        }

        let pluginConfig = configResult.config.plugins.markdownPreview
        guard pluginConfig.enabled else {
            writeLine("Markdown preview plugin is disabled. Enable [plugins.markdown-preview] enabled = true in ~/.omux/config.toml.")
            return 1
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: request.fileURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue == false,
              FileManager.default.isReadableFile(atPath: request.fileURL.path)
        else {
            writeLine("omux markdown-preview error: readable Markdown file not found: \(request.fileURL.path)")
            return 1
        }

        let presentationStyle = request.presentationStyle
            ?? ExtensionPanePresentationStyle(rawValue: pluginConfig.presentation)
            ?? .paneTab

        return try OmuxMarkdownPreviewPlugin(
            renderer: OmuxMarkdownPreviewRenderer(theme: pluginConfig.theme)
        ).run(
            request: OmuxMarkdownPreviewRequest(
                fileURL: request.fileURL,
                paneID: request.paneID,
                title: request.title,
                watch: request.watch,
                axis: request.axis,
                presentationStyle: presentationStyle
            ),
            client: client,
            writeLine: writeLine
        )
    }

    private func runAIStatusCommand(arguments: [String]) throws -> Int32 {
        let configResult = configLoader.load()
        guard configResult.hasErrors == false else {
            return printDiagnosticsAndReturnCode(configResult.diagnostics)
        }

        guard configResult.config.plugins.aiStatus.enabled else {
            writeLine("AI status plugin is disabled. Enable [plugins.ai-status] enabled = true in ~/.omux/config.toml.")
            return 1
        }

        return try OmuxAIStatusPlugin(environment: environment()).run(
            arguments: arguments,
            client: client,
            writeLine: writeLine
        )
    }

    private func parseMarkdownPreviewRequest(_ arguments: [String]) -> OmuxMarkdownPreviewRequest? {
        var filePath: String?
        var paneID: String?
        var title: String?
        var watch = false
        var axis = PaneSplitAxis.columns
        var presentationStyle: ExtensionPanePresentationStyle?
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--watch":
                watch = true
                index += 1
            case "--pane":
                guard index + 1 < arguments.count else {
                    return nil
                }
                paneID = arguments[index + 1]
                index += 2
            case "--title":
                guard index + 1 < arguments.count else {
                    return nil
                }
                title = arguments[index + 1]
                index += 2
            case "--axis":
                guard index + 1 < arguments.count,
                      let parsedAxis = PaneSplitAxis(rawValue: arguments[index + 1])
                else {
                    return nil
                }
                axis = parsedAxis
                index += 2
            case "--presentation":
                guard index + 1 < arguments.count,
                      let parsedPresentation = ExtensionPanePresentationStyle(rawValue: arguments[index + 1])
                else {
                    return nil
                }
                presentationStyle = parsedPresentation
                index += 2
            case "--modal":
                presentationStyle = .modal
                index += 1
            case "--pane-tab":
                presentationStyle = .paneTab
                index += 1
            default:
                guard argument.hasPrefix("-") == false, filePath == nil else {
                    return nil
                }
                filePath = argument
                index += 1
            }
        }

        guard let filePath else {
            return nil
        }

        return OmuxMarkdownPreviewRequest(
            fileURL: URL(fileURLWithPath: resolveCLIPath(filePath)),
            paneID: paneID,
            title: title,
            watch: watch,
            axis: axis,
            presentationStyle: presentationStyle
        )
    }

    private func runExtensionPaneCommand(arguments: [String]) throws -> Int32 {
        guard let subcommand = arguments.first else {
            writeLine("usage: omux extension-pane create|update|close ...")
            return 1
        }

        switch subcommand {
        case "create":
            guard let request = parseExtensionPaneRequest(Array(arguments.dropFirst()), requiresPaneID: false) else {
                writeLine("usage: omux extension-pane create --plugin <id> [--title <title>] [--source <path>] [--html <html>|--html-file <path>] [--actions] [--axis columns|rows] [--presentation pane-tab|modal]")
                return 1
            }
            let response = try client.request(method: .createExtensionPane, params: .object(request))
            writeLine(response.result?.prettyPrinted ?? "")
            return 0
        case "update":
            guard let request = parseExtensionPaneRequest(Array(arguments.dropFirst()), requiresPaneID: true) else {
                writeLine("usage: omux extension-pane update --pane <id> --plugin <id> [--title <title>] [--source <path>] [--html <html>|--html-file <path>] [--status ready|disabled|error] [--message <text>] [--actions] [--presentation pane-tab|modal]")
                return 1
            }
            let response = try client.request(method: .updateExtensionPane, params: .object(request))
            writeLine(response.result?.prettyPrinted ?? "")
            return 0
        case "close":
            guard arguments.count == 3, arguments[1] == "--pane" else {
                writeLine("usage: omux extension-pane close --pane <id>")
                return 1
            }
            let response = try client.request(
                method: .closeExtensionPane,
                params: .object(["paneID": .string(arguments[2])])
            )
            writeLine(response.result?.prettyPrinted ?? "")
            return 0
        default:
            writeLine("usage: omux extension-pane create|update|close ...")
            return 1
        }
    }

    private func parseExtensionPaneRequest(
        _ arguments: [String],
        requiresPaneID: Bool
    ) -> [String: RPCValue]? {
        var params: [String: RPCValue] = [:]
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            if option == "--actions" {
                params["actionsEnabled"] = .bool(true)
                index += 1
                continue
            }
            guard index + 1 < arguments.count else {
                return nil
            }
            let value = arguments[index + 1]
            switch option {
            case "--pane":
                params["paneID"] = .string(value)
            case "--plugin":
                params["pluginID"] = .string(value)
            case "--title":
                params["title"] = .string(value)
            case "--source":
                params["source"] = .string(resolveCLIPath(value))
            case "--html":
                params["html"] = .string(value)
            case "--html-file":
                guard let html = try? String(contentsOfFile: resolveCLIPath(value), encoding: .utf8) else {
                    return nil
                }
                params["html"] = .string(html)
            case "--status":
                guard ExtensionPaneStatus(rawValue: value) != nil else {
                    return nil
                }
                params["status"] = .string(value)
            case "--message":
                params["message"] = .string(value)
            case "--content-kind":
                guard ExtensionPaneContentKind(rawValue: value) != nil else {
                    return nil
                }
                params["contentKind"] = .string(value)
            case "--axis":
                guard PaneSplitAxis(rawValue: value) != nil else {
                    return nil
                }
                params["axis"] = .string(value)
            case "--presentation":
                guard ExtensionPanePresentationStyle(rawValue: value) != nil else {
                    return nil
                }
                params["presentation"] = .string(value)
            default:
                return nil
            }
            index += 2
        }

        guard params["pluginID"] != nil else {
            return nil
        }
        if requiresPaneID, params["paneID"] == nil {
            return nil
        }
        return params
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

    private func parsePaneStatusRequest(_ arguments: [String]) -> ControlPlanePaneStatusRequest? {
        var index = 0
        var target: ControlPlaneTerminalTarget?
        var state: ControlPlanePaneStatusState?
        var value: Int?
        var label: String?
        var message: String?
        var source: String?

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--session":
                guard index + 1 < arguments.count else { return nil }
                target = .session(SessionID(rawValue: arguments[index + 1]))
                index += 2
            case "--pane", "--pane-tab":
                guard index + 1 < arguments.count else { return nil }
                target = .pane(PaneID(rawValue: arguments[index + 1]))
                index += 2
            case "--tab":
                guard index + 1 < arguments.count else { return nil }
                target = .tab(TabID(rawValue: arguments[index + 1]))
                index += 2
            case "--workspace":
                guard index + 1 < arguments.count else { return nil }
                target = .workspace(WorkspaceID(rawValue: arguments[index + 1]))
                index += 2
            case "--focused":
                target = .focused
                index += 1
            case "--state":
                guard index + 1 < arguments.count,
                      let parsedState = ControlPlanePaneStatusState(cliValue: arguments[index + 1])
                else {
                    return nil
                }
                state = parsedState
                index += 2
            case "--value", "--progress":
                guard index + 1 < arguments.count,
                      let parsedValue = Int(arguments[index + 1])
                else {
                    return nil
                }
                value = min(max(parsedValue, 0), 100)
                index += 2
            case "--label":
                guard index + 1 < arguments.count else { return nil }
                label = arguments[index + 1]
                index += 2
            case "--message":
                guard index + 1 < arguments.count else { return nil }
                message = arguments[index + 1]
                index += 2
            case "--source":
                guard index + 1 < arguments.count else { return nil }
                source = arguments[index + 1]
                index += 2
            default:
                guard state == nil,
                      let parsedState = ControlPlanePaneStatusState(cliValue: argument)
                else {
                    return nil
                }
                state = parsedState
                index += 1
            }
        }

        guard let target, let state else {
            return nil
        }

        return ControlPlanePaneStatusRequest(
            target: target,
            state: state,
            value: value,
            label: label,
            message: message,
            source: source
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
            case "--pane", "--pane-tab":
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
        if arguments.first == "clear" {
            return try runHistoryClearCommand(arguments: Array(arguments.dropFirst()))
        }

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

    private func runHistoryClearCommand(arguments: [String]) throws -> Int32 {
        guard let parsed = parseHistoryClearRequest(arguments) else {
            writeLine("usage: omux history clear [--json] [--all|--session <id>|--pane <id>|--pane-tab <id>|--tab <id>|--workspace <id>|--focused]")
            return 1
        }

        let response = try client.request(
            method: .clearTerminalHistory,
            params: parsed.request.rpcValue
        )
        if let error = response.error {
            writeLine("omux error: \(error.message)")
            return 1
        }

        guard let result = response.result else {
            writeLine(parsed.json ? "{}" : activePaneTerminalClearPrefix(for: parsed.request) + "Cleared history for 0 panes.")
            return 0
        }

        if parsed.json {
            writeLine(result.prettyPrinted)
        } else {
            let count = result.objectValue?["clearedCount"]?.integerValue ?? 0
            let message = "Cleared history for \(count) \(count == 1 ? "pane" : "panes")."
            writeLine(activePaneTerminalClearPrefix(for: parsed.request) + message)
        }
        return 0
    }

    private func activePaneTerminalClearPrefix(for request: ControlPlaneHistoryClearRequest) -> String {
        let currentEnvironment = environment()
        guard let paneID = currentEnvironment["OMUX_PANE_ID"], paneID.isEmpty == false else {
            return ""
        }
        guard historyClearTargetsCurrentPane(request, environment: currentEnvironment) else {
            return ""
        }
        return "\u{001B}[H\u{001B}[2J\u{001B}[3J"
    }

    private func historyClearTargetsCurrentPane(
        _ request: ControlPlaneHistoryClearRequest,
        environment: [String: String]
    ) -> Bool {
        guard let target = request.target else {
            return true
        }

        switch target {
        case .focused:
            return true
        case .pane(let id):
            return environment["OMUX_PANE_ID"] == id.rawValue
        case .session(let id):
            return environment["OMUX_SESSION_ID"] == id.rawValue
        case .tab, .workspace:
            return false
        }
    }

    private func parseHistoryClearRequest(
        _ arguments: [String]
    ) -> (request: ControlPlaneHistoryClearRequest, json: Bool)? {
        var json = false
        var targetArguments: [String] = []
        var all = false
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--json":
                json = true
                index += 1
            case "--all":
                all = true
                index += 1
            default:
                targetArguments.append(arguments[index])
                index += 1
            }
        }

        guard all == false || targetArguments.isEmpty else {
            return nil
        }

        if all || targetArguments.isEmpty {
            return (ControlPlaneHistoryClearRequest(), json)
        }

        let parsed = parseTargetPrefix(targetArguments)
        guard let target = parsed.target, parsed.remaining.isEmpty else {
            return nil
        }

        return (ControlPlaneHistoryClearRequest(target: target), json)
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
            writeLine("usage: omux config <doctor|reload|get|apply|init|open|inactive-opacity>")
            return 1
        }

        do {
            switch subcommand {
            case "doctor":
                return try runConfigDoctor()
            case "reload":
                return try runConfigReload()
            case "get":
                return try runConfigGet(arguments: Array(arguments.dropFirst()))
            case "apply":
                return try runConfigApply(arguments: Array(arguments.dropFirst()))
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
            case "open":
                return try runConfigOpen()
            case "inactive-opacity":
                return try runConfigInactiveOpacity(arguments: Array(arguments.dropFirst()))
            default:
                writeLine("usage: omux config <doctor|reload|get|apply|init|open|inactive-opacity>")
                return 1
            }
        } catch {
            writeLine("omux error: \(error)")
            return 1
        }
    }

    private func runConfigOpen() throws -> Int32 {
        let configURL = OmuxConfigPaths.configFileURL
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            writeLine("omux error: config file not found at \(configURL.path). Run 'omux config init' to create one.")
            return 1
        }

        let env = environment()
        let process = Process()

        if let editor = env["VISUAL"] ?? env["EDITOR"], !editor.isEmpty {
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", "\(editor) \(configURL.path.shellEscaped)"]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-t", configURL.path]
        }

        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func runConfigGet(arguments: [String]) throws -> Int32 {
        guard arguments == ["--json"] else {
            writeLine("usage: omux config get --json")
            return 1
        }

        let export = OmuxConfigExporter(loader: configLoader).export()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(export)
        writeLine(String(decoding: data, as: UTF8.self))
        return export.diagnostics.contains(where: { $0.severity.isError }) ? 1 : 0
    }

    private func runConfigApply(arguments: [String]) throws -> Int32 {
        guard arguments.count == 2, arguments[0] == "--json-file" else {
            writeLine("usage: omux config apply --json-file <path>")
            return 1
        }

        let result = try OmuxConfigEditor(loader: configLoader).apply(jsonFileURL: URL(fileURLWithPath: resolveCLIPath(arguments[1])))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(result)
        writeLine(String(decoding: data, as: UTF8.self))
        guard result.diagnostics.contains(where: { $0.severity.isError }) == false else {
            return 1
        }
        return try runConfigReload()
    }

    private func runConfigInactiveOpacity(arguments: [String]) throws -> Int32 {
        guard arguments.count == 1,
              let opacity = Double(arguments[0]),
              (0.0...1.0).contains(opacity)
        else {
            writeLine("usage: omux config inactive-opacity <0.0-1.0>")
            return 1
        }

        let configResult = configLoader.load()
        guard configResult.hasErrors == false else {
            return printDiagnosticsAndReturnCode(configResult.diagnostics)
        }

        let current = configResult.config
        let configURL = current.sourceURL ?? OmuxConfigPaths.configFileURL
        let updated = OmuxConfig(
            schema: current.schema,
            autoCheckUpdate: current.autoCheckUpdate,
            theme: current.theme,
            terminal: current.terminal,
            workspace: current.workspace,
            ui: OmuxConfigUI(
                panes: OmuxConfigUI.Panes(
                    inactiveOpacity: opacity,
                    idleStatusClear: current.ui.panes.idleStatusClear
                ),
                icons: current.ui.icons
            ),
            plugins: current.plugins,
            registries: current.registries,
            keyBindings: current.keyBindings,
            ghostty: current.ghostty,
            sourceURL: configURL
        )

        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try OmuxConfigRenderer.render(config: updated).write(to: configURL, atomically: true, encoding: .utf8)

        writeLine("Inactive pane opacity set to \(renderOpacity(opacity)).")
        return try runConfigReload()
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

    private func runUpdateCommand(arguments: [String], allowReinstallLatest: Bool = false) throws -> Int32 {
        guard arguments.isEmpty else {
            writeLine(allowReinstallLatest ? "usage: omux __debug-update" : "usage: omux update")
            return 1
        }

        let progressRenderer = OmuxTerminalProgressRenderer(writeLine: writeLine)
        _ = try OmuxSelfUpdater(
            versionProvider: versionProvider,
            writeProgress: progressRenderer.render,
            finishProgress: progressRenderer.finish,
            writeLine: writeLine,
            readInputLine: readInputLine
        ).runUpdate(allowReinstallLatest: allowReinstallLatest)
        return 0
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
            autoCheckUpdate: current.autoCheckUpdate,
            theme: OmuxConfigTheme(name: theme.name),
            terminal: current.terminal,
            workspace: current.workspace,
            ui: current.ui,
            plugins: current.plugins,
            registries: current.registries,
            keyBindings: current.keyBindings,
            ghostty: current.ghostty,
            sourceURL: configURL
        )

        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try OmuxConfigRenderer.render(config: updated).write(to: configURL, atomically: true, encoding: .utf8)

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
        OmuxConfigRenderer.render(config: config)
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

    private func renderOpacity(_ value: Double) -> String {
        let rounded = (value * 1_000).rounded() / 1_000
        if rounded.rounded() == rounded {
            return String(format: "%.1f", rounded)
        }
        return String(format: "%.3f", rounded)
            .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
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

struct GitProcessCommand: Equatable {
    let arguments: [String]
    let workingDirectory: URL
}

struct GitProcessResult: Equatable {
    let terminationStatus: Int32
    let standardOutput: String
    let standardError: String
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

struct ThemePickerViewport: Equatable {
    let startIndex: Int
    let endIndex: Int
    let visibleCount: Int

    static func make(
        itemCount: Int,
        selectedIndex: Int,
        terminalRows: Int,
        reservedRows: Int = 2
    ) -> ThemePickerViewport {
        guard itemCount > 0 else {
            return ThemePickerViewport(startIndex: 0, endIndex: 0, visibleCount: 0)
        }

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

private final class OmuxTerminalProgressRenderer {
    private let isTerminal = isatty(STDOUT_FILENO) == 1
    private let writeLine: (String) -> Void
    private var renderedWidth = 0

    init(writeLine: @escaping (String) -> Void) {
        self.writeLine = writeLine
    }

    func render(_ line: String) {
        guard isTerminal else {
            writeLine(line)
            return
        }

        let paddingWidth = max(renderedWidth - line.count, 0)
        renderedWidth = line.count
        print("\r\(line)\(String(repeating: " ", count: paddingWidth))", terminator: "")
        fflush(stdout)
    }

    func finish() {
        guard isTerminal else {
            return
        }
        print("")
    }
}

struct ThemePickerSearch {
    static func filteredThemes(_ themes: [OmuxTheme], query: String) -> [OmuxTheme] {
        let terms = query
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard terms.isEmpty == false else {
            return themes
        }

        return themes.filter { theme in
            terms.allSatisfy { term in
                matches(term: term, in: theme.name.lowercased())
                    || matches(term: term, in: theme.displayName.lowercased())
            }
        }
    }

    private static func matches(term: String, in candidate: String) -> Bool {
        TerminalInteractivePickerSearchMatcher.matches(term: term, in: candidate)
    }
}

struct VaultResumeMismatchContext: Equatable {
    let sessionPath: String?
    let currentPaths: [String]
}

struct VaultResumeChoiceItem: Equatable {
    let keyword: String
    let title: String
    let subtitle: String
    let shellCommand: String

    static func items(sessionID: String, resumeCommand: String, hasWorkspacePath: Bool) -> [VaultResumeChoiceItem] {
        var result = [
            VaultResumeChoiceItem(
                keyword: "resume",
                title: "Resume Here",
                subtitle: "Run this agent session in the current terminal",
                shellCommand: resumeCommand
            ),
        ]
        if hasWorkspacePath {
            result.append(
                VaultResumeChoiceItem(
                    keyword: "workspace",
                    title: "Open Matching Workspace",
                    subtitle: "Open the session path as a workspace and resume there",
                    shellCommand: "\(currentExecutableCommand()) agent-sessions resume \(sessionID.shellEscaped) --workspace"
                )
            )
        }
        result.append(
            VaultResumeChoiceItem(
                keyword: "cancel",
                title: "Cancel",
                subtitle: "Leave the current terminal unchanged",
                shellCommand: ""
            )
        )
        return result
    }

    private static func currentExecutableCommand() -> String {
        let executable = CommandLine.arguments.first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let executable, executable.isEmpty == false else {
            return "omux"
        }
        return executable.shellEscaped
    }
}

private struct VaultResumeChoiceRequest {
    let sessionID: String
    let resumeCommand: String
    let outputPath: String
    let sessionPath: String?
    let currentPaths: [String]
    let execute: Bool

    init?(arguments: [String]) {
        guard let sessionID = arguments.first else {
            return nil
        }
        var resumeCommand: String?
        var outputPath: String?
        var sessionPath: String?
        var currentPaths: [String] = []
        var execute = false
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--execute" {
                execute = true
                index += 1
                continue
            }
            guard index + 1 < arguments.count else {
                return nil
            }
            let value = arguments[index + 1]
            switch argument {
            case "--resume-command":
                resumeCommand = value
            case "--output":
                outputPath = value
            case "--session-path":
                sessionPath = value
            case "--current-path":
                currentPaths.append(value)
            default:
                return nil
            }
            index += 2
        }
        guard let resumeCommand, execute || outputPath != nil else {
            return nil
        }
        self.sessionID = sessionID
        self.resumeCommand = resumeCommand
        self.outputPath = outputPath ?? ""
        self.sessionPath = sessionPath
        self.currentPaths = currentPaths
        self.execute = execute
    }
}

// Kept separate from TerminalInteractivePickerEngine because this picker has
// fixed actions, no search filtering, and mismatch-specific context framing.
private struct TerminalVaultResumeChoicePicker {
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

    func selectChoice(items: [VaultResumeChoiceItem], context: VaultResumeMismatchContext) throws -> VaultResumeChoiceItem? {
        guard Self.isAvailable() else {
            throw PickerError.terminalUnavailable
        }
        guard items.isEmpty == false else {
            return nil
        }

        var selectedIndex = 0
        var renderedLineCount = 0
        return try withRawTerminalMode {
            write("\u{1B}[?25l")
            defer {
                clearRenderedLines(renderedLineCount)
                write("\u{1B}[?25h")
            }

            render(items: items, context: context, selectedIndex: selectedIndex, previousLineCount: &renderedLineCount)
            while true {
                switch readKey() {
                case .up:
                    selectedIndex = selectedIndex == 0 ? items.count - 1 : selectedIndex - 1
                    render(items: items, context: context, selectedIndex: selectedIndex, previousLineCount: &renderedLineCount)
                case .down:
                    selectedIndex = selectedIndex == items.count - 1 ? 0 : selectedIndex + 1
                    render(items: items, context: context, selectedIndex: selectedIndex, previousLineCount: &renderedLineCount)
                case .enter:
                    let item = items[selectedIndex]
                    return item.keyword == "cancel" ? nil : item
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
        items: [VaultResumeChoiceItem],
        context: VaultResumeMismatchContext,
        selectedIndex: Int,
        previousLineCount: inout Int
    ) {
        clearRenderedLines(previousLineCount)
        var lines = [
            "Agent session path differs (Up/Down, Enter, Esc):",
            "Session path: \(context.sessionPath ?? "unknown")",
        ]
        if context.currentPaths.isEmpty == false {
            lines.append("Current workspace paths: \(context.currentPaths.joined(separator: ", "))")
        }
        for (index, item) in items.enumerated() {
            let pointer = index == selectedIndex ? ">" : " "
            let line = "\(pointer) \(item.title) — \(item.subtitle)"
            lines.append(index == selectedIndex ? "\u{1B}[7m\(line)\u{1B}[0m" : line)
        }
        write(lines.map { "\u{1B}[2K\r\($0)" }.joined(separator: "\n") + "\n")
        previousLineCount = lines.count
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
        case 0x6A:
            return .down
        case 0x6B:
            return .up
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

private struct TerminalThemePicker {
    static func isAvailable() -> Bool {
        TerminalInteractivePickerEngine<OmuxTheme>.isAvailable()
    }

    func selectTheme(themes: [OmuxTheme], currentThemeName: String?) throws -> OmuxTheme? {
        guard themes.isEmpty == false else {
            return nil
        }

        let engine = TerminalInteractivePickerEngine<OmuxTheme>(
            allItems: themes,
            initialSelectedIndex: themes.firstIndex(where: { $0.name == currentThemeName }) ?? 0,
            filterItems: ThemePickerSearch.filteredThemes,
            renderLines: { state in
                let selectedOrdinal = state.items.isEmpty ? 0 : min(max(0, state.selectedIndex), state.items.count - 1) + 1
                let searchHint = state.searchQuery.isEmpty
            ? "type to search, Up/Down, Enter, Esc"
            : "type to search, Backspace, Enter, Esc"
                let countLabel = state.items.count == state.totalItemCount
                    ? "\(selectedOrdinal)/\(state.items.count)"
                    : "\(selectedOrdinal)/\(state.items.count) of \(state.totalItemCount)"
                var lines = ["Available themes \(countLabel) (\(searchHint)):"]
                lines.append("Search: \(state.searchQuery)")

                if state.items.isEmpty {
                    lines.append("  No matching themes")
                } else {
                    for index in state.viewport.startIndex..<state.viewport.endIndex {
                        let theme = state.items[index]
                        let currentMarker = theme.name == currentThemeName ? "*" : " "
                        let pointer = index == state.selectedIndex ? ">" : " "
                        let line = "\(pointer)\(currentMarker) \(theme.name) — \(theme.displayName)"
                        lines.append(index == state.selectedIndex ? "\u{1B}[7m\(line)\u{1B}[0m" : line)
                    }
                }

                if state.viewport.visibleCount < state.items.count {
                    lines.append("Showing \(state.viewport.startIndex + 1)-\(state.viewport.endIndex) of \(state.items.count)")
                }

                return lines
            }
        )
        return try engine.select()
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

struct PluginPickerItem: Equatable {
    let commandName: String
    let displayPath: String
    let isEnabled: Bool
    let canToggle: Bool

    var statusLabel: String {
        if canToggle {
            return isEnabled ? "[enabled]" : "[disabled]"
        }
        return "[external]"
    }
}

struct PluginPickerSearch {
    static func filteredItems(_ items: [PluginPickerItem], query: String) -> [PluginPickerItem] {
        let terms = query
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard terms.isEmpty == false else {
            return items
        }

        return items.filter { item in
            terms.allSatisfy { term in
                matches(term: term, in: item.commandName.lowercased())
                    || matches(term: term, in: item.displayPath.lowercased())
                    || matches(term: term, in: item.statusLabel.lowercased())
            }
        }
    }

    private static func matches(term: String, in candidate: String) -> Bool {
        TerminalInteractivePickerSearchMatcher.matches(term: term, in: candidate)
    }
}

private struct TerminalPluginPicker {
    static func isAvailable() -> Bool {
        TerminalInteractivePickerEngine<PluginPickerItem>.isAvailable()
    }

    func selectPlugin(items: [PluginPickerItem]) throws -> PluginPickerItem? {
        guard items.isEmpty == false else {
            return nil
        }

        let engine = TerminalInteractivePickerEngine<PluginPickerItem>(
            allItems: items,
            initialSelectedIndex: 0,
            filterItems: PluginPickerSearch.filteredItems,
            renderLines: { state in
                let selectedOrdinal = state.items.isEmpty ? 0 : min(max(0, state.selectedIndex), state.items.count - 1) + 1
                let searchHint = state.searchQuery.isEmpty
            ? "type to search, Up/Down, Enter toggles, Esc"
            : "type to search, Backspace, Enter toggles, Esc"
                let countLabel = state.items.count == state.totalItemCount
                    ? "\(selectedOrdinal)/\(state.items.count)"
                    : "\(selectedOrdinal)/\(state.items.count) of \(state.totalItemCount)"
                var lines = ["Available plugins \(countLabel) (\(searchHint)):"]
                lines.append("Search: \(state.searchQuery)")

                if state.items.isEmpty {
                    lines.append("  No matching plugins")
                } else {
                    for index in state.viewport.startIndex..<state.viewport.endIndex {
                        let item = state.items[index]
                        let pointer = index == state.selectedIndex ? ">" : " "
                        let line = "\(pointer) \(item.statusLabel) \(item.commandName) — \(item.displayPath)"
                        lines.append(index == state.selectedIndex ? "\u{1B}[7m\(line)\u{1B}[0m" : line)
                    }
                }

                if state.viewport.visibleCount < state.items.count {
                    lines.append("Showing \(state.viewport.startIndex + 1)-\(state.viewport.endIndex) of \(state.items.count)")
                }

                return lines
            }
        )
        return try engine.select()
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

private extension String {
    var shellEscaped: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
