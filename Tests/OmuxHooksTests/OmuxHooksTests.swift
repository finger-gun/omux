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

        let runner = ExternalHookRunner(registry: registry)
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
