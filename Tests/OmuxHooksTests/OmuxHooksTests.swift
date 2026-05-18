import Foundation
import XCTest
@testable import OmuxCore
@testable import OmuxHooks

final class OmuxHooksTests: XCTestCase {
    func testUserHookDirectoryDiscoveryFindsExecutableHandlersInOrder() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let hooksDirectory = tempDirectory.appending(path: "hooks")
        let commandDirectory = hooksDirectory.appending(path: "terminal-command-finished")
        let workspaceDirectory = hooksDirectory.appending(path: "workspace-opened")
        try FileManager.default.createDirectory(at: commandDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspaceDirectory, withIntermediateDirectories: true)

        let second = commandDirectory.appending(path: "20-notify")
        let first = commandDirectory.appending(path: "10-log")
        let note = commandDirectory.appending(path: "README.md")
        let hidden = commandDirectory.appending(path: ".disabled")
        let nested = commandDirectory.appending(path: "30-nested")
        let workspaceHook = workspaceDirectory.appending(path: "10-bootstrap")

        try writeExecutableHook(at: second)
        try writeExecutableHook(at: first)
        try writeHook(at: note)
        try writeExecutableHook(at: hidden)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try writeExecutableHook(at: workspaceHook)

        let registry = UserHookDirectoryDiscovery.registry(in: hooksDirectory)
        let commandMatches = registry.matchingDescriptors(
            for: HookInvocation(category: .command, name: "terminal-command-finished")
        )
        let lifecycleMatches = registry.matchingDescriptors(
            for: HookInvocation(category: .lifecycle, name: "workspace-opened")
        )

        XCTAssertEqual(commandMatches.map { $0.executableURL.lastPathComponent }, ["10-log", "20-notify"])
        XCTAssertEqual(lifecycleMatches.map { $0.executableURL.lastPathComponent }, ["10-bootstrap"])
    }

    func testUserHookDirectoryDiscoveryMissingRootIsEmpty() {
        let missingDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "hooks")

        let registry = UserHookDirectoryDiscovery.registry(in: missingDirectory)
        let matches = registry.matchingDescriptors(
            for: HookInvocation(category: .command, name: "terminal-command-finished")
        )

        XCTAssertTrue(matches.isEmpty)
    }

    func testExternalHookRunnerExecutesProcessWithJSONPayload() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let outputURL = tempDirectory.appending(path: "payload.json")
        let scriptURL = tempDirectory.appending(path: "capture.sh")
        let script = """
        #!/bin/sh
        cat > "$1"
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path(percentEncoded: false)
        )

        let registry = HookRegistry()
        registry.register(
            HookDescriptor(
                category: .lifecycle,
                name: "workspace-opened",
                executableURL: scriptURL,
                arguments: [outputURL.path(percentEncoded: false)]
            )
        )

        let runner = ExternalHookRunner(
            registry: registry,
            pluginsDirectoryURL: tempDirectory.appending(path: "plugins")
        )
        try runner.emit(
            HookInvocation(
                category: .lifecycle,
                name: "workspace-opened",
                payload: .object(["path": .string("/tmp/project")])
            )
        )

        let payload = try Data(contentsOf: outputURL)
        let invocation = try JSONDecoder().decode(HookInvocation.self, from: payload)

        XCTAssertEqual(invocation.name, "workspace-opened")
        XCTAssertEqual(invocation.payload.objectValue?["path"], .string("/tmp/project"))
    }

    func testProcessHookLauncherProvidesDeveloperPathForGuiLaunchedApps() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let outputURL = tempDirectory.appending(path: "path.txt")
        let scriptURL = tempDirectory.appending(path: "capture-path.sh")
        try """
        #!/bin/sh
        printf '%s' "$PATH" > "$1"
        """.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path(percentEncoded: false)
        )

        try ProcessHookLauncher().launch(
            executableURL: scriptURL,
            arguments: [outputURL.path(percentEncoded: false)],
            environment: ["PATH": "/usr/bin:/bin"],
            input: Data()
        )

        let path = try String(contentsOf: outputURL, encoding: .utf8)
        let components = Set(path.split(separator: ":").map(String.init))
        let homeLocalBin = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .standardizedFileURL
            .path(percentEncoded: false)
        XCTAssertTrue(components.contains(homeLocalBin), path)
        XCTAssertTrue(components.contains("/opt/homebrew/bin"), path)
        XCTAssertTrue(components.contains("/usr/local/bin"), path)
        XCTAssertTrue(components.contains("/usr/bin"), path)
        XCTAssertTrue(components.contains("/bin"), path)
    }

    func testExternalHookRunnerContinuesAfterHookFailure() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let registry = HookRegistry(
            descriptors: [
                HookDescriptor(
                    category: .command,
                    name: "terminal-command-finished",
                    executableURL: URL(fileURLWithPath: "/tmp/10-fail")
                ),
                HookDescriptor(
                    category: .command,
                    name: "terminal-command-finished",
                    executableURL: URL(fileURLWithPath: "/tmp/20-success")
                ),
            ]
        )
        let launcher = OrderedHookLauncher(failingBasenames: ["10-fail"])
        let warnings = WarningRecorder()
        let runner = ExternalHookRunner(
            registry: registry,
            pluginsDirectoryURL: tempDirectory.appending(path: "plugins"),
            launcher: launcher,
            warningHandler: { warnings.append($0) }
        )

        try runner.emit(
            HookInvocation(
                category: .command,
                name: "terminal-command-finished",
                payload: .object(["exitCode": .integer(1)])
            )
        )

        XCTAssertEqual(launcher.launchedBasenames, ["10-fail", "20-success"])
        XCTAssertEqual(warnings.values.count, 1)
        XCTAssertTrue(warnings.values[0].contains("terminal-command-finished"))
    }

    func testExternalHookRunnerCanLaunchHooksAsynchronously() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let registry = HookRegistry(
            descriptors: [
                HookDescriptor(
                    category: .lifecycle,
                    name: "workspace-opened",
                    executableURL: URL(fileURLWithPath: "/tmp/10-bootstrap")
                ),
            ]
        )
        let launcher = BlockingHookLauncher()
        let runner = ExternalHookRunner(
            registry: registry,
            pluginsDirectoryURL: tempDirectory.appending(path: "plugins"),
            launcher: launcher,
            executionMode: .asynchronous
        )

        try runner.emit(
            HookInvocation(
                category: .lifecycle,
                name: "workspace-opened",
                payload: .object(["path": .string("/tmp/project")])
            )
        )

        XCTAssertEqual(launcher.started.wait(timeout: .now() + 2), .success)
        launcher.release.signal()
        XCTAssertEqual(launcher.finished.wait(timeout: .now() + 2), .success)
    }

    func testPluginHookSubscriptionDiscoveryLoadsManifestCallbacks() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let pluginsDirectory = tempDirectory.appending(path: "plugins")
        let pluginDirectory = pluginsDirectory.appending(path: "ai-status")
        try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)

        let executableURL = pluginDirectory.appending(path: "plugin")
        try writeExecutableHook(at: executableURL)
        try """
        id = "ai-status"

        [plugin]
        command = "ai-status"
        entrypoint = "plugin"

        [hooks.terminal-title-changed]
        callback = "__omux_hook"
        arguments = ["codex", "title"]
        """.write(to: pluginDirectory.appending(path: "omux-plugin.toml"), atomically: true, encoding: .utf8)

        let descriptors = PluginHookSubscriptionDiscovery.descriptors(in: pluginsDirectory)
        let matches = descriptors.filter {
            $0.matches(HookInvocation(category: .ui, name: "terminal-title-changed"))
        }
        let executablePath = normalizedPath(executableURL)
        let pluginsPath = normalizedPath(pluginsDirectory)

        XCTAssertNotNil(descriptors.first { $0.name == "terminal-title-changed" })
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.arguments, ["__omux_hook", "codex", "title"])
        XCTAssertEqual(matches.first?.environment["OMUX_PLUGIN_COMMAND"], "ai-status")
        XCTAssertEqual(
            matches.first?.environment["OMUX_PLUGIN_EXECUTABLE"].map(normalizedPath),
            executablePath
        )
        XCTAssertEqual(matches.first?.environment["OMUX_PLUGINS_DIR"].map(normalizedPath), pluginsPath)
        XCTAssertEqual(matches.first?.environment["OMUX_PLUGIN_HOOK_NAME"], "terminal-title-changed")
    }

    func testExternalHookRunnerExecutesPluginHookCallbackFromManifest() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let pluginsDirectory = tempDirectory.appending(path: "plugins")
        let pluginDirectory = pluginsDirectory.appending(path: "ai-status")
        try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)

        let executableURL = pluginDirectory.appending(path: "plugin")
        try """
        #!/bin/sh
        printf '%s\n' "$@" > "$0.args"
        env | sort > "$0.env"
        cat > "$0.payload"
        """.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path(percentEncoded: false)
        )
        try """
        id = "ai-status"

        [plugin]
        command = "ai-status"
        entrypoint = "plugin"

        [hooks.terminal-title-changed]
        callback = "__omux_hook"
        arguments = ["codex", "title"]
        """.write(to: pluginDirectory.appending(path: "omux-plugin.toml"), atomically: true, encoding: .utf8)

        let runner = ExternalHookRunner(
            registry: HookRegistry(),
            pluginsDirectoryURL: pluginsDirectory
        )
        try runner.emit(
            HookInvocation(
                category: .ui,
                name: "terminal-title-changed",
                paneID: PaneID(rawValue: "pane-1"),
                payload: .object(["title": .string("⠧ omux")])
            )
        )

        let args = try String(contentsOf: URL(fileURLWithPath: executableURL.path + ".args"), encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        let environmentLines = try String(contentsOf: URL(fileURLWithPath: executableURL.path + ".env"), encoding: .utf8)
        let payload = try Data(contentsOf: URL(fileURLWithPath: executableURL.path + ".payload"))
        let invocation = try JSONDecoder().decode(HookInvocation.self, from: payload)
        let environment = environmentLines
            .split(separator: "\n")
            .reduce(into: [String: String]()) { result, line in
                guard let separatorIndex = line.firstIndex(of: "=") else {
                    return
                }
                let key = String(line[..<separatorIndex])
                let valueStart = line.index(separatorIndex, offsetBy: 1)
                let value = String(line.suffix(from: valueStart))
                result[key] = value
            }

        XCTAssertEqual(args, ["__omux_hook", "codex", "title"])
        XCTAssertEqual(environment["OMUX_PLUGIN_COMMAND"], "ai-status")
        XCTAssertEqual(environment["OMUX_PLUGIN_EXECUTABLE"].map(normalizedPath), normalizedPath(executableURL))
        XCTAssertEqual(environment["OMUX_PLUGINS_DIR"].map(normalizedPath), normalizedPath(pluginsDirectory))
        XCTAssertEqual(environment["OMUX_PLUGIN_HOOK_NAME"], "terminal-title-changed")
        XCTAssertEqual(invocation.name, "terminal-title-changed")
        XCTAssertEqual(invocation.paneID, PaneID(rawValue: "pane-1"))
    }

    func testExternalHookRunnerContinuesAfterPluginHookFailure() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let pluginsDirectory = tempDirectory.appending(path: "plugins")
        let pluginDirectory = pluginsDirectory.appending(path: "ai-status")
        try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
        try writeExecutableHook(at: pluginDirectory.appending(path: "plugin"))
        try """
        id = "ai-status"

        [plugin]
        command = "ai-status"
        entrypoint = "plugin"

        [hooks.terminal-title-changed]
        callback = "__omux_hook"
        """.write(to: pluginDirectory.appending(path: "omux-plugin.toml"), atomically: true, encoding: .utf8)

        let registry = HookRegistry(
            descriptors: [
                HookDescriptor(
                    category: .ui,
                    name: "terminal-title-changed",
                    executableURL: URL(fileURLWithPath: "/tmp/10-success")
                ),
            ]
        )
        let launcher = OrderedHookLauncher(failingBasenames: ["plugin"])
        let warnings = WarningRecorder()
        let runner = ExternalHookRunner(
            registry: registry,
            pluginsDirectoryURL: pluginsDirectory,
            launcher: launcher,
            warningHandler: { warnings.append($0) }
        )

        try runner.emit(
            HookInvocation(
                category: .ui,
                name: "terminal-title-changed",
                payload: .object(["title": .string("⠧ omux")])
            )
        )

        XCTAssertEqual(launcher.launchedBasenames, ["10-success", "plugin"])
        XCTAssertEqual(warnings.values.count, 1)
        XCTAssertTrue(warnings.values[0].contains("terminal-title-changed"))
    }

    private func writeExecutableHook(at url: URL) throws {
        try writeHook(at: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path(percentEncoded: false)
        )
    }

    private func writeHook(at url: URL) throws {
        try """
        #!/bin/sh
        exit 0
        """.write(to: url, atomically: true, encoding: .utf8)
    }

    private func normalizedPath(_ url: URL) -> String {
        normalizedPath(url.path(percentEncoded: false))
    }

    private func normalizedPath(_ path: String) -> String {
        var normalized = URL(fileURLWithPath: path, isDirectory: path.hasSuffix("/"))
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path(percentEncoded: false)
        while normalized.count > 1, normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized
    }
}

private final class OrderedHookLauncher: HookProcessLaunching, @unchecked Sendable {
    private let failingBasenames: Set<String>
    private(set) var launchedBasenames: [String] = []

    init(failingBasenames: Set<String>) {
        self.failingBasenames = failingBasenames
    }

    func launch(executableURL: URL, arguments: [String], environment: [String: String], input: Data) throws {
        _ = arguments
        _ = environment
        _ = input
        let basename = executableURL.lastPathComponent
        launchedBasenames.append(basename)
        if failingBasenames.contains(basename) {
            throw ProcessHookLauncherError.nonZeroExit(
                executablePath: executableURL.path(percentEncoded: false),
                status: 1
            )
        }
    }
}

private final class BlockingHookLauncher: HookProcessLaunching, @unchecked Sendable {
    let started = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    let finished = DispatchSemaphore(value: 0)

    func launch(executableURL: URL, arguments: [String], environment: [String: String], input: Data) throws {
        _ = executableURL
        _ = arguments
        _ = environment
        _ = input
        started.signal()
        _ = release.wait(timeout: .now() + 2)
        finished.signal()
    }
}

private final class WarningRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedValues
    }

    func append(_ value: String) {
        lock.lock()
        storedValues.append(value)
        lock.unlock()
    }
}
