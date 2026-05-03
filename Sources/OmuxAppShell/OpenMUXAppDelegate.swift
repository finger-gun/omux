import AppKit
import Foundation
import OmuxControlPlane
import OmuxConfig
import OmuxCore
import OmuxHooks
import OmuxTerminalBridge
import OmuxTheme

@MainActor
public final class OpenMUXAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
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
    private weak var createPaneTabMenuItem: NSMenuItem?
    private weak var closePaneTabMenuItem: NSMenuItem?
    private weak var nextPaneTabMenuItem: NSMenuItem?
    private weak var nextPaneMenuItem: NSMenuItem?
    private weak var toggleSidebarMenuItem: NSMenuItem?
    private weak var installCLIMenuItem: NSMenuItem?
    private weak var previousWorkspaceMenuItem: NSMenuItem?
    private weak var moveWorkspaceUpMenuItem: NSMenuItem?
    private weak var moveWorkspaceDownMenuItem: NSMenuItem?
    private var workspaceJumpMenuItems: [NSMenuItem] = []

    public override init() {
        let preparedConfiguration = OpenMUXConfigurationCoordinator.prepareInitialState()
        preparedConfiguration.diagnostics.forEach { diagnostic in
            let prefix = diagnostic.severity == .warning ? "warning" : "error"
            fputs("\(prefix): \(diagnostic.message)\n", stderr)
        }

        let bridge = GhosttyTerminalBridge(compiledConfigPath: preparedConfiguration.compiledConfigURL)
        let hookRunner = ExternalHookRunner(
            registry: UserHookDirectoryDiscovery.registry(in: OmuxConfigPaths.hooksDirectoryURL),
            executionMode: .asynchronous
        )
        let workspaceController = WorkspaceController(
            bridge: bridge,
            hookRunner: hookRunner,
            defaultWorkspaceRootPath: preparedConfiguration.defaultWorkspaceRootPath
        )
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
            windowController.window?.delegate = self
            windowController.showWindow(nil)
            if let window = windowController.window {
                window.center()
                window.makeKeyAndOrderFront(nil)
            }
            NSApplication.shared.activate(ignoringOtherApps: true)
            configurationCoordinator.onThemeChange = { [weak self] theme in
                self?.windowController?.updateTheme(theme)
            }
            configurationCoordinator.onWorkspaceDefaultRootChange = { [weak self] path in
                self?.workspaceController.updateDefaultWorkspaceRootPath(path)
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

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        _ = sender
        persistWorkspaceState()
        return .terminateNow
    }

    public func applicationWillTerminate(_ notification: Notification) {
        _ = notification
        persistWorkspaceState()
        controlPlaneService.stop()
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        _ = sender
        persistWorkspaceState()
        return true
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

    @objc private func createPaneTabFromMenu(_ sender: Any?) {
        _ = sender
        do {
            _ = try workspaceController.createPaneTab()
            refreshMenuValidation()
        } catch {
            assertionFailure("Failed to create pane tab: \(error)")
        }
    }

    @objc private func closePaneTabFromMenu(_ sender: Any?) {
        _ = sender
        do {
            _ = try workspaceController.closePaneTab()
            refreshMenuValidation()
        } catch {
            assertionFailure("Failed to close pane tab: \(error)")
        }
    }

    @objc private func focusNextPaneTabFromMenu(_ sender: Any?) {
        _ = sender
        _ = workspaceController.focusNextPaneTab()
        refreshMenuValidation()
    }

    @objc private func focusNextPaneFromMenu(_ sender: Any?) {
        _ = sender
        _ = workspaceController.focusNextPane()
        refreshMenuValidation()
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

    @objc private func moveWorkspaceUpFromMenu(_ sender: Any?) {
        _ = sender
        _ = workspaceController.moveActiveWorkspaceUp()
        refreshMenuValidation()
    }

    @objc private func moveWorkspaceDownFromMenu(_ sender: Any?) {
        _ = sender
        _ = workspaceController.moveActiveWorkspaceDown()
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

    @objc private func installCLIFromMenu(_ sender: Any?) {
        _ = sender

        let installer = OmuxCLIInstaller(executablePath: bundledCLIExecutablePath())
        do {
            let result = try installer.install(destinationPath: installer.defaultUserInstallPath())
            let informativeText: String
            if let pathHintDirectory = result.pathHintDirectory {
                informativeText = """
                Installed omux at \(result.installedPath).

                Add this to your shell profile if omux is still not found:
                export PATH="\(pathHintDirectory):$PATH"
                """
            } else {
                informativeText = "Installed omux at \(result.installedPath)."
            }
            presentAlert(
                messageText: "omux CLI Installed",
                informativeText: informativeText
            )
        } catch {
            presentAlert(
                messageText: "CLI Install Failed",
                informativeText: error.localizedDescription,
                style: .warning
            )
        }
    }

    private func configureMenus() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let installCLIMenuItem = NSMenuItem(
            title: "Install omux CLI",
            action: #selector(installCLIFromMenu(_:)),
            keyEquivalent: ""
        )
        installCLIMenuItem.target = self
        appMenu.addItem(installCLIMenuItem)
        appMenu.addItem(.separator())
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
            keyEquivalent: ""
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

        let moveWorkspaceUpMenuItem = NSMenuItem(
            title: "Move Workspace Up",
            action: #selector(moveWorkspaceUpFromMenu(_:)),
            keyEquivalent: String(UnicodeScalar(NSUpArrowFunctionKey)!)
        )
        moveWorkspaceUpMenuItem.keyEquivalentModifierMask = [.command, .control]
        moveWorkspaceUpMenuItem.target = self
        viewMenu.addItem(moveWorkspaceUpMenuItem)

        let moveWorkspaceDownMenuItem = NSMenuItem(
            title: "Move Workspace Down",
            action: #selector(moveWorkspaceDownFromMenu(_:)),
            keyEquivalent: String(UnicodeScalar(NSDownArrowFunctionKey)!)
        )
        moveWorkspaceDownMenuItem.keyEquivalentModifierMask = [.command, .control]
        moveWorkspaceDownMenuItem.target = self
        viewMenu.addItem(moveWorkspaceDownMenuItem)

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
        removePaneMenuItem.keyEquivalentModifierMask = [.command, .shift]
        removePaneMenuItem.target = self
        viewMenu.addItem(removePaneMenuItem)

        let createPaneTabMenuItem = NSMenuItem(
            title: "New Pane Tab",
            action: #selector(createPaneTabFromMenu(_:)),
            keyEquivalent: "t"
        )
        createPaneTabMenuItem.keyEquivalentModifierMask = [.command]
        createPaneTabMenuItem.target = self
        viewMenu.addItem(createPaneTabMenuItem)

        let closePaneTabMenuItem = NSMenuItem(
            title: "Close Pane Tab",
            action: #selector(closePaneTabFromMenu(_:)),
            keyEquivalent: "w"
        )
        closePaneTabMenuItem.keyEquivalentModifierMask = [.command]
        closePaneTabMenuItem.target = self
        viewMenu.addItem(closePaneTabMenuItem)

        let nextPaneTabMenuItem = NSMenuItem(
            title: "Next Pane Tab",
            action: #selector(focusNextPaneTabFromMenu(_:)),
            keyEquivalent: "\t"
        )
        nextPaneTabMenuItem.keyEquivalentModifierMask = [.control]
        nextPaneTabMenuItem.target = self
        viewMenu.addItem(nextPaneTabMenuItem)

        let nextPaneMenuItem = NSMenuItem(
            title: "Next Pane",
            action: #selector(focusNextPaneFromMenu(_:)),
            keyEquivalent: "\t"
        )
        nextPaneMenuItem.keyEquivalentModifierMask = [.control, .shift]
        nextPaneMenuItem.target = self
        viewMenu.addItem(nextPaneMenuItem)

        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        NSApplication.shared.mainMenu = mainMenu
        self.newWorkspaceMenuItem = newWorkspaceMenuItem
        self.renameWorkspaceMenuItem = renameWorkspaceMenuItem
        self.deleteWorkspaceMenuItem = deleteWorkspaceMenuItem
        self.toggleSidebarMenuItem = toggleSidebarMenuItem
        self.installCLIMenuItem = installCLIMenuItem
        self.previousWorkspaceMenuItem = previousWorkspaceMenuItem
        self.moveWorkspaceUpMenuItem = moveWorkspaceUpMenuItem
        self.moveWorkspaceDownMenuItem = moveWorkspaceDownMenuItem
        self.workspaceJumpMenuItems = workspaceJumpMenuItems
        self.splitRightMenuItem = splitRightMenuItem
        self.splitDownMenuItem = splitDownMenuItem
        self.removePaneMenuItem = removePaneMenuItem
        self.createPaneTabMenuItem = createPaneTabMenuItem
        self.closePaneTabMenuItem = closePaneTabMenuItem
        self.nextPaneTabMenuItem = nextPaneTabMenuItem
        self.nextPaneMenuItem = nextPaneMenuItem
    }

    private func refreshMenuValidation() {
        newWorkspaceMenuItem?.isEnabled = workspaceController.activeWorkspace() != nil
        renameWorkspaceMenuItem?.isEnabled = workspaceController.canRenameActiveWorkspace()
        deleteWorkspaceMenuItem?.isEnabled = workspaceController.canDeleteActiveWorkspace()
        installCLIMenuItem?.isEnabled = bundledCLIExecutablePath().flatMap(FileManager.default.isExecutableFile(atPath:)) ?? false
        let hasWorkspace = workspaceController.activeWorkspace() != nil
        toggleSidebarMenuItem?.isEnabled = hasWorkspace
        previousWorkspaceMenuItem?.isEnabled = workspaceController.canFocusPreviousWorkspace()
        moveWorkspaceUpMenuItem?.isEnabled = workspaceController.canMoveActiveWorkspaceUp()
        moveWorkspaceDownMenuItem?.isEnabled = workspaceController.canMoveActiveWorkspaceDown()
        let workspaceCount = workspaceController.listWorkspaces().count
        for (index, item) in workspaceJumpMenuItems.enumerated() {
            item.isEnabled = index < workspaceCount
        }
        splitRightMenuItem?.isEnabled = hasWorkspace
        splitDownMenuItem?.isEnabled = hasWorkspace
        removePaneMenuItem?.isEnabled = workspaceController.canRemoveActivePane()
        createPaneTabMenuItem?.isEnabled = hasWorkspace
        closePaneTabMenuItem?.isEnabled = workspaceController.canClosePaneTab()
        nextPaneTabMenuItem?.isEnabled = workspaceController.canFocusPaneTab()
        nextPaneMenuItem?.isEnabled = workspaceController.canFocusPane()
    }

    private func restoreInitialWorkspace() throws -> Workspace {
        if let snapshot = workspacePersistenceStore.load() {
            do {
                if let restoredWorkspace = try workspaceController.restorePersistedState(snapshot) {
                    persistWorkspaceState()
                    return restoredWorkspace
            }
        } catch {
            fputs("warning: failed to restore persisted workspace state: \(error)\n", stderr)
        }
    }

        let workspace = try workspaceController.createWorkspace()
        persistWorkspaceState()
        return workspace
    }

    private func persistWorkspaceState() {
        workspacePersistenceStore.save(workspaceController.persistenceSnapshot())
    }

    private func bundledCLIExecutablePath() -> String? {
        let cliURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent("omux", isDirectory: false)
        return cliURL.path
    }

    private func presentAlert(
        messageText: String,
        informativeText: String,
        style: NSAlert.Style = .informational
    ) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = messageText
        alert.informativeText = informativeText
        alert.addButton(withTitle: "OK")

        if let window = windowController?.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

}
