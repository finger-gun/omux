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
    private weak var previousPaneTabMenuItem: NSMenuItem?
    private weak var nextPaneMenuItem: NSMenuItem?
    private weak var previousPaneMenuItem: NSMenuItem?
    private weak var toggleSidebarMenuItem: NSMenuItem?
    private weak var installCLIMenuItem: NSMenuItem?
    private weak var previousWorkspaceMenuItem: NSMenuItem?
    private weak var moveWorkspaceUpMenuItem: NSMenuItem?
    private weak var moveWorkspaceDownMenuItem: NSMenuItem?
    private var workspaceJumpMenuItems: [NSMenuItem] = []
    private var keyBindingRegistry: OpenMUXKeyBindingRegistry
    private let autoCheckUpdate: Bool
    private let cliInstallStatusResolver = OmuxCLIInstallStatusResolver()

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
        self.autoCheckUpdate = preparedConfiguration.autoCheckUpdate
        self.keyBindingRegistry = preparedConfiguration.keyBindingRegistry
        OpenMUXShortcutClassifier.updateKeyBindings(preparedConfiguration.keyBindingRegistry)
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
            configurationCoordinator.onKeyBindingsChange = { [weak self] registry in
                self?.applyKeyBindings(registry)
            }
            configurationCoordinator.onDiagnosticsChange = { diagnostics in
                diagnostics.forEach { diagnostic in
                    let prefix = diagnostic.severity == .warning ? "warning" : "error"
                    fputs("\(prefix): \(diagnostic.message)\n", stderr)
                }
            }
            refreshMenuValidation()
            try controlPlaneService.start()
            if autoCheckUpdate {
                let updateChecker = OpenMUXUpdateAvailabilityChecker(controller: workspaceController)
                Task { @MainActor in
                    await updateChecker.checkIfDue()
                }
            }
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

    @objc private func focusPreviousPaneTabFromMenu(_ sender: Any?) {
        _ = sender
        _ = workspaceController.focusPreviousPaneTab()
        refreshMenuValidation()
    }

    @objc private func focusNextPaneFromMenu(_ sender: Any?) {
        _ = sender
        _ = workspaceController.focusNextPane()
        refreshMenuValidation()
    }

    @objc private func focusPreviousPaneFromMenu(_ sender: Any?) {
        _ = sender
        _ = workspaceController.focusPreviousPane()
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
            refreshMenuValidation()
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

    func configureMenus() {
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

        let workspaceMenuItem = NSMenuItem()
        let workspaceMenu = NSMenu(title: "Workspace")

        let newWorkspaceMenuItem = NSMenuItem(
            title: "New Workspace",
            action: #selector(createWorkspaceFromMenu(_:)),
            keyEquivalent: ""
        )
        newWorkspaceMenuItem.target = self
        workspaceMenu.addItem(newWorkspaceMenuItem)

        let deleteWorkspaceMenuItem = NSMenuItem(
            title: "Delete Workspace",
            action: #selector(deleteWorkspaceFromMenu(_:)),
            keyEquivalent: ""
        )
        deleteWorkspaceMenuItem.target = self
        workspaceMenu.addItem(deleteWorkspaceMenuItem)

        let renameWorkspaceMenuItem = NSMenuItem(
            title: "Rename Workspace…",
            action: #selector(renameWorkspaceFromMenu(_:)),
            keyEquivalent: ""
        )
        renameWorkspaceMenuItem.target = self
        workspaceMenu.addItem(renameWorkspaceMenuItem)
        workspaceMenu.addItem(.separator())

        let previousWorkspaceMenuItem = NSMenuItem(
            title: "Previous Workspace",
            action: #selector(focusPreviousWorkspaceFromMenu(_:)),
            keyEquivalent: ""
        )
        previousWorkspaceMenuItem.target = self
        workspaceMenu.addItem(previousWorkspaceMenuItem)

        let moveWorkspaceUpMenuItem = NSMenuItem(
            title: "Move Workspace Up",
            action: #selector(moveWorkspaceUpFromMenu(_:)),
            keyEquivalent: ""
        )
        moveWorkspaceUpMenuItem.target = self
        workspaceMenu.addItem(moveWorkspaceUpMenuItem)

        let moveWorkspaceDownMenuItem = NSMenuItem(
            title: "Move Workspace Down",
            action: #selector(moveWorkspaceDownFromMenu(_:)),
            keyEquivalent: ""
        )
        moveWorkspaceDownMenuItem.target = self
        workspaceMenu.addItem(moveWorkspaceDownMenuItem)
        workspaceMenu.addItem(.separator())

        var workspaceJumpMenuItems: [NSMenuItem] = []
        for index in 0..<9 {
            let item = NSMenuItem(
                title: "Go to Workspace \(index + 1)",
                action: #selector(focusNumberedWorkspaceFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = index
            workspaceMenu.addItem(item)
            workspaceJumpMenuItems.append(item)
        }

        workspaceMenuItem.submenu = workspaceMenu
        mainMenu.addItem(workspaceMenuItem)

        let paneMenuItem = NSMenuItem()
        let paneMenu = NSMenu(title: "Pane")

        let splitRightMenuItem = NSMenuItem(
            title: "Split Right",
            action: #selector(splitPaneRightFromMenu(_:)),
            keyEquivalent: ""
        )
        splitRightMenuItem.target = self
        paneMenu.addItem(splitRightMenuItem)

        let splitDownMenuItem = NSMenuItem(
            title: "Split Down",
            action: #selector(splitPaneDownFromMenu(_:)),
            keyEquivalent: ""
        )
        splitDownMenuItem.target = self
        paneMenu.addItem(splitDownMenuItem)

        let removePaneMenuItem = NSMenuItem(
            title: "Remove Active Pane",
            action: #selector(removeActivePaneFromMenu(_:)),
            keyEquivalent: ""
        )
        removePaneMenuItem.target = self
        paneMenu.addItem(removePaneMenuItem)
        paneMenu.addItem(.separator())

        let createPaneTabMenuItem = NSMenuItem(
            title: "New Pane Tab",
            action: #selector(createPaneTabFromMenu(_:)),
            keyEquivalent: ""
        )
        createPaneTabMenuItem.target = self
        paneMenu.addItem(createPaneTabMenuItem)

        let closePaneTabMenuItem = NSMenuItem(
            title: "Close Pane Tab",
            action: #selector(closePaneTabFromMenu(_:)),
            keyEquivalent: ""
        )
        closePaneTabMenuItem.target = self
        paneMenu.addItem(closePaneTabMenuItem)

        let nextPaneTabMenuItem = NSMenuItem(
            title: "Next Pane Tab",
            action: #selector(focusNextPaneTabFromMenu(_:)),
            keyEquivalent: ""
        )
        nextPaneTabMenuItem.target = self
        paneMenu.addItem(nextPaneTabMenuItem)

        let previousPaneTabMenuItem = NSMenuItem(
            title: "Previous Pane Tab",
            action: #selector(focusPreviousPaneTabFromMenu(_:)),
            keyEquivalent: ""
        )
        previousPaneTabMenuItem.target = self
        paneMenu.addItem(previousPaneTabMenuItem)
        paneMenu.addItem(.separator())

        let nextPaneMenuItem = NSMenuItem(
            title: "Next Pane",
            action: #selector(focusNextPaneFromMenu(_:)),
            keyEquivalent: ""
        )
        nextPaneMenuItem.target = self
        paneMenu.addItem(nextPaneMenuItem)

        let previousPaneMenuItem = NSMenuItem(
            title: "Previous Pane",
            action: #selector(focusPreviousPaneFromMenu(_:)),
            keyEquivalent: ""
        )
        previousPaneMenuItem.target = self
        paneMenu.addItem(previousPaneMenuItem)

        paneMenuItem.submenu = paneMenu
        mainMenu.addItem(paneMenuItem)

        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")

        let toggleSidebarMenuItem = NSMenuItem(
            title: "Toggle Workspace Column",
            action: #selector(toggleSidebarFromMenu(_:)),
            keyEquivalent: ""
        )
        toggleSidebarMenuItem.target = self
        viewMenu.addItem(toggleSidebarMenuItem)

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
        self.previousPaneTabMenuItem = previousPaneTabMenuItem
        self.nextPaneMenuItem = nextPaneMenuItem
        self.previousPaneMenuItem = previousPaneMenuItem
        applyMenuKeyBindings()
    }

    func applyKeyBindings(_ registry: OpenMUXKeyBindingRegistry) {
        keyBindingRegistry = registry
        applyMenuKeyBindings()
    }

    private func refreshMenuValidation() {
        newWorkspaceMenuItem?.isEnabled = workspaceController.activeWorkspace() != nil
        renameWorkspaceMenuItem?.isEnabled = workspaceController.canRenameActiveWorkspace()
        deleteWorkspaceMenuItem?.isEnabled = workspaceController.canDeleteActiveWorkspace()
        let cliInstaller = OmuxCLIInstaller(executablePath: bundledCLIExecutablePath())
        let cliInstallStatus = cliInstallStatusResolver.status(
            bundledCLIPath: bundledCLIExecutablePath(),
            defaultInstallPath: cliInstaller.defaultUserInstallPath()
        )
        installCLIMenuItem?.title = cliInstallStatus.menuTitle
        installCLIMenuItem?.isEnabled = cliInstallStatus.isActionable
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
        previousPaneTabMenuItem?.isEnabled = workspaceController.canFocusPaneTab()
        nextPaneMenuItem?.isEnabled = workspaceController.canFocusPane()
        previousPaneMenuItem?.isEnabled = workspaceController.canFocusPane()
    }

    private func applyMenuKeyBindings() {
        setShortcut(for: newWorkspaceMenuItem, action: .workspaceCreate)
        setShortcut(for: deleteWorkspaceMenuItem, action: .workspaceClose)
        setShortcut(for: toggleSidebarMenuItem, action: .sidebarToggle)
        setShortcut(for: previousWorkspaceMenuItem, action: .workspacePrevious)
        setShortcut(for: moveWorkspaceUpMenuItem, action: .workspaceMoveUp)
        setShortcut(for: moveWorkspaceDownMenuItem, action: .workspaceMoveDown)
        for (index, item) in workspaceJumpMenuItems.enumerated() {
            guard let action = OpenMUXKeyBindingAction.workspaceFocusAction(displayIndex: index) else {
                continue
            }
            setShortcut(for: item, action: action)
        }
        setShortcut(for: splitRightMenuItem, action: .paneSplitRight)
        setShortcut(for: splitDownMenuItem, action: .paneSplitDown)
        setShortcut(for: removePaneMenuItem, action: .paneRemove)
        setShortcut(for: createPaneTabMenuItem, action: .paneTabCreate)
        setShortcut(for: closePaneTabMenuItem, action: .paneTabClose)
        setShortcut(for: nextPaneTabMenuItem, action: .paneTabNext)
        setShortcut(for: previousPaneTabMenuItem, action: .paneTabPrevious)
        setShortcut(for: nextPaneMenuItem, action: .paneNext)
        setShortcut(for: previousPaneMenuItem, action: .panePrevious)
    }

    private func setShortcut(for item: NSMenuItem?, action: OpenMUXKeyBindingAction) {
        guard let item else {
            return
        }
        guard let chord = keyBindingRegistry.chord(for: action),
              let appKitShortcut = AppKitMenuShortcut(chord: chord) else {
            item.keyEquivalent = ""
            item.keyEquivalentModifierMask = []
            return
        }
        item.keyEquivalent = appKitShortcut.keyEquivalent
        item.keyEquivalentModifierMask = appKitShortcut.modifiers
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

enum OmuxCLIInstallStatus: Equatable {
    case unavailable
    case missing
    case installed
    case repairNeeded

    var menuTitle: String {
        switch self {
        case .unavailable, .missing:
            return "Install omux CLI"
        case .installed:
            return "omux CLI Installed"
        case .repairNeeded:
            return "Repair omux CLI"
        }
    }

    var isActionable: Bool {
        switch self {
        case .missing, .repairNeeded:
            return true
        case .unavailable, .installed:
            return false
        }
    }
}

struct OmuxCLIInstallStatusResolver {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func status(bundledCLIPath: String?, defaultInstallPath: String) -> OmuxCLIInstallStatus {
        guard let bundledCLIPath,
              fileManager.isExecutableFile(atPath: bundledCLIPath)
        else {
            return .unavailable
        }

        let bundledCLIURL = URL(fileURLWithPath: bundledCLIPath, isDirectory: false).standardizedFileURL
        let installURL = URL(fileURLWithPath: defaultInstallPath, isDirectory: false).standardizedFileURL
        if let destination = try? fileManager.destinationOfSymbolicLink(atPath: installURL.path) {
            let destinationURL: URL
            if destination.hasPrefix("/") {
                destinationURL = URL(fileURLWithPath: destination, isDirectory: false)
            } else {
                destinationURL = installURL.deletingLastPathComponent().appendingPathComponent(destination, isDirectory: false)
            }
            return destinationURL.standardizedFileURL.path == bundledCLIURL.path ? .installed : .repairNeeded
        }

        if fileManager.fileExists(atPath: installURL.path) {
            return .repairNeeded
        }

        return .missing
    }
}

private struct AppKitMenuShortcut {
    let keyEquivalent: String
    let modifiers: NSEvent.ModifierFlags

    init?(chord: OpenMUXKeyChord) {
        switch chord.key {
        case "tab":
            keyEquivalent = "\t"
        case "backspace":
            keyEquivalent = "\u{8}"
        case "up":
            keyEquivalent = String(UnicodeScalar(NSUpArrowFunctionKey)!)
        case "down":
            keyEquivalent = String(UnicodeScalar(NSDownArrowFunctionKey)!)
        default:
            keyEquivalent = chord.key
        }

        var modifiers: NSEvent.ModifierFlags = []
        if chord.modifiers.containsCommand {
            modifiers.insert(.command)
        }
        if chord.modifiers.appShellContainsControl {
            modifiers.insert(.control)
        }
        if chord.modifiers.appShellContainsShift {
            modifiers.insert(.shift)
        }
        self.modifiers = modifiers
    }
}

private extension OpenMUXKeyBindingAction {
    static func workspaceFocusAction(displayIndex: Int) -> OpenMUXKeyBindingAction? {
        switch displayIndex {
        case 0: return .workspaceFocus1
        case 1: return .workspaceFocus2
        case 2: return .workspaceFocus3
        case 3: return .workspaceFocus4
        case 4: return .workspaceFocus5
        case 5: return .workspaceFocus6
        case 6: return .workspaceFocus7
        case 7: return .workspaceFocus8
        case 8: return .workspaceFocus9
        default: return nil
        }
    }
}

private extension KeyModifiers {
    var appShellContainsShift: Bool {
        intersection([.leftShift, .rightShift]).isEmpty == false
    }

    var appShellContainsControl: Bool {
        intersection([.leftControl, .rightControl]).isEmpty == false
    }
}
