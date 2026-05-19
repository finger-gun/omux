import AppKit
import Foundation
import OmuxControlPlane
import OmuxConfig
import OmuxCore
import OmuxHooks
import OmuxTerminalBridge
import OmuxTheme
import OmuxVault

@MainActor
public final class OpenMUXAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let workspaceController: WorkspaceController
    private let controlPlaneService: OpenMUXControlPlaneService
    private let vaultStore: VaultStore?
    private let extensionPaneActionService: ExtensionPaneActionService
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
    private weak var createWorktreePaneTabMenuItem: NSMenuItem?
    private weak var closePaneTabMenuItem: NSMenuItem?
    private weak var nextPaneTabMenuItem: NSMenuItem?
    private weak var previousPaneTabMenuItem: NSMenuItem?
    private weak var nextPaneMenuItem: NSMenuItem?
    private weak var previousPaneMenuItem: NSMenuItem?
    private weak var equalizeSplitsMenuItem: NSMenuItem?
    private weak var resizeSplitUpMenuItem: NSMenuItem?
    private weak var resizeSplitDownMenuItem: NSMenuItem?
    private weak var resizeSplitLeftMenuItem: NSMenuItem?
    private weak var resizeSplitRightMenuItem: NSMenuItem?
    private weak var agentSessionsMenuItem: NSMenuItem?
    private weak var openAgentSessionsMenuItem: NSMenuItem?
    private weak var searchAgentSessionsMenuItem: NSMenuItem?
    private weak var reindexAgentSessionsMenuItem: NSMenuItem?
    private weak var toggleSidebarMenuItem: NSMenuItem?
    private weak var toggleAgentSessionsMenuItem: NSMenuItem?
    private weak var commandPaletteWorkspaceMenuItem: NSMenuItem?
    private weak var commandPaletteCommandMenuItem: NSMenuItem?
    private weak var findInPaneMenuItem: NSMenuItem?
    private weak var installCLIMenuItem: NSMenuItem?
    private weak var previousWorkspaceMenuItem: NSMenuItem?
    private weak var moveWorkspaceUpMenuItem: NSMenuItem?
    private weak var moveWorkspaceDownMenuItem: NSMenuItem?
    private var workspaceJumpMenuItems: [NSMenuItem] = []
    private var keyBindingRegistry: OpenMUXKeyBindingRegistry
    private var scrollbackAutosaveTask: Task<Void, Never>?
    private lazy var layoutPersistenceCoordinator = WorkspaceLayoutPersistenceCoordinator { [weak self] in
        self?.persistWorkspaceLayoutStateNow()
    }
    private let autoCheckUpdate: Bool
    private var vaultConfiguration: VaultConfiguration
    private let cliInstallStatusResolver = OmuxCLIInstallStatusResolver()
    private let pluginMenuContributionProvider: () -> [PluginMenuContribution]

    public override init() {
        self.pluginMenuContributionProvider = {
            PluginMenuContributionRegistry().contributions()
        }
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
            defaultWorkspaceRootPath: preparedConfiguration.defaultWorkspaceRootPath,
            persistedScrollback: preparedConfiguration.persistedScrollback,
            paneConfiguration: preparedConfiguration.panes,
            markdownPreviewConfiguration: preparedConfiguration.markdownPreview,
            aiStatusConfiguration: preparedConfiguration.aiStatus,
            scrollbackReplayStore: ScrollbackReplayStore(directoryURL: Self.appReplayDirectory()),
            scrollbackReplayWrapperStore: ScrollbackReplayWrapperStore(directoryURL: Self.appReplayDirectory())
        )
        self.workspaceController = workspaceController
        let vaultStore: VaultStore?
        do {
            vaultStore = try VaultStore(configuration: preparedConfiguration.agentSessions)
        } catch {
            fputs("error: failed to initialize Agent Sessions store; Agent Sessions disabled for this session. configuration=\(preparedConfiguration.agentSessions), error=\(error)\n", stderr)
            vaultStore = nil
        }
        self.vaultStore = vaultStore
        let extensionPaneActionService = ExtensionPaneActionService(controller: workspaceController)
        self.extensionPaneActionService = extensionPaneActionService
        self.configurationCoordinator = OpenMUXConfigurationCoordinator(
            bridge: bridge,
            initialState: preparedConfiguration
        )
        self.controlPlaneService = OpenMUXControlPlaneService(
            controller: workspaceController,
            configurationCoordinator: configurationCoordinator,
            extensionPaneActionService: extensionPaneActionService,
            vaultStore: vaultStore
        )
        self.workspacePersistenceStore = WorkspacePersistenceStore.shared
        self.initialTheme = preparedConfiguration.theme
        self.autoCheckUpdate = preparedConfiguration.autoCheckUpdate
        self.vaultConfiguration = preparedConfiguration.agentSessions
        self.keyBindingRegistry = preparedConfiguration.keyBindingRegistry
        OpenMUXShortcutClassifier.updateKeyBindings(preparedConfiguration.keyBindingRegistry)
        super.init()
    }

    private let initialTheme: WorkspaceShellTheme

    public func applicationDidFinishLaunching(_ notification: Notification) {
        _ = notification
        configureMenus()
        workspaceController.onChange = { [weak self] workspace in
            self?.scheduleWorkspaceLayoutStatePersistence()
            Task { @MainActor in
                self?.windowController?.update(workspace: workspace)
                self?.refreshMenuValidation()
            }
        }

        do {
            let workspace = try restoreInitialWorkspace()
            let windowController = WorkspaceWindowController(
                workspace: workspace,
                controller: workspaceController,
                initialTheme: initialTheme,
                initialPanes: configurationCoordinator.paneConfiguration(),
                initialIcons: configurationCoordinator.iconConfiguration(),
                vaultStore: self.vaultStore,
                vaultConfiguration: vaultConfiguration,
                onClosePaneTab: { [weak self] paneID in
                    self?.closePaneTabWithWorktreePrompt(paneID: paneID)
                },
                onExtensionPaneAction: { [weak self] request in
                    self?.dispatchExtensionPaneAction(request)
                }
            )
            self.windowController = windowController
            controlPlaneService.agentSessionsUIHandler = { [weak self] action in
                guard let self, let windowController = self.windowController else {
                    return .object(["ok": .bool(false), "error": .string("window unavailable")])
                }
                switch action {
                case "open", "show":
                    windowController.setAgentSessionsVisibility(true)
                case "close", "hide":
                    windowController.setAgentSessionsVisibility(false)
                case "toggle":
                    windowController.toggleAgentSessionsVisibility()
                case "palette", "command-palette":
                    windowController.presentAgentSessionsPalette(keyBindings: self.keyBindingRegistry)
                default:
                    return .object(["ok": .bool(false), "error": .string("unsupported action")])
                }
                return .object(["ok": .bool(true), "action": .string(action)])
            }
            windowController.window?.delegate = self
            windowController.showWindow(self)
            if let window = windowController.window {
                window.center()
                window.makeKeyAndOrderFront(self)
            }
            NSApplication.shared.activate(ignoringOtherApps: true)
            configurationCoordinator.onThemeChange = { [weak self] theme in
                self?.windowController?.updateTheme(theme)
            }
            windowController.themeCommitHandler = { [weak self] identifier in
                self?.configurationCoordinator.setTheme(identifier: identifier)
            }
            configurationCoordinator.onWorkspaceDefaultRootChange = { [weak self] path in
                self?.workspaceController.updateDefaultWorkspaceRootPath(path)
            }
            configurationCoordinator.onPersistedScrollbackChange = { [weak self] persistedScrollback in
                self?.workspaceController.updatePersistedScrollback(persistedScrollback)
            }
            configurationCoordinator.onPaneConfigurationChange = { [weak self] panes in
                self?.workspaceController.updatePaneConfiguration(panes)
                self?.windowController?.updatePanes(panes)
            }
            configurationCoordinator.onIconConfigurationChange = { [weak self] icons in
                self?.windowController?.updateIcons(icons)
            }
            configurationCoordinator.onMarkdownPreviewConfigurationChange = { [weak self] configuration in
                self?.workspaceController.updateMarkdownPreviewConfiguration(configuration)
            }
            configurationCoordinator.onAIStatusConfigurationChange = { [weak self] configuration in
                self?.workspaceController.updateAIStatusConfiguration(configuration)
            }
            configurationCoordinator.onAgentSessionsConfigurationChange = { [weak self] configuration in
                self?.vaultConfiguration = configuration
                DispatchQueue.main.async { [weak self] in
                    self?.refreshMenuValidation()
                    NSApp.mainMenu?.update()
                }
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
            startScrollbackAutosave()
            NSWorkspace.shared.notificationCenter.addObserver(
                self,
                selector: #selector(workspaceWillPowerOff),
                name: NSWorkspace.willPowerOffNotification,
                object: nil
            )
            try controlPlaneService.start()
            if vaultConfiguration.enabled && vaultConfiguration.indexOnLaunch, let vaultStore = self.vaultStore {
                Task { @MainActor [weak self, vaultStore] in
                    await self?.reindexAgentSessionsIncrementally(vaultStore: vaultStore)
                }
            }
            if autoCheckUpdate {
                let updateChecker = OpenMUXUpdateAvailabilityChecker(controller: workspaceController)
                Task { @MainActor in
                    await updateChecker.check()
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
        persistWorkspaceStateIncludingScrollback()
        return .terminateNow
    }

    public func applicationWillTerminate(_ notification: Notification) {
        _ = notification
        scrollbackAutosaveTask?.cancel()
        scrollbackAutosaveTask = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        persistWorkspaceStateIncludingScrollback()
        controlPlaneService.stop()
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        _ = sender
        persistWorkspaceStateIncludingScrollback()
        return true
    }

    private func dispatchExtensionPaneAction(_ request: ExtensionPaneActionRequest) {
        let actionService = extensionPaneActionService
        Task.detached {
            do {
                _ = try actionService.dispatch(request)
            } catch {
                fputs("extension-pane action failed: \(error)\n", stderr)
            }
        }
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

    @objc private func createWorktreePaneTabFromMenu(_ sender: Any?) {
        _ = sender
        do {
            let workspace = try workspaceController.createPaneTab()
            do {
                let result = try workspaceController.runCommand(target: .focused, command: "omux worktree --clear")
                if result == nil {
                    // runCommand returned nil (no focused terminal target); close the orphaned tab.
                    if let paneID = workspace?.focusedPane?.id {
                        _ = try? workspaceController.closePane(paneID: paneID)
                    }
                    assertionFailure("Failed to inject worktree command: no focused terminal target")
                }
            } catch {
                // If we can't inject the command, close the tab we just opened to avoid leaving
                // an orphaned empty tab behind.
                if let paneID = workspace?.focusedPane?.id {
                    _ = try? workspaceController.closePane(paneID: paneID)
                }
                assertionFailure("Failed to inject worktree command: \(error)")
            }
            refreshMenuValidation()
        } catch {
            assertionFailure("Failed to create worktree pane tab: \(error)")
        }
    }

    @objc private func closePaneTabFromMenu(_ sender: Any?) {
        _ = sender
        closePaneTabWithWorktreePrompt()
    }

    private func closePaneTabWithWorktreePrompt(paneID: PaneID? = nil) {
        // Capture the working directory before closing (fast, no git I/O).
        let closeCandidate = workspaceController.paneTabCloseCandidate(paneID: paneID)
        do {
            if let paneID {
                _ = try workspaceController.closePane(paneID: paneID)
            } else {
                _ = try workspaceController.closePaneTab()
            }
            refreshMenuValidation()
        } catch {
            assertionFailure("Failed to close pane tab: \(error)")
            return
        }

        // After the close succeeds, check for a linked worktree off the main thread
        // so git I/O never blocks the UI.
        guard let closeCandidate else { return }
        let workingDirectory = closeCandidate.workingDirectory
        let excludedPaneID = closeCandidate.paneID
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let candidate = Self.linkedGitWorktreeOffMain(for: workingDirectory) else { return }
            // Re-check on the main thread now that we have the rootPath.
            await MainActor.run { [weak self] in
                guard let self else { return }
                let hasOther = self.workspaceController.hasOtherTerminalPane(
                    inside: candidate.rootPath,
                    excluding: excludedPaneID
                )
                if hasOther == false {
                    self.presentWorktreeRemovalPrompt(candidate)
                }
            }
        }
    }

    private struct WorktreeDeletionCandidate: Sendable {
        let rootPath: String
        let removalWorkingDirectory: String
    }

    private nonisolated static func linkedGitWorktreeOffMain(for workingDirectory: String) -> WorktreeDeletionCandidate? {
        guard let rootPath = gitOutputOffMain(["-C", workingDirectory, "rev-parse", "--show-toplevel"]) else {
            return nil
        }
        guard let gitDirectory = gitOutputOffMain(["-C", workingDirectory, "rev-parse", "--git-dir"]) else {
            return nil
        }
        guard let gitCommonDirectory = gitOutputOffMain(["-C", workingDirectory, "rev-parse", "--git-common-dir"]) else {
            return nil
        }

        let gitDirectoryURL = resolvedGitURL(gitDirectory, relativeTo: workingDirectory)
        let gitCommonDirectoryURL = resolvedGitURL(gitCommonDirectory, relativeTo: workingDirectory)
        guard gitDirectoryURL != gitCommonDirectoryURL else {
            return nil
        }

        let removalWorkingDirectory = gitCommonDirectoryURL.lastPathComponent == ".git"
            ? gitCommonDirectoryURL.deletingLastPathComponent().path
            : rootPath
        return WorktreeDeletionCandidate(
            rootPath: URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL.path,
            removalWorkingDirectory: removalWorkingDirectory
        )
    }

    private func presentWorktreeRemovalPrompt(_ candidate: WorktreeDeletionCandidate) {
        let alert = NSAlert()
        alert.messageText = "Delete Git Worktree?"
        alert.informativeText = "The last OpenMUX tab using this worktree was closed:\n\n\(candidate.rootPath)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete Worktree")
        alert.addButton(withTitle: "Keep")

        let removeWorktree = { [weak self] in
            self?.removeGitWorktreeAsync(candidate)
        }

        if let window = windowController?.window {
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn {
                    removeWorktree()
                }
            }
        } else if alert.runModal() == .alertFirstButtonReturn {
            removeWorktree()
        }
    }

    private func removeGitWorktreeAsync(_ candidate: WorktreeDeletionCandidate) {
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = Self.runGitOffMain(arguments: ["-C", candidate.removalWorkingDirectory, "worktree", "remove", candidate.rootPath])
            await MainActor.run { [weak self] in
                guard let self, result.terminationStatus != 0 else { return }
                self.presentAlert(
                    messageText: "Delete Worktree Failed",
                    informativeText: result.message ?? "git worktree remove exited with status \(result.terminationStatus).",
                    style: .warning
                )
            }
        }
    }

    private nonisolated static func gitOutputOffMain(_ arguments: [String]) -> String? {
        let result = runGitOffMain(arguments: arguments)
        guard result.terminationStatus == 0 else {
            return nil
        }
        let output = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? nil : output
    }

    private nonisolated static func runGitOffMain(arguments: [String]) -> GitCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git", isDirectory: false)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return GitCommandResult(
                terminationStatus: 1,
                standardOutput: "",
                standardError: error.localizedDescription
            )
        }

        return GitCommandResult(
            terminationStatus: process.terminationStatus,
            standardOutput: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            standardError: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }

    private struct GitCommandResult: Sendable {
        let terminationStatus: Int32
        let standardOutput: String
        let standardError: String

        var message: String? {
            [standardError, standardOutput]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { $0.isEmpty == false }
        }
    }

    private nonisolated static func resolvedGitURL(_ path: String, relativeTo workingDirectory: String) -> URL {
        URL(
            fileURLWithPath: path,
            relativeTo: URL(fileURLWithPath: workingDirectory, isDirectory: true)
        ).standardizedFileURL
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

    @objc private func equalizeSplitsFromMenu(_ sender: Any?) {
        _ = sender
        _ = workspaceController.equalizeSplits()
        refreshMenuValidation()
    }

    @objc private func resizeSplitUpFromMenu(_ sender: Any?) {
        _ = sender
        _ = workspaceController.resizeSplit(.up)
        refreshMenuValidation()
    }

    @objc private func resizeSplitDownFromMenu(_ sender: Any?) {
        _ = sender
        _ = workspaceController.resizeSplit(.down)
        refreshMenuValidation()
    }

    @objc private func resizeSplitLeftFromMenu(_ sender: Any?) {
        _ = sender
        _ = workspaceController.resizeSplit(.left)
        refreshMenuValidation()
    }

    @objc private func resizeSplitRightFromMenu(_ sender: Any?) {
        _ = sender
        _ = workspaceController.resizeSplit(.right)
        refreshMenuValidation()
    }

    @objc private func toggleSidebarFromMenu(_ sender: Any?) {
        _ = sender
        windowController?.toggleSidebarVisibility()
    }

    @objc private func toggleAgentSessionsFromMenu(_ sender: Any?) {
        _ = sender
        windowController?.toggleAgentSessionsVisibility()
    }

    @objc private func openAgentSessionsFromMenu(_ sender: Any?) {
        _ = sender
        windowController?.setAgentSessionsVisibility(true)
    }

    @objc private func searchAgentSessionsFromMenu(_ sender: Any?) {
        _ = sender
        windowController?.presentAgentSessionsPalette(keyBindings: keyBindingRegistry)
    }

    @objc private func reindexAgentSessionsFromMenu(_ sender: Any?) {
        _ = sender
        guard vaultConfiguration.enabled, let vaultStore else {
            return
        }
        Task { @MainActor [weak self, vaultStore] in
            await self?.reindexAgentSessionsIncrementally(vaultStore: vaultStore)
        }
    }

    @MainActor
    private func reindexAgentSessionsIncrementally(vaultStore: VaultStore) async {
        for agent in prioritizedAgentSessionsAgents() {
            do {
                let warnings = try await vaultStore.reindex(agent: agent)
                for warning in warnings {
                    fputs("Agent Sessions warning: \(warning)\n", stderr)
                }
                windowController?.vaultIndexDidUpdate()
            } catch {
                fputs("Agent Sessions indexing failed for \(agent.rawValue): \(error)\n", stderr)
            }
        }
    }

    private func prioritizedAgentSessionsAgents() -> [VaultAgentKind] {
        let priority: [VaultAgentKind] = [.codex, .gemini, .copilot]
        let included = vaultConfiguration.includedAgents.filter { $0 != .custom }
        var result = priority.filter { included.contains($0) }
        result += included.filter { result.contains($0) == false }
        return result
    }

    @objc private func openWorkspaceCommandPaletteFromMenu(_ sender: Any?) {
        _ = sender
        windowController?.presentCommandPalette(initialQuery: "", keyBindings: keyBindingRegistry)
    }

    @objc private func openCommandPaletteFromMenu(_ sender: Any?) {
        _ = sender
        windowController?.presentCommandPalette(initialQuery: ">", keyBindings: keyBindingRegistry)
    }

    @objc private func findInPaneFromMenu(_ sender: Any?) {
        _ = sender
        windowController?.presentPaneFind()
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

    @objc private func openConfigFromMenu(_ sender: Any?) {
        _ = sender
        NSWorkspace.shared.open(OmuxConfigPaths.configFileURL)
    }

    @objc private func reloadConfigFromMenu(_ sender: Any?) {
        _ = sender
        _ = configurationCoordinator.reload()
        refreshMenuValidation()
    }

    @objc private func invokePluginMenuItem(_ sender: Any?) {
        guard let item = sender as? NSMenuItem,
              let contribution = item.representedObject as? PluginMenuContribution
        else {
            return
        }

        switch contribution.target {
        case .builtin(let identifier):
            switch identifier {
            case "config.open":
                NSWorkspace.shared.open(OmuxConfigPaths.configFileURL)
            case "config.reload":
                _ = configurationCoordinator.reload()
            default:
                return
            }
        case .plugin(_, let arguments, let executableURL):
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            process.environment = Self.pluginEnvironment(
                commandName: contribution.pluginID,
                executableURL: executableURL
            )
            do {
                try process.run()
            } catch {
                fputs("plugin menu item failed: \(error)\n", stderr)
            }
        }
        refreshMenuValidation()
    }

    private static func pluginEnvironment(commandName: String, executableURL: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment.merging([
            "OMUX_PLUGIN_COMMAND": commandName,
            "OMUX_PLUGIN_EXECUTABLE": executableURL.path,
            "OMUX_PLUGINS_DIR": executableURL.deletingLastPathComponent().path,
        ]) { current, _ in current }
        let existingPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = [
            existingPath,
            "\(NSHomeDirectory())/.local/bin",
            "\(NSHomeDirectory())/bin",
            "/Applications/OpenMUX.app/Contents/MacOS",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
        ].joined(separator: ":")
        if let bundledCLIURL = bundledCLIURL() {
            environment["OMUX_CLI"] = bundledCLIURL.path
        }
        return environment
    }

    private static func bundledCLIURL() -> URL? {
        let bundleURL = Bundle.main.bundleURL
        let candidates = [
            bundleURL.appendingPathComponent("Contents/MacOS/omux", isDirectory: false),
            URL(fileURLWithPath: "/Applications/OpenMUX.app/Contents/MacOS/omux", isDirectory: false),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    @discardableResult
    func configureMenus(assigningToApplication: Bool = true) -> NSMenu {
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
        editMenu.addItem(.separator())
        let findInPaneMenuItem = NSMenuItem(
            title: "Find in Pane…",
            action: #selector(findInPaneFromMenu(_:)),
            keyEquivalent: ""
        )
        findInPaneMenuItem.target = self
        editMenu.addItem(findInPaneMenuItem)
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let configurationMenuItem = NSMenuItem()
        let configurationMenu = NSMenu(title: "Configuration")
        let openConfigMenuItem = NSMenuItem(
            title: "Open",
            action: #selector(openConfigFromMenu(_:)),
            keyEquivalent: ""
        )
        openConfigMenuItem.target = self
        configurationMenu.addItem(openConfigMenuItem)
        let reloadConfigMenuItem = NSMenuItem(
            title: "Reload",
            action: #selector(reloadConfigFromMenu(_:)),
            keyEquivalent: ""
        )
        reloadConfigMenuItem.target = self
        configurationMenu.addItem(reloadConfigMenuItem)

        let pluginMenuContributions = pluginMenuContributionProvider()
            .filter { $0.location == "Configuration" }
        if pluginMenuContributions.isEmpty == false {
            configurationMenu.addItem(.separator())
            for contribution in pluginMenuContributions {
                let item = NSMenuItem(
                    title: contribution.title,
                    action: #selector(invokePluginMenuItem(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = contribution
                configurationMenu.addItem(item)
            }
        }

        configurationMenuItem.submenu = configurationMenu
        mainMenu.addItem(configurationMenuItem)

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

        let createWorktreePaneTabMenuItem = NSMenuItem(
            title: "New Worktree Pane Tab…",
            action: #selector(createWorktreePaneTabFromMenu(_:)),
            keyEquivalent: ""
        )
        createWorktreePaneTabMenuItem.target = self
        paneMenu.addItem(createWorktreePaneTabMenuItem)

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
        paneMenu.addItem(.separator())

        let resizeSplitMenuItem = NSMenuItem(title: "Resize Split", action: nil, keyEquivalent: "")
        let resizeSplitMenu = NSMenu(title: "Resize Split")

        let equalizeSplitsMenuItem = NSMenuItem(
            title: "Equalize Splits",
            action: #selector(equalizeSplitsFromMenu(_:)),
            keyEquivalent: ""
        )
        equalizeSplitsMenuItem.target = self
        resizeSplitMenu.addItem(equalizeSplitsMenuItem)
        resizeSplitMenu.addItem(.separator())

        let resizeSplitUpMenuItem = NSMenuItem(
            title: "Move Divider Up",
            action: #selector(resizeSplitUpFromMenu(_:)),
            keyEquivalent: ""
        )
        resizeSplitUpMenuItem.target = self
        resizeSplitMenu.addItem(resizeSplitUpMenuItem)

        let resizeSplitDownMenuItem = NSMenuItem(
            title: "Move Divider Down",
            action: #selector(resizeSplitDownFromMenu(_:)),
            keyEquivalent: ""
        )
        resizeSplitDownMenuItem.target = self
        resizeSplitMenu.addItem(resizeSplitDownMenuItem)

        let resizeSplitLeftMenuItem = NSMenuItem(
            title: "Move Divider Left",
            action: #selector(resizeSplitLeftFromMenu(_:)),
            keyEquivalent: ""
        )
        resizeSplitLeftMenuItem.target = self
        resizeSplitMenu.addItem(resizeSplitLeftMenuItem)

        let resizeSplitRightMenuItem = NSMenuItem(
            title: "Move Divider Right",
            action: #selector(resizeSplitRightFromMenu(_:)),
            keyEquivalent: ""
        )
        resizeSplitRightMenuItem.target = self
        resizeSplitMenu.addItem(resizeSplitRightMenuItem)

        resizeSplitMenuItem.submenu = resizeSplitMenu
        paneMenu.addItem(resizeSplitMenuItem)

        paneMenuItem.submenu = paneMenu
        mainMenu.addItem(paneMenuItem)

        let agentSessionsMenuItem = NSMenuItem()
        let agentSessionsMenu = NSMenu(title: "Agents")

        let openAgentSessionsMenuItem = NSMenuItem(
            title: "Show Agent Sessions",
            action: #selector(openAgentSessionsFromMenu(_:)),
            keyEquivalent: ""
        )
        openAgentSessionsMenuItem.target = self
        agentSessionsMenu.addItem(openAgentSessionsMenuItem)

        let searchAgentSessionsMenuItem = NSMenuItem(
            title: "Search Agent Sessions…",
            action: #selector(searchAgentSessionsFromMenu(_:)),
            keyEquivalent: ""
        )
        searchAgentSessionsMenuItem.target = self
        agentSessionsMenu.addItem(searchAgentSessionsMenuItem)

        agentSessionsMenu.addItem(.separator())

        let reindexAgentSessionsMenuItem = NSMenuItem(
            title: "Reindex Agent Sessions",
            action: #selector(reindexAgentSessionsFromMenu(_:)),
            keyEquivalent: ""
        )
        reindexAgentSessionsMenuItem.target = self
        agentSessionsMenu.addItem(reindexAgentSessionsMenuItem)

        agentSessionsMenuItem.submenu = agentSessionsMenu
        mainMenu.addItem(agentSessionsMenuItem)

        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")

        let toggleSidebarMenuItem = NSMenuItem(
            title: "Toggle Workspace Column",
            action: #selector(toggleSidebarFromMenu(_:)),
            keyEquivalent: ""
        )
        toggleSidebarMenuItem.target = self
        viewMenu.addItem(toggleSidebarMenuItem)

        let toggleAgentSessionsMenuItem = NSMenuItem(
            title: "Toggle Agent Sessions",
            action: #selector(toggleAgentSessionsFromMenu(_:)),
            keyEquivalent: ""
        )
        toggleAgentSessionsMenuItem.target = self
        viewMenu.addItem(toggleAgentSessionsMenuItem)

        viewMenu.addItem(.separator())

        let commandPaletteWorkspaceMenuItem = NSMenuItem(
            title: "Command Palette",
            action: #selector(openWorkspaceCommandPaletteFromMenu(_:)),
            keyEquivalent: ""
        )
        commandPaletteWorkspaceMenuItem.target = self
        viewMenu.addItem(commandPaletteWorkspaceMenuItem)

        let commandPaletteCommandMenuItem = NSMenuItem(
            title: "Command Palette Commands",
            action: #selector(openCommandPaletteFromMenu(_:)),
            keyEquivalent: ""
        )
        commandPaletteCommandMenuItem.target = self
        viewMenu.addItem(commandPaletteCommandMenuItem)

        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        if assigningToApplication {
            NSApplication.shared.mainMenu = mainMenu
        }
        self.newWorkspaceMenuItem = newWorkspaceMenuItem
        self.renameWorkspaceMenuItem = renameWorkspaceMenuItem
        self.deleteWorkspaceMenuItem = deleteWorkspaceMenuItem
        self.toggleSidebarMenuItem = toggleSidebarMenuItem
        self.toggleAgentSessionsMenuItem = toggleAgentSessionsMenuItem
        self.commandPaletteWorkspaceMenuItem = commandPaletteWorkspaceMenuItem
        self.commandPaletteCommandMenuItem = commandPaletteCommandMenuItem
        self.findInPaneMenuItem = findInPaneMenuItem
        self.installCLIMenuItem = installCLIMenuItem
        self.previousWorkspaceMenuItem = previousWorkspaceMenuItem
        self.moveWorkspaceUpMenuItem = moveWorkspaceUpMenuItem
        self.moveWorkspaceDownMenuItem = moveWorkspaceDownMenuItem
        self.workspaceJumpMenuItems = workspaceJumpMenuItems
        self.splitRightMenuItem = splitRightMenuItem
        self.splitDownMenuItem = splitDownMenuItem
        self.removePaneMenuItem = removePaneMenuItem
        self.createPaneTabMenuItem = createPaneTabMenuItem
        self.createWorktreePaneTabMenuItem = createWorktreePaneTabMenuItem
        self.closePaneTabMenuItem = closePaneTabMenuItem
        self.nextPaneTabMenuItem = nextPaneTabMenuItem
        self.previousPaneTabMenuItem = previousPaneTabMenuItem
        self.nextPaneMenuItem = nextPaneMenuItem
        self.previousPaneMenuItem = previousPaneMenuItem
        self.equalizeSplitsMenuItem = equalizeSplitsMenuItem
        self.resizeSplitUpMenuItem = resizeSplitUpMenuItem
        self.resizeSplitDownMenuItem = resizeSplitDownMenuItem
        self.resizeSplitLeftMenuItem = resizeSplitLeftMenuItem
        self.resizeSplitRightMenuItem = resizeSplitRightMenuItem
        self.agentSessionsMenuItem = agentSessionsMenuItem
        self.openAgentSessionsMenuItem = openAgentSessionsMenuItem
        self.searchAgentSessionsMenuItem = searchAgentSessionsMenuItem
        self.reindexAgentSessionsMenuItem = reindexAgentSessionsMenuItem
        applyMenuKeyBindings()
        return mainMenu
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
        let agentSessionsMenuVisible = vaultConfiguration.enabled
        agentSessionsMenuItem?.isHidden = !agentSessionsMenuVisible
        openAgentSessionsMenuItem?.isEnabled = hasWorkspace && agentSessionsMenuVisible
        searchAgentSessionsMenuItem?.isEnabled = hasWorkspace && agentSessionsMenuVisible
        reindexAgentSessionsMenuItem?.isEnabled = hasWorkspace && agentSessionsMenuVisible && vaultStore != nil
        toggleSidebarMenuItem?.isEnabled = hasWorkspace
        toggleAgentSessionsMenuItem?.isHidden = !agentSessionsMenuVisible
        toggleAgentSessionsMenuItem?.isEnabled = hasWorkspace && agentSessionsMenuVisible
        commandPaletteWorkspaceMenuItem?.isEnabled = hasWorkspace
        commandPaletteCommandMenuItem?.isEnabled = hasWorkspace
        findInPaneMenuItem?.isEnabled = hasWorkspace
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
        createWorktreePaneTabMenuItem?.isEnabled = workspaceController.resolveTerminalTarget(.focused) != nil
        closePaneTabMenuItem?.isEnabled = workspaceController.canClosePaneTab()
        nextPaneTabMenuItem?.isEnabled = workspaceController.canFocusPaneTab()
        previousPaneTabMenuItem?.isEnabled = workspaceController.canFocusPaneTab()
        nextPaneMenuItem?.isEnabled = workspaceController.canFocusPane()
        previousPaneMenuItem?.isEnabled = workspaceController.canFocusPane()
        equalizeSplitsMenuItem?.isEnabled = workspaceController.canEqualizeSplits()
        resizeSplitUpMenuItem?.isEnabled = workspaceController.canResizeSplit(.up)
        resizeSplitDownMenuItem?.isEnabled = workspaceController.canResizeSplit(.down)
        resizeSplitLeftMenuItem?.isEnabled = workspaceController.canResizeSplit(.left)
        resizeSplitRightMenuItem?.isEnabled = workspaceController.canResizeSplit(.right)
    }

    private func applyMenuKeyBindings() {
        setShortcut(for: newWorkspaceMenuItem, action: .workspaceCreate)
        setShortcut(for: deleteWorkspaceMenuItem, action: .workspaceClose)
        setShortcut(for: toggleSidebarMenuItem, action: .sidebarToggle)
        setShortcut(for: toggleAgentSessionsMenuItem, action: .agentSessionsToggle)
        setShortcut(for: commandPaletteWorkspaceMenuItem, action: .commandPaletteWorkspace)
        setShortcut(for: commandPaletteCommandMenuItem, action: .commandPaletteCommand)
        setShortcut(for: findInPaneMenuItem, action: .paneFind)
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
        setShortcut(for: createWorktreePaneTabMenuItem, action: .paneTabCreateWorktree)
        setShortcut(for: closePaneTabMenuItem, action: .paneTabClose)
        setShortcut(for: nextPaneTabMenuItem, action: .paneTabNext)
        setShortcut(for: previousPaneTabMenuItem, action: .paneTabPrevious)
        setShortcut(for: nextPaneMenuItem, action: .paneNext)
        setShortcut(for: previousPaneMenuItem, action: .panePrevious)
        setShortcut(for: equalizeSplitsMenuItem, action: .paneResizeEqualize)
        setShortcut(for: resizeSplitUpMenuItem, action: .paneResizeUp)
        setShortcut(for: resizeSplitDownMenuItem, action: .paneResizeDown)
        setShortcut(for: resizeSplitLeftMenuItem, action: .paneResizeLeft)
        setShortcut(for: resizeSplitRightMenuItem, action: .paneResizeRight)
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
        if let snapshot = workspacePersistenceStore.load(scrollbackPayloadResolution: .initiallyVisible) {
            do {
                if let restoredWorkspace = try workspaceController.restorePersistedState(snapshot) {
                    return restoredWorkspace
            }
        } catch {
            fputs("warning: failed to restore persisted workspace state: \(error)\n", stderr)
        }
    }

        let workspace = try workspaceController.createWorkspace()
        persistWorkspaceLayoutStateNow()
        return workspace
    }

    private func scheduleWorkspaceLayoutStatePersistence() {
        layoutPersistenceCoordinator.scheduleLayoutSave()
    }

    private func flushWorkspaceLayoutStatePersistence() {
        layoutPersistenceCoordinator.flushLayoutSave()
    }

    private func persistWorkspaceLayoutStateNow() {
        workspacePersistenceStore.save(workspaceController.persistenceSnapshot(mode: .layoutOnly))
    }

    private func persistWorkspaceStateIncludingScrollback() {
        flushWorkspaceLayoutStatePersistence()
        workspacePersistenceStore.save(workspaceController.persistenceSnapshotForConfiguredPersistence())
    }

    private func startScrollbackAutosave() {
        guard scrollbackAutosaveTask == nil else {
            return
        }

        scrollbackAutosaveTask = Task { @MainActor [weak self] in
            while Task.isCancelled == false {
                try? await Task.sleep(nanoseconds: 120_000_000_000)
                guard Task.isCancelled == false else {
                    return
                }
                self?.persistWorkspaceStateIncludingScrollback()
            }
        }
    }

    @objc private func workspaceWillPowerOff(_ notification: Notification) {
        _ = notification
        persistWorkspaceStateIncludingScrollback()
    }

    private static func appReplayDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenMUX", isDirectory: true)
            .appendingPathComponent("Replay", isDirectory: true)
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
        case "left":
            keyEquivalent = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        case "right":
            keyEquivalent = String(UnicodeScalar(NSRightArrowFunctionKey)!)
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
