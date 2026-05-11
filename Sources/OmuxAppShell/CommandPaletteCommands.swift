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
        descriptors: [CommandPaletteCommandDescriptor] = CommandPaletteCommandDescriptorCatalog.bundledDescriptors()
    ) -> [CommandPaletteCommand] {
        descriptors.compactMap { descriptor in
            command(from: descriptor, controller: controller, keyBindings: keyBindings)
        }
    }

    private static func command(
        from descriptor: CommandPaletteCommandDescriptor,
        controller: WorkspaceController,
        keyBindings: OpenMUXKeyBindingRegistry
    ) -> CommandPaletteCommand? {
        guard let target = invocationTarget(for: descriptor.command) else {
            return nil
        }
        let enabled = isEnabled(command: descriptor.command, controller: controller)
        return CommandPaletteCommand(
            id: descriptor.id,
            title: descriptor.title,
            subtitle: descriptor.subtitle,
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
            guard OpenMUXCLICommandCatalog.command(id: command.target) != nil else {
                return nil
            }
            return .cliCommand(command.target)
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
            guard let spec = OpenMUXCLICommandCatalog.command(id: command.target) else { return false }
            return isEnabled(cliCommand: spec, controller: controller)
        }
    }

    private static func isEnabled(cliCommand _: OpenMUXCLICommandSpec, controller: WorkspaceController) -> Bool {
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
            return "No focused terminal"
        }
    }

    private static func isEnabled(action: OpenMUXKeyBindingAction, controller: WorkspaceController) -> Bool {
        switch action {
        case .commandPaletteWorkspace, .commandPaletteCommand:
            return false
        case .workspaceCreate, .paneSplitRight, .paneSplitDown, .paneTabCreate, .sidebarToggle:
            return controller.activeWorkspace() != nil
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
            case .sidebarToggle:
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
            case .paneTabClose:
                guard try closePaneTab() != nil else { return .failed("Pane tab could not be closed") }
            case .paneTabNext:
                guard focusNextPaneTab() != nil else { return .failed("No next pane tab") }
            case .paneTabPrevious:
                guard focusPreviousPaneTab() != nil else { return .failed("No previous pane tab") }
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
