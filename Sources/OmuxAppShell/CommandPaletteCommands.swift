import Foundation
import OmuxControlPlane
import OmuxCore

enum CommandPaletteInvocationResult: Equatable {
    case invoked
    case inert
    case disabled(String?)
    case failed(String)
}

struct CommandPaletteCommandCatalog {
    static func commands(
        controller: WorkspaceController,
        keyBindings: OpenMUXKeyBindingRegistry,
        descriptors: [CommandPaletteCommandDescriptor] = CommandPaletteCommandDescriptorCatalog.bundledDescriptors(),
        subtitleOverrides: [String: String] = [:]
    ) -> [CommandPaletteCommand] {
        descriptors.compactMap { descriptor in
            command(from: descriptor, controller: controller, keyBindings: keyBindings, subtitleOverrides: subtitleOverrides)
        }
    }

    private static func command(
        from descriptor: CommandPaletteCommandDescriptor,
        controller: WorkspaceController,
        keyBindings: OpenMUXKeyBindingRegistry,
        subtitleOverrides: [String: String] = [:]
    ) -> CommandPaletteCommand? {
        guard let target = invocationTarget(for: descriptor.command) else {
            return nil
        }
        let enabled = isEnabled(command: descriptor.command, controller: controller)
        return CommandPaletteCommand(
            id: descriptor.id,
            title: descriptor.title,
            subtitle: subtitleOverrides[descriptor.id] ?? descriptor.subtitle,
            category: descriptor.category.paletteCategory,
            matchText: descriptor.matchText,
            aliases: descriptor.aliases,
            shortcutLabel: shortcutLabel(for: target, keyBindings: keyBindings),
            requiresArguments: descriptor.requiresArguments,
            hasSafeDefaultTarget: descriptor.hasSafeDefaultTarget,
            isEnabled: enabled,
            disabledReason: enabled ? nil : disabledReason(for: descriptor.command, descriptor: descriptor),
            invocationTarget: target
        )
    }

    private static func invocationTarget(for command: CommandPaletteCommandDescriptor.Command) -> CommandPaletteInvocationTarget? {
        switch command.kind {
        case .action:
            guard let action = OpenMUXKeyBindingAction(rawValue: command.target) else {
                return nil
            }
            return .action(action)
        case .builtin:
            switch command.target {
            case "theme.switch":
                return .themeSwitch
            case "workspace.restore-recently-closed":
                return .restoreWorkspacePalette
            case "workspace.clear-recently-closed":
                return .clearRecentlyClosedWorkspaces
            case "omux.agent-sessions.open":
                return .vaultSessions
            default:
                guard let spec = OpenMUXCLICommandCatalog.command(id: command.target) else {
                    return nil
                }
                if spec.paletteExecution == .configOpen {
                    return .configOpen
                }
                return .cliCommand(command.target)
            }
        }
    }

    private static func shortcutLabel(
        for target: CommandPaletteInvocationTarget,
        keyBindings: OpenMUXKeyBindingRegistry
    ) -> String? {
        guard case .action(let action) = target else {
            return nil
        }
        return keyBindings.chord(for: action)?.displayLabel
    }

    private static func isEnabled(
        command: CommandPaletteCommandDescriptor.Command,
        controller: WorkspaceController
    ) -> Bool {
        switch command.kind {
        case .action:
            guard let action = OpenMUXKeyBindingAction(rawValue: command.target) else { return false }
            return isEnabled(action: action, controller: controller)
        case .builtin:
            switch command.target {
            case "theme.switch":
                return true
            case "workspace.restore-recently-closed":
                return controller.commandPaletteRecentlyClosedWorkspaces().isEmpty == false
            case "workspace.clear-recently-closed":
                return controller.commandPaletteRecentlyClosedWorkspaces().isEmpty == false
            case "omux.agent-sessions.open":
                return true
            default:
                guard let spec = OpenMUXCLICommandCatalog.command(id: command.target) else { return false }
                if spec.paletteExecution == .configOpen {
                    return true
                }
                return isEnabled(cliCommand: spec, controller: controller)
            }
        }
    }

    private static func isEnabled(cliCommand spec: OpenMUXCLICommandSpec, controller: WorkspaceController) -> Bool {
        if case .unavailable = spec.paletteExecution { return false }
        return controller.resolveTerminalTarget(.focused) != nil
    }

    private static func disabledReason(
        for command: CommandPaletteCommandDescriptor.Command,
        descriptor: CommandPaletteCommandDescriptor
    ) -> String? {
        switch command.kind {
        case .action:
            return descriptor.disabledReason
        case .builtin:
            if command.target == "theme.switch" {
                return descriptor.disabledReason
            }
            // Prefer the spec's own disabled reason (e.g. .unavailable message) over the generic fallback
            if let specReason = descriptor.disabledReason {
                return specReason
            }
            return "No focused terminal"
        }
    }

    private static func isEnabled(action: OpenMUXKeyBindingAction, controller: WorkspaceController) -> Bool {
        switch action {
        case .commandPaletteWorkspace, .commandPaletteCommand:
            return false
        case .workspaceCreate, .paneSplitRight, .paneSplitDown, .paneTabCreate, .sidebarToggle, .agentSessionsToggle:
            return controller.activeWorkspace() != nil
        case .workspaceRestoreLastClosed:
            return controller.commandPaletteRecentlyClosedWorkspaces().isEmpty == false
        case .paneTabCreateWorktree:
            return controller.resolveTerminalTarget(.focused) != nil
        case .workspaceClose:
            return controller.canDeleteActiveWorkspace()
        case .workspacePrevious:
            return controller.canFocusPreviousWorkspace()
        case .workspaceMoveUp:
            return controller.canMoveActiveWorkspaceUp()
        case .workspaceMoveDown:
            return controller.canMoveActiveWorkspaceDown()
        case .workspaceFocus1, .workspaceFocus2, .workspaceFocus3, .workspaceFocus4, .workspaceFocus5, .workspaceFocus6, .workspaceFocus7, .workspaceFocus8, .workspaceFocus9:
            return false
        case .paneRemove:
            return controller.canRemoveActivePane()
        case .paneNext, .panePrevious:
            return controller.canFocusPane()
        case .paneResizeEqualize:
            return controller.canEqualizeSplits()
        case .paneResizeUp:
            return controller.canResizeSplit(.up)
        case .paneResizeDown:
            return controller.canResizeSplit(.down)
        case .paneResizeLeft:
            return controller.canResizeSplit(.left)
        case .paneResizeRight:
            return controller.canResizeSplit(.right)
        case .paneTabClose, .paneTabNext, .paneTabPrevious:
            return controller.canFocusPaneTab()
        case .paneFind:
            return controller.activeWorkspace()?.focusedPane?.isTerminal == true
        }
    }
}

extension WorkspaceController {
    func commandPaletteWorkspaces() -> [CommandPaletteWorkspace] {
        let activeID = activeWorkspace()?.id
        return allWorkspaces().enumerated().map { index, workspace in
            workspace.commandPaletteWorkspace(visibleOrder: index, activeWorkspaceID: activeID)
        }
    }

    @discardableResult
    func invokeCommandPaletteResult(_ result: CommandPaletteResult) -> CommandPaletteInvocationResult {
        guard result.isEnabled else {
            return .disabled(result.disabledReason)
        }

        switch result.invocationTarget {
        case .workspace(let workspaceID):
            guard activeWorkspace()?.id != workspaceID else { return .inert }
            return restore(workspaceID: workspaceID) == nil ? .failed("Workspace is no longer available") : .invoked
        case .action(let action):
            return invokePaletteAction(action)
        case .cliCommand(let commandID):
            return invokePaletteCLICommand(commandID)
        case .themeSwitch:
            return .inert
        case .restoreWorkspacePalette:
            return .inert
        case .clearRecentlyClosedWorkspaces:
            clearRecentlyClosedWorkspaces()
            return .invoked
        case .reopenClosedWorkspace(let workspaceID):
            let entries = commandPaletteRecentlyClosedWorkspaces()
            guard let entry = entries.first(where: { $0.id == workspaceID }) else {
                return .failed("Workspace is no longer in the recently closed list")
            }
            do {
                _ = try reopenClosedWorkspace(entry)
                removeRecentlyClosedWorkspace(byID: entry.id)
                return .invoked
            } catch {
                return .failed(error.localizedDescription)
            }
        case .vaultSessions, .vaultSession:
            return .inert
        case .configOpen:
            return .inert
        }
    }

    @discardableResult
    private func invokePaletteAction(_ action: OpenMUXKeyBindingAction) -> CommandPaletteInvocationResult {
        do {
            switch action {
            case .commandPaletteWorkspace, .commandPaletteCommand:
                return .inert
            case .workspaceCreate:
                _ = try createWorkspace()
            case .workspaceRestoreLastClosed:
                guard try restoreMostRecentlyClosedWorkspace() != nil else {
                    return .failed("No recently closed workspaces")
                }
            case .workspaceClose:
                guard try deleteActiveWorkspace() != nil else { return .failed("Workspace could not be closed") }
            case .workspacePrevious:
                guard focusPreviousWorkspace() != nil else { return .failed("Previous workspace is no longer available") }
            case .workspaceMoveUp:
                guard moveActiveWorkspaceUp() != nil else { return .failed("Workspace could not move up") }
            case .workspaceMoveDown:
                guard moveActiveWorkspaceDown() != nil else { return .failed("Workspace could not move down") }
            case .workspaceFocus1, .workspaceFocus2, .workspaceFocus3, .workspaceFocus4, .workspaceFocus5, .workspaceFocus6, .workspaceFocus7, .workspaceFocus8, .workspaceFocus9:
                return .inert
            case .sidebarToggle, .agentSessionsToggle:
                return .failed("Sidebar toggle is handled by the app shell")
            case .paneSplitRight:
                guard try splitFocusedPane(axis: .columns) != nil else { return .failed("Pane could not split right") }
            case .paneSplitDown:
                guard try splitFocusedPane(axis: .rows) != nil else { return .failed("Pane could not split down") }
            case .paneRemove:
                guard try removeActivePane() != nil else { return .failed("Pane could not be removed") }
            case .paneNext:
                guard focusNextPane() != nil else { return .failed("No next pane") }
            case .panePrevious:
                guard focusPreviousPane() != nil else { return .failed("No previous pane") }
            case .paneResizeEqualize:
                guard equalizeSplits() != nil else { return .failed("No split to equalize") }
            case .paneResizeUp:
                guard resizeSplit(.up) != nil else { return .failed("Divider could not move up") }
            case .paneResizeDown:
                guard resizeSplit(.down) != nil else { return .failed("Divider could not move down") }
            case .paneResizeLeft:
                guard resizeSplit(.left) != nil else { return .failed("Divider could not move left") }
            case .paneResizeRight:
                guard resizeSplit(.right) != nil else { return .failed("Divider could not move right") }
            case .paneTabCreate:
                guard try createPaneTab() != nil else { return .failed("Pane tab could not be created") }
            case .paneTabCreateWorktree:
                guard try runCommand(target: .focused, command: "omux worktree \(Self.generatedWorktreeBranchName().shellEscaped)") != nil else {
                    return .failed("No focused terminal")
                }
            case .paneTabClose:
                guard try closePaneTab() != nil else { return .failed("Pane tab could not be closed") }
            case .paneTabNext:
                guard focusNextPaneTab() != nil else { return .failed("No next pane tab") }
            case .paneTabPrevious:
                guard focusPreviousPaneTab() != nil else { return .failed("No previous pane tab") }
            case .paneFind:
                return .failed("Pane find is handled by the app shell")
            }
            return .invoked
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    @discardableResult
    private func invokePaletteCLICommand(_ commandID: String) -> CommandPaletteInvocationResult {
        guard let spec = OpenMUXCLICommandCatalog.command(id: commandID) else {
            return .failed("Unsupported palette CLI command")
        }

        if case .unavailable(let reason) = spec.paletteExecution {
            return .disabled(reason)
        }

        do {
            let result: ControlPlaneActionResult?
            if spec.submitsFromPalette {
                result = try runCommand(target: .focused, command: spec.paletteTerminalCommand)
            } else {
                result = try sendText(target: .focused, text: spec.paletteTerminalCommand)
            }
            guard result != nil else {
                return .failed("No focused terminal")
            }
            return .invoked
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private static func generatedWorktreeBranchName() -> String {
        "worktree/\(UUID().uuidString.prefix(8).lowercased())"
    }
}

private extension String {
    var shellEscaped: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

extension CommandPaletteSearch {
    static func recentlyClosedResults(
        query: String,
        entries: [RecentlyClosedWorkspaceEntry]
    ) -> [CommandPaletteResult] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        return entries.enumerated().compactMap { _, entry in
            let pathSearchText = entry.workspacePaths.joined(separator: " ")
            let searchText = "\(entry.name) \(pathSearchText)".trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
            guard normalizedQuery.isEmpty || searchText.contains(normalizedQuery) || entry.name.localizedLowercase.contains(normalizedQuery) else {
                return nil
            }
            return CommandPaletteResult(
                id: "recently-closed:\(entry.id.rawValue)",
                title: entry.name,
                subtitle: entry.workspacePathSummary,
                category: .workspace,
                matchText: "\(entry.name) \(pathSearchText)",
                aliases: entry.workspacePaths,
                isEnabled: true,
                invocationTarget: .reopenClosedWorkspace(entry.id)
            )
        }
    }

    static func themeResults(query: String, activeIdentifier: String?) -> [CommandPaletteResult] {
        let themes = WorkspaceShellTheme.availableThemes
        let items = themes.map { theme in
            (theme: theme, searchText: "\(theme.displayName) \(theme.identifier)")
        }

        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase

        let filtered: [(theme: WorkspaceShellTheme, score: Int, index: Int)] = items.enumerated().compactMap { index, item in
            if normalizedQuery.isEmpty {
                return (item.theme, 0, index)
            }
            let candidate = item.searchText.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
            if candidate == normalizedQuery { return (item.theme, 0, index) }
            if candidate.hasPrefix(normalizedQuery) { return (item.theme, 10, index) }
            if candidate.contains(normalizedQuery) { return (item.theme, 20, index) }
            let parts = normalizedQuery.split(separator: " ")
            if parts.allSatisfy({ candidate.contains($0) }) { return (item.theme, 30, index) }
            return nil
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            return lhs.index < rhs.index
        }

        return filtered.map { entry in
            CommandPaletteResult(
                id: entry.theme.identifier,
                title: entry.theme.displayName,
                category: .action,
                matchText: "\(entry.theme.displayName) \(entry.theme.identifier)",
                isActive: entry.theme.identifier == activeIdentifier,
                invocationTarget: .themeSwitch
            )
        }
    }
}

extension OpenMUXKeyChord {
    var displayLabel: String {
        description
            .split(separator: "+")
            .map { part in
                switch part {
                case "cmd":   return "⌘"
                case "ctrl":  return "⌃"
                case "shift": return "⇧"
                case "alt":   return "⌥"
                case "up":    return "↑"
                case "down":  return "↓"
                case "left":  return "←"
                case "right": return "→"
                case "tab":   return "⇥"
                case "enter", "return": return "↩"
                case "delete", "backspace": return "⌫"
                case "escape": return "⎋"
                default: return String(part).uppercased()
                }
            }
            .joined()
    }
}
