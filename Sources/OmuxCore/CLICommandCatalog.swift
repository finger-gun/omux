import Foundation

public enum OpenMUXCLIPaletteExecution: Equatable, Sendable {
    case keyBindingAction(OpenMUXKeyBindingAction)
    case createWorkspaceTab
    /// Sends the command as text to the focused terminal tab and submits it.
    case sendToTerminal
    case configOpen
    case unavailable(String)
}

public struct OpenMUXCLICommandSpec: Equatable, Sendable {
    public let id: String
    public let usage: String
    public let title: String
    public let summary: String
    public let aliases: [String]
    public let requiresArguments: Bool
    public let hasSafeDefaultTarget: Bool
    public let includeInUsage: Bool
    public let paletteExecution: OpenMUXCLIPaletteExecution
    private let explicitDisabledReason: String?

    public init(
        id: String,
        usage: String,
        title: String,
        summary: String,
        aliases: [String] = [],
        requiresArguments: Bool = false,
        hasSafeDefaultTarget: Bool = true,
        includeInUsage: Bool = true,
        disabledReason: String? = nil,
        paletteExecution: OpenMUXCLIPaletteExecution
    ) {
        self.id = id
        self.usage = usage
        self.title = title
        self.summary = summary
        self.aliases = aliases
        self.requiresArguments = requiresArguments
        self.hasSafeDefaultTarget = hasSafeDefaultTarget
        self.includeInUsage = includeInUsage
        self.paletteExecution = paletteExecution
        self.explicitDisabledReason = disabledReason
    }

    public var matchText: String {
        ([usage, title, summary] + aliases).joined(separator: " ")
    }

    public var disabledReason: String? {
        if let explicitDisabledReason {
            return explicitDisabledReason
        }
        guard case .unavailable(let reason) = paletteExecution else {
            return nil
        }
        return reason
    }

    public var paletteTerminalCommand: String {
        Self.commandTemplate(from: usage)
    }

    public var submitsFromPalette: Bool {
        requiresArguments == false
    }

    private static func commandTemplate(from usage: String) -> String {
        var result = ""
        var optionalDepth = 0

        for character in usage {
            if character == "[" {
                optionalDepth += 1
                continue
            }
            if character == "]" {
                optionalDepth = max(optionalDepth - 1, 0)
                continue
            }
            if optionalDepth == 0 {
                result.append(character)
            }
        }

        return result
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

public enum OpenMUXCLICommandCatalog {
    public static let commands: [OpenMUXCLICommandSpec] = [
        OpenMUXCLICommandSpec(
            id: "omux.config.doctor",
            usage: "omux config doctor",
            title: "omux: Config Doctor",
            summary: "Validate the current OpenMUX configuration",
            aliases: ["configuration diagnostics", "doctor"],
            paletteExecution: .sendToTerminal
        ),
        OpenMUXCLICommandSpec(
            id: "omux.config.reload",
            usage: "omux config reload",
            title: "omux: Reload Config",
            summary: "Reload OpenMUX configuration",
            aliases: ["configuration reload"],
            paletteExecution: .sendToTerminal
        ),
        OpenMUXCLICommandSpec(
            id: "omux.config.init",
            usage: "omux config init",
            title: "omux: Initialize Config",
            summary: "Write a starter OpenMUX configuration file",
            aliases: ["configuration init", "starter config"],
            paletteExecution: .sendToTerminal
        ),
        OpenMUXCLICommandSpec(
            id: "omux.config.open",
            usage: "omux config open",
            title: "omux: Open Config",
            summary: "Open the OpenMUX configuration file in the default editor",
            aliases: ["configuration open", "edit config", "open settings", "system editor", "default app"],
            paletteExecution: .configOpen
        ),
        OpenMUXCLICommandSpec(
            id: "omux.config.open-terminal",
            usage: "omux config open",
            title: "omux: Open Config in Terminal Editor",
            summary: "Open the OpenMUX configuration file with VISUAL or EDITOR in the focused terminal",
            aliases: ["configuration open terminal", "edit config terminal", "terminal editor", "visual editor"],
            includeInUsage: false,
            paletteExecution: .sendToTerminal
        ),
        OpenMUXCLICommandSpec(
            id: "omux.config.inactive-opacity",
            usage: "omux config inactive-opacity <0.0-1.0>",
            title: "omux: Set Inactive Pane Opacity",
            summary: "Update inactive pane opacity in configuration",
            aliases: ["inactive opacity", "pane opacity"],
            requiresArguments: true,
            hasSafeDefaultTarget: false,
            paletteExecution: .sendToTerminal
        ),
        OpenMUXCLICommandSpec(
            id: "omux.version",
            usage: "omux version",
            title: "omux: Version",
            summary: "Print the installed OpenMUX version",
            aliases: ["--version"],
            paletteExecution: .sendToTerminal
        ),
        OpenMUXCLICommandSpec(
            id: "omux.help",
            usage: "omux help",
            title: "omux: Help",
            summary: "Print CLI usage",
            aliases: ["--help", "-h"],
            paletteExecution: .sendToTerminal
        ),
        OpenMUXCLICommandSpec(
            id: "omux.update",
            usage: "omux update",
            title: "omux: Update",
            summary: "Update OpenMUX from the command line",
            aliases: ["self update"],
            paletteExecution: .sendToTerminal
        ),
        OpenMUXCLICommandSpec(
            id: "omux.theme",
            usage: "omux theme",
            title: "omux: Pick Theme",
            summary: "Select a theme interactively",
            aliases: ["theme picker"],
            paletteExecution: .sendToTerminal
        ),
        OpenMUXCLICommandSpec(
            id: "omux.theme.set",
            usage: "omux theme <name>",
            title: "omux: Set Theme",
            summary: "Set the active theme by name",
            aliases: ["theme name"],
            requiresArguments: true,
            hasSafeDefaultTarget: false,
            paletteExecution: .sendToTerminal
        ),
        OpenMUXCLICommandSpec(
            id: "omux.theme.list",
            usage: "omux theme list",
            title: "omux: List Themes",
            summary: "List installed themes",
            aliases: ["themes"],
            paletteExecution: .sendToTerminal
        ),
        OpenMUXCLICommandSpec(
            id: "omux.plugins",
            usage: "omux plugins",
            title: "omux: List Plugins",
            summary: "List installed CLI plugins",
            aliases: ["omux plugin list"],
            paletteExecution: .sendToTerminal
        ),
        OpenMUXCLICommandSpec(
            id: "omux.plugin.list",
            usage: "omux plugin list",
            title: "omux: Plugin List",
            summary: "List installed CLI plugins",
            aliases: ["plugins"],
            paletteExecution: .sendToTerminal
        ),
        OpenMUXCLICommandSpec(
            id: "omux.plugin.path",
            usage: "omux plugin path",
            title: "omux: Plugin Path",
            summary: "Print the user plugin directory path",
            aliases: ["plugins path"],
            paletteExecution: .sendToTerminal
        ),
        OpenMUXCLICommandSpec(
            id: "omux.list",
            usage: "omux list [--full]",
            title: "omux: List Workspaces",
            summary: "Print workspace state as JSON",
            aliases: ["workspace list", "workspaces"],
            paletteExecution: .sendToTerminal
        ),
        OpenMUXCLICommandSpec(
            id: "omux.sessions",
            usage: "omux sessions",
            title: "omux: List Sessions",
            summary: "Print terminal sessions as JSON",
            aliases: ["omux session"],
            paletteExecution: .sendToTerminal
        ),
        OpenMUXCLICommandSpec(
            id: "omux.panes",
            usage: "omux panes",
            title: "omux: List Panes",
            summary: "Print panes as JSON",
            aliases: ["omux pane"],
            paletteExecution: .sendToTerminal
        ),
        OpenMUXCLICommandSpec(
            id: "omux.events",
            usage: "omux events",
            title: "omux: Stream Events",
            summary: "Stream terminal events",
            aliases: ["terminal events"],
            paletteExecution: .sendToTerminal
        ),
        OpenMUXCLICommandSpec(
            id: "omux.history",
            usage: "omux history [--json] [--max-lines <count>] [--max-bytes <count>] [<pane-id>|all]",
            title: "omux: History",
            summary: "Print terminal scrollback history",
            aliases: ["scrollback"],
            paletteExecution: .sendToTerminal
        ),
        OpenMUXCLICommandSpec(
            id: "omux.history.clear",
            usage: "omux history clear [--json] [--all|--session <id>|--pane <id>|--pane-tab <id>|--tab <id>|--workspace <id>|--focused]",
            title: "omux: Clear History",
            summary: "Clear persisted terminal history",
            aliases: ["clear scrollback"],
            paletteExecution: .sendToTerminal
        ),
        OpenMUXCLICommandSpec(
            id: "omux.markdown-preview",
            usage: "omux markdown-preview <file> [--watch] [--pane <id>] [--title <title>] [--axis columns|rows]",
            title: "omux: Markdown Preview",
            summary: "Open a Markdown preview extension pane",
            aliases: ["markdown", "preview"],
            requiresArguments: true,
            hasSafeDefaultTarget: false,
            paletteExecution: .sendToTerminal
        ),
        OpenMUXCLICommandSpec(
            id: "omux.extension-pane.create",
            usage: "omux extension-pane create --plugin <id> [--title <title>] [--source <path>] [--html <html>|--html-file <path>]",
            title: "omux: Create Extension Pane",
            summary: "Create an extension pane for a plugin",
            aliases: ["extension create", "plugin pane"],
            requiresArguments: true,
            hasSafeDefaultTarget: false,
            paletteExecution: .sendToTerminal
        ),
        OpenMUXCLICommandSpec(
            id: "omux.extension-pane.update",
            usage: "omux extension-pane update --pane <id> --plugin <id> [--title <title>] [--source <path>] [--html <html>|--html-file <path>] [--status ready|disabled|error] [--message <text>]",
            title: "omux: Update Extension Pane",
            summary: "Update extension pane content and status",
            aliases: ["extension update", "plugin pane update"],
            requiresArguments: true,
            hasSafeDefaultTarget: false,
            paletteExecution: .sendToTerminal
        ),
        OpenMUXCLICommandSpec(
            id: "omux.extension-pane.close",
            usage: "omux extension-pane close --pane <id>",
            title: "omux: Close Extension Pane",
            summary: "Close an extension pane",
            aliases: ["extension close", "plugin pane close"],
            requiresArguments: true,
            hasSafeDefaultTarget: false,
            paletteExecution: .sendToTerminal
        ),
        OpenMUXCLICommandSpec(
            id: "omux.open",
            usage: "omux open [path]",
            title: "omux: Open Workspace",
            summary: "Open a workspace, defaulting to the configured workspace root",
            aliases: ["new workspace", "workspace open"],
            disabledReason: "No active workspace",
            paletteExecution: .keyBindingAction(.workspaceCreate)
        ),
        OpenMUXCLICommandSpec(
            id: "omux.workspace-close",
            usage: "omux workspace-close [workspace-id]",
            title: "omux: Close Workspace",
            summary: "Close the active workspace or a workspace ID",
            aliases: ["delete workspace", "close workspace"],
            disabledReason: "No workspace to close",
            paletteExecution: .keyBindingAction(.workspaceClose)
        ),
        OpenMUXCLICommandSpec(
            id: "omux.tab",
            usage: "omux tab",
            title: "omux: Create Workspace Tab",
            summary: "Create a new workspace tab",
            aliases: ["new tab", "workspace tab"],
            disabledReason: "No active workspace",
            paletteExecution: .createWorkspaceTab
        ),
        OpenMUXCLICommandSpec(
            id: "omux.split",
            usage: "omux split [--session <id>|--pane <id>|--tab <id>|--workspace <id>|--focused] [left|right|up|down]",
            title: "omux: Split Pane",
            summary: "Split the focused pane to the right by default",
            aliases: ["split pane", "split right", "horizontal split"],
            disabledReason: "No focused pane",
            paletteExecution: .keyBindingAction(.paneSplitRight)
        ),
        OpenMUXCLICommandSpec(
            id: "omux.pane-remove",
            usage: "omux pane-remove [--session <id>|--pane <id>|--tab <id>|--workspace <id>|--focused]",
            title: "omux: Remove Pane",
            summary: "Remove the focused pane by default",
            aliases: ["close pane", "remove active pane"],
            disabledReason: "No removable pane",
            paletteExecution: .keyBindingAction(.paneRemove)
        ),
        OpenMUXCLICommandSpec(
            id: "omux.pane-tab",
            usage: "omux pane-tab",
            title: "omux: Create Pane Tab",
            summary: "Create a new pane tab",
            aliases: ["new pane tab"],
            disabledReason: "No active workspace",
            paletteExecution: .keyBindingAction(.paneTabCreate)
        ),
        OpenMUXCLICommandSpec(
            id: "omux.pane-tab-next",
            usage: "omux pane-tab-next",
            title: "omux: Next Pane Tab",
            summary: "Focus the next pane tab",
            aliases: ["next tab"],
            disabledReason: "No alternate pane tab",
            paletteExecution: .keyBindingAction(.paneTabNext)
        ),
        OpenMUXCLICommandSpec(
            id: "omux.pane-tab-prev",
            usage: "omux pane-tab-prev",
            title: "omux: Previous Pane Tab",
            summary: "Focus the previous pane tab",
            aliases: ["previous pane tab", "prev tab"],
            disabledReason: "No alternate pane tab",
            paletteExecution: .keyBindingAction(.paneTabPrevious)
        ),
        OpenMUXCLICommandSpec(
            id: "omux.pane-tab-focus",
            usage: "omux pane-tab-focus <pane-id>",
            title: "omux: Focus Pane Tab",
            summary: "Focus a pane tab by pane ID",
            aliases: ["focus pane tab"],
            requiresArguments: true,
            hasSafeDefaultTarget: false,
            paletteExecution: .sendToTerminal
        ),
        OpenMUXCLICommandSpec(
            id: "omux.pane-tab-close",
            usage: "omux pane-tab-close [pane-id]",
            title: "omux: Close Pane Tab",
            summary: "Close the focused pane tab by default",
            aliases: ["close pane tab"],
            disabledReason: "No pane tab to close",
            paletteExecution: .keyBindingAction(.paneTabClose)
        ),
        OpenMUXCLICommandSpec(
            id: "omux.pane-next",
            usage: "omux pane-next",
            title: "omux: Next Pane",
            summary: "Focus the next pane",
            aliases: ["next pane"],
            disabledReason: "No alternate pane",
            paletteExecution: .keyBindingAction(.paneNext)
        ),
        OpenMUXCLICommandSpec(
            id: "omux.pane-prev",
            usage: "omux pane-prev",
            title: "omux: Previous Pane",
            summary: "Focus the previous pane",
            aliases: ["previous pane", "prev pane"],
            disabledReason: "No alternate pane",
            paletteExecution: .keyBindingAction(.panePrevious)
        ),
        OpenMUXCLICommandSpec(
            id: "omux.focus",
            usage: "omux focus <session-id>|--session <id>|--pane <id>|--tab <id>|--workspace <id>|--focused",
            title: "omux: Focus Target",
            summary: "Focus a session, pane, tab, workspace, or the focused target",
            aliases: ["focus session", "focus pane"],
            requiresArguments: true,
            hasSafeDefaultTarget: false,
            paletteExecution: .sendToTerminal
        ),
        OpenMUXCLICommandSpec(
            id: "omux.run",
            usage: "omux run <session-id> <command>",
            title: "omux: Run Command",
            summary: "Run a shell command in a terminal session",
            aliases: ["run in session"],
            requiresArguments: true,
            hasSafeDefaultTarget: false,
            paletteExecution: .sendToTerminal
        ),
        OpenMUXCLICommandSpec(
            id: "omux.run.target",
            usage: "omux run --session <id>|--pane <id>|--tab <id>|--workspace <id>|--focused -- <command>",
            title: "omux: Run Command in Target",
            summary: "Run a shell command in an explicit target",
            aliases: ["run focused"],
            requiresArguments: true,
            hasSafeDefaultTarget: false,
            paletteExecution: .sendToTerminal
        ),
        OpenMUXCLICommandSpec(
            id: "omux.send-text",
            usage: "omux send-text --session <id>|--pane <id>|--tab <id>|--workspace <id>|--focused -- <text>",
            title: "omux: Send Text",
            summary: "Send text to a terminal target",
            aliases: ["type text", "send input"],
            requiresArguments: true,
            hasSafeDefaultTarget: false,
            paletteExecution: .sendToTerminal
        ),
        OpenMUXCLICommandSpec(
            id: "omux.pane-status",
            usage: "omux pane-status --session <id>|--pane <id>|--tab <id>|--workspace <id>|--focused --state working|indeterminate|error|needs-input|idle|clear [--value <0-100>] [--label <text>] [--message <text>] [--source <name>]",
            title: "omux: Pane Status",
            summary: "Update a terminal pane status indicator",
            aliases: ["pane status", "status indicator"],
            requiresArguments: true,
            hasSafeDefaultTarget: false,
            paletteExecution: .sendToTerminal
        ),
        OpenMUXCLICommandSpec(
            id: "omux.notify",
            usage: "omux notify <title> [body]",
            title: "omux: Send Notification",
            summary: "Send an OpenMUX notification",
            aliases: ["notification"],
            requiresArguments: true,
            hasSafeDefaultTarget: false,
            paletteExecution: .sendToTerminal
        ),
        OpenMUXCLICommandSpec(
            id: "omux.restore",
            usage: "omux restore <workspace-id>",
            title: "omux: Restore Workspace",
            summary: "Restore a workspace by ID",
            aliases: ["restore layout"],
            requiresArguments: true,
            hasSafeDefaultTarget: false,
            paletteExecution: .sendToTerminal
        ),
        OpenMUXCLICommandSpec(
            id: "omux.install-cli",
            usage: "omux install-cli [destination]",
            title: "omux: Install CLI",
            summary: "Install the omux CLI executable",
            aliases: ["cli install"],
            paletteExecution: .sendToTerminal
        ),
        OpenMUXCLICommandSpec(
            id: "omux.pane-find",
            usage: "omux pane-find",
            title: "omux: Find in Pane",
            summary: "Search the scrollback of the focused pane",
            aliases: ["find in pane", "search pane", "find pane"],
            paletteExecution: .keyBindingAction(.paneFind)
        ),
    ]

    public static let usage: String = {
        let lines = commands
            .filter(\.includeInUsage)
            .map { "  \($0.usage)" }
            .joined(separator: "\n")
        return """
        OpenMUX CLI

        Commands:
        \(lines)
        """
    }()

    public static func command(id: String) -> OpenMUXCLICommandSpec? {
        commands.first { $0.id == id }
    }
}
