import AppKit
import Foundation
import OmuxControlPlane
import OmuxConfig
import OmuxCore
import OmuxHooks
import OmuxTerminalBridge
import OmuxTheme

@MainActor
public final class OpenMUXAppDelegate: NSObject, NSApplicationDelegate {
    private let workspaceController: WorkspaceController
    private let controlPlaneService: OpenMUXControlPlaneService
    private let configurationCoordinator: OpenMUXConfigurationCoordinator
    private let workspacePersistenceStore: any WorkspacePersistenceStoring
    private var windowController: WorkspaceWindowController?
    private weak var newWorkspaceMenuItem: NSMenuItem?
    private weak var renameWorkspaceMenuItem: NSMenuItem?
    private weak var deleteWorkspaceMenuItem: NSMenuItem?
    private weak var splitRightMenuItem: NSMenuItem?
    private weak var splitDownMenuItem: NSMenuItem?
    private weak var removePaneMenuItem: NSMenuItem?
    private weak var toggleSidebarMenuItem: NSMenuItem?
    private weak var previousWorkspaceMenuItem: NSMenuItem?
    private var workspaceJumpMenuItems: [NSMenuItem] = []

    public override init() {
        let preparedConfiguration = OpenMUXConfigurationCoordinator.prepareInitialState()
        preparedConfiguration.diagnostics.forEach { diagnostic in
            let prefix = diagnostic.severity == .warning ? "warning" : "error"
            fputs("\(prefix): \(diagnostic.message)\n", stderr)
        }

        let bridge = GhosttyTerminalBridge(compiledConfigPath: preparedConfiguration.compiledConfigURL)
        let hookRunner = ExternalHookRunner()
        let workspaceController = WorkspaceController(bridge: bridge, hookRunner: hookRunner)
        self.workspaceController = workspaceController
        self.configurationCoordinator = OpenMUXConfigurationCoordinator(
            bridge: bridge,
            initialState: preparedConfiguration
        )
        self.controlPlaneService = OpenMUXControlPlaneService(
            controller: workspaceController,
            configurationCoordinator: configurationCoordinator
        )
        self.workspacePersistenceStore = WorkspacePersistenceStore.shared
        self.initialTheme = preparedConfiguration.theme
        super.init()
    }

    private let initialTheme: WorkspaceShellTheme

    public func applicationDidFinishLaunching(_ notification: Notification) {
        _ = notification
        configureMenus()
        workspaceController.onChange = { [weak self] workspace in
            Task { @MainActor in
                self?.persistWorkspaceState()
                self?.windowController?.update(workspace: workspace)
                self?.refreshMenuValidation()
            }
        }

        do {
            let workspace = try restoreInitialWorkspace()
            let windowController = WorkspaceWindowController(
                workspace: workspace,
                controller: workspaceController,
                initialTheme: initialTheme
            )
            self.windowController = windowController
            windowController.showWindow(nil)
            configurationCoordinator.onThemeChange = { [weak self] theme in
                self?.windowController?.updateTheme(theme)
            }
            configurationCoordinator.onDiagnosticsChange = { diagnostics in
                diagnostics.forEach { diagnostic in
                    let prefix = diagnostic.severity == .warning ? "warning" : "error"
                    fputs("\(prefix): \(diagnostic.message)\n", stderr)
                }
            }
            refreshMenuValidation()
            try controlPlaneService.start()
        } catch {
            assertionFailure("Failed to launch OpenMUX foundation: \(error)")
        }
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        _ = sender
        return true
    }

    public func applicationWillTerminate(_ notification: Notification) {
        _ = notification
        persistWorkspaceState()
        controlPlaneService.stop()
    }

    @objc private func createWorkspaceFromMenu(_ sender: Any?) {
        _ = sender
        do {
            _ = try workspaceController.createWorkspace()
            refreshMenuValidation()
        } catch {
            assertionFailure("Failed to create workspace: \(error)")
        }
    }

    @objc private func deleteWorkspaceFromMenu(_ sender: Any?) {
        _ = sender
        do {
            _ = try workspaceController.deleteActiveWorkspace()
            refreshMenuValidation()
        } catch {
            assertionFailure("Failed to delete workspace: \(error)")
        }
    }

    @objc private func renameWorkspaceFromMenu(_ sender: Any?) {
        _ = sender
        windowController?.presentRenameWorkspacePrompt()
    }

    @objc private func splitPaneRightFromMenu(_ sender: Any?) {
        _ = sender
        do {
            _ = try workspaceController.splitFocusedPane(axis: .columns)
            refreshMenuValidation()
        } catch {
            assertionFailure("Failed to split pane right: \(error)")
        }
    }

    @objc private func splitPaneDownFromMenu(_ sender: Any?) {
        _ = sender
        do {
            _ = try workspaceController.splitFocusedPane(axis: .rows)
            refreshMenuValidation()
        } catch {
            assertionFailure("Failed to split pane down: \(error)")
        }
    }

    @objc private func removeActivePaneFromMenu(_ sender: Any?) {
        _ = sender
        do {
            _ = try workspaceController.removeActivePane()
            refreshMenuValidation()
        } catch {
            assertionFailure("Failed to remove active pane: \(error)")
        }
    }

    @objc private func toggleSidebarFromMenu(_ sender: Any?) {
        _ = sender
        windowController?.toggleSidebarVisibility()
    }

    @objc private func focusPreviousWorkspaceFromMenu(_ sender: Any?) {
        _ = sender
        _ = workspaceController.focusPreviousWorkspace()
        refreshMenuValidation()
    }

    @objc private func focusNumberedWorkspaceFromMenu(_ sender: Any?) {
        guard let item = sender as? NSMenuItem else {
            return
        }

        let index = item.tag
        _ = workspaceController.focusWorkspace(atDisplayIndex: index)
        refreshMenuValidation()
    }

    private func configureMenus() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Quit OpenMUX",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")

        let newWorkspaceMenuItem = NSMenuItem(
            title: "New Workspace",
            action: #selector(createWorkspaceFromMenu(_:)),
            keyEquivalent: "n"
        )
        newWorkspaceMenuItem.target = self
        viewMenu.addItem(newWorkspaceMenuItem)

        let deleteWorkspaceMenuItem = NSMenuItem(
            title: "Delete Workspace",
            action: #selector(deleteWorkspaceFromMenu(_:)),
            keyEquivalent: "w"
        )
        deleteWorkspaceMenuItem.target = self
        viewMenu.addItem(deleteWorkspaceMenuItem)

        let renameWorkspaceMenuItem = NSMenuItem(
            title: "Rename Workspace…",
            action: #selector(renameWorkspaceFromMenu(_:)),
            keyEquivalent: ""
        )
        renameWorkspaceMenuItem.target = self
        viewMenu.addItem(renameWorkspaceMenuItem)
        viewMenu.addItem(.separator())

        let toggleSidebarMenuItem = NSMenuItem(
            title: "Toggle Workspace Column",
            action: #selector(toggleSidebarFromMenu(_:)),
            keyEquivalent: "b"
        )
        toggleSidebarMenuItem.target = self
        viewMenu.addItem(toggleSidebarMenuItem)

        let previousWorkspaceMenuItem = NSMenuItem(
            title: "Previous Workspace",
            action: #selector(focusPreviousWorkspaceFromMenu(_:)),
            keyEquivalent: "0"
        )
        previousWorkspaceMenuItem.target = self
        viewMenu.addItem(previousWorkspaceMenuItem)

        var workspaceJumpMenuItems: [NSMenuItem] = []
        for index in 0..<9 {
            let item = NSMenuItem(
                title: "Go to Workspace \(index + 1)",
                action: #selector(focusNumberedWorkspaceFromMenu(_:)),
                keyEquivalent: "\(index + 1)"
            )
            item.target = self
            item.tag = index
            viewMenu.addItem(item)
            workspaceJumpMenuItems.append(item)
        }

        viewMenu.addItem(.separator())

        let splitRightMenuItem = NSMenuItem(
            title: "Split Right",
            action: #selector(splitPaneRightFromMenu(_:)),
            keyEquivalent: "d"
        )
        splitRightMenuItem.keyEquivalentModifierMask = [.command]
        splitRightMenuItem.target = self
        viewMenu.addItem(splitRightMenuItem)

        let splitDownMenuItem = NSMenuItem(
            title: "Split Down",
            action: #selector(splitPaneDownFromMenu(_:)),
            keyEquivalent: "D"
        )
        splitDownMenuItem.keyEquivalentModifierMask = [.command, .shift]
        splitDownMenuItem.target = self
        viewMenu.addItem(splitDownMenuItem)

        let removePaneMenuItem = NSMenuItem(
            title: "Remove Active Pane",
            action: #selector(removeActivePaneFromMenu(_:)),
            keyEquivalent: "\u{8}"
        )
        removePaneMenuItem.target = self
        viewMenu.addItem(removePaneMenuItem)

        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        NSApplication.shared.mainMenu = mainMenu
        self.newWorkspaceMenuItem = newWorkspaceMenuItem
        self.renameWorkspaceMenuItem = renameWorkspaceMenuItem
        self.deleteWorkspaceMenuItem = deleteWorkspaceMenuItem
        self.toggleSidebarMenuItem = toggleSidebarMenuItem
        self.previousWorkspaceMenuItem = previousWorkspaceMenuItem
        self.workspaceJumpMenuItems = workspaceJumpMenuItems
        self.splitRightMenuItem = splitRightMenuItem
        self.splitDownMenuItem = splitDownMenuItem
        self.removePaneMenuItem = removePaneMenuItem
    }

    private func refreshMenuValidation() {
        newWorkspaceMenuItem?.isEnabled = workspaceController.activeWorkspace() != nil
        renameWorkspaceMenuItem?.isEnabled = workspaceController.canRenameActiveWorkspace()
        deleteWorkspaceMenuItem?.isEnabled = workspaceController.canDeleteActiveWorkspace()
        let hasWorkspace = workspaceController.activeWorkspace() != nil
        toggleSidebarMenuItem?.isEnabled = hasWorkspace
        previousWorkspaceMenuItem?.isEnabled = workspaceController.canFocusPreviousWorkspace()
        let workspaceCount = workspaceController.listWorkspaces().count
        for (index, item) in workspaceJumpMenuItems.enumerated() {
            item.isEnabled = index < workspaceCount
        }
        splitRightMenuItem?.isEnabled = hasWorkspace
        splitDownMenuItem?.isEnabled = hasWorkspace
        removePaneMenuItem?.isEnabled = workspaceController.canRemoveActivePane()
    }

    private func restoreInitialWorkspace() throws -> Workspace {
        if let snapshot = workspacePersistenceStore.load(),
           let restoredWorkspace = try workspaceController.restorePersistedState(snapshot) {
            persistWorkspaceState()
            return restoredWorkspace
        }

        let workspace = try workspaceController.openWorkspace(at: FileManager.default.currentDirectoryPath)
        persistWorkspaceState()
        return workspace
    }

    private func persistWorkspaceState() {
        workspacePersistenceStore.save(workspaceController.persistenceSnapshot())
    }

}
