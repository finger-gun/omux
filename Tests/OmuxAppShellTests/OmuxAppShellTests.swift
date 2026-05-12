import AppKit
import OmuxConfig
import OmuxTheme
import Foundation
import XCTest
@testable import OmuxControlPlane
@testable import OmuxAppShell
@testable import OmuxCore
@testable import OmuxHooks
@testable import OmuxTerminalBridge

final class OmuxAppShellTests: XCTestCase {
    private enum TestUpdateError: Error {
        case unavailable
    }

    @MainActor
    private final class InMemorySidebarVisibilityStore: WorkspaceSidebarVisibilityStoring {
        var isSidebarVisible: Bool

        init(isSidebarVisible: Bool = true) {
            self.isSidebarVisible = isSidebarVisible
        }
    }

    private func requestControlMethod(
        _ method: ControlMethod,
        socketPath: String,
        params: RPCValue? = nil
    ) throws -> JSONRPCResponse {
        let requestFinished = expectation(description: "control-plane \(method.rawValue) request finished")
        let responseBox = LockedBox<JSONRPCResponse?>(nil)
        let errorBox = LockedBox<Error?>(nil)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let client = OmuxControlClient(socketPath: socketPath)
                responseBox.value = try client.request(method: method, params: params)
            } catch {
                errorBox.value = error
            }
            requestFinished.fulfill()
        }

        wait(for: [requestFinished], timeout: 3)

        if let error = errorBox.value {
            throw error
        }
        return try XCTUnwrap(responseBox.value)
    }

    private func versionFixture(version: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "\(version)\n".write(to: root.appendingPathComponent("VERSION"), atomically: true, encoding: .utf8)
        let executableURL = root.appendingPathComponent("bin/omux", isDirectory: false)
        try FileManager.default.createDirectory(at: executableURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: executableURL, atomically: true, encoding: .utf8)
        return root
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func shellSingleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func release(version: String) -> OpenMUXRelease {
        OpenMUXRelease(
            tagName: "v\(version)",
            version: OpenMUXSemanticVersion(parsing: version)!,
            assets: []
        )
    }

    private func targetPaneID(in response: JSONRPCResponse) -> PaneID? {
        guard case .object(let object)? = response.result,
              case .object(let target)? = object["target"],
              case .string(let paneID)? = target["paneID"]
        else {
            return nil
        }

        return PaneID(rawValue: paneID)
    }

    @MainActor
    func testApplicationMenuUsesScopeShortcutLadder() {
        let delegate = OpenMUXAppDelegate()
        let mainMenu = delegate.configureMenus(assigningToApplication: false)
        delegate.applyKeyBindings(.defaults)

        let menus = mainMenu.items
            .compactMap(\.submenu)
        let workspaceMenu = menus.first { $0.title == "Workspace" }
        let paneMenu = menus.first { $0.title == "Pane" }
        let viewMenu = menus.first { $0.title == "View" }
        let configurationMenu = menus.first { $0.title == "Configuration" }
        let resizeSplitMenu = paneMenu?.items.first { $0.title == "Resize Split" }?.submenu
        XCTAssertNotNil(workspaceMenu)
        XCTAssertNotNil(paneMenu)
        XCTAssertNotNil(viewMenu)
        XCTAssertNotNil(configurationMenu)
        XCTAssertNotNil(resizeSplitMenu)

        XCTAssertTrue(workspaceMenu?.items.containsShortcut(
            title: "New Workspace",
            key: "n",
            modifiers: [.command]
        ) ?? false)
        XCTAssertTrue(workspaceMenu?.items.containsShortcut(
            title: "Delete Workspace",
            key: "n",
            modifiers: [.command, .shift]
        ) ?? false)
        XCTAssertTrue(workspaceMenu?.items.containsShortcut(
            title: "Move Workspace Up",
            key: String(UnicodeScalar(NSUpArrowFunctionKey)!),
            modifiers: [.command, .control, .shift]
        ) ?? false)
        XCTAssertTrue(workspaceMenu?.items.containsShortcut(
            title: "Move Workspace Down",
            key: String(UnicodeScalar(NSDownArrowFunctionKey)!),
            modifiers: [.command, .control, .shift]
        ) ?? false)
        XCTAssertFalse(viewMenu?.items.containsShortcut(
            title: "New Workspace",
            key: "n",
            modifiers: [.command]
        ) ?? true)
        XCTAssertTrue(viewMenu?.items.containsShortcut(
            title: "Toggle Workspace Column",
            key: "b",
            modifiers: [.command]
        ) ?? false)
        XCTAssertTrue(viewMenu?.items.containsShortcut(
            title: "Command Palette",
            key: "p",
            modifiers: [.command]
        ) ?? false)
        XCTAssertTrue(viewMenu?.items.containsShortcut(
            title: "Command Palette Commands",
            key: "p",
            modifiers: [.command, .shift]
        ) ?? false)
        XCTAssertFalse(viewMenu?.items.containsShortcut(
            title: "New Pane",
            key: "t",
            modifiers: [.command, .shift]
        ) ?? true)
        XCTAssertFalse(viewMenu?.items.containsShortcut(
            key: "t",
            modifiers: [.command, .shift]
        ) ?? true)
        XCTAssertTrue(paneMenu?.items.containsShortcut(
            title: "Remove Active Pane",
            key: "w",
            modifiers: [.command, .shift]
        ) ?? false)
        XCTAssertFalse(paneMenu?.items.containsShortcut(
            title: "Remove Active Pane",
            key: "\u{8}",
            modifiers: [.command, .shift]
        ) ?? true)
        XCTAssertFalse(paneMenu?.items.containsShortcut(
            key: "\u{8}",
            modifiers: [.command, .shift]
        ) ?? true)
        XCTAssertTrue(paneMenu?.items.containsShortcut(
            title: "New Pane Tab",
            key: "t",
            modifiers: [.command]
        ) ?? false)
        XCTAssertTrue(paneMenu?.items.containsShortcut(
            title: "Close Pane Tab",
            key: "w",
            modifiers: [.command]
        ) ?? false)
        XCTAssertTrue(resizeSplitMenu?.items.containsShortcut(
            title: "Equalize Splits",
            key: "=",
            modifiers: [.command, .control]
        ) ?? false)
        XCTAssertTrue(resizeSplitMenu?.items.containsShortcut(
            title: "Move Divider Up",
            key: String(UnicodeScalar(NSUpArrowFunctionKey)!),
            modifiers: [.command, .control]
        ) ?? false)
        XCTAssertTrue(resizeSplitMenu?.items.containsShortcut(
            title: "Move Divider Down",
            key: String(UnicodeScalar(NSDownArrowFunctionKey)!),
            modifiers: [.command, .control]
        ) ?? false)
        XCTAssertTrue(resizeSplitMenu?.items.containsShortcut(
            title: "Move Divider Left",
            key: String(UnicodeScalar(NSLeftArrowFunctionKey)!),
            modifiers: [.command, .control]
        ) ?? false)
        XCTAssertTrue(resizeSplitMenu?.items.containsShortcut(
            title: "Move Divider Right",
            key: String(UnicodeScalar(NSRightArrowFunctionKey)!),
            modifiers: [.command, .control]
        ) ?? false)
        XCTAssertNotNil(configurationMenu?.items.first { $0.title == "Open" })
        XCTAssertNotNil(configurationMenu?.items.first { $0.title == "Reload" })
    }

    func testPluginMenuContributionRegistryParsesMenuMetadata() throws {
        let root = try temporaryDirectory()
        let pluginsDirectory = root.appendingPathComponent("plugins", isDirectory: true)
        let pluginDirectory = pluginsDirectory.appendingPathComponent("settings-ui", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
        let executableURL = pluginDirectory.appendingPathComponent("plugin")
        try "#!/bin/sh\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        try """
        schema = 1
        id = "settings-ui"
        name = "Settings UI"
        description = "Edit OpenMUX settings."
        version = "0.1.0"
        kind = "plugin"

        [plugin]
        command = "settings-ui"
        entrypoint = "plugin"

        [menu.configuration.open-settings]
        location = "Configuration"
        title = "Open Settings"
        command = "settings-ui"
        arguments = []

        [menu.configuration.reload]
        location = "Configuration"
        title = "Reload Config"
        builtin = "config.reload"
        """.write(to: pluginDirectory.appendingPathComponent("omux-plugin.toml"), atomically: true, encoding: .utf8)

        let contributions = PluginMenuContributionRegistry(pluginsDirectoryURL: pluginsDirectory).contributions()

        XCTAssertEqual(contributions.map(\.title), ["Open Settings", "Reload Config"])
        XCTAssertEqual(contributions.map(\.location), ["Configuration", "Configuration"])
        guard case .plugin(let command, let arguments, let executable)? = contributions.first?.target else {
            return XCTFail("expected plugin contribution")
        }
        XCTAssertEqual(command, "settings-ui")
        XCTAssertEqual(arguments, [])
        XCTAssertEqual(executable.standardizedFileURL, executableURL.standardizedFileURL)
        guard case .builtin("config.reload")? = contributions.last?.target else {
            return XCTFail("expected builtin contribution")
        }
    }

    func testPluginMenuContributionRegistryReportsInvalidTargetsAndRefreshesFromDisk() throws {
        let root = try temporaryDirectory()
        let pluginsDirectory = root.appendingPathComponent("plugins", isDirectory: true)
        let pluginDirectory = pluginsDirectory.appendingPathComponent("settings-ui", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
        let executableURL = pluginDirectory.appendingPathComponent("plugin")
        try "#!/bin/sh\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        let manifestURL = pluginDirectory.appendingPathComponent("omux-plugin.toml")
        try """
        schema = 1
        id = "settings-ui"
        kind = "plugin"

        [plugin]
        command = "settings-ui"
        entrypoint = "plugin"

        [menu.configuration.bad]
        location = "Configuration"
        title = "Bad"
        builtin = "terminal.run-shell"
        """.write(to: manifestURL, atomically: true, encoding: .utf8)

        let registry = PluginMenuContributionRegistry(pluginsDirectoryURL: pluginsDirectory)
        let invalid = registry.load()
        XCTAssertTrue(invalid.contributions.isEmpty)
        XCTAssertTrue(invalid.diagnostics.first?.message.contains("unsupported builtin target") ?? false)

        try FileManager.default.removeItem(at: manifestURL)
        try """
        schema = 1
        id = "settings-ui"
        kind = "plugin"

        [plugin]
        command = "settings-ui"
        entrypoint = "plugin"

        [menu.configuration.open]
        location = "Configuration"
        title = "Open Settings"
        command = "settings-ui"
        """.write(to: manifestURL, atomically: true, encoding: .utf8)

        XCTAssertEqual(registry.contributions().map(\.title), ["Open Settings"])
        try FileManager.default.removeItem(at: pluginDirectory)
        XCTAssertTrue(registry.contributions().isEmpty)
    }

    @MainActor
    func testApplicationMenuReflectsReboundAndUnboundKeybindings() throws {
        let delegate = OpenMUXAppDelegate()
        let mainMenu = delegate.configureMenus(assigningToApplication: false)
        delegate.applyKeyBindings(
            .effective(overrides: [
                OpenMUXKeyBindingOverride(
                    chord: try OpenMUXKeyChord(parsing: "cmd+shift+w"),
                    action: nil
                ),
                OpenMUXKeyBindingOverride(
                    chord: try OpenMUXKeyChord(parsing: "cmd+shift+p"),
                    action: .paneRemove
                ),
            ])
        )

        let paneMenu = mainMenu.items
            .compactMap(\.submenu)
            .first { $0.title == "Pane" }

        XCTAssertFalse(paneMenu?.items.containsShortcut(
            title: "Remove Active Pane",
            key: "w",
            modifiers: [.command, .shift]
        ) ?? true)
        XCTAssertTrue(paneMenu?.items.containsShortcut(
            title: "Remove Active Pane",
            key: "p",
            modifiers: [.command, .shift]
        ) ?? false)
    }

    func testCLIInstallStatusResolverDetectsMissingInstalledAndRepairStates() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundledCLIURL = root.appendingPathComponent("OpenMUX.app/Contents/MacOS/omux", isDirectory: false)
        let installedCLIURL = root.appendingPathComponent(".local/bin/omux", isDirectory: false)
        let staleCLIURL = root.appendingPathComponent(".build/debug/omux", isDirectory: false)

        try FileManager.default.createDirectory(at: bundledCLIURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: installedCLIURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staleCLIURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: bundledCLIURL, atomically: true, encoding: .utf8)
        try "#!/bin/sh\n".write(to: staleCLIURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundledCLIURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staleCLIURL.path)

        let resolver = OmuxCLIInstallStatusResolver()

        XCTAssertEqual(
            resolver.status(bundledCLIPath: bundledCLIURL.path, defaultInstallPath: installedCLIURL.path),
            .missing
        )

        try FileManager.default.createSymbolicLink(at: installedCLIURL, withDestinationURL: bundledCLIURL)
        XCTAssertEqual(
            resolver.status(bundledCLIPath: bundledCLIURL.path, defaultInstallPath: installedCLIURL.path),
            .installed
        )

        try FileManager.default.removeItem(at: installedCLIURL)
        try FileManager.default.createSymbolicLink(at: installedCLIURL, withDestinationURL: staleCLIURL)
        XCTAssertEqual(
            resolver.status(bundledCLIPath: bundledCLIURL.path, defaultInstallPath: installedCLIURL.path),
            .repairNeeded
        )
        XCTAssertEqual(OmuxCLIInstallStatus.repairNeeded.menuTitle, "Repair omux CLI")
    }

    func testWorkspaceControllerCreatesTabsAndSplits() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        XCTAssertEqual(workspace.tabs.count, 1)
        XCTAssertEqual(workspace.tabs[0].panes.count, 1)

        let withNewTab = try XCTUnwrap(controller.createTab())
        XCTAssertEqual(withNewTab.tabs.count, 2)
        XCTAssertEqual(withNewTab.focusedTab?.panes.count, 1)

        let withSplit = try XCTUnwrap(controller.splitFocusedPane())
        XCTAssertEqual(withSplit.focusedTab?.panes.count, 2)
        XCTAssertEqual(withSplit.focusedTab?.focusedPaneID, withSplit.focusedTab?.panes.last?.id)
    }

    func testExtensionPaneActionDispatchInvokesOwningPlugin() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )
        _ = try controller.openWorkspace(at: "/tmp")

        let root = try temporaryDirectory()
        let pluginsDirectory = root.appendingPathComponent("plugins", isDirectory: true)
        let pluginDirectory = pluginsDirectory.appendingPathComponent("settings-ui", isDirectory: true)
        let captureURL = root.appendingPathComponent("action.json")
        try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
        let executableURL = pluginDirectory.appendingPathComponent("plugin")
        try """
        #!/bin/sh
        test "$1" = "__omux_action" || exit 9
        cat > \(shellSingleQuoted(captureURL.path))
        printf '{"success":true,"message":"ok","payload":{"saved":true}}\\n'
        """.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

        let result = try XCTUnwrap(controller.createExtensionPane(
            title: "Settings",
            descriptor: ExtensionPaneDescriptor(
                pluginID: "settings-ui",
                contentKind: .html,
                html: "<button>Save</button>",
                actionsEnabled: true
            )
        ))
        let service = ExtensionPaneActionService(controller: controller, pluginsDirectoryURL: pluginsDirectory)

        let response = try service.dispatch(ExtensionPaneActionRequest(
            paneID: result.pane.id,
            pluginID: "settings-ui",
            action: "save",
            payload: .object(["theme": .string("default")])
        ))

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.message, "ok")
        let captured = try String(contentsOf: captureURL, encoding: .utf8)
        XCTAssertTrue(captured.contains("\"action\":\"save\""))
        XCTAssertTrue(captured.contains("\"pluginID\":\"settings-ui\""))
        XCTAssertTrue(captured.contains("\"paneID\":\"\(result.pane.id.rawValue)\""))
    }

    func testExtensionPaneActionRejectsWrongPluginMalformedPayloadAndShellAction() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )
        _ = try controller.openWorkspace(at: "/tmp")
        let root = try temporaryDirectory()
        let pluginsDirectory = root.appendingPathComponent("plugins", isDirectory: true)
        let pluginDirectory = pluginsDirectory.appendingPathComponent("settings-ui", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
        let executableURL = pluginDirectory.appendingPathComponent("plugin")
        try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

        let result = try XCTUnwrap(controller.createExtensionPane(
            title: "Settings",
            descriptor: ExtensionPaneDescriptor(pluginID: "settings-ui", contentKind: .html, html: "<p></p>", actionsEnabled: true)
        ))
        let service = ExtensionPaneActionService(controller: controller, pluginsDirectoryURL: pluginsDirectory)

        XCTAssertThrowsError(try service.dispatch(ExtensionPaneActionRequest(
            paneID: result.pane.id,
            pluginID: "other-plugin",
            action: "save",
            payload: .object([:])
        ))) { error in
            XCTAssertTrue(String(describing: error).contains("settings-ui"))
        }

        XCTAssertThrowsError(try service.dispatch(ExtensionPaneActionRequest(
            paneID: result.pane.id,
            pluginID: "settings-ui",
            action: "save",
            payload: .string("not-json-object")
        ))) { error in
            XCTAssertTrue(String(describing: error).contains("payload must be a JSON object"))
        }

        XCTAssertThrowsError(try service.dispatch(ExtensionPaneActionRequest(
            paneID: result.pane.id,
            pluginID: "settings-ui",
            action: "run-shell",
            payload: .object(["command": .string("echo should-not-run")])
        ))) { error in
            XCTAssertTrue(String(describing: error).contains("unsupported extension pane action"))
        }
    }

    func testExtensionPaneActionReportsPluginFailure() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )
        _ = try controller.openWorkspace(at: "/tmp")
        let root = try temporaryDirectory()
        let pluginsDirectory = root.appendingPathComponent("plugins", isDirectory: true)
        let pluginDirectory = pluginsDirectory.appendingPathComponent("settings-ui", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
        let executableURL = pluginDirectory.appendingPathComponent("plugin")
        try "#!/bin/sh\necho nope >&2\nexit 12\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

        let result = try XCTUnwrap(controller.createExtensionPane(
            title: "Settings",
            descriptor: ExtensionPaneDescriptor(pluginID: "settings-ui", contentKind: .html, html: "<p></p>", actionsEnabled: true)
        ))
        let service = ExtensionPaneActionService(controller: controller, pluginsDirectoryURL: pluginsDirectory)

        XCTAssertThrowsError(try service.dispatch(ExtensionPaneActionRequest(
            paneID: result.pane.id,
            pluginID: "settings-ui",
            action: "save",
            payload: .object([:])
        ))) { error in
            XCTAssertTrue(String(describing: error).contains("status 12"))
            XCTAssertTrue(String(describing: error).contains("nope"))
        }
    }

    func testExtensionPaneActionsDoNotAlterTerminalTextRouting() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: runtime),
            hookRunner: ExternalHookRunner()
        )
        let workspace = try controller.openWorkspace(at: "/tmp")
        let terminalPaneID = try XCTUnwrap(workspace.focusedPane?.id)
        try controller.sendText(target: .pane(terminalPaneID), text: "å´Ω")

        let root = try temporaryDirectory()
        let pluginsDirectory = root.appendingPathComponent("plugins", isDirectory: true)
        let pluginDirectory = pluginsDirectory.appendingPathComponent("settings-ui", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
        let executableURL = pluginDirectory.appendingPathComponent("plugin")
        try "#!/bin/sh\ncat >/dev/null\nprintf '{\"success\":true}\\n'\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

        let result = try XCTUnwrap(controller.createExtensionPane(
            title: "Settings",
            descriptor: ExtensionPaneDescriptor(pluginID: "settings-ui", contentKind: .html, html: "<input>", actionsEnabled: true)
        ))
        let service = ExtensionPaneActionService(controller: controller, pluginsDirectoryURL: pluginsDirectory)

        _ = try service.dispatch(ExtensionPaneActionRequest(
            paneID: result.pane.id,
            pluginID: "settings-ui",
            action: "save",
            payload: .object(["value": .string("Option/dead-key text stays in pane")])
        ))
        XCTAssertEqual(runtime.currentInputText(), "å´Ω")

        try controller.sendText(target: .pane(terminalPaneID), text: "β")
        XCTAssertEqual(runtime.currentInputText(), "å´Ωβ")
    }

    func testCommandPaletteWorkspaceInvocationAndSearchAreReadOnly() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )
        var publishedEvents: [ControlPlaneEvent] = []
        controller.onControlPlaneEvent = { publishedEvents.append($0) }

        let first = try controller.openWorkspace(at: "/tmp/first")
        let second = try controller.openWorkspace(at: "/tmp/second")
        publishedEvents.removeAll()

        let snapshot = controller.persistenceSnapshot(mode: .layoutOnly)
        let workspaces = controller.commandPaletteWorkspaces()
        let searchResults = CommandPaletteSearch.workspaceResults(query: "first", workspaces: workspaces)

        XCTAssertEqual(snapshot, controller.persistenceSnapshot(mode: .layoutOnly))
        XCTAssertTrue(publishedEvents.isEmpty)
        XCTAssertEqual(searchResults.first?.invocationTarget, .workspace(first.id))

        let firstResult = try XCTUnwrap(searchResults.first)
        let invocation = controller.invokeCommandPaletteResult(firstResult)

        XCTAssertEqual(invocation, .invoked)
        XCTAssertEqual(controller.activeWorkspace()?.id, first.id)
        XCTAssertEqual(publishedEvents.map(\.name), ["workspace.restored"])
        publishedEvents.removeAll()

        let activeResult = CommandPaletteResult(
            id: "workspace:\(first.id.rawValue)",
            title: first.name,
            category: .workspace,
            matchText: first.name,
            invocationTarget: .workspace(first.id)
        )
        XCTAssertEqual(controller.invokeCommandPaletteResult(activeResult), .inert)
        XCTAssertTrue(publishedEvents.isEmpty)

        let missingResult = CommandPaletteResult(
            id: "workspace:missing",
            title: "Missing",
            category: .workspace,
            matchText: "Missing",
            invocationTarget: .workspace(WorkspaceID(rawValue: "missing"))
        )
        XCTAssertEqual(controller.invokeCommandPaletteResult(missingResult), .failed("Workspace is no longer available"))
        XCTAssertEqual(controller.activeWorkspace()?.id, first.id)
        XCTAssertNotEqual(controller.activeWorkspace()?.id, second.id)
    }

    func testCommandPaletteCommandMetadataAndInvocation() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: runtime),
            hookRunner: ExternalHookRunner()
        )
        _ = try controller.openWorkspace(at: "/tmp")

        let commands = CommandPaletteCommandCatalog.commands(controller: controller, keyBindings: .defaults)
        let results = CommandPaletteSearch.commandResults(query: "split right", commands: commands)
        let splitRight = try XCTUnwrap(results.first { $0.invocationTarget == .action(.paneSplitRight) })

        XCTAssertEqual(splitRight.shortcutLabel, "⌘D")
        XCTAssertEqual(splitRight.category, .action)
        XCTAssertEqual(controller.invokeCommandPaletteResult(splitRight), .invoked)
        XCTAssertEqual(controller.activeWorkspace()?.focusedTab?.panes.count, 2)

        let disabled = CommandPaletteResult(
            id: "disabled",
            title: "Disabled",
            category: .action,
            matchText: "disabled",
            isEnabled: false,
            disabledReason: "No context",
            invocationTarget: .action(.paneRemove)
        )
        XCTAssertEqual(controller.invokeCommandPaletteResult(disabled), .disabled("No context"))

        let cliCommands = commands.filter { $0.category == .cli }
        XCTAssertEqual(cliCommands.count, OpenMUXCLICommandCatalog.commands.count)
        XCTAssertTrue(cliCommands.allSatisfy(\.isEnabled))

        let cliVersion = try XCTUnwrap(CommandPaletteSearch.commandResults(query: "omux version", commands: commands).first {
            $0.invocationTarget == .cliCommand("omux.version")
        })
        XCTAssertEqual(controller.invokeCommandPaletteResult(cliVersion), .invoked)
        XCTAssertEqual(runtime.executedCommands, ["omux version"])

        let openConfigInTerminal = try XCTUnwrap(CommandPaletteSearch.commandResults(query: "terminal editor", commands: commands).first {
            $0.invocationTarget == .cliCommand("omux.config.open-terminal")
        })
        XCTAssertEqual(openConfigInTerminal.title, "omux: Open Config in Terminal Editor")
        XCTAssertEqual(controller.invokeCommandPaletteResult(openConfigInTerminal), .invoked)
        XCTAssertEqual(runtime.executedCommands, ["omux version", "omux config open"])

        let cliWithArguments = try XCTUnwrap(CommandPaletteSearch.commandResults(query: "inactive opacity", commands: commands).first {
            $0.invocationTarget == .cliCommand("omux.config.inactive-opacity")
        })
        XCTAssertEqual(controller.invokeCommandPaletteResult(cliWithArguments), .invoked)
        XCTAssertEqual(runtime.executedCommands, ["omux version", "omux config open"])
        XCTAssertEqual(runtime.currentInputText(), "omux config inactive-opacity <0.0-1.0>")
    }

    func testCommandPaletteConfigOpenCommandsReflectTerminalRequirement() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let commands = CommandPaletteCommandCatalog.commands(controller: controller, keyBindings: .defaults)
        let openConfig = try XCTUnwrap(commands.first { $0.id == "cli:omux.config.open" })
        let openConfigInTerminal = try XCTUnwrap(commands.first { $0.id == "cli:omux.config.open-terminal" })

        XCTAssertTrue(openConfig.isEnabled)
        XCTAssertEqual(openConfig.invocationTarget, .configOpen)
        XCTAssertFalse(openConfigInTerminal.isEnabled)
        XCTAssertEqual(openConfigInTerminal.disabledReason, "No focused terminal")
        XCTAssertEqual(openConfigInTerminal.invocationTarget, .cliCommand("omux.config.open-terminal"))
    }

    func testCommandPaletteShortcutLabelsUseConfiguredBindings() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )
        _ = try controller.openWorkspace(at: "/tmp")
        let keyBindings = OpenMUXKeyBindingRegistry.effective(overrides: [
            OpenMUXKeyBindingOverride(chord: try OpenMUXKeyChord(parsing: "cmd+d"), action: nil),
            OpenMUXKeyBindingOverride(chord: try OpenMUXKeyChord(parsing: "cmd+shift+d"), action: .paneSplitRight),
            OpenMUXKeyBindingOverride(chord: try OpenMUXKeyChord(parsing: "cmd+shift+w"), action: nil),
        ])

        let commands = CommandPaletteCommandCatalog.commands(controller: controller, keyBindings: keyBindings)
        let splitRight = try XCTUnwrap(commands.first { $0.invocationTarget == .action(.paneSplitRight) })
        let removePane = try XCTUnwrap(commands.first { $0.invocationTarget == .action(.paneRemove) })

        XCTAssertEqual(splitRight.shortcutLabel, "⌘⇧D")
        XCTAssertNil(removePane.shortcutLabel)
    }

    func testCommandPaletteCommandsLoadFromBundledDescriptors() throws {
        let descriptors = CommandPaletteCommandDescriptorCatalog.bundledDescriptors()

        XCTAssertTrue(descriptors.contains { descriptor in
            descriptor.id == "action:pane.split-right"
                && descriptor.command.kind == .action
                && descriptor.command.target == "pane.split-right"
        })
        XCTAssertTrue(descriptors.contains { descriptor in
            descriptor.id == "cli:omux.split"
                && descriptor.command.kind == .builtin
                && descriptor.command.target == "omux.split"
        })
        let cliTargets = Set(descriptors.compactMap { descriptor in
            descriptor.category == .cli && descriptor.command.kind == .builtin ? descriptor.command.target : nil
        })
        XCTAssertEqual(cliTargets, Set(OpenMUXCLICommandCatalog.commands.map(\.id)))
        XCTAssertTrue(descriptors.contains { descriptor in
            descriptor.id == "builtin:switch-theme"
                && descriptor.command.kind == .builtin
                && descriptor.command.target == "theme.switch"
        })
        XCTAssertEqual(Set(descriptors.map(\.id)).count, descriptors.count)
    }

    func testCommandPaletteDescriptorValidationDropsDuplicatesAndUnsupportedTargets() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let first = root.appendingPathComponent("a-first.json")
        let duplicate = root.appendingPathComponent("z-duplicate.json")
        let invalid = root.appendingPathComponent("invalid.json")
        try Data("""
        {
          "id": "action:pane.split-right",
          "title": "Split Pane Right",
          "category": "action",
          "matchText": "split right",
          "aliases": [],
          "requiresArguments": false,
          "hasSafeDefaultTarget": true,
          "command": { "kind": "action", "target": "pane.split-right" }
        }
        """.utf8).write(to: first)
        try Data("""
        {
          "id": "action:pane.split-right",
          "title": "Duplicate",
          "category": "action",
          "matchText": "duplicate",
          "aliases": [],
          "requiresArguments": false,
          "hasSafeDefaultTarget": true,
          "command": { "kind": "action", "target": "pane.split-down" }
        }
        """.utf8).write(to: duplicate)
        try Data("""
        {
          "id": "cli:unsupported",
          "title": "Unsupported",
          "category": "cli",
          "matchText": "unsupported",
          "aliases": [],
          "requiresArguments": false,
          "hasSafeDefaultTarget": true,
          "command": { "kind": "builtin", "target": "unsupported.target" }
        }
        """.utf8).write(to: invalid)

        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )
        _ = try controller.openWorkspace(at: "/tmp")
        let descriptors = CommandPaletteCommandDescriptorCatalog.loadDescriptors(from: [duplicate, first, invalid])
        let commands = CommandPaletteCommandCatalog.commands(
            controller: controller,
            keyBindings: .defaults,
            descriptors: descriptors
        )

        XCTAssertEqual(commands.map(\.id), ["action:pane.split-right"])
        XCTAssertEqual(commands.first?.invocationTarget, .action(.paneSplitRight))
    }

    func testTerminalTextActivationOpensMarkdownPreviewWhenPluginEnabled() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TerminalTextActivationTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let readmeURL = root.appendingPathComponent("README.md")
        try "# Hello\n".write(to: readmeURL, atomically: true, encoding: .utf8)

        let runtime = ActionEmittingGhosttyRuntime()
        runtime.transcript = "README.md"
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner(),
            markdownPreviewConfiguration: OmuxConfigPlugins.MarkdownPreview(enabled: true)
        )
        var events = [ControlPlaneEvent]()
        controller.onTerminalEvent = { events.append($0) }
        let workspace = try controller.openWorkspace(at: root.path)
        let pane = try XCTUnwrap(workspace.focusedPane)
        let session = try XCTUnwrap(pane.terminalSession)
        _ = try bridge.attach(session: session, to: pane)

        let claimed = controller.handleTerminalTextActivation(
            TerminalTextActivationRequest(
                paneID: pane.id,
                location: CGPoint(x: 1, y: 1),
                viewSize: CGSize(width: 80, height: 20),
                terminalSize: TerminalSize(columns: 10, rows: 1),
                modifiers: [.leftCommand]
            )
        )

        XCTAssertTrue(claimed)
        let extensionPane = controller.activeWorkspace()?.tabs
            .flatMap(\.panes)
            .compactMap(\.extensionPane)
            .first { $0.source == readmeURL.path }
        XCTAssertEqual(extensionPane?.pluginID, "dev.fingergun.markdown-preview")
        XCTAssertEqual(extensionPane?.status, .ready)
        XCTAssertTrue(extensionPane?.html?.contains("<h1>Hello</h1>") ?? false)
        XCTAssertTrue(events.contains { event in
            event.name == ControlPlaneTerminalEventName.textActivated.rawValue
                && event.paneID == pane.id
                && event.payload.objectValue?["token"] == .string("README.md")
        })
    }

    func testTerminalTextActivationDoesNotClaimMarkdownWhenPluginDisabled() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TerminalTextActivationTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let readmeURL = root.appendingPathComponent("README.md")
        try "# Hello\n".write(to: readmeURL, atomically: true, encoding: .utf8)

        let runtime = ActionEmittingGhosttyRuntime()
        runtime.transcript = "README.md"
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner(),
            markdownPreviewConfiguration: OmuxConfigPlugins.MarkdownPreview(enabled: false)
        )
        let workspace = try controller.openWorkspace(at: root.path)
        let pane = try XCTUnwrap(workspace.focusedPane)
        let session = try XCTUnwrap(pane.terminalSession)
        _ = try bridge.attach(session: session, to: pane)

        let claimed = controller.handleTerminalTextActivation(
            TerminalTextActivationRequest(
                paneID: pane.id,
                location: CGPoint(x: 1, y: 1),
                viewSize: CGSize(width: 80, height: 20),
                terminalSize: TerminalSize(columns: 10, rows: 1),
                modifiers: [.leftCommand]
            )
        )

        XCTAssertFalse(claimed)
        XCTAssertTrue(controller.activeWorkspace()?.tabs.flatMap(\.panes).allSatisfy { $0.extensionPane == nil } ?? false)
    }

    func testWorkspaceControllerResizesAndEqualizesFocusedSplit() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        _ = try controller.openWorkspace(at: "/tmp")
        _ = try controller.splitFocusedPane(axis: .columns)

        XCTAssertTrue(controller.canResizeSplit(.left))
        let resized = try XCTUnwrap(controller.resizeSplit(.left))
        guard case .split(axis: .columns, proportions: let resizedProportions, children: _)? = resized.focusedTab?.rootLayout else {
            return XCTFail("expected root layout to remain a split")
        }
        XCTAssertEqual(resizedProportions[0], 0.45, accuracy: 0.0001)
        XCTAssertEqual(resizedProportions[1], 0.55, accuracy: 0.0001)

        let equalized = try XCTUnwrap(controller.equalizeSplits())
        guard case .split(axis: .columns, proportions: let equalizedProportions, children: _)? = equalized.focusedTab?.rootLayout else {
            return XCTFail("expected root layout to remain a split")
        }
        XCTAssertEqual(equalizedProportions[0], 0.5, accuracy: 0.0001)
        XCTAssertEqual(equalizedProportions[1], 0.5, accuracy: 0.0001)
    }

    @MainActor
    func testWorkspaceControllerStoresUpdateAvailability() {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        controller.setUpdateAvailability(OpenMUXUpdateAvailability(version: "0.5.0"))

        XCTAssertEqual(controller.currentUpdateAvailability(), OpenMUXUpdateAvailability(version: "0.5.0"))
    }

    @MainActor
    func testSidebarRendersUpdateNotice() {
        let sidebar = WorkspaceSidebarView(frame: NSRect(x: 0, y: 0, width: 224, height: 400))

        sidebar.render(
            workspaceItems: [],
            theme: .defaultTheme,
            onSelectWorkspace: { _ in },
            onCreateWorkspace: {},
            onDeleteWorkspace: {},
            canDeleteWorkspace: false,
            updateAvailability: OpenMUXUpdateAvailability(version: "0.5.0"),
            onMoveWorkspace: { _, _ in },
            onToggleWorkspaceExpansion: { _ in },
            onSelectPane: { _ in }
        )

        XCTAssertEqual(sidebar.updateNoticeTextForTesting, "New version 0.5.0 run: omux update")
    }

    @MainActor
    func testSidebarScrollsWorkspaceListAboveUpdateNotice() throws {
        let sidebar = WorkspaceSidebarView(frame: NSRect(x: 0, y: 0, width: 224, height: 180))
        let items = (0..<16).flatMap { index in
            [
                SidebarItem(
                    kind: .workspace,
                    identifier: "workspace-\(index)",
                    icon: nil,
                    progress: nil,
                    title: "Workspace \(index)",
                    subtitle: nil,
                    isActive: index == 0,
                    isExpanded: true,
                    action: .workspace(WorkspaceID(rawValue: "workspace-\(index)")),
                    contextMenuProvider: nil
                ),
                SidebarItem(
                    kind: .terminal,
                    identifier: "pane-\(index)",
                    icon: nil,
                    progress: nil,
                    title: "Pane \(index)",
                    subtitle: "~/project-\(index)",
                    isActive: false,
                    action: .pane(PaneID(rawValue: "pane-\(index)")),
                    contextMenuProvider: nil
                ),
            ]
        }

        sidebar.render(
            workspaceItems: items,
            theme: .defaultTheme,
            onSelectWorkspace: { _ in },
            onCreateWorkspace: {},
            onDeleteWorkspace: {},
            canDeleteWorkspace: true,
            updateAvailability: OpenMUXUpdateAvailability(version: "0.5.0"),
            onMoveWorkspace: { _, _ in },
            onToggleWorkspaceExpansion: { _ in },
            onSelectPane: { _ in }
        )
        sidebar.layoutSubtreeIfNeeded()

        let scrollView = try XCTUnwrap(findView(ofType: NSScrollView.self, in: sidebar))
        let noticeLabel = try XCTUnwrap(findLabelView(withString: "New version 0.5.0", in: sidebar))
        let noticeView = try XCTUnwrap(noticeLabel.superview)
        let scrollFrame = scrollView.convert(scrollView.bounds, to: sidebar)
        let noticeFrame = noticeView.convert(noticeView.bounds, to: sidebar)

        XCTAssertLessThanOrEqual(scrollFrame.maxY, noticeFrame.minY)
        XCTAssertEqual(sidebar.updateNoticeTextForTesting, "New version 0.5.0 run: omux update")
    }

    @MainActor
    func testSidebarPinsShortWorkspaceListToTopOfScrollArea() throws {
        let sidebar = WorkspaceSidebarView(frame: NSRect(x: 0, y: 0, width: 224, height: 780))
        let items = [
            SidebarItem(
                kind: .workspace,
                identifier: "workspace-1",
                icon: nil,
                progress: nil,
                title: "Workspace 1",
                subtitle: nil,
                isActive: true,
                isExpanded: true,
                action: .workspace(WorkspaceID(rawValue: "workspace-1")),
                contextMenuProvider: nil
            ),
            SidebarItem(
                kind: .terminal,
                identifier: "pane-1",
                icon: nil,
                progress: nil,
                title: "Pane 1",
                subtitle: "~/project",
                isActive: false,
                action: .pane(PaneID(rawValue: "pane-1")),
                contextMenuProvider: nil
            ),
        ]

        sidebar.render(
            workspaceItems: items,
            theme: .defaultTheme,
            onSelectWorkspace: { _ in },
            onCreateWorkspace: {},
            onDeleteWorkspace: {},
            canDeleteWorkspace: true,
            updateAvailability: nil,
            onMoveWorkspace: { _, _ in },
            onToggleWorkspaceExpansion: { _ in },
            onSelectPane: { _ in }
        )
        sidebar.layoutSubtreeIfNeeded()

        let scrollView = try XCTUnwrap(findView(ofType: NSScrollView.self, in: sidebar))
        let titleLabel = try XCTUnwrap(findLabelView(withString: "WORKSPACES · 1", in: sidebar))
        let scrollFrame = scrollView.convert(scrollView.bounds, to: sidebar)
        let titleFrame = titleLabel.convert(titleLabel.bounds, to: sidebar)

        XCTAssertLessThanOrEqual(abs(titleFrame.minY - scrollFrame.minY), 4)
    }

    @MainActor
    func testUpdateCheckerSetsAvailabilityWhenLatestReleaseIsNewer() async throws {
        let root = try versionFixture(version: "0.4.0")
        defer { try? FileManager.default.removeItem(at: root) }
        var releaseCalls = 0
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )
        _ = try controller.openWorkspace(at: "/tmp")
        let checker = OpenMUXUpdateAvailabilityChecker(
            controller: controller,
            versionProvider: OpenMUXVersionProvider(
                executablePath: root.appendingPathComponent("bin/omux").path,
                currentDirectoryPath: root.path
            ),
            latestRelease: {
                releaseCalls += 1
                return Self.release(version: "0.5.0")
            }
        )

        await checker.check()

        XCTAssertEqual(releaseCalls, 1)
        XCTAssertEqual(controller.currentUpdateAvailability(), OpenMUXUpdateAvailability(version: "0.5.0"))
    }

    @MainActor
    func testUpdateCheckerFetchesOnEachStartupCheck() async throws {
        let root = try versionFixture(version: "0.4.0")
        defer { try? FileManager.default.removeItem(at: root) }
        var releaseCalls = 0
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )
        _ = try controller.openWorkspace(at: "/tmp")
        let checker = OpenMUXUpdateAvailabilityChecker(
            controller: controller,
            versionProvider: OpenMUXVersionProvider(
                executablePath: root.appendingPathComponent("bin/omux").path,
                currentDirectoryPath: root.path
            ),
            latestRelease: {
                releaseCalls += 1
                return Self.release(version: "0.5.0")
            }
        )

        await checker.check()
        await checker.check()

        XCTAssertEqual(releaseCalls, 2)
        XCTAssertEqual(controller.currentUpdateAvailability(), OpenMUXUpdateAvailability(version: "0.5.0"))
    }

    @MainActor
    func testUpdateCheckerDoesNotCacheFailedCheck() async throws {
        let root = try versionFixture(version: "0.4.0")
        defer { try? FileManager.default.removeItem(at: root) }
        var releaseCalls = 0
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )
        _ = try controller.openWorkspace(at: "/tmp")
        let checker = OpenMUXUpdateAvailabilityChecker(
            controller: controller,
            versionProvider: OpenMUXVersionProvider(
                executablePath: root.appendingPathComponent("bin/omux").path,
                currentDirectoryPath: root.path
            ),
            latestRelease: {
                releaseCalls += 1
                throw TestUpdateError.unavailable
            }
        )

        await checker.check()
        await checker.check()

        XCTAssertEqual(releaseCalls, 2)
        XCTAssertNil(controller.currentUpdateAvailability())
    }

    @MainActor
    func testUpdateCheckerClearsAvailabilityWhenInstalledVersionIsCurrent() async throws {
        let root = try versionFixture(version: "0.5.0")
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )
        _ = try controller.openWorkspace(at: "/tmp")
        controller.setUpdateAvailability(OpenMUXUpdateAvailability(version: "0.5.0"))
        let checker = OpenMUXUpdateAvailabilityChecker(
            controller: controller,
            versionProvider: OpenMUXVersionProvider(
                executablePath: root.appendingPathComponent("bin/omux").path,
                currentDirectoryPath: root.path
            ),
            latestRelease: {
                Self.release(version: "0.5.0")
            }
        )

        await checker.check()

        XCTAssertNil(controller.currentUpdateAvailability())
    }

    func testFocusPaneTabActivatesContainingWorkspace() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )
        var publishedEvents: [ControlPlaneEvent] = []
        controller.onControlPlaneEvent = { event in
            publishedEvents.append(event)
        }

        let firstWorkspace = try controller.openWorkspace(at: "/tmp/first")
        let firstPaneID = try XCTUnwrap(firstWorkspace.focusedPane?.id)
        let secondWorkspace = try controller.createWorkspace()
        XCTAssertEqual(controller.activeWorkspace()?.id, secondWorkspace.id)
        publishedEvents.removeAll()

        let focusedWorkspace = try XCTUnwrap(controller.focusPaneTab(paneID: firstPaneID))

        XCTAssertEqual(focusedWorkspace.id, firstWorkspace.id)
        XCTAssertEqual(controller.activeWorkspace()?.id, firstWorkspace.id)
        XCTAssertEqual(controller.activeWorkspace()?.focusedPane?.id, firstPaneID)
        XCTAssertEqual(publishedEvents.map(\.name), ["paneTab.focused"])
        XCTAssertEqual(publishedEvents.first?.workspaceID, firstWorkspace.id)
        XCTAssertEqual(publishedEvents.first?.paneID, firstPaneID)
    }

    func testFocusMissingPaneTabIsInert() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )
        var publishedEvents: [ControlPlaneEvent] = []
        controller.onControlPlaneEvent = { event in
            publishedEvents.append(event)
        }

        let workspace = try controller.openWorkspace(at: "/tmp")
        let focusedPaneID = try XCTUnwrap(workspace.focusedPane?.id)
        publishedEvents.removeAll()

        XCTAssertNil(controller.focusPaneTab(paneID: PaneID(rawValue: "missing-pane")))
        XCTAssertEqual(controller.activeWorkspace()?.id, workspace.id)
        XCTAssertEqual(controller.activeWorkspace()?.focusedPane?.id, focusedPaneID)
        XCTAssertTrue(publishedEvents.isEmpty)
    }

    func testWorkspaceControllerUsesConfiguredDefaultRootForNewWorkspace() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner(),
            defaultWorkspaceRootPath: "/tmp"
        )

        let workspace = try controller.createWorkspace()

        XCTAssertEqual(workspace.rootPath, "/tmp")
    }

    func testWorkspaceControllerCanSplitDown() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        _ = try controller.openWorkspace(at: "/tmp")
        let withVerticalSplit = try XCTUnwrap(controller.splitFocusedPane(axis: .rows))

        XCTAssertEqual(withVerticalSplit.focusedTab?.panes.count, 2)
    }

    func testWorkspaceControllerSupportsNestedSplitLayouts() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        _ = try controller.openWorkspace(at: "/tmp")
        let splitDown = try XCTUnwrap(controller.splitFocusedPane(axis: .rows))
        let bottomPaneID = try XCTUnwrap(splitDown.focusedTab?.focusedPaneID)

        _ = controller.focus(paneID: bottomPaneID)
        let nestedLayout = try XCTUnwrap(controller.splitFocusedPane(axis: .columns))

        XCTAssertEqual(nestedLayout.focusedTab?.panes.count, 3)

        guard case .split(axis: .rows, proportions: _, children: let rootChildren)? = nestedLayout.focusedTab?.rootLayout else {
            return XCTFail("expected a row split at the root")
        }

        XCTAssertEqual(rootChildren.count, 2)
        guard case .split(axis: .columns, proportions: _, children: let nestedChildren) = rootChildren[1] else {
            return XCTFail("expected the lower pane to become a nested column split")
        }

        XCTAssertEqual(nestedChildren.count, 2)
        guard case .paneStack = rootChildren[0] else {
            return XCTFail("expected the upper region to remain a pane stack")
        }
        guard case .paneStack = nestedChildren[0] else {
            return XCTFail("expected nested children to be pane stacks")
        }
        guard case .paneStack = nestedChildren[1] else {
            return XCTFail("expected nested children to be pane stacks")
        }
    }

    func testPaneTabSplitAgainstFullWidthBottomPaneSplitsTargetRegion() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let topPaneID = try XCTUnwrap(workspace.focusedPane?.id)
        let splitDown = try XCTUnwrap(controller.splitFocusedPane(axis: .rows))
        let bottomPaneID = try XCTUnwrap(splitDown.focusedPane?.id)
        _ = controller.focus(paneID: topPaneID)
        let topStackID = try XCTUnwrap(controller.activeWorkspace()?.focusedPaneStack?.id)
        let withPaneTab = try XCTUnwrap(controller.createPaneTab(in: topStackID))
        let movedPaneID = try XCTUnwrap(withPaneTab.focusedPane?.id)
        let bottomStackID = try XCTUnwrap(
            withPaneTab.focusedTab?.rootLayout.paneStack(containingPaneID: bottomPaneID)?.id
        )

        let moved = try XCTUnwrap(controller.movePaneTabToSplit(
            paneID: movedPaneID,
            sourceStackID: topStackID,
            targetStackID: bottomStackID,
            direction: .right
        ))

        guard case .split(axis: .rows, proportions: _, children: let rootChildren)? = moved.focusedTab?.rootLayout else {
            return XCTFail("expected root layout to remain a row split")
        }

        XCTAssertEqual(rootChildren.count, 2)
        guard case .paneStack(let topStack) = rootChildren[0] else {
            return XCTFail("expected top region to remain a pane stack")
        }
        guard case .split(axis: .columns, proportions: _, children: let bottomChildren) = rootChildren[1] else {
            return XCTFail("expected bottom region to split into columns")
        }

        XCTAssertEqual(topStack.panes.map(\.id), [topPaneID])
        XCTAssertEqual(bottomChildren.count, 2)
        XCTAssertTrue(bottomChildren[0].containsPane(id: bottomPaneID))
        XCTAssertTrue(bottomChildren[1].containsPane(id: movedPaneID))
    }

    func testWorkspaceControllerCyclesPanesInVisibleLayoutOrder() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let firstPaneID = try XCTUnwrap(workspace.focusedPane?.id)
        let splitWorkspace = try XCTUnwrap(controller.splitFocusedPane(axis: .columns))
        let secondPaneID = try XCTUnwrap(splitWorkspace.focusedPane?.id)
        XCTAssertEqual(splitWorkspace.focusedTab?.visiblePaneIDs, [firstPaneID, secondPaneID])

        let next = try XCTUnwrap(controller.focusNextPane())
        XCTAssertEqual(next.focusedPane?.id, firstPaneID)

        let previous = try XCTUnwrap(controller.focusPreviousPane())
        XCTAssertEqual(previous.focusedPane?.id, secondPaneID)
    }

    @MainActor
    func testWorkspaceAutomationCanChainSplitFocusAndRunByReturnedIDs() throws {
        let bridge = GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime())
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let lower = try XCTUnwrap(controller.splitPane(target: .workspace(workspace.id), axis: .rows))
        let lowerLeft = try XCTUnwrap(controller.splitPane(target: .pane(lower.created.paneID), axis: .columns))

        let expectation = expectation(description: "targeted command executes in selected pane")
        expectation.assertForOverFulfill = false
        let token = bridge.addObserver(for: lowerLeft.created.paneID) { snapshot in
            if snapshot.renderedText.contains("automation-dev\n") {
                expectation.fulfill()
            }
        }

        let runResult = try XCTUnwrap(controller.runCommand(
            target: .pane(lowerLeft.created.paneID),
            command: "printf 'automation-dev' && printf '\\n'"
        ))

        XCTAssertEqual(runResult.target?.paneID, lowerLeft.created.paneID)
        waitForExpectations(timeout: 3)
        bridge.removeObserver(for: lowerLeft.created.paneID, token: token)
    }

    func testWorkspaceControllerCreatesAndClosesPaneTabsInFocusedStack() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let originalPaneID = try XCTUnwrap(workspace.focusedPane?.id)

        let withPaneTab = try XCTUnwrap(controller.createPaneTab())
        XCTAssertEqual(withPaneTab.focusedTab?.panes.count, 2)
        XCTAssertEqual(withPaneTab.focusedTab?.paneStacks.count, 1)
        XCTAssertNotEqual(withPaneTab.focusedTab?.focusedPaneID, originalPaneID)

        let focusedPaneTabID = try XCTUnwrap(withPaneTab.focusedTab?.focusedPaneID)
        let refocused = try XCTUnwrap(controller.focusPaneTab(paneID: originalPaneID))
        XCTAssertEqual(refocused.focusedTab?.focusedPaneID, originalPaneID)

        let closed = try XCTUnwrap(controller.closePaneTab(paneID: focusedPaneTabID))
        XCTAssertEqual(closed.focusedTab?.panes.count, 1)
        XCTAssertEqual(closed.focusedTab?.focusedPaneID, originalPaneID)
    }

    func testWorkspaceControllerCyclesPaneTabsInFocusedStack() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )
        var focusEvents = [ControlPlaneEvent]()
        controller.onControlPlaneEvent = { event in
            if event.name == ControlPlaneActionEventName.paneTabFocused.rawValue {
                focusEvents.append(event)
            }
        }

        let workspace = try controller.openWorkspace(at: "/tmp")
        let firstPaneID = try XCTUnwrap(workspace.focusedPane?.id)
        let withPaneTab = try XCTUnwrap(controller.createPaneTab())
        let secondPaneID = try XCTUnwrap(withPaneTab.focusedPane?.id)

        let next = try XCTUnwrap(controller.focusNextPaneTab())
        XCTAssertEqual(next.focusedPane?.id, firstPaneID)

        let previous = try XCTUnwrap(controller.focusPreviousPaneTab())
        XCTAssertEqual(previous.focusedPane?.id, secondPaneID)
        XCTAssertEqual(focusEvents.map(\.paneID), [firstPaneID, secondPaneID])
        XCTAssertNil(controller.focusNextPane())
    }

    func testWorkspaceControllerKeepsSinglePaneTabNavigationInert() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )
        var focusEventCount = 0
        controller.onControlPlaneEvent = { event in
            if event.name == ControlPlaneActionEventName.paneTabFocused.rawValue {
                focusEventCount += 1
            }
        }

        _ = try controller.openWorkspace(at: "/tmp")

        XCTAssertNil(controller.focusNextPaneTab())
        XCTAssertNil(controller.focusPreviousPaneTab())
        XCTAssertNil(controller.focusNextPane())
        XCTAssertNil(controller.focusPreviousPane())
        XCTAssertEqual(focusEventCount, 0)
    }

    func testWorkspaceControllerCreatesPaneTabInExplicitStack() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let originalPaneID = try XCTUnwrap(workspace.focusedPane?.id)
        let splitWorkspace = try XCTUnwrap(controller.splitFocusedPane(axis: .rows))
        let splitPaneID = try XCTUnwrap(splitWorkspace.focusedPane?.id)
        let targetStackID = try XCTUnwrap(splitWorkspace.focusedTab?.rootLayout.paneStack(containingPaneID: splitPaneID)?.id)
        let originalStackID = try XCTUnwrap(splitWorkspace.focusedTab?.rootLayout.paneStack(containingPaneID: originalPaneID)?.id)

        _ = try XCTUnwrap(controller.focus(paneID: originalPaneID))
        let updatedWorkspace = try XCTUnwrap(controller.createPaneTab(in: targetStackID))
        let originalStack = try XCTUnwrap(updatedWorkspace.focusedTab?.rootLayout.paneStack(id: originalStackID))
        let targetStack = try XCTUnwrap(updatedWorkspace.focusedTab?.rootLayout.paneStack(id: targetStackID))

        XCTAssertEqual(originalStack.panes.map(\.id), [originalPaneID])
        XCTAssertEqual(targetStack.panes.count, 2)
        XCTAssertEqual(updatedWorkspace.focusedPane?.id, targetStack.focusedPaneID)
        XCTAssertNotEqual(updatedWorkspace.focusedPane?.id, originalPaneID)
    }

    func testPaneCreationInheritsLatestKnownWorkingDirectory() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp/project")
        let originalPane = try XCTUnwrap(workspace.focusedPane)
        let originalSurfaceID = try XCTUnwrap(bridge.surface(for: originalPane.id)?.runtimeSurfaceID)
        runtime.emit(.workingDirectoryChanged("/tmp/project/packages/api"), on: originalSurfaceID)

        let splitWorkspace = try XCTUnwrap(controller.splitFocusedPane(axis: .columns))
        let splitPane = try XCTUnwrap(splitWorkspace.focusedPane)
        XCTAssertEqual(splitPane.session.workingDirectory, "/tmp/project/packages/api")

        let splitSurfaceID = try XCTUnwrap(bridge.surface(for: splitPane.id)?.runtimeSurfaceID)
        runtime.emit(.workingDirectoryChanged("/tmp/project/packages/web"), on: splitSurfaceID)
        let paneTabWorkspace = try XCTUnwrap(controller.createPaneTab())

        XCTAssertEqual(paneTabWorkspace.focusedPane?.session.workingDirectory, "/tmp/project/packages/web")
    }

    func testNewPanesDoNotInheritTerminalReportedTitleFromFocusedPane() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp/omux")
        let originalPane = try XCTUnwrap(workspace.focusedPane)
        let runtimeSurfaceID = try XCTUnwrap(bridge.surface(for: originalPane.id)?.runtimeSurfaceID)

        runtime.emit(.titleChanged("GitHub Copilot"), on: runtimeSurfaceID)
        XCTAssertEqual(controller.activeWorkspace()?.focusedPane?.title, "GitHub Copilot")

        let splitWorkspace = try XCTUnwrap(controller.splitFocusedPane(axis: .columns))
        XCTAssertEqual(splitWorkspace.focusedPane?.title, "omux")

        let paneTabWorkspace = try XCTUnwrap(controller.createPaneTab())
        XCTAssertEqual(paneTabWorkspace.focusedPane?.title, "omux")
    }

    func testTerminalApplicationTitlesDriveIconsWithoutReplacingPathTitle() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp/omux")
        let pane = try XCTUnwrap(workspace.focusedPane)
        let runtimeSurfaceID = try XCTUnwrap(bridge.surface(for: pane.id)?.runtimeSurfaceID)

        runtime.emit(.titleChanged("hx"), on: runtimeSurfaceID)

        let updatedPane = try XCTUnwrap(controller.activeWorkspace()?.focusedPane)
        XCTAssertEqual(updatedPane.title, "omux")
        XCTAssertEqual(updatedPane.terminalState.reportedTitle, "hx")
        XCTAssertEqual(WorkspaceIconResolver().icon(for: updatedPane).kind, .helix)
    }

    func testTerminalHistoryResolvesActivePaneAndAllWorkspaceScopes() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )

        let firstWorkspace = try controller.openWorkspace(at: "/tmp/omux")
        let firstPane = try XCTUnwrap(firstWorkspace.focusedPane)
        let firstSurfaceID = try XCTUnwrap(bridge.surface(for: firstPane.id)?.runtimeSurfaceID)
        runtime.scrollbackBySurface[firstSurfaceID] = "omux-one\nomux-two"

        let splitWorkspace = try XCTUnwrap(controller.splitFocusedPane(axis: .columns))
        let splitPane = try XCTUnwrap(splitWorkspace.focusedPane)
        let splitSurfaceID = try XCTUnwrap(bridge.surface(for: splitPane.id)?.runtimeSurfaceID)
        runtime.scrollbackBySurface[splitSurfaceID] = "split-history"

        let secondWorkspace = try controller.openWorkspace(at: "/tmp/dungeon")
        let secondPane = try XCTUnwrap(secondWorkspace.focusedPane)
        let secondSurfaceID = try XCTUnwrap(bridge.surface(for: secondPane.id)?.runtimeSurfaceID)
        runtime.scrollbackBySurface[secondSurfaceID] = "dungeon-history"

        let activeHistory = try XCTUnwrap(controller.terminalHistory(ControlPlaneHistoryRequest()))
        XCTAssertEqual(activeHistory.items.map(\.workspaceID), [secondWorkspace.id])
        XCTAssertEqual(activeHistory.items.map(\.paneID), [secondPane.id])
        XCTAssertEqual(activeHistory.items.first?.text, "dungeon-history")

        let paneHistory = try XCTUnwrap(controller.terminalHistory(ControlPlaneHistoryRequest(
            scope: .pane(firstPane.id),
            maxBytes: 1_000,
            maxLines: 1
        )))
        XCTAssertEqual(paneHistory.items.map(\.paneID), [firstPane.id])
        XCTAssertEqual(paneHistory.items.first?.text, "omux-two")
        XCTAssertEqual(paneHistory.items.first?.lineCount, 1)
        XCTAssertTrue(paneHistory.items.first?.truncated == true)

        let allHistory = try XCTUnwrap(controller.terminalHistory(ControlPlaneHistoryRequest(scope: .all)))
        XCTAssertEqual(Set(allHistory.items.map(\.paneID)), Set([firstPane.id, splitPane.id, secondPane.id]))
        XCTAssertNil(controller.terminalHistory(ControlPlaneHistoryRequest(scope: .pane(PaneID(rawValue: "missing")))))
    }

    func testTerminalHistoryReportsUnavailableAndDoesNotMutatePersistenceOrInput() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp/empty")
        let pane = try XCTUnwrap(workspace.focusedPane)

        let history = try XCTUnwrap(controller.terminalHistory(ControlPlaneHistoryRequest(scope: .pane(pane.id))))
        XCTAssertEqual(history.items.count, 1)
        XCTAssertEqual(history.items.first?.text, "")
        XCTAssertEqual(history.items.first?.unavailable, "history unavailable")
        XCTAssertEqual(runtime.sentTextCount, 0)

        let snapshot = try XCTUnwrap(controller.persistenceSnapshot())
        let persistedPane = try XCTUnwrap(snapshot.workspaces.first?.tabs.first?.panes.first)
        XCTAssertNil(persistedPane.terminalState.restoredScrollback)
    }

    func testWorkspaceControllerPublishesSharedActionEvents() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )
        var publishedEvents: [ControlPlaneEvent] = []
        controller.onControlPlaneEvent = { event in
            publishedEvents.append(event)
        }

        let workspace = try controller.openWorkspace(at: "/tmp")
        let originalSessionID = try XCTUnwrap(workspace.focusedPane?.session.id)

        _ = try XCTUnwrap(controller.createTab())
        let splitWorkspace = try XCTUnwrap(controller.splitFocusedPane(axis: .rows))
        let splitPaneID = try XCTUnwrap(splitWorkspace.focusedPane?.id)
        let splitSessionID = try XCTUnwrap(splitWorkspace.focusedPane?.session.id)
        let paneTabWorkspace = try XCTUnwrap(controller.createPaneTab())
        let paneTabID = try XCTUnwrap(paneTabWorkspace.focusedPane?.id)
        _ = try XCTUnwrap(controller.focusPaneTab(paneID: splitPaneID))
        _ = try XCTUnwrap(controller.closePaneTab(paneID: paneTabID))
        XCTAssertTrue(try controller.focus(sessionID: originalSessionID))
        XCTAssertTrue(try controller.runCommand(in: splitSessionID, command: "pwd"))

        XCTAssertEqual(
            publishedEvents.map(\.name),
            [
                "workspace.opened",
                "tab.created",
                "pane.split",
                "paneTab.created",
                "paneTab.focused",
                "paneTab.closed",
                "session.focused",
                "terminal.inputSent",
                "command.started",
            ]
        )
        XCTAssertEqual(publishedEvents[0].payload.objectValue?["path"], .string("/tmp"))
        XCTAssertEqual(publishedEvents[2].payload.objectValue?["axis"], .string("rows"))
        XCTAssertNotNil(publishedEvents[3].payload.objectValue?["paneStackID"])
        XCTAssertEqual(publishedEvents[4].paneID, splitPaneID)
        XCTAssertEqual(publishedEvents[7].payload.objectValue?["text"], .string("pwd"))
        XCTAssertEqual(publishedEvents[7].payload.objectValue?["source"], .string("action.runCommand"))
    }

    func testWorkspaceControllerPublishesSparseNotificationAndRestoreEvents() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )
        var publishedEvents: [ControlPlaneEvent] = []
        controller.onControlPlaneEvent = { event in
            publishedEvents.append(event)
        }

        let firstWorkspace = try controller.openWorkspace(at: "/tmp")
        let secondWorkspace = try controller.openWorkspace(at: "/var/tmp")

        publishedEvents.removeAll()
        try controller.notify(NotificationRequest(title: "Done", body: "Build finished"))
        let restoredWorkspace = try XCTUnwrap(controller.restore(workspaceID: firstWorkspace.id))

        XCTAssertEqual(restoredWorkspace.id, firstWorkspace.id)
        XCTAssertEqual(publishedEvents.map(\.name), ["notification.raised", "workspace.restored"])
        XCTAssertEqual(publishedEvents[0].workspaceID, secondWorkspace.id)
        XCTAssertNil(publishedEvents[0].paneID)
        XCTAssertNil(publishedEvents[0].sessionID)
        XCTAssertEqual(publishedEvents[1].workspaceID, firstWorkspace.id)
        XCTAssertNil(publishedEvents[1].paneID)
    }

    func testWorkspaceControllerDoesNotPublishActionEventsForRejectedActions() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )
        var publishedEvents: [ControlPlaneEvent] = []
        controller.onControlPlaneEvent = { event in
            publishedEvents.append(event)
        }

        _ = try controller.openWorkspace(at: "/tmp")
        publishedEvents.removeAll()

        XCTAssertFalse(try controller.focus(sessionID: SessionID(rawValue: "missing-session")))
        XCTAssertFalse(try controller.runCommand(in: SessionID(rawValue: "missing-session"), command: "pwd"))
        XCTAssertNil(try controller.closePaneTab(paneID: PaneID(rawValue: "missing-pane")))
        XCTAssertNil(controller.restore(workspaceID: WorkspaceID(rawValue: "missing-workspace")))
        XCTAssertTrue(publishedEvents.isEmpty)
    }

    func testWorkspaceControllerRemovesActivePaneByClosingSinglePaneTab() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        _ = try controller.openWorkspace(at: "/tmp")
        let workspaceWithSecondTab = try XCTUnwrap(controller.createTab())
        XCTAssertEqual(workspaceWithSecondTab.tabs.count, 2)
        XCTAssertTrue(controller.canRemoveActivePane())

        let updatedWorkspace = try XCTUnwrap(controller.removeActivePane())
        XCTAssertEqual(updatedWorkspace.tabs.count, 1)
        XCTAssertEqual(updatedWorkspace.focusedTab?.title, "Main")
        XCTAssertFalse(controller.canRemoveActivePane())
    }

    func testWorkspaceControllerRemovesActivePaneAndCollapsesSplit() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        _ = try controller.openWorkspace(at: "/tmp")
        let splitWorkspace = try XCTUnwrap(controller.splitFocusedPane(axis: .columns))
        XCTAssertEqual(splitWorkspace.focusedTab?.panes.count, 2)

        let updatedWorkspace = try XCTUnwrap(controller.removeActivePane())
        XCTAssertEqual(updatedWorkspace.focusedTab?.panes.count, 1)

        guard case .paneStack? = updatedWorkspace.focusedTab?.rootLayout else {
            return XCTFail("expected split layout to collapse back to a single pane stack")
        }
    }

    func testWorkspaceControllerCanCloseTerminalPaneThatOpenedExtensionPreview() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let terminalPaneID = try XCTUnwrap(workspace.focusedPane?.id)
        let terminalSurfaceID = try XCTUnwrap(bridge.surface(for: terminalPaneID)?.runtimeSurfaceID)
        let extensionResult = try XCTUnwrap(controller.createExtensionPane(
            title: "README.md",
            descriptor: ExtensionPaneDescriptor(
                pluginID: "dev.fingergun.markdown-preview",
                contentKind: .html,
                source: "/tmp/README.md",
                html: "<h1>README</h1>"
            )
        ))

        let updatedWorkspace = try XCTUnwrap(controller.closePane(paneID: terminalPaneID))

        XCTAssertEqual(updatedWorkspace.focusedTab?.panes.map(\.id), [extensionResult.pane.id])
        XCTAssertEqual(updatedWorkspace.focusedPane?.id, extensionResult.pane.id)
        XCTAssertEqual(runtime.destroyedSurfaceIDs, [terminalSurfaceID])
    }

    func testWorkspaceControllerDeletesActiveWorkspaceWhenAnotherExists() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let firstWorkspace = try controller.openWorkspace(at: "/tmp")
        let secondWorkspace = try controller.createWorkspace()
        XCTAssertNotEqual(firstWorkspace.id, secondWorkspace.id)
        XCTAssertTrue(controller.canDeleteActiveWorkspace())

        let survivingWorkspace = try XCTUnwrap(controller.deleteActiveWorkspace())
        XCTAssertEqual(survivingWorkspace.id, firstWorkspace.id)
        XCTAssertFalse(controller.canDeleteActiveWorkspace())
    }

    func testWorkspaceControllerCreatesUniquelyNamedWorkspaces() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let firstWorkspace = try controller.openWorkspace(at: "/tmp")
        let secondWorkspace = try controller.createWorkspace()

        XCTAssertEqual(firstWorkspace.name, "Workspace 1")
        XCTAssertEqual(secondWorkspace.name, "Workspace 2")
    }

    func testWorkspaceControllerReusesLowestAvailableGeneratedWorkspaceName() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        _ = try controller.openWorkspace(at: "/tmp")
        let secondWorkspace = try controller.createWorkspace()
        _ = try controller.createWorkspace()
        _ = try controller.closeWorkspace(secondWorkspace.id)

        let replacementWorkspace = try controller.createWorkspace()
        XCTAssertEqual(replacementWorkspace.name, "Workspace 2")
    }

    func testWorkspaceControllerCanRenameWorkspace() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let renamedWorkspace = try XCTUnwrap(controller.renameWorkspace(workspace.id, to: "Project Alpha"))

        XCTAssertEqual(renamedWorkspace.name, "Project Alpha")
        XCTAssertEqual(controller.activeWorkspace()?.name, "Project Alpha")
    }

    func testWorkspaceControllerCanRemoveCustomWorkspaceName() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        _ = try controller.renameWorkspace(workspace.id, to: "Project Alpha")
        let resetWorkspace = try XCTUnwrap(controller.removeCustomWorkspaceName(workspace.id))

        XCTAssertEqual(resetWorkspace.name, "Workspace 1")
        XCTAssertNil(resetWorkspace.customName)
    }

    func testWorkspaceControllerRestoresPersistedWorkspacesWithFreshTerminalState() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )

        let firstWorkspace = try controller.openWorkspace(at: "/tmp")
        let firstPane = try XCTUnwrap(firstWorkspace.focusedPane)
        let firstSurfaceID = try XCTUnwrap(bridge.surface(for: firstPane.id)?.runtimeSurfaceID)
        runtime.emit(.workingDirectoryChanged("/var/tmp"), on: firstSurfaceID)
        runtime.emit(.progressReported(state: .active, progress: 42), on: firstSurfaceID)

        _ = try controller.renameWorkspace(firstWorkspace.id, to: "Client Shell")
        let splitWorkspace = try XCTUnwrap(controller.splitFocusedPane(axis: .columns))
        _ = controller.updateSplitProportions(
            [0.7, 0.3],
            forChildPaneIDs: [
                firstPane.id,
                try XCTUnwrap(splitWorkspace.focusedPane?.id),
            ]
        )
        _ = controller.focus(paneID: try XCTUnwrap(splitWorkspace.focusedPane?.id))
        let secondWorkspace = try controller.createWorkspace()

        let snapshot = try XCTUnwrap(controller.persistenceSnapshot())
        let restoredController = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let restoredActiveWorkspace = try XCTUnwrap(restoredController.restorePersistedState(snapshot))
        let restoredWorkspaces = restoredController.allWorkspaces()

        XCTAssertEqual(restoredWorkspaces.count, 2)
        XCTAssertEqual(restoredWorkspaces[0].name, "Client Shell")
        XCTAssertEqual(restoredWorkspaces[0].focusedTab?.panes.count, 2)
        XCTAssertEqual(restoredWorkspaces[0].focusedPane?.session.workingDirectory, "/var/tmp")
        XCTAssertNil(restoredWorkspaces[0].focusedPane?.terminalState.statusSummary)
        guard case .split(axis: .columns, proportions: let restoredProportions, children: _)? = restoredWorkspaces[0].focusedTab?.rootLayout else {
            return XCTFail("expected restored layout to keep split proportions")
        }
        XCTAssertEqual(restoredProportions.count, 2)
        XCTAssertEqual(restoredProportions[0], 0.7, accuracy: 0.0001)
        XCTAssertEqual(restoredProportions[1], 0.3, accuracy: 0.0001)
        XCTAssertEqual(restoredActiveWorkspace.id, secondWorkspace.id)
        XCTAssertEqual(restoredController.activeWorkspace()?.id, secondWorkspace.id)
    }

    func testTerminalProgressRemovedShowsBriefIdleStateThenClears() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner(),
            paneConfiguration: OmuxConfigUI.Panes(idleStatusClear: .afterDelay),
            progressIdleClearDelay: 0.01
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let pane = try XCTUnwrap(workspace.focusedPane)
        let runtimeSurfaceID = try XCTUnwrap(bridge.surface(for: pane.id)?.runtimeSurfaceID)
        let idleCleared = expectation(description: "idle state cleared")
        controller.onChange = { workspace in
            if workspace.focusedPane?.terminalState.progress == nil {
                idleCleared.fulfill()
            }
        }

        runtime.emit(.progressReported(state: .active, progress: 42), on: runtimeSurfaceID)
        runtime.emit(.progressReported(state: .removed, progress: nil), on: runtimeSurfaceID)

        XCTAssertEqual(controller.activeWorkspace()?.focusedPane?.terminalState.progress?.state, .paused)
        wait(for: [idleCleared], timeout: 1)
        XCTAssertNil(controller.activeWorkspace()?.focusedPane?.terminalState.progress)
    }

    func testWorkspaceControllerPersistsDistinctPaneWorkingDirectoriesAcrossWorkspaces() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )

        let omuxWorkspace = try controller.openWorkspace(at: "/Users/example/projects/omux")
        let omuxPane = try XCTUnwrap(omuxWorkspace.focusedPane)
        runtime.emit(
            .workingDirectoryChanged("/Users/example/projects/omux/Sources"),
            on: try XCTUnwrap(bridge.surface(for: omuxPane.id)?.runtimeSurfaceID)
        )

        let dungeonWorkspace = try controller.createWorkspace()
        let dungeonPane = try XCTUnwrap(dungeonWorkspace.focusedPane)
        runtime.emit(
            .workingDirectoryChanged("/Users/example/projects/DungeonPlanner"),
            on: try XCTUnwrap(bridge.surface(for: dungeonPane.id)?.runtimeSurfaceID)
        )
        let dungeonSplit = try XCTUnwrap(controller.splitFocusedPane(axis: .rows))
        let dungeonSplitPane = try XCTUnwrap(dungeonSplit.focusedPane)
        runtime.emit(
            .workingDirectoryChanged("/Users/example/projects/DungeonPlanner/App"),
            on: try XCTUnwrap(bridge.surface(for: dungeonSplitPane.id)?.runtimeSurfaceID)
        )

        let snapshot = try XCTUnwrap(controller.persistenceSnapshot())
        let restoredController = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )
        _ = try XCTUnwrap(restoredController.restorePersistedState(snapshot))

        let restoredDirectories = restoredController.allWorkspaces()
            .flatMap(\.tabs)
            .flatMap(\.panes)
            .map(\.session.workingDirectory)

        XCTAssertTrue(restoredDirectories.contains("/Users/example/projects/omux/Sources"))
        XCTAssertTrue(restoredDirectories.contains("/Users/example/projects/DungeonPlanner"))
        XCTAssertTrue(restoredDirectories.contains("/Users/example/projects/DungeonPlanner/App"))
    }

    func testWorkspacePersistenceStoresBoundedPaneScrollbackForHistoryCommand() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp/project")
        let pane = try XCTUnwrap(workspace.focusedPane)
        let surfaceID = try XCTUnwrap(bridge.surface(for: pane.id)?.runtimeSurfaceID)
        runtime.scrollbackBySurface[surfaceID] = (1...4_500).map { "line-\($0)" }.joined(separator: "\n")

        let snapshot = try XCTUnwrap(controller.persistenceSnapshot())
        let persistedPane = try XCTUnwrap(snapshot.workspaces.first?.focusedPane)

        XCTAssertEqual(persistedPane.terminalState.restoredScrollback?.text.split(separator: "\n").count, 4_000)
        XCTAssertEqual(persistedPane.terminalState.restoredScrollback?.text.split(separator: "\n").first, "line-501")
        XCTAssertEqual(persistedPane.terminalState.restoredScrollback?.text.split(separator: "\n").last, "line-4500")
        XCTAssertTrue(persistedPane.terminalState.restoredScrollback?.truncated == true)
    }

    func testWorkspacePersistenceLayoutOnlyModeSkipsPaneScrollbackCapture() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let scrollback = PaneScrollbackSnapshot(text: "previous output", truncated: false)
        let session = SessionDescriptor(shell: "/bin/zsh", workingDirectory: "/tmp/project")
        let pane = Pane(
            title: "project",
            session: session,
            terminalState: PaneTerminalState(restoredScrollback: scrollback)
        )
        let tab = Tab(title: "Main", panes: [pane], focusedPaneID: pane.id)
        let workspace = Workspace(generatedName: "Workspace 1", rootPath: "/tmp/project", tabs: [tab], focusedTabID: tab.id)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )

        _ = try XCTUnwrap(controller.restorePersistedState(.init(workspaces: [workspace], activeWorkspaceID: workspace.id)))
        let surfaceID = try XCTUnwrap(bridge.surface(for: pane.id)?.runtimeSurfaceID)
        runtime.scrollbackBySurface[surfaceID] = "fresh output"

        let snapshot = try XCTUnwrap(controller.persistenceSnapshot(mode: .layoutOnly))
        let persistedPane = try XCTUnwrap(snapshot.workspaces.first?.focusedPane)

        XCTAssertEqual(runtime.terminalTextSnapshotCount, 0)
        XCTAssertEqual(persistedPane.terminalState.restoredScrollback, scrollback)
    }

    func testWorkspacePersistenceScrollbackModeUsesConfiguredBounds() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp/project")
        let pane = try XCTUnwrap(workspace.focusedPane)
        let surfaceID = try XCTUnwrap(bridge.surface(for: pane.id)?.runtimeSurfaceID)
        runtime.scrollbackBySurface[surfaceID] = (1...10).map { "line-\($0)" }.joined(separator: "\n")

        let snapshot = try XCTUnwrap(controller.persistenceSnapshot(mode: .includeScrollback(maxBytes: 1_024, maxLines: 3)))
        let persistedPane = try XCTUnwrap(snapshot.workspaces.first?.focusedPane)

        XCTAssertEqual(runtime.terminalTextSnapshotCount, 1)
        XCTAssertEqual(persistedPane.terminalState.restoredScrollback?.text, "line-8\nline-9\nline-10")
        XCTAssertTrue(persistedPane.terminalState.restoredScrollback?.truncated == true)
    }

    func testHistoryClearSuppressesImmediateScrollbackRecaptureUntilTextChanges() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp/project")
        let pane = try XCTUnwrap(workspace.focusedPane)
        let surfaceID = try XCTUnwrap(bridge.surface(for: pane.id)?.runtimeSurfaceID)
        runtime.scrollbackBySurface[surfaceID] = "secret history"

        let result = try XCTUnwrap(controller.clearTerminalHistory(ControlPlaneHistoryClearRequest()))
        let clearedSnapshot = try XCTUnwrap(controller.persistenceSnapshot(mode: .includeScrollback()))
        let clearedPane = try XCTUnwrap(clearedSnapshot.workspaces.first?.focusedPane)

        XCTAssertEqual(result.clearedCount, 1)
        XCTAssertNil(clearedPane.terminalState.restoredScrollback)
        XCTAssertEqual(runtime.clearedScreenAndScrollbackSurfaceIDs, [surfaceID])
        XCTAssertEqual(runtime.scrollbackBySurface[surfaceID], "")

        runtime.scrollbackBySurface[surfaceID] = "new history"
        let updatedSnapshot = try XCTUnwrap(controller.persistenceSnapshot(mode: .includeScrollback()))
        let updatedPane = try XCTUnwrap(updatedSnapshot.workspaces.first?.focusedPane)

        XCTAssertEqual(updatedPane.terminalState.restoredScrollback?.text, "new history")
    }

    func testHistoryClearIgnoresExtensionPanes() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp/project")
        let terminalPane = try XCTUnwrap(workspace.focusedPane)
        let surfaceID = try XCTUnwrap(bridge.surface(for: terminalPane.id)?.runtimeSurfaceID)
        runtime.scrollbackBySurface[surfaceID] = "terminal history"
        let extensionResult = try XCTUnwrap(controller.createExtensionPane(
            title: "Preview",
            descriptor: ExtensionPaneDescriptor(pluginID: "dev.fingergun.markdown-preview", source: "/tmp/project/README.md")
        ))

        let result = try XCTUnwrap(controller.clearTerminalHistory(ControlPlaneHistoryClearRequest()))

        XCTAssertNotNil(extensionResult.pane.extensionPane)
        XCTAssertEqual(result.clearedCount, 1)
        XCTAssertEqual(runtime.clearedScreenAndScrollbackSurfaceIDs, [surfaceID])
    }

    func testPersistenceSanitizesRepeatedPromptAndLoginTailNoise() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp/project")
        let pane = try XCTUnwrap(workspace.focusedPane)
        let surfaceID = try XCTUnwrap(bridge.surface(for: pane.id)?.runtimeSurfaceID)
        let prompt = "omux [bug-fix-auto-updater][$!?][v6.3][aws]"
        runtime.scrollbackBySurface[surfaceID] = """
        useful output
        Last login: Tue May 5 09:00:00 on ttys001
        \(prompt)
        Last login: Tue May 5 10:00:00 on ttys002
        \(prompt)
        """

        let snapshot = try XCTUnwrap(controller.persistenceSnapshot(mode: .includeScrollback()))
        let persistedPane = try XCTUnwrap(snapshot.workspaces.first?.focusedPane)

        XCTAssertEqual(
            persistedPane.terminalState.restoredScrollback?.text,
            """
            useful output
            Last login: Tue May 5 10:00:00 on ttys002
            """
        )
    }

    func testWorkspaceRestoreKeepsSavedScrollbackForHistoryCommandWithoutRenderingIt() throws {
        let scrollback = PaneScrollbackSnapshot(text: "previous output", truncated: false)
        let session = SessionDescriptor(shell: "/bin/zsh", workingDirectory: "/tmp/project")
        let pane = Pane(
            title: "project",
            session: session,
            terminalState: PaneTerminalState(restoredScrollback: scrollback)
        )
        let tab = Tab(title: "Main", panes: [pane], focusedPaneID: pane.id)
        let workspace = Workspace(generatedName: "Workspace 1", rootPath: "/tmp/project", tabs: [tab], focusedTabID: tab.id)
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        _ = try XCTUnwrap(controller.restorePersistedState(.init(workspaces: [workspace], activeWorkspaceID: workspace.id)))

        XCTAssertEqual(controller.activeWorkspace()?.focusedPane?.terminalState.restoredScrollback, scrollback)
        XCTAssertEqual(controller.activeWorkspace()?.focusedPane?.session.workingDirectory, "/tmp/project")

        let history = try XCTUnwrap(controller.terminalHistory(ControlPlaneHistoryRequest(scope: .pane(pane.id))))
        XCTAssertEqual(history.items.first?.text, "previous output")

        let persistedAgain = try XCTUnwrap(controller.persistenceSnapshot())
        XCTAssertEqual(persistedAgain.workspaces.first?.focusedPane?.terminalState.restoredScrollback, scrollback)
    }

    func testWorkspaceRestoreLaunchesReplayWrapperWhenPersistedScrollbackIsEnabled() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Workspace Replay Tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let scrollback = PaneScrollbackSnapshot(text: "\u{001B}[32mrestored output\u{001B}[0m", truncated: false)
        let session = SessionDescriptor(shell: "/bin/zsh", workingDirectory: "/tmp/project")
        let pane = Pane(
            title: "project",
            session: session,
            terminalState: PaneTerminalState(restoredScrollback: scrollback)
        )
        let tab = Tab(title: "Main", panes: [pane], focusedPaneID: pane.id)
        let workspace = Workspace(generatedName: "Workspace 1", rootPath: "/tmp/project", tabs: [tab], focusedTabID: tab.id)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner(),
            persistedScrollback: OmuxConfigTerminal.PersistedScrollback(enabled: true, maxLines: 4_000, maxBytes: 1_048_576),
            scrollbackReplayStore: ScrollbackReplayStore(directoryURL: root.appendingPathComponent("Replay", isDirectory: true)),
            scrollbackReplayWrapperStore: ScrollbackReplayWrapperStore(directoryURL: root.appendingPathComponent("Replay", isDirectory: true))
        )

        _ = try XCTUnwrap(controller.restorePersistedState(.init(workspaces: [workspace], activeWorkspaceID: workspace.id)))
        let surfaceID = try XCTUnwrap(bridge.surface(for: pane.id)?.runtimeSurfaceID)
        let launchSession = try XCTUnwrap(runtime.session(for: surfaceID))

        XCTAssertTrue(launchSession.shell.hasPrefix("/bin/sh '"))
        XCTAssertFalse(launchSession.shell.contains("direct:"))
        XCTAssertEqual(launchSession.environment["SHELL"], "/bin/zsh")
        let replayPath = try XCTUnwrap(launchSession.environment[ScrollbackReplayStore.environmentKey])
        XCTAssertEqual(try String(contentsOfFile: replayPath, encoding: .utf8), scrollback.text)
        XCTAssertEqual(controller.activeWorkspace()?.focusedPane?.session.shell, "/bin/zsh")
    }

    func testWorkspaceRestoreSkipsReplayWrapperWhenPersistedScrollbackIsDisabled() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceReplayTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let scrollback = PaneScrollbackSnapshot(text: "previous output", truncated: false)
        let session = SessionDescriptor(shell: "/bin/zsh", workingDirectory: "/tmp/project")
        let pane = Pane(
            title: "project",
            session: session,
            terminalState: PaneTerminalState(restoredScrollback: scrollback)
        )
        let tab = Tab(title: "Main", panes: [pane], focusedPaneID: pane.id)
        let workspace = Workspace(generatedName: "Workspace 1", rootPath: "/tmp/project", tabs: [tab], focusedTabID: tab.id)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner(),
            persistedScrollback: OmuxConfigTerminal.PersistedScrollback(enabled: false),
            scrollbackReplayStore: ScrollbackReplayStore(directoryURL: root.appendingPathComponent("Replay", isDirectory: true)),
            scrollbackReplayWrapperStore: ScrollbackReplayWrapperStore(directoryURL: root.appendingPathComponent("Replay", isDirectory: true))
        )

        _ = try XCTUnwrap(controller.restorePersistedState(.init(workspaces: [workspace], activeWorkspaceID: workspace.id)))
        let surfaceID = try XCTUnwrap(bridge.surface(for: pane.id)?.runtimeSurfaceID)

        var expectedEnvironment = session.environment
        expectedEnvironment[OpenMUXTerminalEnvironment.paneIDKey] = pane.id.rawValue
        expectedEnvironment[OpenMUXTerminalEnvironment.sessionIDKey] = session.id.rawValue
        XCTAssertEqual(
            runtime.session(for: surfaceID),
            SessionDescriptor(
                id: session.id,
                shell: session.shell,
                workingDirectory: session.workingDirectory,
                environment: expectedEnvironment
            )
        )
    }

    func testWorkspacePersistenceDropsRestoredScrollbackWhenFreshRuntimeCaptureIsAvailableEmpty() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let scrollback = PaneScrollbackSnapshot(text: "previous output", truncated: false)
        let session = SessionDescriptor(shell: "/bin/zsh", workingDirectory: "/tmp/project")
        let pane = Pane(
            title: "project",
            session: session,
            terminalState: PaneTerminalState(restoredScrollback: scrollback)
        )
        let tab = Tab(title: "Main", panes: [pane], focusedPaneID: pane.id)
        let workspace = Workspace(generatedName: "Workspace 1", rootPath: "/tmp/project", tabs: [tab], focusedTabID: tab.id)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )

        _ = try XCTUnwrap(controller.restorePersistedState(.init(workspaces: [workspace], activeWorkspaceID: workspace.id)))
        let surfaceID = try XCTUnwrap(bridge.surface(for: pane.id)?.runtimeSurfaceID)
        runtime.scrollbackBySurface[surfaceID] = ""

        let persistedAgain = try XCTUnwrap(controller.persistenceSnapshot())

        XCTAssertNil(persistedAgain.workspaces.first?.focusedPane?.terminalState.restoredScrollback)
    }

    func testWorkspaceControllerSupportsOrderedWorkspaceSwitchingAndPreviousRecall() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let firstWorkspace = try controller.openWorkspace(at: "/tmp")
        let secondWorkspace = try controller.createWorkspace()

        XCTAssertEqual(controller.activeWorkspace()?.id, secondWorkspace.id)
        XCTAssertEqual(controller.focusWorkspace(atDisplayIndex: 0)?.id, firstWorkspace.id)
        XCTAssertEqual(controller.activeWorkspace()?.id, firstWorkspace.id)
        XCTAssertEqual(controller.focusPreviousWorkspace()?.id, secondWorkspace.id)
        XCTAssertEqual(controller.activeWorkspace()?.id, secondWorkspace.id)
    }

    func testWorkspaceControllerMovesActiveWorkspaceUpAndDown() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let firstWorkspace = try controller.openWorkspace(at: "/tmp")
        let secondWorkspace = try controller.createWorkspace()
        let thirdWorkspace = try controller.createWorkspace()

        XCTAssertEqual(controller.listWorkspaces().map(\.id), [firstWorkspace.id, secondWorkspace.id, thirdWorkspace.id])
        XCTAssertEqual(controller.activeWorkspace()?.id, thirdWorkspace.id)
        XCTAssertTrue(controller.canMoveActiveWorkspaceUp())
        XCTAssertFalse(controller.canMoveActiveWorkspaceDown())

        let movedUp = try XCTUnwrap(controller.moveActiveWorkspaceUp())
        XCTAssertEqual(movedUp.id, thirdWorkspace.id)
        XCTAssertEqual(controller.listWorkspaces().map(\.id), [firstWorkspace.id, thirdWorkspace.id, secondWorkspace.id])
        XCTAssertTrue(controller.canMoveActiveWorkspaceUp())
        XCTAssertTrue(controller.canMoveActiveWorkspaceDown())

        let movedDown = try XCTUnwrap(controller.moveActiveWorkspaceDown())
        XCTAssertEqual(movedDown.id, thirdWorkspace.id)
        XCTAssertEqual(controller.listWorkspaces().map(\.id), [firstWorkspace.id, secondWorkspace.id, thirdWorkspace.id])
        XCTAssertFalse(controller.canMoveActiveWorkspaceDown())
    }

    func testWorkspaceControllerDoesNotMoveActiveWorkspacePastBounds() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        _ = try controller.openWorkspace(at: "/tmp")
        let secondWorkspace = try controller.createWorkspace()

        XCTAssertNil(controller.moveActiveWorkspaceDown())
        XCTAssertEqual(controller.activeWorkspace()?.id, secondWorkspace.id)

        _ = controller.moveActiveWorkspaceUp()
        XCTAssertNil(controller.moveActiveWorkspaceUp())
        XCTAssertFalse(controller.canMoveActiveWorkspaceUp())
        XCTAssertTrue(controller.canMoveActiveWorkspaceDown())
    }

    func testWorkspaceControllerPersistsReorderedWorkspaceOrder() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let firstWorkspace = try controller.openWorkspace(at: "/tmp")
        let secondWorkspace = try controller.createWorkspace()
        let thirdWorkspace = try controller.createWorkspace()

        _ = controller.moveWorkspace(thirdWorkspace.id, toDisplayIndex: 0)
        XCTAssertEqual(controller.listWorkspaces().map(\.id), [thirdWorkspace.id, firstWorkspace.id, secondWorkspace.id])

        let snapshot = try XCTUnwrap(controller.persistenceSnapshot())
        let restoredController = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        _ = try XCTUnwrap(restoredController.restorePersistedState(snapshot))
        XCTAssertEqual(restoredController.listWorkspaces().map(\.id), [thirdWorkspace.id, firstWorkspace.id, secondWorkspace.id])
        XCTAssertEqual(restoredController.activeWorkspace()?.id, thirdWorkspace.id)
    }

    func testWorkspaceControllerIgnoresMissingOrderedWorkspace() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        XCTAssertNil(controller.focusWorkspace(atDisplayIndex: 8))
        XCTAssertEqual(controller.activeWorkspace()?.id, workspace.id)
        XCTAssertFalse(controller.canFocusPreviousWorkspace())
    }

    func testRunCommandTargetsLiveSession() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let sessionID = try XCTUnwrap(workspace.focusedPane?.session.id)
        XCTAssertTrue(try controller.runCommand(in: sessionID, command: "printf 'hello'"))
    }

    func testRunCommandPublishesInputSentOnlyAfterBridgeDelivery() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: runtime),
            hookRunner: ExternalHookRunner()
        )
        var publishedEvents: [ControlPlaneEvent] = []
        controller.onTerminalEvent = { event in
            publishedEvents.append(event)
        }

        let workspace = try controller.openWorkspace(at: "/tmp")
        let sessionID = try XCTUnwrap(workspace.focusedPane?.session.id)
        publishedEvents.removeAll()

        XCTAssertTrue(try controller.runCommand(in: sessionID, command: "ls"))

        let inputSent = try XCTUnwrap(publishedEvents.first { $0.name == "terminal.inputSent" })
        XCTAssertEqual(inputSent.workspaceID, workspace.id)
        XCTAssertEqual(inputSent.paneID, workspace.focusedPane?.id)
        XCTAssertEqual(inputSent.sessionID, sessionID)
        XCTAssertEqual(inputSent.payload.objectValue?["text"], .string("ls"))
        XCTAssertEqual(inputSent.payload.objectValue?["key"], .null)
        XCTAssertEqual(inputSent.payload.objectValue?["source"], .string("action.runCommand"))
    }

    func testRunCommandDoesNotPublishInputSentWhenBridgeDeliveryFails() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: runtime),
            hookRunner: ExternalHookRunner()
        )
        var publishedEvents: [ControlPlaneEvent] = []
        controller.onTerminalEvent = { event in
            publishedEvents.append(event)
        }

        let workspace = try controller.openWorkspace(at: "/tmp")
        let sessionID = try XCTUnwrap(workspace.focusedPane?.session.id)
        runtime.failNextSend = true
        publishedEvents.removeAll()

        XCTAssertThrowsError(try controller.runCommand(in: sessionID, command: "ls"))
        XCTAssertFalse(publishedEvents.contains { $0.name == "terminal.inputSent" })
    }

    func testSendTextPublishesInputSent() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )
        var publishedEvents: [ControlPlaneEvent] = []
        controller.onTerminalEvent = { event in
            publishedEvents.append(event)
        }

        let workspace = try controller.openWorkspace(at: "/tmp")
        let paneID = try XCTUnwrap(workspace.focusedPane?.id)
        publishedEvents.removeAll()

        _ = try controller.sendText(target: .pane(paneID), text: "ls\n")

        let inputSent = try XCTUnwrap(publishedEvents.first { $0.name == "terminal.inputSent" })
        XCTAssertEqual(inputSent.payload.objectValue?["text"], .string("ls\n"))
        XCTAssertEqual(inputSent.payload.objectValue?["source"], .string("action.sendText"))
    }

    func testTypedTerminalInputDoesNotPublishInputSent() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )
        var publishedEvents: [ControlPlaneEvent] = []
        controller.onTerminalEvent = { event in
            publishedEvents.append(event)
        }

        let workspace = try controller.openWorkspace(at: "/tmp")
        let paneID = try XCTUnwrap(workspace.focusedPane?.id)
        publishedEvents.removeAll()

        try controller.handleInput(
            NormalizedKeyEvent(
                keyCode: 37,
                key: "l",
                text: "l",
                modifiers: [],
                phase: .keyDown,
                isRepeat: false,
                route: .terminal
            ),
            in: paneID
        )

        XCTAssertFalse(publishedEvents.contains { $0.name == "terminal.inputSent" })
    }

    @MainActor
    func testRunCommandPreservesSessionContinuity() throws {
        let bridge = GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime())
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let sessionID = try XCTUnwrap(workspace.focusedPane?.session.id)
        let paneID = try XCTUnwrap(workspace.focusedPane?.id)

        let expectation = expectation(description: "same session receives multiple commands")
        expectation.assertForOverFulfill = false
        let token = bridge.addObserver(for: paneID) { snapshot in
            if snapshot.renderedText.contains("/\n") {
                expectation.fulfill()
            }
        }

        XCTAssertTrue(try controller.runCommand(in: sessionID, command: "cd /"))
        XCTAssertTrue(try controller.runCommand(in: sessionID, command: "pwd"))

        waitForExpectations(timeout: 3)
        bridge.removeObserver(for: paneID, token: token)
    }

    @MainActor
    func testWorkspaceWindowHostsBridgeProvidedTerminalPaneView() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let windowController = WorkspaceWindowController(workspace: workspace, controller: controller)
        let rootView = try XCTUnwrap(windowController.window?.contentViewController?.view)

        XCTAssertNotNil(findHostedTerminalPaneView(in: rootView))
    }

    @MainActor
    func testWorkspaceWindowUsesTerminalNativeShellChrome() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        _ = try controller.createTab()
        let windowController = WorkspaceWindowController(workspace: workspace, controller: controller)
        let rootView = try XCTUnwrap(windowController.window?.contentViewController?.view)

        XCTAssertNotNil(findView(ofType: WorkspaceSidebarView.self, in: rootView))
        XCTAssertNotNil(findView(ofType: WorkspaceCanvasView.self, in: rootView))
    }

    @MainActor
    func testWorkspaceWindowMovesTabNavigationIntoSidebar() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        _ = try controller.openWorkspace(at: "/tmp")
        let updatedWorkspace = try XCTUnwrap(controller.createTab())
        let windowController = WorkspaceWindowController(workspace: updatedWorkspace, controller: controller)
        let rootView = try XCTUnwrap(windowController.window?.contentViewController?.view)
        let sidebar = try XCTUnwrap(findView(ofType: WorkspaceSidebarView.self, in: rootView))

        XCTAssertTrue(findLabel(withString: "Workspace 1", in: sidebar))
        XCTAssertFalse(findLabel(withString: "SESSIONS", in: sidebar))
    }

    @MainActor
    func testWorkspaceWindowShowsVisibleSidebarNavigation() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        _ = try controller.openWorkspace(at: "/tmp")
        let updatedWorkspace = try XCTUnwrap(controller.createTab())
        let windowController = WorkspaceWindowController(workspace: updatedWorkspace, controller: controller)
        let window = try XCTUnwrap(windowController.window)
        let rootView = try XCTUnwrap(window.contentViewController?.view)
        let sidebar = try XCTUnwrap(findView(ofType: WorkspaceSidebarView.self, in: rootView))

        window.contentView?.layoutSubtreeIfNeeded()
        rootView.layoutSubtreeIfNeeded()

        let wsLabel = try XCTUnwrap(findLabelView(withString: "Workspace 1", in: sidebar))
        let wsButton = try XCTUnwrap(findAncestor(ofType: SidebarItemButton.self, for: wsLabel))
        XCTAssertNotNil(wsButton)
        XCTAssertGreaterThanOrEqual(findViews(ofType: NSImageView.self, in: sidebar).count, 2)
    }

    @MainActor
    func testWorkspaceRowContextMenuIncludesResetOnlyForCustomNames() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        _ = try controller.renameWorkspace(workspace.id, to: "Project Alpha")
        let secondWorkspace = try controller.createWorkspace()
        let windowController = WorkspaceWindowController(
            workspace: try XCTUnwrap(controller.activeWorkspace()),
            controller: controller
        )
        let rootView = try XCTUnwrap(windowController.window?.contentViewController?.view)
        let sidebar = try XCTUnwrap(findView(ofType: WorkspaceSidebarView.self, in: rootView))

        let renamedLabel = try XCTUnwrap(findLabelView(withString: "Project Alpha", in: sidebar))
        let renamedButton = try XCTUnwrap(findAncestor(ofType: SidebarItemButton.self, for: renamedLabel))
        let defaultLabel = try XCTUnwrap(findLabelView(withString: secondWorkspace.name, in: sidebar))
        let defaultButton = try XCTUnwrap(findAncestor(ofType: SidebarItemButton.self, for: defaultLabel))

        let renamedMenuTitles = renamedButton.menu?.items.map(\.title) ?? []
        let defaultMenuTitles = defaultButton.menu?.items.map(\.title) ?? []

        XCTAssertTrue(renamedMenuTitles.contains("Remove Custom Name"))
        XCTAssertFalse(defaultMenuTitles.contains("Remove Custom Name"))
        XCTAssertTrue(renamedMenuTitles.contains("Close Others"))
        XCTAssertTrue(renamedMenuTitles.contains("Close Above"))
        XCTAssertTrue(renamedMenuTitles.contains("Close Below"))
    }

    @MainActor
    func testConfigurationCoordinatorReloadPublishesThemeChange() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configURL = home.appendingPathComponent("config.toml")
        let themesDirectoryURL = home.appendingPathComponent("themes", isDirectory: true)
        let generatedURL = home.appendingPathComponent("generated/ghostty", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }

        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try """
        schema = 1

        [theme]
        name = "monokai-soda"
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let evaluator = OmuxConfigurationEvaluator(
            configLoader: OmuxConfigLoader(configURL: configURL),
            themeRegistry: OmuxThemeRegistry(userThemesDirectoryURL: themesDirectoryURL),
            compiler: OmuxThemeCompiler(generatedGhosttyDirectoryURL: generatedURL)
        )
        let prepared = OpenMUXConfigurationCoordinator.prepareInitialState(evaluator: evaluator)
        let coordinator = OpenMUXConfigurationCoordinator(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            initialState: prepared,
            evaluator: evaluator
        )

        let expectation = expectation(description: "theme changed")
        coordinator.onThemeChange = { theme in
            if theme.identifier == "nord" {
                expectation.fulfill()
            }
        }

        try """
        schema = 1

        [theme]
        name = "nord"
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let result = coordinator.reload()

        XCTAssertTrue(result.applied)
        waitForExpectations(timeout: 2)
    }

    @MainActor
    func testConfigurationCoordinatorReloadPublishesKeyBindingChange() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configURL = home.appendingPathComponent("config.toml")
        let themesDirectoryURL = home.appendingPathComponent("themes", isDirectory: true)
        let generatedURL = home.appendingPathComponent("generated/ghostty", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }

        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try """
        schema = 1

        [theme]
        name = "monokai-soda"
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let evaluator = OmuxConfigurationEvaluator(
            configLoader: OmuxConfigLoader(configURL: configURL),
            themeRegistry: OmuxThemeRegistry(userThemesDirectoryURL: themesDirectoryURL),
            compiler: OmuxThemeCompiler(generatedGhosttyDirectoryURL: generatedURL)
        )
        let prepared = OpenMUXConfigurationCoordinator.prepareInitialState(evaluator: evaluator)
        let coordinator = OpenMUXConfigurationCoordinator(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            initialState: prepared,
            evaluator: evaluator
        )

        let expectation = expectation(description: "keybindings changed")
        coordinator.onKeyBindingsChange = { registry in
            if registry.chord(for: .paneRemove)?.description == "cmd+shift+p" {
                expectation.fulfill()
            }
        }

        try """
        schema = 1

        [theme]
        name = "monokai-soda"

        [keys]
        "cmd+shift+w" = "none"
        "cmd+shift+p" = "pane.remove"
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let result = coordinator.reload()

        XCTAssertTrue(result.applied)
        XCTAssertEqual(coordinator.keyBindingRegistry().chord(for: .paneRemove)?.description, "cmd+shift+p")
        waitForExpectations(timeout: 2)
    }

    @MainActor
    func testConfigurationCoordinatorReloadPublishesPersistedScrollbackChange() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configURL = home.appendingPathComponent("config.toml")
        let themesDirectoryURL = home.appendingPathComponent("themes", isDirectory: true)
        let generatedURL = home.appendingPathComponent("generated/ghostty", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }

        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try """
        schema = 1

        [theme]
        name = "monokai-soda"
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let evaluator = OmuxConfigurationEvaluator(
            configLoader: OmuxConfigLoader(configURL: configURL),
            themeRegistry: OmuxThemeRegistry(userThemesDirectoryURL: themesDirectoryURL),
            compiler: OmuxThemeCompiler(generatedGhosttyDirectoryURL: generatedURL)
        )
        let prepared = OpenMUXConfigurationCoordinator.prepareInitialState(evaluator: evaluator)
        let coordinator = OpenMUXConfigurationCoordinator(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            initialState: prepared,
            evaluator: evaluator
        )

        let expectation = expectation(description: "persisted scrollback changed")
        coordinator.onPersistedScrollbackChange = { persistedScrollback in
            if persistedScrollback.enabled == false,
               persistedScrollback.maxLines == 200,
               persistedScrollback.maxBytes == 4096 {
                expectation.fulfill()
            }
        }

        try """
        schema = 1

        [theme]
        name = "monokai-soda"

        [terminal]
        persist_scrollback = false
        persist_scrollback_lines = 200
        persist_scrollback_bytes = 4096
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let result = coordinator.reload()

        XCTAssertTrue(result.applied)
        waitForExpectations(timeout: 2)
    }

    @MainActor
    func testWorkspaceWindowSidebarTracksMultipleWorkspaces() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        _ = try controller.openWorkspace(at: "/tmp")
        let secondWorkspace = try controller.createWorkspace()
        let windowController = WorkspaceWindowController(workspace: secondWorkspace, controller: controller)
        let rootView = try XCTUnwrap(windowController.window?.contentViewController?.view)
        let sidebar = try XCTUnwrap(findView(ofType: WorkspaceSidebarView.self, in: rootView))

        XCTAssertTrue(findLabel(withString: "WORKSPACES · 2", in: sidebar))
        XCTAssertGreaterThanOrEqual(findViews(ofType: SidebarItemButton.self, in: sidebar).count, 2)
    }

    @MainActor
    func testWorkspaceSidebarCollapseHidesPaneRowsUntilWorkspaceFocus() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let firstWorkspace = try controller.openWorkspace(at: "/tmp/sidebar-collapse-first")
        _ = try controller.renameWorkspace(firstWorkspace.id, to: "First")
        let secondWorkspace = try controller.openWorkspace(at: "/tmp/sidebar-collapse-second")
        _ = try controller.renameWorkspace(secondWorkspace.id, to: "Second")
        let windowController = WorkspaceWindowController(
            workspace: try XCTUnwrap(controller.activeWorkspace()),
            controller: controller
        )
        let window = try XCTUnwrap(windowController.window)
        let rootView = try XCTUnwrap(window.contentViewController?.view)
        let sidebar = try XCTUnwrap(findView(ofType: WorkspaceSidebarView.self, in: rootView))

        rootView.layoutSubtreeIfNeeded()
        XCTAssertTrue(findLabel(withString: "/tmp/sidebar-collapse-first", in: sidebar))

        let firstLabel = try XCTUnwrap(findLabelView(withString: "First", in: sidebar))
        let firstButton = try XCTUnwrap(findAncestor(ofType: SidebarItemButton.self, for: firstLabel))
        let collapseItem = try XCTUnwrap(firstButton.menu?.items.first { $0.title == "Collapse Workspace Panes" })
        XCTAssertTrue(NSApp.sendAction(collapseItem.action!, to: collapseItem.target, from: collapseItem))
        rootView.layoutSubtreeIfNeeded()

        XCTAssertTrue(findLabel(withString: "First", in: sidebar))
        XCTAssertTrue(findLabel(withString: "Second", in: sidebar))
        XCTAssertFalse(findLabel(withString: "/tmp/sidebar-collapse-first", in: sidebar))
        XCTAssertTrue(findLabel(withString: "/tmp/sidebar-collapse-second", in: sidebar))

        let restoredWorkspace = try XCTUnwrap(controller.restore(workspaceID: firstWorkspace.id))
        windowController.update(workspace: restoredWorkspace)
        rootView.layoutSubtreeIfNeeded()

        XCTAssertEqual(controller.activeWorkspace()?.id, firstWorkspace.id)
        XCTAssertTrue(findLabel(withString: "/tmp/sidebar-collapse-first", in: sidebar))
    }

    @MainActor
    func testWorkspaceWindowReflectsReorderedWorkspaceSidebarOrder() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let firstWorkspace = try controller.openWorkspace(at: "/tmp")
        _ = try controller.renameWorkspace(firstWorkspace.id, to: "Alpha")
        let secondWorkspace = try controller.createWorkspace()
        _ = try controller.renameWorkspace(secondWorkspace.id, to: "Beta")
        let thirdWorkspace = try controller.createWorkspace()
        let reorderedWorkspace = try XCTUnwrap(controller.renameWorkspace(thirdWorkspace.id, to: "Gamma"))

        let windowController = WorkspaceWindowController(workspace: reorderedWorkspace, controller: controller)
        let window = try XCTUnwrap(windowController.window)
        let rootView = try XCTUnwrap(window.contentViewController?.view)
        let sidebar = try XCTUnwrap(findView(ofType: WorkspaceSidebarView.self, in: rootView))

        _ = controller.moveWorkspace(thirdWorkspace.id, toDisplayIndex: 0)
        windowController.update(workspace: try XCTUnwrap(controller.activeWorkspace()))
        window.contentView?.layoutSubtreeIfNeeded()
        rootView.layoutSubtreeIfNeeded()

        let alphaLabel = try XCTUnwrap(findLabelView(withString: "Alpha", in: sidebar))
        let gammaLabel = try XCTUnwrap(findLabelView(withString: "Gamma", in: sidebar))
        let betaLabel = try XCTUnwrap(findLabelView(withString: "Beta", in: sidebar))

        let gammaFrame = gammaLabel.convert(gammaLabel.bounds, to: rootView)
        let alphaFrame = alphaLabel.convert(alphaLabel.bounds, to: rootView)
        let betaFrame = betaLabel.convert(betaLabel.bounds, to: rootView)

        XCTAssertGreaterThan(gammaFrame.minY, alphaFrame.minY)
        XCTAssertGreaterThan(alphaFrame.minY, betaFrame.minY)
    }

    @MainActor
    func testWorkspaceWindowUsesUnifiedTitlebarConfiguration() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let renamedWorkspace = try XCTUnwrap(controller.renameWorkspace(workspace.id, to: "Project Alpha"))
        let windowController = WorkspaceWindowController(workspace: renamedWorkspace, controller: controller)
        let window = try XCTUnwrap(windowController.window)

        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertTrue(window.isMovableByWindowBackground)
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertEqual(window.title, "Project Alpha")
        XCTAssertTrue(window.contentViewController?.view is WorkspaceRootView)
    }

    @MainActor
    func testWorkspaceRootViewDoubleClickInUnifiedTitlebarRequestsZoom() throws {
        let rootView = WorkspaceRootView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        rootView.titlebarHeightOverrideForTesting = 36
        let window = NSWindow(
            contentRect: rootView.bounds,
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = rootView
        var zoomRequested = false
        rootView.titlebarDoubleClickHandler = { _ in
            zoomRequested = true
        }

        let event = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: NSPoint(x: 80, y: 470),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 2,
                pressure: 1
            )
        )

        rootView.mouseDown(with: event)

        XCTAssertTrue(zoomRequested)
    }

    @MainActor
    func testWorkspaceWindowRendersHorizontalSplitForSplitRight() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        _ = try controller.openWorkspace(at: "/tmp")
        let splitWorkspace = try XCTUnwrap(controller.splitFocusedPane(axis: .columns))
        let windowController = WorkspaceWindowController(workspace: splitWorkspace, controller: controller)
        let window = try XCTUnwrap(windowController.window)
        windowController.showWindow(nil)
        let rootView = try XCTUnwrap(window.contentViewController?.view)

        window.contentView?.layoutSubtreeIfNeeded()
        rootView.layoutSubtreeIfNeeded()

        let paneCards = findViews(ofType: PaneCardView.self, in: rootView)
        XCTAssertEqual(paneCards.count, 2)
        let firstFrame = paneCards[0].convert(paneCards[0].bounds, to: rootView)
        let secondFrame = paneCards[1].convert(paneCards[1].bounds, to: rootView)
        XCTAssertEqual(firstFrame.minY, secondFrame.minY, accuracy: 1)
        XCTAssertNotEqual(firstFrame.minX, secondFrame.minX)
    }

    @MainActor
    func testSplitDividerDoesNotOptIntoWindowBackgroundDragging() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        _ = try controller.openWorkspace(at: "/tmp")
        let splitWorkspace = try XCTUnwrap(controller.splitFocusedPane(axis: .columns))
        let windowController = WorkspaceWindowController(workspace: splitWorkspace, controller: controller)
        let window = try XCTUnwrap(windowController.window)
        windowController.showWindow(nil)
        let rootView = try XCTUnwrap(window.contentViewController?.view)

        window.contentView?.layoutSubtreeIfNeeded()
        rootView.layoutSubtreeIfNeeded()

        let splitLayoutView = try XCTUnwrap(findView(ofType: SplitLayoutView.self, in: rootView))
        XCTAssertFalse(splitLayoutView.mouseDownCanMoveWindow)
    }

    @MainActor
    func testWorkspaceWindowUsesDedicatedPaneHeaderChrome() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let windowController = WorkspaceWindowController(workspace: workspace, controller: controller)
        let rootView = try XCTUnwrap(windowController.window?.contentViewController?.view)

        XCTAssertNotNil(findView(ofType: PaneHeaderView.self, in: rootView))
        XCTAssertNil(findView(ofType: NSSegmentedControl.self, in: rootView))
    }

    @MainActor
    func testWorkspaceWindowPreservesFocusedPaneResponderAcrossTerminalStateUpdates() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )

        _ = try controller.openWorkspace(at: "/tmp")
        let splitWorkspace = try XCTUnwrap(controller.splitFocusedPane())
        let secondPane = try XCTUnwrap(splitWorkspace.focusedPane)
        let secondSurfaceID = try XCTUnwrap(bridge.surface(for: secondPane.id)?.runtimeSurfaceID)

        let windowController = WorkspaceWindowController(workspace: splitWorkspace, controller: controller)
        let window = try XCTUnwrap(windowController.window)
        let rootView = try XCTUnwrap(window.contentViewController?.view)
        rootView.layoutSubtreeIfNeeded()

        var paneViews = findViews(ofType: HostedTerminalPaneView.self, in: rootView)
        XCTAssertEqual(paneViews.count, 2)
        let secondPaneView = try XCTUnwrap(paneViews.last)
        window.makeFirstResponder(secondPaneView.focusTarget)

        runtime.emit(.workingDirectoryChanged("/var/tmp"), on: secondSurfaceID)
        windowController.update(workspace: try XCTUnwrap(controller.activeWorkspace()))
        rootView.layoutSubtreeIfNeeded()

        paneViews = findViews(ofType: HostedTerminalPaneView.self, in: rootView)
        XCTAssertEqual(paneViews.count, 2)
        XCTAssertTrue(window.firstResponder === paneViews.last?.focusTarget)
    }

    @MainActor
    func testWorkspaceWindowIgnoresInactiveWorkspaceUpdatesForDisplay() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )

        let firstWorkspace = try controller.openWorkspace(at: "/tmp")
        let firstPane = try XCTUnwrap(firstWorkspace.focusedPane)
        let firstSurfaceID = try XCTUnwrap(bridge.surface(for: firstPane.id)?.runtimeSurfaceID)
        let secondWorkspace = try controller.createWorkspace()

        XCTAssertEqual(controller.activeWorkspace()?.id, secondWorkspace.id)

        let windowController = WorkspaceWindowController(workspace: secondWorkspace, controller: controller)
        XCTAssertEqual(windowController.window?.title, secondWorkspace.name)

        runtime.emit(.progressReported(state: .active, progress: 42), on: firstSurfaceID)
        windowController.update(workspace: firstWorkspace)

        XCTAssertEqual(controller.activeWorkspace()?.id, secondWorkspace.id)
        XCTAssertEqual(windowController.window?.title, secondWorkspace.name)
    }

    @MainActor
    func testWorkspaceWindowDoesNotDuplicateFocusedPaneTitleAheadOfTabs() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let focusedPaneTitle = try XCTUnwrap(workspace.focusedPane?.title)
        let windowController = WorkspaceWindowController(workspace: workspace, controller: controller)
        let rootView = try XCTUnwrap(windowController.window?.contentViewController?.view)
        let paneHeader = try XCTUnwrap(findView(ofType: PaneHeaderView.self, in: rootView))

        XCTAssertEqual(countVisibleLabels(withString: focusedPaneTitle, in: paneHeader), 1)
    }

    @MainActor
    func testWorkspaceWindowRestoresPersistedSidebarVisibility() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let store = InMemorySidebarVisibilityStore(isSidebarVisible: false)
        let windowController = WorkspaceWindowController(
            workspace: workspace,
            controller: controller,
            sidebarVisibilityStore: store
        )
        let rootView = try XCTUnwrap(windowController.window?.contentViewController?.view)
        let sidebar = try XCTUnwrap(findView(ofType: WorkspaceSidebarView.self, in: rootView))

        rootView.layoutSubtreeIfNeeded()

        XCTAssertTrue(sidebar.isHidden)

        windowController.toggleSidebarVisibility()
        XCTAssertTrue(store.isSidebarVisible)
        XCTAssertFalse(sidebar.isHidden)
    }

    func testBuiltInThemesIncludeDefaultAndCuratedPresets() {
        let presets = WorkspaceShellTheme.builtInPresets
        let identifiers = Set(presets.map(\.identifier))

        XCTAssertTrue(identifiers.contains("monokai-soda"))
        XCTAssertTrue(identifiers.contains("catppuccin"))
        XCTAssertTrue(identifiers.contains("dracula"))
        XCTAssertTrue(identifiers.contains("nord"))
        XCTAssertTrue(identifiers.contains("gruvbox"))
        XCTAssertTrue(identifiers.contains("one-dark"))
        XCTAssertTrue(identifiers.contains("solarized-dark"))
        XCTAssertTrue(identifiers.contains("solarized-light"))
        XCTAssertEqual(presets.count, identifiers.count)
        XCTAssertEqual(WorkspaceShellTheme.defaultTheme.identifier, "monokai-soda")
        XCTAssertNotEqual(WorkspaceShellTheme.defaultTheme.terminalPalette, WorkspaceShellTheme.builtInPresets.first(where: { $0.identifier == "catppuccin" })?.terminalPalette)
        XCTAssertTrue(
            presets.allSatisfy {
                $0.shell.windowBackground.isEqual($0.terminalPalette.backgroundColor)
            }
        )
    }

    func testBuiltInThemesUseReadableSelectedShellText() {
        let failures = WorkspaceShellTheme.builtInPresets.compactMap { theme -> String? in
            let ratio = WorkspaceShellTheme.contrastRatio(theme.shell.selectedText, theme.shell.selection)
            guard ratio < 4.5 else {
                return nil
            }
            return "\(theme.identifier): \(ratio)"
        }

        XCTAssertTrue(failures.isEmpty, "Low selected shell contrast: \(failures.joined(separator: ", "))")
    }

    func testTerminalActionCoordinatorUpdatesPaneStateAndPublishesControlPlaneEvent() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let pane = try XCTUnwrap(workspace.focusedPane)
        let runtimeSurfaceID = try XCTUnwrap(bridge.surface(for: pane.id)?.runtimeSurfaceID)
        var publishedEvent: ControlPlaneTerminalEvent?
        controller.onTerminalEvent = { event in
            publishedEvent = event
        }

        runtime.emit(.workingDirectoryChanged("/var/tmp"), on: runtimeSurfaceID)

        XCTAssertEqual(controller.activeWorkspace()?.focusedPane?.session.workingDirectory, "/var/tmp")
        XCTAssertEqual(controller.activeWorkspace()?.focusedPane?.terminalState.reportedWorkingDirectory, "/var/tmp")
        XCTAssertEqual(publishedEvent?.name, "terminal.cwdChanged")
        XCTAssertEqual(publishedEvent?.payload.objectValue?["path"], .string("/var/tmp"))
    }

    @MainActor
    func testWorkspaceWindowShowsPaneStatusOrbsForTerminalProgressEvents() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let pane = try XCTUnwrap(workspace.focusedPane)
        let runtimeSurfaceID = try XCTUnwrap(bridge.surface(for: pane.id)?.runtimeSurfaceID)
        let windowController = WorkspaceWindowController(workspace: workspace, controller: controller)
        let rootView = try XCTUnwrap(windowController.window?.contentViewController?.view)

        runtime.emit(.progressReported(state: .active, progress: 42), on: runtimeSurfaceID)
        windowController.update(workspace: try XCTUnwrap(controller.activeWorkspace()))
        rootView.layoutSubtreeIfNeeded()

        let visibleActiveOrbs = findViews(ofType: PaneProgressOrbView.self, in: rootView)
            .filter { $0.isHidden == false && $0.progressStateForTesting == .active }
        XCTAssertGreaterThanOrEqual(visibleActiveOrbs.count, 2)
        XCTAssertFalse(findLabel(withString: "Progress 42%", in: rootView))
    }

    @MainActor
    func testWorkspaceWindowShowsYellowStatusOrbsWhenPaneNeedsInput() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let pane = try XCTUnwrap(workspace.focusedPane)
        let windowController = WorkspaceWindowController(workspace: workspace, controller: controller)
        let rootView = try XCTUnwrap(windowController.window?.contentViewController?.view)

        controller.setPaneStatus(
            ControlPlanePaneStatusRequest(
                target: .pane(pane.id),
                state: .needsInput,
                label: "Codex",
                message: "choose an option",
                source: "hook.codex"
            )
        )
        windowController.update(workspace: try XCTUnwrap(controller.activeWorkspace()))
        rootView.layoutSubtreeIfNeeded()

        let visibleInputOrbs = findViews(ofType: PaneProgressOrbView.self, in: rootView)
            .filter { $0.isHidden == false && $0.progressStateForTesting == .needsInput }
        XCTAssertGreaterThanOrEqual(visibleInputOrbs.count, 2)
        XCTAssertTrue(visibleInputOrbs.allSatisfy { $0.progressColorForTesting?.isEqual(NSColor.systemYellow) == true })
        XCTAssertTrue(visibleInputOrbs.contains { $0.accessibilityLabel() == "Pane needs user input" })
    }

    @MainActor
    func testIdleStatusOrbsClearOnFocusByDefault() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let firstPane = try XCTUnwrap(workspace.focusedPane)
        let updatedWorkspace = try XCTUnwrap(controller.createPaneTab())
        let secondPane = try XCTUnwrap(updatedWorkspace.focusedPane)
        XCTAssertEqual(controller.activeWorkspace()?.focusedPane?.id, secondPane.id)

        controller.setPaneStatus(
            ControlPlanePaneStatusRequest(
                target: .pane(firstPane.id),
                state: .idle,
                source: "test"
            )
        )

        XCTAssertEqual(
            controller.activeWorkspace()?.tabs.flatMap(\.panes).first { $0.id == firstPane.id }?.terminalState.progress?.state,
            .paused
        )

        controller.focus(paneID: firstPane.id)

        XCTAssertEqual(controller.activeWorkspace()?.focusedPane?.id, firstPane.id)
        XCTAssertNil(controller.activeWorkspace()?.focusedPane?.terminalState.progress)
    }

    @MainActor
    func testIdleStatusOrbsCanUseDelayPolicy() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner(),
            paneConfiguration: OmuxConfigUI.Panes(idleStatusClear: .afterDelay),
            progressIdleClearDelay: 60
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let pane = try XCTUnwrap(workspace.focusedPane)

        controller.setPaneStatus(
            ControlPlanePaneStatusRequest(
                target: .pane(pane.id),
                state: .idle,
                source: "test"
            )
        )

        XCTAssertEqual(controller.activeWorkspace()?.focusedPane?.terminalState.progress?.state, .paused)
    }

    @MainActor
    func testWorkspaceWindowSuppressesCwdOnlyPaneStatusRow() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let pane = try XCTUnwrap(workspace.focusedPane)
        let runtimeSurfaceID = try XCTUnwrap(bridge.surface(for: pane.id)?.runtimeSurfaceID)
        let windowController = WorkspaceWindowController(workspace: workspace, controller: controller)
        let rootView = try XCTUnwrap(windowController.window?.contentViewController?.view)
        let paneCard = try XCTUnwrap(findView(ofType: PaneCardView.self, in: rootView))

        runtime.emit(.workingDirectoryChanged("/var/tmp"), on: runtimeSurfaceID)
        windowController.update(workspace: try XCTUnwrap(controller.activeWorkspace()))
        rootView.layoutSubtreeIfNeeded()

        XCTAssertFalse(findLabel(withString: "/var/tmp", in: paneCard))
    }

    @MainActor
    func testWorkspaceWindowUsesConfiguredInactivePaneOpacity() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let windowController = WorkspaceWindowController(
            workspace: workspace,
            controller: controller,
            initialPanes: OmuxConfigUI.Panes(inactiveOpacity: 0.72)
        )
        let rootView = try XCTUnwrap(windowController.window?.contentViewController?.view)
        var paneCard = try XCTUnwrap(findView(ofType: PaneCardView.self, in: rootView))

        XCTAssertEqual(paneCard.alphaValue, 0.72, accuracy: 0.001)

        windowController.updatePanes(OmuxConfigUI.Panes(inactiveOpacity: 0.9))
        rootView.layoutSubtreeIfNeeded()
        paneCard = try XCTUnwrap(findView(ofType: PaneCardView.self, in: rootView))

        XCTAssertEqual(paneCard.alphaValue, 0.9, accuracy: 0.001)
    }

    @MainActor
    func testWorkspaceWindowShowsTerminalMetadataRowsAndNavigatesViaSidebar() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let firstPane = try XCTUnwrap(workspace.focusedPane)
        let updatedWorkspace = try XCTUnwrap(controller.createPaneTab())
        let secondPane = try XCTUnwrap(updatedWorkspace.focusedPane)
        let secondSurfaceID = try XCTUnwrap(bridge.surface(for: secondPane.id)?.runtimeSurfaceID)
        let windowController = WorkspaceWindowController(workspace: updatedWorkspace, controller: controller)
        let window = try XCTUnwrap(windowController.window)
        let rootView = try XCTUnwrap(window.contentViewController?.view)
        let sidebar = try XCTUnwrap(findView(ofType: WorkspaceSidebarView.self, in: rootView))

        runtime.emit(.workingDirectoryChanged("/var/tmp"), on: secondSurfaceID)
        windowController.update(workspace: try XCTUnwrap(controller.activeWorkspace()))
        rootView.layoutSubtreeIfNeeded()

        XCTAssertTrue(findLabel(withString: "/tmp", in: sidebar))
        let secondPathLabel = try XCTUnwrap(findLabelView(withString: "/var/tmp", in: sidebar))
        let secondPathButton = try XCTUnwrap(findAncestor(ofType: SidebarItemButton.self, for: secondPathLabel))
        secondPathButton.mouseDown(with: makeMouseEvent(window: window))

        XCTAssertEqual(controller.activeWorkspace()?.focusedPane?.id, secondPane.id)
        XCTAssertNotEqual(firstPane.id, secondPane.id)
    }

    @MainActor
    func testWorkspaceWindowSidebarTerminalRowActivatesInactiveWorkspace() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let firstWorkspace = try controller.openWorkspace(at: "/tmp/sidebar-first")
        let firstPaneID = try XCTUnwrap(firstWorkspace.focusedPane?.id)
        let secondWorkspace = try controller.openWorkspace(at: "/tmp/sidebar-second")
        XCTAssertEqual(controller.activeWorkspace()?.id, secondWorkspace.id)

        let windowController = WorkspaceWindowController(workspace: secondWorkspace, controller: controller)
        let window = try XCTUnwrap(windowController.window)
        let rootView = try XCTUnwrap(window.contentViewController?.view)
        let sidebar = try XCTUnwrap(findView(ofType: WorkspaceSidebarView.self, in: rootView))

        rootView.layoutSubtreeIfNeeded()
        let firstPathLabel = try XCTUnwrap(findLabelView(withString: "/tmp/sidebar-first", in: sidebar))
        let firstPathButton = try XCTUnwrap(findAncestor(ofType: SidebarItemButton.self, for: firstPathLabel))

        firstPathButton.mouseDown(with: makeMouseEvent(window: window))

        XCTAssertEqual(controller.activeWorkspace()?.id, firstWorkspace.id)
        XCTAssertEqual(controller.activeWorkspace()?.focusedPane?.id, firstPaneID)
    }

    @MainActor
    func testWorkspaceSidebarDragRegionsDoNotMoveWindow() {
        XCTAssertFalse(WorkspaceSidebarView().mouseDownCanMoveWindow)
        XCTAssertFalse(SidebarItemButton().mouseDownCanMoveWindow)
    }

    @MainActor
    func testSidebarStatusOrbDoesNotShiftTerminalMetadata() throws {
        let theme = WorkspaceShellTheme.defaultTheme
        let icon = OmuxRenderedIcon(
            text: "T",
            font: .systemFont(ofSize: 11, weight: .medium),
            accessibilityLabel: "Terminal",
            symbolName: nil,
            prefersSymbol: false,
            colorToken: .ansiCyan,
            colorsEnabled: true
        )
        let baseItem = SidebarItem(
            kind: .terminal,
            identifier: "pane",
            icon: icon,
            progress: nil,
            title: "build",
            subtitle: "~/project",
            isActive: false,
            action: .pane(PaneID()),
            contextMenuProvider: nil
        )
        let progressItem = SidebarItem(
            kind: .terminal,
            identifier: "pane",
            icon: icon,
            progress: PaneProgress(state: .paused),
            title: "build",
            subtitle: "~/project",
            isActive: false,
            action: .pane(PaneID()),
            contextMenuProvider: nil
        )
        let baseButton = SidebarItemButton(frame: NSRect(x: 0, y: 0, width: 200, height: baseItem.rowHeight))
        let progressButton = SidebarItemButton(frame: NSRect(x: 0, y: 0, width: 200, height: progressItem.rowHeight))

        baseButton.configure(item: baseItem, theme: theme)
        progressButton.configure(item: progressItem, theme: theme)
        baseButton.layoutSubtreeIfNeeded()
        progressButton.layoutSubtreeIfNeeded()

        let baseTitle = try XCTUnwrap(findLabelView(withString: "build", in: baseButton))
        let progressTitle = try XCTUnwrap(findLabelView(withString: "build", in: progressButton))
        let progressOrb = try XCTUnwrap(findView(ofType: PaneProgressOrbView.self, in: progressButton))

        XCTAssertEqual(baseTitle.frame.minX, progressTitle.frame.minX, accuracy: 0.001)
        XCTAssertLessThan(progressOrb.frame.maxX, progressTitle.frame.minX)
    }

    @MainActor
    func testPaneTabAddButtonCreatesTabInClickedPaneStack() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let originalPaneID = try XCTUnwrap(workspace.focusedPane?.id)
        let splitWorkspace = try XCTUnwrap(controller.splitFocusedPane(axis: .rows))
        let splitPaneID = try XCTUnwrap(splitWorkspace.focusedPane?.id)
        let targetStackID = try XCTUnwrap(splitWorkspace.focusedTab?.rootLayout.paneStack(containingPaneID: splitPaneID)?.id)
        let originalStackID = try XCTUnwrap(splitWorkspace.focusedTab?.rootLayout.paneStack(containingPaneID: originalPaneID)?.id)
        let refocusedWorkspace = try XCTUnwrap(controller.focus(paneID: originalPaneID))
        let windowController = WorkspaceWindowController(workspace: refocusedWorkspace, controller: controller)
        let window = try XCTUnwrap(windowController.window)
        let rootView = try XCTUnwrap(window.contentViewController?.view)

        let addButton = try XCTUnwrap(
            findViews(ofType: NSControl.self, in: rootView)
                .first { $0.identifier?.rawValue == "pane-tab-add-\(targetStackID.rawValue)" }
        )

        addButton.mouseDown(with: makeMouseEvent(window: window))

        let updatedWorkspace = try XCTUnwrap(controller.activeWorkspace())
        let originalStack = try XCTUnwrap(updatedWorkspace.focusedTab?.rootLayout.paneStack(id: originalStackID))
        let targetStack = try XCTUnwrap(updatedWorkspace.focusedTab?.rootLayout.paneStack(id: targetStackID))
        XCTAssertEqual(originalStack.panes.map(\.id), [originalPaneID])
        XCTAssertEqual(targetStack.panes.count, 2)
        XCTAssertEqual(updatedWorkspace.focusedPane?.id, targetStack.focusedPaneID)
    }

    @MainActor
    func testPaneTabAddButtonIsInlineAfterLastPaneTab() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        _ = try controller.openWorkspace(at: "/tmp")
        let workspace = try XCTUnwrap(controller.createPaneTab())
        let paneStack = try XCTUnwrap(workspace.focusedPaneStack)
        let windowController = WorkspaceWindowController(workspace: workspace, controller: controller)
        let rootView = try XCTUnwrap(windowController.window?.contentViewController?.view)
        let tabStrip = try XCTUnwrap(
            findViews(ofType: NSStackView.self, in: rootView)
                .first { $0.identifier?.rawValue == "pane-tab-strip-\(paneStack.id.rawValue)" }
        )

        let arrangedIdentifiers = tabStrip.arrangedSubviews.compactMap { $0.identifier?.rawValue }

        XCTAssertEqual(
            arrangedIdentifiers,
            paneStack.panes.map { "pane-tab-\($0.id.rawValue)" } + ["pane-tab-add-\(paneStack.id.rawValue)"]
        )
    }

    @MainActor
    func testPaneTabInlineCloseTargetsSpecificPaneTab() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let firstPaneID = try XCTUnwrap(workspace.focusedPane?.id)
        let updatedWorkspace = try XCTUnwrap(controller.createPaneTab())
        let secondPaneID = try XCTUnwrap(updatedWorkspace.focusedPane?.id)
        let windowController = WorkspaceWindowController(workspace: updatedWorkspace, controller: controller)
        let window = try XCTUnwrap(windowController.window)
        let rootView = try XCTUnwrap(window.contentViewController?.view)
        let firstCloseButton = try XCTUnwrap(
            findViews(ofType: NSControl.self, in: rootView)
                .first { $0.identifier?.rawValue == "pane-tab-close-\(firstPaneID.rawValue)" }
        )

        firstCloseButton.mouseDown(with: makeMouseEvent(window: window))

        let paneIDs = controller.activeWorkspace()?.focusedPaneStack?.panes.map(\.id)
        XCTAssertEqual(paneIDs, [secondPaneID])
    }

    @MainActor
    func testSinglePaneTabDoesNotRenderInlineCloseOrGenericCloseControl() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let windowController = WorkspaceWindowController(workspace: workspace, controller: controller)
        let rootView = try XCTUnwrap(windowController.window?.contentViewController?.view)
        let paneHeader = try XCTUnwrap(findView(ofType: PaneHeaderView.self, in: rootView))
        let closeControls = findViews(ofType: NSControl.self, in: paneHeader).filter {
            $0.identifier?.rawValue.hasPrefix("pane-tab-close-") == true
        }
        let genericCloseControls = findViews(ofType: NSControl.self, in: paneHeader).filter {
            $0.accessibilityLabel() == "Close pane tab"
        }

        XCTAssertEqual(closeControls.count, 0)
        XCTAssertEqual(genericCloseControls.count, 0)
    }

    @MainActor
    func testPaneTabsKeepContextMenusWithInlineCloseControls() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        _ = try controller.openWorkspace(at: "/tmp")
        let workspace = try XCTUnwrap(controller.createPaneTab())
        let paneStack = try XCTUnwrap(workspace.focusedPaneStack)
        let windowController = WorkspaceWindowController(workspace: workspace, controller: controller)
        let rootView = try XCTUnwrap(windowController.window?.contentViewController?.view)

        let tabButtons = findViews(ofType: NSControl.self, in: rootView).filter { control in
            guard let identifier = control.identifier?.rawValue else {
                return false
            }
            return identifier.hasPrefix("pane-tab-")
                && identifier.hasPrefix("pane-tab-close-") == false
                && identifier.hasPrefix("pane-tab-add-") == false
        }

        XCTAssertEqual(tabButtons.count, paneStack.panes.count)
        XCTAssertTrue(tabButtons.allSatisfy { $0.menu != nil })
    }

    @MainActor
    func testPaneTabContextMenuExposesRenameAndCloseVariants() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let updatedWorkspace = try XCTUnwrap(controller.createPaneTab())
        let windowController = WorkspaceWindowController(workspace: updatedWorkspace, controller: controller)
        let rootView = try XCTUnwrap(windowController.window?.contentViewController?.view)

        let tabButtons = findViews(ofType: NSControl.self, in: rootView).filter { $0.menu != nil }
        XCTAssertEqual(tabButtons.count, 2)
        let menuTitles = tabButtons[0].menu?.items.map(\.title) ?? []

        XCTAssertTrue(menuTitles.contains("Rename…"))
        XCTAssertTrue(menuTitles.contains("Close"))
        XCTAssertTrue(menuTitles.contains("Close Others"))
        XCTAssertTrue(menuTitles.contains("Close Above"))
        XCTAssertTrue(menuTitles.contains("Close Below"))
        XCTAssertEqual(workspace.tabs.count, 1)
    }

    @MainActor
    func testSidebarTerminalRowContextMenuExposesRenameAndCloseVariants() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let updatedWorkspace = try XCTUnwrap(controller.createPaneTab())
        let secondPane = try XCTUnwrap(updatedWorkspace.focusedPane)
        let renamedWorkspace = try XCTUnwrap(controller.renamePaneTab(secondPane.id, to: "hx"))
        let windowController = WorkspaceWindowController(workspace: renamedWorkspace, controller: controller)
        let rootView = try XCTUnwrap(windowController.window?.contentViewController?.view)
        let sidebar = try XCTUnwrap(findView(ofType: WorkspaceSidebarView.self, in: rootView))

        let terminalLabel = try XCTUnwrap(findLabelView(withString: "hx", in: sidebar))
        let terminalButton = try XCTUnwrap(findAncestor(ofType: SidebarItemButton.self, for: terminalLabel))
        let menuTitles = terminalButton.menu?.items.map(\.title) ?? []

        XCTAssertTrue(menuTitles.contains("Rename…"))
        XCTAssertTrue(menuTitles.contains("Close"))
        XCTAssertTrue(menuTitles.contains("Close Others"))
        XCTAssertTrue(menuTitles.contains("Close Above"))
        XCTAssertTrue(menuTitles.contains("Close Below"))
        XCTAssertEqual(workspace.tabs.count, 1)
    }

    @MainActor
    func testWorkspaceWindowShowsGitAwareTerminalMetadataWhenRepositoryIsAvailable() throws {
        let repositoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        try runGit(["init", repositoryURL.path])
        try runGit(["-C", repositoryURL.path, "branch", "-M", "main"])

        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: repositoryURL.path)
        let windowController = WorkspaceWindowController(workspace: workspace, controller: controller)
        let rootView = try XCTUnwrap(windowController.window?.contentViewController?.view)
        let sidebar = try XCTUnwrap(findView(ofType: WorkspaceSidebarView.self, in: rootView))
        let expectedTitle = "main"

        XCTAssertTrue(findLabel(withString: expectedTitle, in: sidebar))
        XCTAssertTrue(findLabel(withString: repositoryURL.path, in: sidebar))
    }

    @MainActor
    func testWorkspaceWindowPrefersPaneTitleInTerminalMetadataRows() throws {
        let repositoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        try runGit(["init", repositoryURL.path])
        try runGit(["-C", repositoryURL.path, "branch", "-M", "main"])

        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: repositoryURL.path)
        let paneID = try XCTUnwrap(workspace.focusedPane?.id)
        let renamedWorkspace = try XCTUnwrap(controller.renamePaneTab(paneID, to: "hx"))
        let windowController = WorkspaceWindowController(workspace: renamedWorkspace, controller: controller)
        let rootView = try XCTUnwrap(windowController.window?.contentViewController?.view)
        let sidebar = try XCTUnwrap(findView(ofType: WorkspaceSidebarView.self, in: rootView))

        XCTAssertTrue(findLabel(withString: "hx", in: sidebar))
        XCTAssertTrue(findLabel(withString: "main · \(repositoryURL.path)", in: sidebar))
    }

    @MainActor
    func testWorkspaceWindowKeepsSinglePaneFilledAcrossCanvas() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let windowController = WorkspaceWindowController(workspace: workspace, controller: controller)
        let window = try XCTUnwrap(windowController.window)
        windowController.showWindow(nil)
        let rootView = try XCTUnwrap(window.contentViewController?.view)
        let sidebar = try XCTUnwrap(findView(ofType: WorkspaceSidebarView.self, in: rootView))
        let canvas = try XCTUnwrap(findView(ofType: WorkspaceCanvasView.self, in: rootView))
        let hostedPane = try XCTUnwrap(findView(ofType: HostedTerminalPaneView.self, in: rootView))

        window.contentView?.layoutSubtreeIfNeeded()
        rootView.layoutSubtreeIfNeeded()

        let sidebarFrame = sidebar.convert(sidebar.bounds, to: rootView)
        let canvasFrame = canvas.convert(canvas.bounds, to: rootView)
        let hostedFrame = hostedPane.convert(hostedPane.bounds, to: rootView)

        XCTAssertEqual(canvasFrame.minX, sidebarFrame.maxX, accuracy: 1)
        XCTAssertEqual(canvasFrame.maxX, rootView.bounds.maxX, accuracy: 1)
        XCTAssertEqual(hostedFrame.minX, canvasFrame.minX, accuracy: 1)
        XCTAssertEqual(hostedFrame.maxX, canvasFrame.maxX, accuracy: 1)
    }

    func testTerminalActionCoordinatorEmitsStructuredHooksAndNativeNotifications() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let launcher = CapturingHookLauncher()
        let registry = HookRegistry()
        registry.register(
            HookDescriptor(
                category: .command,
                name: "terminal-command-finished",
                executableURL: URL(fileURLWithPath: "/usr/bin/true")
            )
        )
        let runner = ExternalHookRunner(
            registry: registry,
            launcher: launcher
        )
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: runner
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let pane = try XCTUnwrap(workspace.focusedPane)
        let runtimeSurfaceID = try XCTUnwrap(bridge.surface(for: pane.id)?.runtimeSurfaceID)

        runtime.emit(.commandFinished(exitCode: 0, durationNanoseconds: 123), on: runtimeSurfaceID)

        let invocation = try XCTUnwrap(launcher.invocations.first)
        XCTAssertEqual(invocation.name, "terminal-command-finished")
        XCTAssertEqual(invocation.payload.objectValue?["exitCode"], .integer(0))
        XCTAssertEqual(controller.latestNotification()?.title, "Command finished")
    }

    func testCommandFailureHookReceivesCommandContextAndOutputState() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        runtime.transcript = "runtime output tail"
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let launcher = CapturingHookLauncher()
        let registry = HookRegistry()
        for hookName in ["command-started", "terminal-command-finished", "command-failed"] {
            registry.register(
                HookDescriptor(
                    category: .command,
                    name: hookName,
                    executableURL: URL(fileURLWithPath: "/usr/bin/true")
                )
            )
        }
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner(registry: registry, launcher: launcher)
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let pane = try XCTUnwrap(workspace.focusedPane)
        let runtimeSurfaceID = try XCTUnwrap(bridge.surface(for: pane.id)?.runtimeSurfaceID)

        _ = try controller.runCommand(target: .session(pane.session.id), command: "pnpm test")
        runtime.emit(.commandFinished(exitCode: 1, durationNanoseconds: 456), on: runtimeSurfaceID)

        XCTAssertEqual(launcher.invocations.map(\.name), [
            "command-started",
            "terminal-command-finished",
            "command-failed",
        ])
        let failed = try XCTUnwrap(launcher.invocations.last)
        XCTAssertEqual(failed.workspaceID, workspace.id)
        XCTAssertEqual(failed.paneID, pane.id)
        XCTAssertEqual(failed.sessionID, pane.session.id)
        XCTAssertEqual(failed.payload.objectValue?["command"], .string("pnpm test"))
        XCTAssertEqual(failed.payload.objectValue?["cwd"], .string("/tmp"))
        XCTAssertEqual(failed.payload.objectValue?["exitCode"], .integer(1))
        XCTAssertEqual(failed.payload.objectValue?["durationNanoseconds"], .integer(456))
        XCTAssertEqual(failed.payload.objectValue?["outputContext"]?.objectValue?["kind"], .string("tail"))
        XCTAssertEqual(failed.payload.objectValue?["outputContext"]?.objectValue?["tail"], .string("runtime output tail"))
        XCTAssertEqual(failed.payload.objectValue?["outputContext"]?.objectValue?["truncated"], .bool(false))
        XCTAssertEqual(launcher.invocations[0].payload.objectValue?["outputContext"]?.objectValue?["kind"], .string("unavailable"))
    }

    func testInputSentHookReceivesForwardedTerminalInput() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let launcher = CapturingHookLauncher()
        let registry = HookRegistry()
        registry.register(
            HookDescriptor(
                category: .input,
                name: "terminal-input-sent",
                executableURL: URL(fileURLWithPath: "/usr/bin/true")
            )
        )
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner(registry: registry, launcher: launcher)
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let sessionID = try XCTUnwrap(workspace.focusedPane?.session.id)

        XCTAssertTrue(try controller.runCommand(in: sessionID, command: "printf 'input-hook'"))

        let invocation = try XCTUnwrap(launcher.invocations.first)
        XCTAssertEqual(invocation.category, .input)
        XCTAssertEqual(invocation.name, "terminal-input-sent")
        XCTAssertEqual(invocation.payload.objectValue?["text"], .string("printf 'input-hook'"))
        XCTAssertEqual(invocation.payload.objectValue?["source"], .string("action.runCommand"))
    }

    func testInputSentHookFailureDoesNotCancelForwardedInput() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let registry = HookRegistry()
        registry.register(
            HookDescriptor(
                category: .input,
                name: "terminal-input-sent",
                executableURL: URL(fileURLWithPath: "/usr/bin/false")
            )
        )
        let runner = ExternalHookRunner(
            registry: registry,
            launcher: ClosureHookLauncher { throw ProcessHookLauncherError.nonZeroExit(executablePath: "/usr/bin/false", status: 1) },
            warningHandler: { _ in }
        )
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: runtime),
            hookRunner: runner
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let sessionID = try XCTUnwrap(workspace.focusedPane?.session.id)

        XCTAssertTrue(try controller.runCommand(in: sessionID, command: "printf 'still-runs'"))
        XCTAssertEqual(runtime.sentTextCount, 1)
    }

    func testTitleChangedDoesNotPublishInputSentOrHook() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let launcher = CapturingHookLauncher()
        let registry = HookRegistry()
        registry.register(
            HookDescriptor(
                category: .input,
                name: "terminal-input-sent",
                executableURL: URL(fileURLWithPath: "/usr/bin/true")
            )
        )
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner(registry: registry, launcher: launcher)
        )
        var publishedEvents: [ControlPlaneEvent] = []
        controller.onTerminalEvent = { event in
            publishedEvents.append(event)
        }

        let workspace = try controller.openWorkspace(at: "/tmp")
        let pane = try XCTUnwrap(workspace.focusedPane)
        let runtimeSurfaceID = try XCTUnwrap(bridge.surface(for: pane.id)?.runtimeSurfaceID)
        publishedEvents.removeAll()

        runtime.emit(.titleChanged("ls"), on: runtimeSurfaceID)

        XCTAssertEqual(publishedEvents.map(\.name), ["terminal.titleChanged"])
        XCTAssertTrue(launcher.invocations.isEmpty)
    }

    func testCommandFinishedControlPlaneEventCarriesBoundedOutputContext() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        runtime.transcript = (1...500).map { "event-\($0)" }.joined(separator: "\n")
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )
        var publishedEvent: ControlPlaneTerminalEvent?
        controller.onTerminalEvent = { event in
            if event.name == "terminal.commandFinished" {
                publishedEvent = event
            }
        }

        let workspace = try controller.openWorkspace(at: "/tmp")
        let pane = try XCTUnwrap(workspace.focusedPane)
        let runtimeSurfaceID = try XCTUnwrap(bridge.surface(for: pane.id)?.runtimeSurfaceID)

        runtime.emit(.commandFinished(exitCode: 0, durationNanoseconds: 123), on: runtimeSurfaceID)

        let payload = try XCTUnwrap(publishedEvent?.payload.objectValue)
        let outputContext = try XCTUnwrap(payload["outputContext"]?.objectValue)
        XCTAssertEqual(outputContext["kind"], .string("tail"))
        XCTAssertEqual(outputContext["truncated"], .bool(true))
        XCTAssertTrue(outputContext["tail"]?.stringValue?.contains("event-500") == true)
        XCTAssertEqual(publishedEvent?.paneID, pane.id)
        XCTAssertEqual(publishedEvent?.sessionID, pane.session.id)
    }

    func testSuccessfulCommandCompletionDoesNotEmitCommandFailedHook() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let launcher = CapturingHookLauncher()
        let registry = HookRegistry()
        for hookName in ["terminal-command-finished", "command-failed"] {
            registry.register(
                HookDescriptor(
                    category: .command,
                    name: hookName,
                    executableURL: URL(fileURLWithPath: "/usr/bin/true")
                )
            )
        }
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner(registry: registry, launcher: launcher)
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let pane = try XCTUnwrap(workspace.focusedPane)
        let runtimeSurfaceID = try XCTUnwrap(bridge.surface(for: pane.id)?.runtimeSurfaceID)

        runtime.emit(.commandFinished(exitCode: 0, durationNanoseconds: 1), on: runtimeSurfaceID)

        XCTAssertEqual(launcher.invocations.map(\.name), ["terminal-command-finished"])
    }

    func testDiscoveredUserHookReceivesWorkspaceInvocation() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let workspaceHooksDirectory = tempDirectory
            .appending(path: "hooks")
            .appending(path: "workspace-opened")
        try FileManager.default.createDirectory(at: workspaceHooksDirectory, withIntermediateDirectories: true)

        let hookURL = workspaceHooksDirectory.appending(path: "10-capture")
        try """
        #!/bin/sh
        exit 0
        """.write(to: hookURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: hookURL.path(percentEncoded: false)
        )

        let launcher = CapturingHookLauncher()
        let runner = ExternalHookRunner(
            registry: UserHookDirectoryDiscovery.registry(in: tempDirectory.appending(path: "hooks")),
            launcher: launcher
        )
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: runner
        )

        let workspace = try controller.openWorkspace(at: "/tmp")

        let invocation = try XCTUnwrap(launcher.invocations.first)
        XCTAssertEqual(invocation.name, "workspace-opened")
        XCTAssertEqual(invocation.category, .lifecycle)
        XCTAssertEqual(invocation.workspaceID, workspace.id)
        XCTAssertEqual(invocation.payload.objectValue?["path"], .string("/tmp"))
    }

    func testWorkspaceOpenedHookMutationsAreNotOverwrittenByStaleOpenUpdate() throws {
        var controller: WorkspaceController!
        var changedPaneCounts: [Int] = []
        let registry = HookRegistry()
        registry.register(
            HookDescriptor(
                category: .lifecycle,
                name: "workspace-opened",
                executableURL: URL(fileURLWithPath: "/usr/bin/true")
            )
        )
        let launcher = ClosureHookLauncher {
            _ = try controller.splitPane(target: .focused, axis: .rows)
        }
        controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner(registry: registry, launcher: launcher)
        )
        controller.onChange = { workspace in
            changedPaneCounts.append(workspace.focusedTab?.panes.count ?? 0)
        }

        let opened = try controller.openWorkspace(at: "/tmp")

        XCTAssertEqual(opened.focusedTab?.panes.count, 1)
        XCTAssertEqual(controller.activeWorkspace()?.focusedTab?.panes.count, 2)
        XCTAssertEqual(changedPaneCounts.first, 1)
        XCTAssertEqual(changedPaneCounts.last, 2)
    }

    @MainActor
    func testControlPlaneOpenWorkspaceWithoutPathUsesConfiguredDefaultRoot() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner(),
            defaultWorkspaceRootPath: "/tmp"
        )
        let configurationCoordinator = OpenMUXConfigurationCoordinator(
            bridge: bridge,
            initialState: OpenMUXPreparedConfiguration(
                theme: .defaultTheme,
                defaultWorkspaceRootPath: "/tmp",
                keyBindingRegistry: .defaults,
                compiledConfigURL: nil,
                compiledHash: nil,
                diagnostics: []
            )
        )
        let socketURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "open.sock")
        let service = OpenMUXControlPlaneService(
            controller: controller,
            configurationCoordinator: configurationCoordinator,
            socketPath: socketURL.path(percentEncoded: false)
        )
        defer {
            service.stop()
            try? FileManager.default.removeItem(at: socketURL.deletingLastPathComponent())
        }

        try service.start()

        let requestFinished = expectation(description: "control-plane open request finished")
        let responseBox = LockedBox<JSONRPCResponse?>(nil)
        let errorBox = LockedBox<Error?>(nil)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let client = OmuxControlClient(socketPath: socketURL.path(percentEncoded: false))
                responseBox.value = try client.request(method: .openWorkspace, params: nil)
            } catch {
                errorBox.value = error
            }
            requestFinished.fulfill()
        }

        wait(for: [requestFinished], timeout: 3)

        XCTAssertNil(errorBox.value)
        XCTAssertNil(responseBox.value?.error)
        XCTAssertEqual(controller.activeWorkspace()?.rootPath, "/tmp")
    }

    @MainActor
    func testControlPlaneNavigationMethodsReturnFocusedTerminalContext() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )
        let configurationCoordinator = OpenMUXConfigurationCoordinator(
            bridge: bridge,
            initialState: OpenMUXPreparedConfiguration(
                theme: .defaultTheme,
                defaultWorkspaceRootPath: "/tmp",
                keyBindingRegistry: .defaults,
                compiledConfigURL: nil,
                compiledHash: nil,
                diagnostics: []
            )
        )
        let socketURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "navigation.sock")
        let service = OpenMUXControlPlaneService(
            controller: controller,
            configurationCoordinator: configurationCoordinator,
            socketPath: socketURL.path(percentEncoded: false)
        )
        defer {
            service.stop()
            try? FileManager.default.removeItem(at: socketURL.deletingLastPathComponent())
        }

        try service.start()

        let workspace = try controller.openWorkspace(at: "/tmp")
        let firstPaneID = try XCTUnwrap(workspace.focusedPane?.id)
        let withPaneTab = try XCTUnwrap(controller.createPaneTab())
        let secondPaneID = try XCTUnwrap(withPaneTab.focusedPane?.id)

        let nextTabResponse = try requestControlMethod(.focusNextPaneTab, socketPath: socketURL.path(percentEncoded: false))
        XCTAssertNil(nextTabResponse.error)
        XCTAssertEqual(targetPaneID(in: nextTabResponse), firstPaneID)

        let previousTabResponse = try requestControlMethod(.focusPreviousPaneTab, socketPath: socketURL.path(percentEncoded: false))
        XCTAssertNil(previousTabResponse.error)
        XCTAssertEqual(targetPaneID(in: previousTabResponse), secondPaneID)

        let singleVisiblePaneResponse = try requestControlMethod(.focusNextPane, socketPath: socketURL.path(percentEncoded: false))
        XCTAssertEqual(singleVisiblePaneResponse.error?.code, 409)

        let splitWorkspace = try XCTUnwrap(controller.splitFocusedPane(axis: .columns))
        let splitPaneID = try XCTUnwrap(splitWorkspace.focusedPane?.id)
        let nextPaneResponse = try requestControlMethod(.focusNextPane, socketPath: socketURL.path(percentEncoded: false))
        XCTAssertNil(nextPaneResponse.error)
        XCTAssertEqual(targetPaneID(in: nextPaneResponse), secondPaneID)

        let previousPaneResponse = try requestControlMethod(.focusPreviousPane, socketPath: socketURL.path(percentEncoded: false))
        XCTAssertNil(previousPaneResponse.error)
        XCTAssertEqual(targetPaneID(in: previousPaneResponse), splitPaneID)
    }

    @MainActor
    func testControlPlaneClosesWorkspaceAndRemovesTargetedPane() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner(),
            defaultWorkspaceRootPath: "/tmp"
        )
        let configurationCoordinator = OpenMUXConfigurationCoordinator(
            bridge: bridge,
            initialState: OpenMUXPreparedConfiguration(
                theme: .defaultTheme,
                defaultWorkspaceRootPath: "/tmp",
                keyBindingRegistry: .defaults,
                compiledConfigURL: nil,
                compiledHash: nil,
                diagnostics: []
            )
        )
        let socketURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "remove.sock")
        let service = OpenMUXControlPlaneService(
            controller: controller,
            configurationCoordinator: configurationCoordinator,
            socketPath: socketURL.path(percentEncoded: false)
        )
        defer {
            service.stop()
            try? FileManager.default.removeItem(at: socketURL.deletingLastPathComponent())
        }

        try service.start()

        let firstWorkspace = try controller.openWorkspace(at: "/tmp")
        let secondWorkspace = try controller.createWorkspace()
        let closeExplicitResponse = try requestControlMethod(
            .closeWorkspace,
            socketPath: socketURL.path(percentEncoded: false),
            params: .object(["workspaceID": .string(secondWorkspace.id.rawValue)])
        )
        XCTAssertNil(closeExplicitResponse.error)
        XCTAssertEqual(controller.allWorkspaces().map(\.id), [firstWorkspace.id])

        let closeLastResponse = try requestControlMethod(.closeWorkspace, socketPath: socketURL.path(percentEncoded: false))
        XCTAssertEqual(closeLastResponse.error?.code, 409)

        let splitWorkspace = try XCTUnwrap(controller.splitFocusedPane(axis: .columns))
        let firstPaneID = try XCTUnwrap(splitWorkspace.focusedTab?.visiblePaneIDs.first)
        let secondPaneID = try XCTUnwrap(splitWorkspace.focusedPane?.id)
        let removePaneResponse = try requestControlMethod(
            .removePane,
            socketPath: socketURL.path(percentEncoded: false),
            params: .object(["target": ControlPlaneTerminalTarget.pane(firstPaneID).rpcValue])
        )

        XCTAssertNil(removePaneResponse.error)
        XCTAssertEqual(targetPaneID(in: removePaneResponse), firstPaneID)
        XCTAssertEqual(controller.activeWorkspace()?.focusedTab?.panes.map(\.id), [secondPaneID])

        let invalidPaneResponse = try requestControlMethod(
            .removePane,
            socketPath: socketURL.path(percentEncoded: false),
            params: .object(["target": ControlPlaneTerminalTarget.pane(PaneID(rawValue: "missing")).rpcValue])
        )
        XCTAssertEqual(invalidPaneResponse.error?.code, 404)
    }

    @MainActor
    func testControlPlanePaneStatusUpdatesProgressOrbStateAndPublishesEvent() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner(),
            defaultWorkspaceRootPath: "/tmp"
        )
        let configurationCoordinator = OpenMUXConfigurationCoordinator(
            bridge: bridge,
            initialState: OpenMUXPreparedConfiguration(
                theme: .defaultTheme,
                defaultWorkspaceRootPath: "/tmp",
                keyBindingRegistry: .defaults,
                compiledConfigURL: nil,
                compiledHash: nil,
                diagnostics: []
            )
        )
        let socketURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "pane-status.sock")
        let service = OpenMUXControlPlaneService(
            controller: controller,
            configurationCoordinator: configurationCoordinator,
            socketPath: socketURL.path(percentEncoded: false)
        )
        defer {
            service.stop()
            try? FileManager.default.removeItem(at: socketURL.deletingLastPathComponent())
        }

        var publishedEvent: ControlPlaneEvent?
        controller.onControlPlaneEvent = { event in
            if event.name == ControlPlaneActionEventName.paneStatusChanged.rawValue {
                publishedEvent = event
            }
        }
        try service.start()

        let workspace = try controller.openWorkspace(at: "/tmp")
        let pane = try XCTUnwrap(workspace.focusedPane)
        let response = try requestControlMethod(
            .paneStatus,
            socketPath: socketURL.path(percentEncoded: false),
            params: ControlPlanePaneStatusRequest(
                target: .pane(pane.id),
                state: .error,
                label: "Codex",
                message: "tests failed",
                source: "hook.codex"
            ).rpcValue
        )

        XCTAssertNil(response.error)
        XCTAssertEqual(controller.activeWorkspace()?.focusedPane?.terminalState.progress?.state, .error)
        XCTAssertEqual(publishedEvent?.paneID, pane.id)
        XCTAssertEqual(publishedEvent?.payload.objectValue?["state"], .string("error"))
        XCTAssertEqual(publishedEvent?.payload.objectValue?["label"], .string("Codex"))
        XCTAssertEqual(publishedEvent?.payload.objectValue?["message"], .string("tests failed"))
        XCTAssertEqual(publishedEvent?.payload.objectValue?["source"], .string("hook.codex"))
    }

    @MainActor
    func testControlPlaneManagesExtensionPaneLifecycleAndRejectsTerminalClose() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner(),
            defaultWorkspaceRootPath: "/tmp"
        )
        let configurationCoordinator = OpenMUXConfigurationCoordinator(
            bridge: bridge,
            initialState: OpenMUXPreparedConfiguration(
                theme: .defaultTheme,
                defaultWorkspaceRootPath: "/tmp",
                keyBindingRegistry: .defaults,
                compiledConfigURL: nil,
                compiledHash: nil,
                diagnostics: []
            )
        )
        let socketURL = URL(fileURLWithPath: "/tmp/omux-ext-\(UUID().uuidString).sock")
        let service = OpenMUXControlPlaneService(
            controller: controller,
            configurationCoordinator: configurationCoordinator,
            socketPath: socketURL.path(percentEncoded: false)
        )
        defer {
            service.stop()
            try? FileManager.default.removeItem(at: socketURL)
        }

        try service.start()

        let workspace = try controller.openWorkspace(at: "/tmp")
        let terminalPaneID = try XCTUnwrap(workspace.focusedPane?.id)
        let createResponse = try requestControlMethod(
            .createExtensionPane,
            socketPath: socketURL.path(percentEncoded: false),
            params: .object([
                "pluginID": .string("dev.fingergun.markdown-preview"),
                "title": .string("README.md"),
                "source": .string("/tmp/README.md"),
                "html": .string("<h1>README</h1>"),
            ])
        )

        XCTAssertNil(createResponse.error)
        guard case .object(let created)? = createResponse.result,
              case .string(let extensionPaneIDRaw)? = created["paneID"]
        else {
            return XCTFail("expected extension pane result")
        }

        let extensionPaneID = PaneID(rawValue: extensionPaneIDRaw)
        let updateResponse = try requestControlMethod(
            .updateExtensionPane,
            socketPath: socketURL.path(percentEncoded: false),
            params: .object([
                "paneID": .string(extensionPaneID.rawValue),
                "pluginID": .string("dev.fingergun.markdown-preview"),
                "title": .string("README.md"),
                "status": .string("error"),
                "message": .string("render failed"),
            ])
        )
        XCTAssertNil(updateResponse.error)
        XCTAssertEqual(
            controller.allWorkspaces().flatMap(\.tabs).flatMap(\.panes).first(where: { $0.id == extensionPaneID })?.extensionPane?.status,
            .error
        )

        let closeTerminalResponse = try requestControlMethod(
            .closeExtensionPane,
            socketPath: socketURL.path(percentEncoded: false),
            params: .object(["paneID": .string(terminalPaneID.rawValue)])
        )
        XCTAssertEqual(closeTerminalResponse.error?.code, 400)

        let closeExtensionResponse = try requestControlMethod(
            .closeExtensionPane,
            socketPath: socketURL.path(percentEncoded: false),
            params: .object(["paneID": .string(extensionPaneID.rawValue)])
        )
        XCTAssertNil(closeExtensionResponse.error)
        XCTAssertNil(controller.allWorkspaces().flatMap(\.tabs).flatMap(\.panes).first(where: { $0.id == extensionPaneID }))
    }

    @MainActor
    func testControlPlaneWorkspaceMutationsRunOnMainThreadForHookDrivenRequests() throws {
        let runtime = MainThreadRecordingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )
        let configurationCoordinator = OpenMUXConfigurationCoordinator(
            bridge: bridge,
            initialState: OpenMUXPreparedConfiguration(
                theme: .defaultTheme,
                defaultWorkspaceRootPath: "/tmp",
                keyBindingRegistry: .defaults,
                compiledConfigURL: nil,
                compiledHash: nil,
                diagnostics: []
            )
        )
        let socketURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "control.sock")
        let service = OpenMUXControlPlaneService(
            controller: controller,
            configurationCoordinator: configurationCoordinator,
            socketPath: socketURL.path(percentEncoded: false)
        )
        defer {
            service.stop()
            try? FileManager.default.removeItem(at: socketURL.deletingLastPathComponent())
        }

        try service.start()
        _ = try controller.openWorkspace(at: "/tmp")

        let requestFinished = expectation(description: "control-plane split request finished")
        let responseBox = LockedBox<JSONRPCResponse?>(nil)
        let errorBox = LockedBox<Error?>(nil)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let client = OmuxControlClient(socketPath: socketURL.path(percentEncoded: false))
                let response = try client.request(
                    method: .splitPane,
                    params: .object(["axis": .string(PaneSplitAxis.rows.rawValue)])
                )
                responseBox.value = response
            } catch {
                errorBox.value = error
            }
            requestFinished.fulfill()
        }

        wait(for: [requestFinished], timeout: 3)

        XCTAssertNil(errorBox.value)
        XCTAssertNil(responseBox.value?.error)
        XCTAssertEqual(runtime.nonMainThreadOperations, [])
        XCTAssertEqual(controller.activeWorkspace()?.focusedTab?.panes.count, 2)
    }

    @MainActor
    func testControlPlaneTerminalHistoryReturnsPaneMetadataAndInvalidPaneError() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )
        let configurationCoordinator = OpenMUXConfigurationCoordinator(
            bridge: bridge,
            initialState: OpenMUXPreparedConfiguration(
                theme: .defaultTheme,
                defaultWorkspaceRootPath: "/tmp",
                keyBindingRegistry: .defaults,
                compiledConfigURL: nil,
                compiledHash: nil,
                diagnostics: []
            )
        )
        let socketURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "h.sock")
        let service = OpenMUXControlPlaneService(
            controller: controller,
            configurationCoordinator: configurationCoordinator,
            socketPath: socketURL.path(percentEncoded: false)
        )
        defer {
            service.stop()
            try? FileManager.default.removeItem(at: socketURL.deletingLastPathComponent())
        }

        try service.start()
        let workspace = try controller.openWorkspace(at: "/tmp/history")
        let pane = try XCTUnwrap(workspace.focusedPane)
        let surfaceID = try XCTUnwrap(bridge.surface(for: pane.id)?.runtimeSurfaceID)
        runtime.scrollbackBySurface[surfaceID] = "one\ntwo\nthree"

        let requestFinished = expectation(description: "history request finished")
        let responseBox = LockedBox<JSONRPCResponse?>(nil)
        let errorBox = LockedBox<Error?>(nil)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let client = OmuxControlClient(socketPath: socketURL.path(percentEncoded: false))
                responseBox.value = try client.request(
                    method: .terminalHistory,
                    params: .object([
                        "paneID": .string(pane.id.rawValue),
                        "maxLines": .integer(2),
                        "maxBytes": .integer(1_000),
                    ])
                )
            } catch {
                errorBox.value = error
            }
            requestFinished.fulfill()
        }

        wait(for: [requestFinished], timeout: 3)

        XCTAssertNil(errorBox.value)
        XCTAssertNil(responseBox.value?.error)
        guard case .object(let result)? = responseBox.value?.result,
              case .array(let items)? = result["items"],
              case .object(let item)? = items.first
        else {
            return XCTFail("expected history result")
        }
        XCTAssertEqual(item["workspaceID"], .string(workspace.id.rawValue))
        XCTAssertEqual(item["paneID"], .string(pane.id.rawValue))
        XCTAssertEqual(item["text"], .string("two\nthree"))
        XCTAssertEqual(item["truncated"], .bool(true))

        let invalidRequestFinished = expectation(description: "invalid history request finished")
        let invalidResponseBox = LockedBox<JSONRPCResponse?>(nil)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                invalidResponseBox.value = try OmuxControlClient(socketPath: socketURL.path(percentEncoded: false)).request(
                    method: .terminalHistory,
                    params: .object(["paneID": .string("missing")])
                )
            } catch {
                errorBox.value = error
            }
            invalidRequestFinished.fulfill()
        }
        wait(for: [invalidRequestFinished], timeout: 3)

        XCTAssertNil(errorBox.value)
        XCTAssertEqual(invalidResponseBox.value?.error?.code, 404)
    }

    func testPaneTabTitleFormatterKeepsShortTitlesUnchanged() {
        XCTAssertEqual(PaneTabTitleFormatter.displayTitle("Opencode"), "Opencode")
        XCTAssertEqual(PaneTabTitleFormatter.displayTitle("~/Projects/DungeonPlanner"), "~/Projects/DungeonPlanner")

        let exactMaximum = String(repeating: "a", count: PaneTabTitleFormatter.defaultMaximumLength)
        XCTAssertEqual(PaneTabTitleFormatter.displayTitle(exactMaximum), exactMaximum)
    }

    func testPaneTabTitleFormatterBoundsLongTitles() {
        let title = ".../T/openmux-update-0733BCA7-E332-40BC-B156-16BA405604E7/unpacked"
        let displayTitle = PaneTabTitleFormatter.displayTitle(title, maximumLength: 44)

        XCTAssertLessThanOrEqual(displayTitle.count, 44)
        XCTAssertTrue(displayTitle.hasPrefix(".../T/openmux-update"))
        XCTAssertTrue(displayTitle.hasSuffix("unpacked"))
        XCTAssertNotEqual(displayTitle, title)
    }

    func testPaneTabTitleFormatterSplitsTruncatedTitlesWithinMaximum() {
        XCTAssertEqual(PaneTabTitleFormatter.displayTitle("abcdefghij", maximumLength: 8), "ab...hij")
        XCTAssertEqual(PaneTabTitleFormatter.displayTitle("abcdefghij", maximumLength: 9), "abc...hij")
    }

    @MainActor
    func testPaneTabTitleLabelDoesNotMiddleTruncateShortTitles() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )
        let workspace = try controller.openWorkspace(at: "/tmp")
        let pane = try XCTUnwrap(workspace.focusedPane)
        let renamedWorkspace = try XCTUnwrap(controller.renamePaneTab(pane.id, to: "Opencode"))
        let windowController = WorkspaceWindowController(
            workspace: renamedWorkspace,
            controller: controller
        )
        let rootView = try XCTUnwrap(windowController.window?.contentViewController?.view)
        rootView.layoutSubtreeIfNeeded()

        let tabButton = try XCTUnwrap(findViews(ofType: NSControl.self, in: rootView).first {
            $0.identifier?.rawValue == "pane-tab-\(pane.id.rawValue)"
        })
        let titleLabel = try XCTUnwrap(findLabelView(withString: "Opencode", in: tabButton))

        XCTAssertEqual(titleLabel.stringValue, "Opencode")
        XCTAssertNotEqual(titleLabel.lineBreakMode, .byTruncatingMiddle)
        XCTAssertGreaterThanOrEqual(titleLabel.frame.width, titleLabel.intrinsicContentSize.width)
    }

    func testPaneTabDragRequiresInitializedTerminalPane() throws {
        let firstPane = Pane(
            title: "one",
            session: SessionDescriptor(shell: "/bin/zsh", workingDirectory: "/tmp")
        )
        var secondPane = Pane(
            title: "two",
            session: SessionDescriptor(shell: "/bin/zsh", workingDirectory: "/tmp")
        )
        let uninitializedStack = PaneStack(panes: [firstPane, secondPane], focusedPaneID: firstPane.id)
        let uninitializedTab = Tab(title: "Main", rootLayout: .paneStack(uninitializedStack), focusedPaneID: firstPane.id)

        secondPane.terminalState.reportedTitle = "zsh"
        let initializedStack = PaneStack(panes: [firstPane, secondPane], focusedPaneID: firstPane.id)
        let initializedTab = Tab(title: "Main", rootLayout: .paneStack(initializedStack), focusedPaneID: firstPane.id)
        let stackID = initializedStack.id

        XCTAssertFalse(
            PaneTabDragReadiness.canStart(
                paneID: secondPane.id,
                sourceStackID: uninitializedStack.id,
                in: uninitializedTab,
                attachedSessionExists: false
            )
        )
        XCTAssertFalse(
            PaneTabDragReadiness.canStart(
                paneID: secondPane.id,
                sourceStackID: uninitializedStack.id,
                in: uninitializedTab,
                attachedSessionExists: true
            )
        )

        XCTAssertFalse(
            PaneTabDragReadiness.canStart(
                paneID: secondPane.id,
                sourceStackID: stackID,
                in: initializedTab,
                attachedSessionExists: false
            )
        )
        XCTAssertTrue(
            PaneTabDragReadiness.canStart(
                paneID: secondPane.id,
                sourceStackID: stackID,
                in: initializedTab,
                attachedSessionExists: true
            )
        )
    }

    func testPaneTabDragRequiresReadyExtensionPane() throws {
        let firstPane = Pane(
            title: "one",
            session: SessionDescriptor(shell: "/bin/zsh", workingDirectory: "/tmp")
        )
        let disabledPane = Pane(
            title: "extension",
            extensionPane: ExtensionPaneDescriptor(pluginID: "test", status: .disabled)
        )
        let readyPane = Pane(
            title: "extension",
            extensionPane: ExtensionPaneDescriptor(pluginID: "test", status: .ready)
        )
        let disabledStack = PaneStack(panes: [firstPane, disabledPane], focusedPaneID: firstPane.id)
        let readyStack = PaneStack(panes: [firstPane, readyPane], focusedPaneID: firstPane.id)
        let disabledTab = Tab(title: "Main", rootLayout: .paneStack(disabledStack), focusedPaneID: firstPane.id)
        let readyTab = Tab(title: "Main", rootLayout: .paneStack(readyStack), focusedPaneID: firstPane.id)
        let disabledStackID = disabledStack.id
        let readyStackID = readyStack.id

        XCTAssertFalse(
            PaneTabDragReadiness.canStart(
                paneID: disabledPane.id,
                sourceStackID: disabledStackID,
                in: disabledTab,
                attachedSessionExists: true
            )
        )
        XCTAssertTrue(
            PaneTabDragReadiness.canStart(
                paneID: readyPane.id,
                sourceStackID: readyStackID,
                in: readyTab,
                attachedSessionExists: false
            )
        )
    }

    func testWorkspaceIconResolverDetectsProjectMarkersAndAITitles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceIconResolverTests-\(UUID().uuidString)", isDirectory: true)
        let app = root.appendingPathComponent("app", isDirectory: true)
        let source = app.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try "{}".write(to: app.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let resolver = WorkspaceIconResolver()
        let nodePane = Pane(title: "Shell", session: SessionDescriptor(shell: "/bin/sh", workingDirectory: source.path))
        let aiPane = Pane(title: "GitHub Copilot", session: SessionDescriptor(shell: "/bin/sh", workingDirectory: source.path))

        XCTAssertEqual(resolver.icon(for: nodePane).kind, .node)
        XCTAssertEqual(resolver.icon(for: aiPane).kind, .ai)
    }

    func testWorkspaceIconResolverDetectsTerminalApplicationTitles() throws {
        let resolver = WorkspaceIconResolver()
        let cases: [(String, OmuxSemanticIcon.Kind)] = [
            ("hx", .helix),
            ("helix src/main.swift", .helix),
            ("vim README.md", .vim),
            ("nvim init.lua", .neovim),
            ("tmux", .tmux),
            ("ssh dev.example.com", .ssh),
            ("lazygit", .git),
            ("lazydocker", .docker),
            ("nano notes.txt", .nano),
            ("emacs", .emacs),
        ]

        for (title, expectedKind) in cases {
            let pane = Pane(
                title: "project",
                session: SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp/project"),
                terminalState: PaneTerminalState(reportedTitle: title)
            )
            XCTAssertEqual(resolver.icon(for: pane).kind, expectedKind, title)
        }
    }

    func testWorkspaceIconResolverDetectsTerminalApplicationScreenText() throws {
        let resolver = WorkspaceIconResolver()
        let pane = Pane(
            title: "project",
            session: SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp/project")
        )

        XCTAssertEqual(
            resolver.icon(for: pane, terminalText: "VIM - Vi IMproved\nversion 9.1").kind,
            .vim
        )
        XCTAssertEqual(
            resolver.icon(for: pane, terminalText: "UW PICO 5.09 New Buffer\n^G Get Help").kind,
            .nano
        )
        XCTAssertEqual(
            resolver.icon(for: pane, terminalText: "[scratch]\nNOR [scratch] 1 sel 1:1").kind,
            .helix
        )
    }

    @MainActor
    func testSidebarAndPaneTabsUseTerminalScreenTextForFullScreenAppIcons() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )
        let workspace = try controller.openWorkspace(at: "/tmp/omux")
        let pane = try XCTUnwrap(workspace.focusedPane)
        let runtimeSurfaceID = try XCTUnwrap(bridge.surface(for: pane.id)?.runtimeSurfaceID)
        runtime.scrollbackBySurface[runtimeSurfaceID] = "VIM - Vi IMproved\nversion 9.1"

        let windowController = WorkspaceWindowController(
            workspace: workspace,
            controller: controller,
            initialIcons: OmuxConfigUI.Icons(provider: .text)
        )
        let rootView = try XCTUnwrap(windowController.window?.contentViewController?.view)
        rootView.layoutSubtreeIfNeeded()

        let vimIconLabels = findViews(ofType: NSTextField.self, in: rootView)
            .filter { $0.stringValue == "Vi" }
        XCTAssertGreaterThanOrEqual(vimIconLabels.count, 2)
    }

    func testWorkspaceIconResolverAggregatesWorkspaceIcons() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceIconResolverTests-\(UUID().uuidString)", isDirectory: true)
        let swiftProject = root.appendingPathComponent("swift", isDirectory: true)
        let plainProject = root.appendingPathComponent("plain", isDirectory: true)
        try FileManager.default.createDirectory(at: swiftProject, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: plainProject, withIntermediateDirectories: true)
        try "// swift-tools-version: 6.0\n".write(
            to: swiftProject.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let plainPane = Pane(title: "Shell", session: SessionDescriptor(shell: "/bin/sh", workingDirectory: plainProject.path))
        let swiftPane = Pane(title: "Shell", session: SessionDescriptor(shell: "/bin/sh", workingDirectory: swiftProject.path))
        let tab = Tab(title: "Main", panes: [plainPane, swiftPane], focusedPaneID: plainPane.id)
        let workspace = Workspace(generatedName: "Workspace", rootPath: root.path, tabs: [tab], focusedTabID: tab.id)

        XCTAssertEqual(WorkspaceIconResolver().icon(for: workspace).kind, .swift)
    }

    @MainActor
    func testIconRendererUsesBundledNerdFontByDefault() throws {
        let icon = try XCTUnwrap(
            OmuxIconRenderer(
                configuration: OmuxConfigUI.Icons(provider: .nerdFont),
                pointSize: 11,
                weight: .medium
            ).render(.node)
        )

        XCTAssertEqual(icon.text, OmuxSemanticIcon.node.nerdFontGlyph)
        XCTAssertEqual(icon.font.familyName, "Symbols Nerd Font Mono")
        XCTAssertFalse(icon.prefersSymbol)
        XCTAssertEqual(icon.colorToken, .ansiGreen)
    }

    @MainActor
    func testBundledIconFontLoadsFromPackagedAppContentsResources() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BundledIconFontTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let appURL = root.appendingPathComponent("OpenMUX.app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        let executableURL = contentsURL.appendingPathComponent("MacOS/OpenMUXApp", isDirectory: false)
        let fontURL = resourcesURL
            .appendingPathComponent("OpenMUX_OmuxAppShell.bundle", isDirectory: true)
            .appendingPathComponent("SymbolsNerdFontMono-Regular.ttf", isDirectory: false)

        try FileManager.default.createDirectory(at: fontURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: executableURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0]).write(to: fontURL)
        try Data().write(to: executableURL)

        XCTAssertEqual(
            BundledIconFont.fontURL(
                mainBundleURL: appURL,
                mainResourceURL: resourcesURL,
                mainExecutableURL: executableURL
            )?.standardizedFileURL,
            fontURL.standardizedFileURL
        )
    }

    @MainActor
    func testBundledIconFontDoesNotUseSwiftPMFallbackForPackagedApp() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BundledIconFontTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let appURL = root.appendingPathComponent("OpenMUX.app", isDirectory: true)
        let executableURL = appURL
            .appendingPathComponent("Contents/MacOS/OpenMUXApp", isDirectory: false)
        try FileManager.default.createDirectory(at: executableURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: executableURL)

        XCTAssertNil(
            BundledIconFont.fontURL(
                mainBundleURL: appURL,
                mainResourceURL: nil,
                mainExecutableURL: executableURL
            )
        )
    }

    @MainActor
    func testIconRendererPrefersSFSymbolsWhenConfigured() throws {
        let icon = try XCTUnwrap(
            OmuxIconRenderer(
                configuration: OmuxConfigUI.Icons(provider: .sfSymbols),
                pointSize: 11,
                weight: .medium
            ).render(.node)
        )

        XCTAssertTrue(icon.prefersSymbol)
        XCTAssertEqual(icon.symbolName, "hexagon")
        XCTAssertEqual(icon.text, "JS")
        XCTAssertEqual(icon.colorToken, .ansiGreen)
    }

    @MainActor
    func testIconRendererCarriesColorToggle() throws {
        let icon = try XCTUnwrap(
            OmuxIconRenderer(
                configuration: OmuxConfigUI.Icons(provider: .text, colorsEnabled: false),
                pointSize: 11,
                weight: .medium
            ).render(.helix)
        )

        XCTAssertEqual(icon.text, "Hx")
        XCTAssertFalse(icon.colorsEnabled)
    }

    @MainActor
    func testIconRendererUsesDNAGlyphForHelix() throws {
        let icon = try XCTUnwrap(
            OmuxIconRenderer(
                configuration: OmuxConfigUI.Icons(provider: .nerdFont),
                pointSize: 11,
                weight: .medium
            ).render(.helix)
        )

        XCTAssertEqual(icon.text, "\u{ed7d}")
        XCTAssertEqual(icon.font.familyName, "Symbols Nerd Font Mono")
    }

    @MainActor
    func testSidebarAndPaneTabsRenderConfiguredTextIcons() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceIconUITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "{}".write(to: root.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )
        let workspace = try controller.openWorkspace(at: root.path)
        let windowController = WorkspaceWindowController(
            workspace: workspace,
            controller: controller,
            initialIcons: OmuxConfigUI.Icons(provider: .text)
        )
        let rootView = try XCTUnwrap(windowController.window?.contentViewController?.view)
        windowController.window?.contentView?.layoutSubtreeIfNeeded()
        rootView.layoutSubtreeIfNeeded()

        let iconLabels = findViews(ofType: NSTextField.self, in: rootView)
            .filter { $0.stringValue == "JS" }
        XCTAssertGreaterThanOrEqual(iconLabels.count, 2)
    }

    @MainActor
    private func findHostedTerminalPaneView(in view: NSView) -> HostedTerminalPaneView? {
        if let hosted = view as? HostedTerminalPaneView {
            return hosted
        }

        for subview in view.subviews {
            if let hosted = findHostedTerminalPaneView(in: subview) {
                return hosted
            }
        }

        return nil
    }

    @MainActor
    private func findView<T: NSView>(ofType type: T.Type, in view: NSView) -> T? {
        if let matched = view as? T {
            return matched
        }

        for subview in view.subviews {
            if let matched = findView(ofType: type, in: subview) {
                return matched
            }
        }

        return nil
    }

    @MainActor
    private func findLabel(withString string: String, in view: NSView) -> Bool {
        if let label = view as? NSTextField, label.stringValue == string {
            return true
        }

        return view.subviews.contains { findLabel(withString: string, in: $0) }
    }

    @MainActor
    private func findLabelView(withString string: String, in view: NSView) -> NSTextField? {
        if let label = view as? NSTextField, label.stringValue == string {
            return label
        }

        for subview in view.subviews {
            if let label = findLabelView(withString: string, in: subview) {
                return label
            }
        }

        return nil
    }

    @MainActor
    private func findViews<T: NSView>(ofType type: T.Type, in view: NSView) -> [T] {
        var matches: [T] = []
        if let matched = view as? T {
            matches.append(matched)
        }
        for subview in view.subviews {
            matches.append(contentsOf: findViews(ofType: type, in: subview))
        }
        return matches
    }

    @MainActor
    private func countVisibleNonEmptyLabels(in view: NSView) -> Int {
        let ownCount: Int
        if let label = view as? NSTextField, !label.isHidden, !label.stringValue.isEmpty {
            ownCount = 1
        } else {
            ownCount = 0
        }

        return ownCount + view.subviews.reduce(0) { $0 + countVisibleNonEmptyLabels(in: $1) }
    }

    @MainActor
    private func countVisibleLabels(withString string: String, in view: NSView) -> Int {
        let ownCount: Int
        if let label = view as? NSTextField, !label.isHidden, label.stringValue == string {
            ownCount = 1
        } else {
            ownCount = 0
        }

        return ownCount + view.subviews.reduce(0) { $0 + countVisibleLabels(withString: string, in: $1) }
    }

    @MainActor
    private func findAncestor<T: NSView>(ofType type: T.Type, for view: NSView) -> T? {
        var current = view.superview
        while let candidate = current {
            if let matched = candidate as? T {
                return matched
            }
            current = candidate.superview
        }
        return nil
    }

    @MainActor
    private func makeMouseEvent(window: NSWindow) -> NSEvent {
        try! XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: NSPoint(x: 12, y: 12),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            )
        )
    }

    private func runGit(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}

private extension Array where Element == NSMenuItem {
    func containsShortcut(title: String, key: String, modifiers expectedModifiers: NSEvent.ModifierFlags) -> Bool {
        contains { item in
            item.title == title
                && item.keyEquivalent == key
                && item.keyEquivalentModifierMask.structuralShortcutModifiers == expectedModifiers
        }
    }

    func containsShortcut(key: String, modifiers expectedModifiers: NSEvent.ModifierFlags) -> Bool {
        contains { item in
            item.keyEquivalent == key
                && item.keyEquivalentModifierMask.structuralShortcutModifiers == expectedModifiers
        }
    }
}

private extension NSEvent.ModifierFlags {
    var structuralShortcutModifiers: NSEvent.ModifierFlags {
        intersection([.command, .shift, .control, .option])
    }
}

private final class ActionEmittingGhosttyRuntime: GhosttyRuntime {
    private var sessions: [String: SessionDescriptor] = [:]
    private var transcriptBySurface: [String: String] = [:]
    private var inputBySurface: [String: String] = [:]
    private var terminalActionHandler: (@Sendable (RuntimeTerminalActionRecord) -> Bool)?
    var scrollbackBySurface: [String: String] = [:]
    var transcript = ""
    var sentTextCount = 0
    private(set) var executedCommands: [String] = []
    private(set) var destroyedSurfaceIDs: [String] = []
    private(set) var terminalTextSnapshotCount = 0
    private(set) var clearedScreenAndScrollbackSurfaceIDs: [String] = []
    var failNextSend = false

    func createSurface(for paneID: PaneID) throws -> String {
        "action:\(paneID.rawValue)"
    }

    func attach(session: SessionDescriptor, to runtimeSurfaceID: String) throws {
        sessions[runtimeSurfaceID] = session
    }

    func session(for runtimeSurfaceID: String) -> SessionDescriptor? {
        sessions[runtimeSurfaceID]
    }

    func destroySurface(runtimeSurfaceID: String) throws {
        destroyedSurfaceIDs.append(runtimeSurfaceID)
        sessions.removeValue(forKey: runtimeSurfaceID)
        transcriptBySurface.removeValue(forKey: runtimeSurfaceID)
        inputBySurface.removeValue(forKey: runtimeSurfaceID)
    }

    @MainActor
    func makeHostedSurfaceView(for paneID: PaneID, runtimeSurfaceID: String) -> NSView? {
        _ = paneID
        _ = runtimeSurfaceID
        return NSView()
    }

    func ownsSession(for runtimeSurfaceID: String) -> Bool {
        sessions[runtimeSurfaceID] != nil
    }

    func send(text: String, to runtimeSurfaceID: String) throws {
        guard sessions[runtimeSurfaceID] != nil else {
            throw TerminalBridgeError.runtimeAttachFailed(runtimeSurfaceID)
        }
        if failNextSend {
            failNextSend = false
            throw TerminalBridgeError.runtimeAttachFailed(runtimeSurfaceID)
        }

        sentTextCount += 1
        inputBySurface[runtimeSurfaceID, default: ""].append(text)
    }

    func currentInputText() -> String {
        inputBySurface.values.joined()
    }

    func handle(_ event: NormalizedKeyEvent, on runtimeSurfaceID: String) throws {
        guard sessions[runtimeSurfaceID] != nil else {
            throw TerminalBridgeError.runtimeAttachFailed(runtimeSurfaceID)
        }

        guard event.phase == .keyDown, event.keyCode == 36 else {
            return
        }

        let command = inputBySurface[runtimeSurfaceID, default: ""]
        inputBySurface[runtimeSurfaceID] = ""
        executedCommands.append(command.trimmingCharacters(in: .whitespacesAndNewlines))
        execute(command: command, on: runtimeSurfaceID)
    }

    func setTerminalActionHandler(
        _ handler: (@Sendable (RuntimeTerminalActionRecord) -> Bool)?
    ) {
        terminalActionHandler = handler
    }

    func snapshot(
        paneID: PaneID,
        sessionID: SessionID,
        descriptor: SessionDescriptor,
        runtimeSurfaceID: String,
        defaultSize: TerminalSize
    ) -> TerminalSessionSnapshot? {
        guard sessions[runtimeSurfaceID] != nil else {
            return nil
        }

        let surfaceTranscript = transcript + transcriptBySurface[runtimeSurfaceID, default: ""]
        return TerminalSessionSnapshot(
            paneID: paneID,
            sessionID: sessionID,
            runtimeSurfaceID: runtimeSurfaceID,
            transcript: surfaceTranscript,
            currentInput: inputBySurface[runtimeSurfaceID, default: ""],
            shell: descriptor.shell,
            workingDirectory: sessions[runtimeSurfaceID]?.workingDirectory ?? descriptor.workingDirectory,
            columns: defaultSize.columns,
            rows: defaultSize.rows
        )
    }

    func scrollbackSnapshot(runtimeSurfaceID: String, maxBytes: Int, maxLines: Int) -> PaneScrollbackSnapshot? {
        terminalTextSnapshot(
            runtimeSurfaceID: runtimeSurfaceID,
            maxBytes: maxBytes,
            maxLines: maxLines
        ).scrollbackSnapshot
    }

    func clearScreenAndScrollback(runtimeSurfaceID: String) throws -> Bool {
        guard sessions[runtimeSurfaceID] != nil else {
            throw TerminalBridgeError.runtimeAttachFailed(runtimeSurfaceID)
        }
        clearedScreenAndScrollbackSurfaceIDs.append(runtimeSurfaceID)
        scrollbackBySurface[runtimeSurfaceID] = ""
        transcriptBySurface[runtimeSurfaceID] = ""
        inputBySurface[runtimeSurfaceID] = ""
        return true
    }

    func terminalTextSnapshot(runtimeSurfaceID: String, maxBytes: Int, maxLines: Int) -> TerminalTextSnapshot {
        terminalTextSnapshotCount += 1
        if let scrollback = scrollbackBySurface[runtimeSurfaceID] {
            return TerminalTextSnapshot.bounded(
                text: scrollback,
                maxBytes: maxBytes,
                maxLines: maxLines
            )
        }

        let surfaceText = transcript + transcriptBySurface[runtimeSurfaceID, default: ""]
        guard surfaceText.isEmpty == false || inputBySurface[runtimeSurfaceID]?.isEmpty == false else {
            return .unavailable(reason: "history unavailable", maxBytes: maxBytes, maxLines: maxLines)
        }

        return TerminalTextSnapshot.bounded(
            text: surfaceText + inputBySurface[runtimeSurfaceID, default: ""],
            maxBytes: maxBytes,
            maxLines: maxLines
        )
    }

    func emit(_ action: TerminalAction, on runtimeSurfaceID: String) {
        if case .workingDirectoryChanged(let path) = action,
           var session = sessions[runtimeSurfaceID] {
            session.workingDirectory = path
            sessions[runtimeSurfaceID] = session
        }
        _ = terminalActionHandler?(RuntimeTerminalActionRecord(runtimeSurfaceID: runtimeSurfaceID, action: action))
    }

    private func execute(command: String, on runtimeSurfaceID: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return
        }

        if trimmed.hasPrefix("cd ") {
            updateWorkingDirectory(String(trimmed.dropFirst(3)), on: runtimeSurfaceID)
            return
        }

        if trimmed == "pwd" {
            transcriptBySurface[runtimeSurfaceID, default: ""].append((sessions[runtimeSurfaceID]?.workingDirectory ?? "/tmp") + "\n")
            return
        }

        let output = trimmed
            .components(separatedBy: " && ")
            .compactMap(printfOutput)
            .joined()
        transcriptBySurface[runtimeSurfaceID, default: ""].append(output)
    }

    private func updateWorkingDirectory(_ path: String, on runtimeSurfaceID: String) {
        guard var session = sessions[runtimeSurfaceID] else {
            return
        }

        let cleaned = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("/") {
            session.workingDirectory = cleaned
        } else {
            session.workingDirectory = URL(fileURLWithPath: session.workingDirectory)
                .appendingPathComponent(cleaned)
                .standardizedFileURL
                .path
        }
        sessions[runtimeSurfaceID] = session
        emit(.workingDirectoryChanged(session.workingDirectory), on: runtimeSurfaceID)
    }

    private func printfOutput(from command: String) -> String? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("printf '"), trimmed.hasSuffix("'") else {
            return nil
        }

        let start = trimmed.index(trimmed.startIndex, offsetBy: "printf '".count)
        let end = trimmed.index(before: trimmed.endIndex)
        return String(trimmed[start..<end])
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\'", with: "'")
    }
}

private final class MainThreadRecordingGhosttyRuntime: GhosttyRuntime, @unchecked Sendable {
    private let lock = NSLock()
    private var sessions: [String: SessionDescriptor] = [:]
    private var recordedNonMainThreadOperations: [String] = []

    var nonMainThreadOperations: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedNonMainThreadOperations
    }

    func createSurface(for paneID: PaneID) throws -> String {
        recordThread(operation: "createSurface")
        return "main-thread:\(paneID.rawValue)"
    }

    func attach(session: SessionDescriptor, to runtimeSurfaceID: String) throws {
        recordThread(operation: "attach")
        lock.lock()
        sessions[runtimeSurfaceID] = session
        lock.unlock()
    }

    func destroySurface(runtimeSurfaceID: String) throws {
        recordThread(operation: "destroySurface")
        lock.lock()
        sessions.removeValue(forKey: runtimeSurfaceID)
        lock.unlock()
    }

    @MainActor
    func makeHostedSurfaceView(for paneID: PaneID, runtimeSurfaceID: String) -> NSView? {
        _ = paneID
        _ = runtimeSurfaceID
        return NSView()
    }

    func ownsSession(for runtimeSurfaceID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return sessions[runtimeSurfaceID] != nil
    }

    func snapshot(
        paneID: PaneID,
        sessionID: SessionID,
        descriptor: SessionDescriptor,
        runtimeSurfaceID: String,
        defaultSize: TerminalSize
    ) -> TerminalSessionSnapshot? {
        lock.lock()
        let hasSession = sessions[runtimeSurfaceID] != nil
        lock.unlock()
        guard hasSession else {
            return nil
        }

        return TerminalSessionSnapshot(
            paneID: paneID,
            sessionID: sessionID,
            runtimeSurfaceID: runtimeSurfaceID,
            transcript: "",
            currentInput: "",
            shell: descriptor.shell,
            workingDirectory: descriptor.workingDirectory,
            columns: defaultSize.columns,
            rows: defaultSize.rows
        )
    }

    private func recordThread(operation: String) {
        guard Thread.isMainThread == false else {
            return
        }

        lock.lock()
        recordedNonMainThreadOperations.append(operation)
        lock.unlock()
    }
}

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }
}

private final class CapturingHookLauncher: HookProcessLaunching, @unchecked Sendable {
    private(set) var invocations: [HookInvocation] = []

    func launch(executableURL: URL, arguments: [String], environment: [String: String], input: Data) throws {
        _ = executableURL
        _ = arguments
        _ = environment
        invocations.append(try JSONDecoder().decode(HookInvocation.self, from: input))
    }
}

private final class ClosureHookLauncher: HookProcessLaunching, @unchecked Sendable {
    private let body: () throws -> Void

    init(body: @escaping () throws -> Void) {
        self.body = body
    }

    func launch(executableURL: URL, arguments: [String], environment: [String: String], input: Data) throws {
        _ = executableURL
        _ = arguments
        _ = environment
        _ = input
        try body()
    }
}
