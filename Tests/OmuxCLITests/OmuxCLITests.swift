import Foundation
import XCTest
@testable import OmuxCLI
@testable import OmuxConfig
@testable import OmuxControlPlane
@testable import OmuxCore
@testable import OmuxAIStatusPlugin
@testable import OmuxMarkdownPreviewPlugin
@testable import OmuxTheme

final class OmuxCLITests: XCTestCase {
    private final class FakeRunningAppManager: OmuxRunningApplicationManaging {
        var apps: [OmuxRunningApplication]
        private(set) var terminateCalls = 0

        init(apps: [OmuxRunningApplication] = []) {
            self.apps = apps
        }

        func runningApplications(bundleIdentifier: String) -> [OmuxRunningApplication] {
            _ = bundleIdentifier
            return apps
        }

        func terminate(bundleIdentifier: String) {
            _ = bundleIdentifier
            terminateCalls += 1
            apps = []
        }
    }

    func testCLIUsesPublicControlPlane() throws {
        let socketPath = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "cli.sock")
            .path(percentEncoded: false)

        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            switch request.method {
            case ControlMethod.listWorkspaces.rawValue:
                return JSONRPCResponse(id: request.id, result: .array([
                    .object([
                        "id": .string("workspace-1"),
                        "name": .string("demo"),
                        "rootPath": .string("/tmp/demo"),
                    ]),
                ]))
            default:
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 404, message: "unexpected"))
            }
        }
        defer { server.stop() }

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: socketPath),
            writeLine: { output.append($0) }
        )

        let exitCode = command.run(arguments: ["omux", "list"])

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(output.count, 1)
        XCTAssertTrue(output[0].contains("demo"))
        XCTAssertTrue(output[0].contains("/tmp/demo"))
    }

    func testCLIVersionUsesLocalVersionProvider() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "1.2.3\n".write(to: root.appendingPathComponent("VERSION"), atomically: true, encoding: .utf8)
        let executableURL = root.appendingPathComponent("bin/omux", isDirectory: false)
        try FileManager.default.createDirectory(at: executableURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: executableURL, atomically: true, encoding: .utf8)

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(),
            writeLine: { output.append($0) },
            readInputLine: { nil },
            configLoader: OmuxConfigLoader(),
            themeRegistry: OmuxThemeRegistry(),
            installer: OmuxCLIInstaller(),
            versionProvider: OpenMUXVersionProvider(executablePath: executableURL.path, currentDirectoryPath: root.path)
        )

        XCTAssertEqual(command.run(arguments: ["omux", "version"]), 0)
        XCTAssertEqual(output, ["1.2.3"])
    }

    func testDebugUpdateCommandIsHiddenFromUsage() {
        XCTAssertFalse(OmuxCLICommand.usage.contains("__debug-update"))
    }

    func testSelfUpdaterCancelsWhenUserDeclinesRunningAppClose() throws {
        let fixture = try makeUpdateFixture(currentVersion: "0.4.0", latestVersion: "0.5.0")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let appManager = FakeRunningAppManager(apps: [OmuxRunningApplication(processIdentifier: 123)])
        var output = [String]()
        var helperLaunched = false

        let updater = OmuxSelfUpdater(
            versionProvider: fixture.versionProvider,
            latestRelease: { fixture.release },
            fileManager: .default,
            homeDirectoryURL: fixture.homeURL,
            temporaryDirectoryURL: fixture.tempURL,
            executablePath: fixture.executableURL.path,
            appManager: appManager,
            download: { source, destination, _ in
                try FileManager.default.copyItem(at: source, to: destination)
            },
            launchDetachedHelper: { _, _ in helperLaunched = true },
            writeLine: { output.append($0) },
            readInputLine: { "n" }
        )

        let outcome = try updater.runUpdate()

        XCTAssertEqual(outcome.state, .cancelled)
        XCTAssertFalse(helperLaunched)
        XCTAssertTrue(output.contains("Update cancelled."))
    }

    func testSelfUpdaterStagesAndLaunchesDetachedHelper() throws {
        let fixture = try makeUpdateFixture(currentVersion: "0.4.0", latestVersion: "0.5.0")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let appManager = FakeRunningAppManager()
        var manifestURL: URL?
        var helperURL: URL?
        var output = [String]()

        let updater = OmuxSelfUpdater(
            versionProvider: fixture.versionProvider,
            latestRelease: { fixture.release },
            fileManager: .default,
            homeDirectoryURL: fixture.homeURL,
            temporaryDirectoryURL: fixture.tempURL,
            executablePath: fixture.executableURL.path,
            appManager: appManager,
            download: { source, destination, progress in
                progress(OmuxDownloadProgress(bytesDownloaded: 5, totalBytes: 10))
                progress(OmuxDownloadProgress(bytesDownloaded: 10, totalBytes: 10))
                try FileManager.default.copyItem(at: source, to: destination)
            },
            launchDetachedHelper: { helper, manifest in
                helperURL = helper
                manifestURL = manifest
            },
            writeLine: { output.append($0) },
            readInputLine: { nil }
        )

        let outcome = try updater.runUpdate()

        guard case .handedOff(let version, _) = outcome.state else {
            return XCTFail("expected helper handoff")
        }
        XCTAssertEqual(version, "0.5.0")
        let manifestPath = try XCTUnwrap(manifestURL?.path)
        let helperDirectoryURL = try XCTUnwrap(helperURL?.deletingLastPathComponent())
        let manifest = try JSONDecoder().decode(
            OmuxUpdateManifest.self,
            from: Data(contentsOf: URL(fileURLWithPath: manifestPath))
        )
        XCTAssertEqual(manifest.version, "0.5.0")
        XCTAssertEqual(manifest.targetAppPath, fixture.installedAppURL.path)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: helperDirectoryURL.appendingPathComponent("OpenMUX_OmuxTheme.bundle", isDirectory: true).path
        ))
        XCTAssertTrue(output.contains("OpenMUX 0.5.0 [##########----------] 50% 5 B / 10 B"))
        XCTAssertTrue(output.contains("OpenMUX 0.5.0 [####################] 100% 10 B / 10 B"))
    }

    func testSelfUpdaterDebugReinstallDownloadsLatestAndPromptsBeforeInstall() throws {
        let fixture = try makeUpdateFixture(currentVersion: "0.5.0", latestVersion: "0.5.0")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let appManager = FakeRunningAppManager()
        var helperURL: URL?
        var output = [String]()

        let updater = OmuxSelfUpdater(
            versionProvider: fixture.versionProvider,
            latestRelease: { fixture.release },
            fileManager: .default,
            homeDirectoryURL: fixture.homeURL,
            temporaryDirectoryURL: fixture.tempURL,
            executablePath: fixture.executableURL.path,
            appManager: appManager,
            download: { source, destination, progress in
                progress(OmuxDownloadProgress(bytesDownloaded: 5, totalBytes: 10))
                progress(OmuxDownloadProgress(bytesDownloaded: 10, totalBytes: 10))
                try FileManager.default.copyItem(at: source, to: destination)
            },
            launchDetachedHelper: { helper, _ in
                helperURL = helper
            },
            writeLine: { output.append($0) },
            readInputLine: { "y" }
        )

        let outcome = try updater.runUpdate(allowReinstallLatest: true)

        guard case .handedOff(let version, _) = outcome.state else {
            return XCTFail("expected helper handoff")
        }
        XCTAssertEqual(version, "0.5.0")
        XCTAssertNotNil(helperURL)
        XCTAssertTrue(output.contains("Debug update: reinstalling OpenMUX 0.5.0 over installed OpenMUX 0.5.0."))
        XCTAssertTrue(output.contains("OpenMUX 0.5.0 [##########----------] 50% 5 B / 10 B"))
        XCTAssertTrue(output.contains("OpenMUX 0.5.0 [####################] 100% 10 B / 10 B"))
        XCTAssertTrue(output.contains("Install OpenMUX 0.5.0 to \(fixture.installedAppURL.path) and relaunch? [y/N]"))
    }

    func testSelfUpdaterDebugReinstallCancelsWhenUserDeclinesInstall() throws {
        let fixture = try makeUpdateFixture(currentVersion: "0.5.0", latestVersion: "0.5.0")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var helperLaunched = false
        var output = [String]()

        let updater = OmuxSelfUpdater(
            versionProvider: fixture.versionProvider,
            latestRelease: { fixture.release },
            fileManager: .default,
            homeDirectoryURL: fixture.homeURL,
            temporaryDirectoryURL: fixture.tempURL,
            executablePath: fixture.executableURL.path,
            appManager: FakeRunningAppManager(),
            download: { source, destination, progress in
                progress(OmuxDownloadProgress(bytesDownloaded: 10, totalBytes: 10))
                try FileManager.default.copyItem(at: source, to: destination)
            },
            launchDetachedHelper: { _, _ in helperLaunched = true },
            writeLine: { output.append($0) },
            readInputLine: { "n" }
        )

        let outcome = try updater.runUpdate(allowReinstallLatest: true)

        XCTAssertEqual(outcome.state, .cancelled)
        XCTAssertFalse(helperLaunched)
        XCTAssertTrue(output.contains("Debug update cancelled."))
        XCTAssertTrue(output.contains("OpenMUX 0.5.0 [####################] 100% 10 B / 10 B"))
    }

    func testUpdateHelperKeepsInstallOnlyAfterSuccessfulRelaunch() throws {
        let fixture = try makeHelperInstallFixture(currentVersion: "0.4.0", latestVersion: "0.5.0")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let appManager = FakeRunningAppManager()

        let updater = OmuxSelfUpdater(
            fileManager: .default,
            appManager: appManager,
            openApplication: { _ in
                appManager.apps = [OmuxRunningApplication(processIdentifier: 456)]
                return true
            },
            sleep: { _ in },
            relaunchTimeoutSeconds: 0.1,
            relaunchStabilitySeconds: 0,
            writeLine: { _ in },
            readInputLine: { nil }
        )

        try updater.runHelper(manifest: fixture.manifest)

        XCTAssertEqual(bundleVersion(at: fixture.targetAppURL), "0.5.0")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.backupAppURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.stagingRoot.path))
    }

    func testUpdateHelperRollsBackWhenRelaunchFails() throws {
        let fixture = try makeHelperInstallFixture(currentVersion: "0.4.0", latestVersion: "0.5.0")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let appManager = FakeRunningAppManager()

        let updater = OmuxSelfUpdater(
            fileManager: .default,
            appManager: appManager,
            openApplication: { _ in false },
            sleep: { _ in },
            relaunchTimeoutSeconds: 0.1,
            relaunchStabilitySeconds: 0,
            writeLine: { _ in },
            readInputLine: { nil }
        )

        XCTAssertThrowsError(try updater.runHelper(manifest: fixture.manifest)) { error in
            XCTAssertEqual(
                error as? OmuxSelfUpdater.UpdateError,
                .installFailed(.appRelaunchFailed("Launch Services rejected \(fixture.targetAppURL.path)"))
            )
        }
        XCTAssertEqual(bundleVersion(at: fixture.targetAppURL), "0.4.0")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.backupAppURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.stagingRoot.path))
    }

    private func makeUpdateFixture(
        currentVersion: String,
        latestVersion: String
    ) throws -> (
        root: URL,
        homeURL: URL,
        tempURL: URL,
        executableURL: URL,
        installedAppURL: URL,
        versionProvider: OpenMUXVersionProvider,
        release: OpenMUXRelease
    ) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let homeURL = root.appendingPathComponent("home", isDirectory: true)
        let tempURL = root.appendingPathComponent("tmp", isDirectory: true)
        let installedAppURL = root.appendingPathComponent("Installed/OpenMUX.app", isDirectory: true)
        let executableURL = installedAppURL.appendingPathComponent("Contents/MacOS/omux", isDirectory: false)
        let releaseRoot = root.appendingPathComponent("release", isDirectory: true)
        let stagedAppURL = releaseRoot.appendingPathComponent("OpenMUX.app", isDirectory: true)
        try FileManager.default.createDirectory(at: executableURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: installedAppURL.appendingPathComponent("Contents/Resources/OpenMUX_OmuxTheme.bundle", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stagedAppURL.appendingPathComponent("Contents/MacOS", isDirectory: true), withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        try writeInfoPlist(version: currentVersion, to: installedAppURL)
        try writeInfoPlist(version: latestVersion, to: stagedAppURL)

        let archiveURL = releaseRoot.appendingPathComponent("OpenMUX-\(latestVersion)-macos-unsigned.zip")
        try runDitto(arguments: ["-c", "-k", "--sequesterRsrc", "--keepParent", stagedAppURL.path, archiveURL.path])
        let checksum = try sha256(archiveURL)
        let checksumURL = releaseRoot.appendingPathComponent("checksums.txt")
        try "\(checksum)  \(archiveURL.lastPathComponent)\n".write(to: checksumURL, atomically: true, encoding: .utf8)

        let provider = OpenMUXVersionProvider(executablePath: executableURL.path, currentDirectoryPath: root.path)
        let release = OpenMUXRelease(
            tagName: "v\(latestVersion)",
            version: try XCTUnwrap(OpenMUXSemanticVersion(parsing: latestVersion)),
            assets: [
                OpenMUXReleaseAsset(name: archiveURL.lastPathComponent, downloadURL: archiveURL),
                OpenMUXReleaseAsset(name: "checksums.txt", downloadURL: checksumURL),
            ]
        )
        return (root, homeURL, tempURL, executableURL, installedAppURL, provider, release)
    }

    private func makeHelperInstallFixture(
        currentVersion: String,
        latestVersion: String
    ) throws -> (
        root: URL,
        stagingRoot: URL,
        targetAppURL: URL,
        backupAppURL: URL,
        manifest: OmuxUpdateManifest
    ) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let stagingRoot = root.appendingPathComponent("staging", isDirectory: true)
        let stagedAppURL = stagingRoot.appendingPathComponent("unpacked/OpenMUX.app", isDirectory: true)
        let helperURL = stagingRoot.appendingPathComponent("helper", isDirectory: true)
        let targetAppURL = root.appendingPathComponent("Installed/OpenMUX.app", isDirectory: true)
        let backupAppURL = helperURL.appendingPathComponent("OpenMUX.app.backup", isDirectory: true)
        try FileManager.default.createDirectory(at: stagedAppURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetAppURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: helperURL, withIntermediateDirectories: true)
        try writeInfoPlist(version: currentVersion, to: targetAppURL)
        try writeInfoPlist(version: latestVersion, to: stagedAppURL)

        let manifest = OmuxUpdateManifest(
            stagedAppPath: stagedAppURL.path,
            targetAppPath: targetAppURL.path,
            backupAppPath: backupAppURL.path,
            logPath: helperURL.appendingPathComponent("update.log", isDirectory: false).path,
            stagingRootPath: stagingRoot.path,
            bundleIdentifier: "dev.fingergun.omux",
            version: latestVersion,
            reopenAfterInstall: true,
            terminationTimeoutSeconds: 0.1
        )
        return (root, stagingRoot, targetAppURL, backupAppURL, manifest)
    }

    private func writeInfoPlist(version: String, to appURL: URL) throws {
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": "dev.fingergun.omux",
            "CFBundleShortVersionString": version,
        ]
        (plist as NSDictionary).write(to: contentsURL.appendingPathComponent("Info.plist"), atomically: true)
    }

    private func bundleVersion(at appURL: URL) -> String? {
        let infoURL = appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Info.plist", isDirectory: false)
        return (NSDictionary(contentsOf: infoURL) as? [String: Any])?["CFBundleShortVersionString"] as? String
    }

    private func runDitto(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private func sha256(_ fileURL: URL) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
        process.arguments = ["-a", "256", fileURL.path]
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return try XCTUnwrap(output.split(separator: " ").first.map(String.init))
    }

    func testCLIOpenAcceptsOptionalPath() throws {
        let socketPath = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "open.sock")
            .path(percentEncoded: false)
        let requests = LockedValue<[JSONRPCRequest]>([])
        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            requests.value.append(request)
            return JSONRPCResponse(id: request.id, result: .string("ok"))
        }
        defer { server.stop() }

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: socketPath),
            writeLine: { output.append($0) }
        )

        XCTAssertEqual(command.run(arguments: ["omux", "open"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "open", "/tmp"]), 0)

        XCTAssertEqual(requests.value.map(\.method), [
            ControlMethod.openWorkspace.rawValue,
            ControlMethod.openWorkspace.rawValue,
        ])
        XCTAssertNil(requests.value[0].params)
        guard case .object(let params)? = requests.value[1].params,
              case .string("/tmp")? = params["path"] else {
            return XCTFail("expected explicit open path")
        }
        XCTAssertEqual(output, ["ok", "ok"])
    }

    func testCLIWorkspaceCloseAndPaneRemoveSendExpectedTargets() throws {
        let socketPath = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "remove.sock")
            .path(percentEncoded: false)
        let requests = LockedValue<[JSONRPCRequest]>([])
        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            requests.value.append(request)
            return JSONRPCResponse(id: request.id, result: .string("ok"))
        }
        defer { server.stop() }

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: socketPath),
            writeLine: { output.append($0) }
        )

        XCTAssertEqual(command.run(arguments: ["omux", "workspace-close"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "workspace-close", "workspace-1"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "pane-remove"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "pane-remove", "--pane", "pane-1"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "pane-remove", "pane-1"]), 1)

        XCTAssertEqual(requests.value.map(\.method), [
            ControlMethod.closeWorkspace.rawValue,
            ControlMethod.closeWorkspace.rawValue,
            ControlMethod.removePane.rawValue,
            ControlMethod.removePane.rawValue,
        ])
        XCTAssertNil(requests.value[0].params)
        guard case .object(let closeParams)? = requests.value[1].params,
              case .string("workspace-1")? = closeParams["workspaceID"] else {
            return XCTFail("expected explicit workspace close target")
        }
        XCTAssertNil(requests.value[2].params)
        guard case .object(let removeParams)? = requests.value[3].params,
              case .object(let target)? = removeParams["target"],
              case .string("pane")? = target["type"],
              case .string("pane-1")? = target["id"] else {
            return XCTFail("expected explicit pane remove target")
        }
        XCTAssertEqual(output, ["ok", "ok", "ok", "ok", "usage: omux pane-remove [--session <id>|--pane <id>|--tab <id>|--workspace <id>|--focused]"])
    }

    func testCLISupportsTabSplitAndRunCommands() throws {
        let socketPath = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "commands.sock")
            .path(percentEncoded: false)

        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            let axis = request.params.flatMap {
                if case .object(let object) = $0, case .string(let axis)? = object["axis"] {
                    return axis
                }
                return nil
            } ?? "none"
            return JSONRPCResponse(id: request.id, result: .string("\(request.method):\(axis)"))
        }
        defer { server.stop() }

        let client = OmuxControlClient(socketPath: socketPath)
        var output = [String]()
        let command = OmuxCLICommand(client: client, writeLine: { output.append($0) })

        XCTAssertEqual(command.run(arguments: ["omux", "tab"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "split"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "split", "down"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "pane-tab"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "pane-tab-next"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "pane-tab-prev"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "pane-tab-focus", "pane-1"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "pane-tab-close", "pane-1"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "pane-next"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "pane-prev"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "pane-remove"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "pane-remove", "--pane", "pane-1"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "workspace-close"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "workspace-close", "workspace-1"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "run", "session-1", "pwd"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "run", "--pane", "pane-1", "--", "echo", "hello"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "send-text", "--session", "session-1", "--", "hello", "world"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "pane-status", "--pane", "pane-1", "--state", "working"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "sessions"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "session"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "panes"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "pane"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "agent-sessions", "open"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "as", "toggle"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "agents", "palette"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "as"]), 0)

        XCTAssertEqual(output, [
            "\(ControlMethod.createTab.rawValue):none",
            "\(ControlMethod.splitPane.rawValue):columns",
            "\(ControlMethod.splitPane.rawValue):rows",
            "\(ControlMethod.createPaneTab.rawValue):none",
            "\(ControlMethod.focusNextPaneTab.rawValue):none",
            "\(ControlMethod.focusPreviousPaneTab.rawValue):none",
            "\(ControlMethod.focusPaneTab.rawValue):none",
            "\(ControlMethod.closePaneTab.rawValue):none",
            "\(ControlMethod.focusNextPane.rawValue):none",
            "\(ControlMethod.focusPreviousPane.rawValue):none",
            "\(ControlMethod.removePane.rawValue):none",
            "\(ControlMethod.removePane.rawValue):none",
            "\(ControlMethod.closeWorkspace.rawValue):none",
            "\(ControlMethod.closeWorkspace.rawValue):none",
            "\(ControlMethod.runCommand.rawValue):none",
            "\(ControlMethod.runCommand.rawValue):none",
            "\(ControlMethod.sendText.rawValue):none",
            "\(ControlMethod.paneStatus.rawValue):none",
            "\(ControlMethod.listSessions.rawValue):none",
            "\(ControlMethod.listSessions.rawValue):none",
            "\(ControlMethod.listPanes.rawValue):none",
            "\(ControlMethod.listPanes.rawValue):none",
            "\(ControlMethod.agentSessionsUI.rawValue):none",
            "\(ControlMethod.agentSessionsUI.rawValue):none",
            "\(ControlMethod.agentSessionsUI.rawValue):none",
            "\(ControlMethod.agentSessionsUI.rawValue):none",
        ])
    }

    func testCLIListFullRequestsDetailedWorkspaceTopology() throws {
        let socketPath = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "list-full.sock")
            .path(percentEncoded: false)

        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            let full: Bool
            if case .object(let params)? = request.params,
               case .bool(true)? = params["full"] {
                full = true
            } else {
                full = false
            }
            return JSONRPCResponse(id: request.id, result: .string("\(request.method):\(full)"))
        }
        defer { server.stop() }

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: socketPath),
            writeLine: { output.append($0) }
        )

        XCTAssertEqual(command.run(arguments: ["omux", "list", "--full"]), 0)
        XCTAssertEqual(output, ["\(ControlMethod.listWorkspaces.rawValue):true"])
    }

    func testCLISendsPaneStatusRequestForHooksAndPlugins() throws {
        let socketPath = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "pane-status.sock")
            .path(percentEncoded: false)
        let requests = LockedValue<[JSONRPCRequest]>([])
        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            requests.value.append(request)
            return JSONRPCResponse(id: request.id, result: .string("ok"))
        }
        defer { server.stop() }

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: socketPath),
            writeLine: { output.append($0) }
        )

        XCTAssertEqual(
            command.run(arguments: [
                "omux", "pane-status",
                "--pane", "pane-1",
                "--state", "working",
                "--value", "42",
                "--label", "Codex",
                "--message", "running tests",
                "--source", "hook.codex",
            ]),
            0
        )
        XCTAssertEqual(command.run(arguments: ["omux", "pane-status", "--focused", "clear"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "pane-status", "--focused", "--state", "needs-input"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "pane-status", "--state", "working"]), 1)

        XCTAssertEqual(requests.value.map(\.method), [
            ControlMethod.paneStatus.rawValue,
            ControlMethod.paneStatus.rawValue,
            ControlMethod.paneStatus.rawValue,
        ])

        guard case .object(let firstParams)? = requests.value[0].params,
              case .object(let target)? = firstParams["target"],
              case .string("pane")? = target["type"],
              case .string("pane-1")? = target["id"],
              case .string("working")? = firstParams["state"],
              case .number(42)? = firstParams["value"],
              case .string("Codex")? = firstParams["label"],
              case .string("running tests")? = firstParams["message"],
              case .string("hook.codex")? = firstParams["source"] else {
            return XCTFail("expected pane status params")
        }

        guard case .object(let secondParams)? = requests.value[1].params,
              case .object(let secondTarget)? = secondParams["target"],
              case .string("focused")? = secondTarget["type"],
              case .string("clear")? = secondParams["state"] else {
            return XCTFail("expected focused clear params")
        }

        guard case .object(let thirdParams)? = requests.value[2].params,
              case .object(let thirdTarget)? = thirdParams["target"],
              case .string("focused")? = thirdTarget["type"],
              case .string("needs-input")? = thirdParams["state"] else {
            return XCTFail("expected focused needs-input params")
        }

        XCTAssertEqual(output, [
            "ok",
            "ok",
            "ok",
            "usage: omux pane-status --session <id>|--pane <id>|--tab <id>|--workspace <id>|--focused --state working|indeterminate|error|needs-input|idle|clear [--value <0-100>] [--label <text>] [--message <text>] [--source <name>]",
        ])
    }

    func testCLIBundledAIStatusPluginSendsPaneStatus() throws {
        let socketPath = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "ai-status.sock")
            .path(percentEncoded: false)
        let requests = LockedValue<[JSONRPCRequest]>([])
        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            requests.value.append(request)
            return JSONRPCResponse(id: request.id, result: .string("ok"))
        }
        defer { server.stop() }

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: socketPath),
            writeLine: { output.append($0) }
        )

        XCTAssertEqual(
            command.run(arguments: [
                "omux", "ai-status", "codex", "title",
                "--pane", "pane-1",
                "--title", "waiting for approval",
            ]),
            0
        )

        XCTAssertEqual(requests.value.map(\.method), [ControlMethod.paneStatus.rawValue])
        guard case .object(let params)? = requests.value.first?.params,
              case .object(let target)? = params["target"],
              case .string("pane")? = target["type"],
              case .string("pane-1")? = target["id"],
              case .string("needs-input")? = params["state"],
              case .string("Codex")? = params["label"],
              case .string("waiting for approval")? = params["message"],
              case .string("plugin.ai-status.codex")? = params["source"] else {
            return XCTFail("expected ai-status pane-status params")
        }
        XCTAssertEqual(output, ["ok"])
    }

    func testBundledAIStatusHookRelayMapsVendorEvents() throws {
        let socketPath = "/tmp/omux-ai-status-hook-\(UUID().uuidString).sock"
        let requests = LockedValue<[JSONRPCRequest]>([])
        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            requests.value.append(request)
            return JSONRPCResponse(id: request.id, result: .string("ok"))
        }
        defer { server.stop() }

        var output = [String]()
        let plugin = OmuxAIStatusPlugin(
            environment: [:],
            standardInputData: {
                #"{"message":"Approve shell command?"}"#.data(using: .utf8) ?? Data()
            }
        )

        XCTAssertEqual(
            try plugin.run(
                arguments: [
                    "hook",
                    "--source", "codex",
                    "--event", "PermissionRequest",
                    "--pane", "pane-1",
                ],
                client: OmuxControlClient(socketPath: socketPath),
                writeLine: { output.append($0) }
            ),
            0
        )

        XCTAssertEqual(requests.value.map(\.method), [ControlMethod.paneStatus.rawValue])
        guard case .object(let params)? = requests.value.first?.params,
              case .object(let target)? = params["target"],
              case .string("pane")? = target["type"],
              case .string("pane-1")? = target["id"],
              case .string("needs-input")? = params["state"],
              case .string("Codex")? = params["label"],
              case .string("Approve shell command?")? = params["message"],
              case .string("plugin.ai-status.codex.hook")? = params["source"] else {
            return XCTFail("expected Codex hook pane-status params")
        }
        XCTAssertEqual(output, ["ok"])
    }

    func testBundledAIStatusHookRelayNoopsWithoutTarget() throws {
        let requests = LockedValue<[JSONRPCRequest]>([])
        var output = [String]()
        let plugin = OmuxAIStatusPlugin(
            environment: [:],
            standardInputData: {
                #"{"message":"Approve shell command?"}"#.data(using: .utf8) ?? Data()
            }
        )

        XCTAssertEqual(
            try plugin.run(
                arguments: [
                    "hook",
                    "--source", "codex",
                    "--event", "PermissionRequest",
                ],
                client: OmuxControlClient(socketPath: "/tmp/unused-\(UUID().uuidString).sock"),
                writeLine: { output.append($0) }
            ),
            0
        )

        XCTAssertTrue(requests.value.isEmpty)
        XCTAssertEqual(output, ["{}"])
    }

    func testBundledAIStatusHookAdapterMapsFirstWaveVendorEvents() throws {
        let gemini = OmuxAIStatusHookAdapter.observe(
            source: "gemini",
            event: "PreToolUse",
            payload: #"{"toolName":"shell"}"#.data(using: .utf8) ?? Data()
        )
        XCTAssertEqual(gemini?.state, .working)
        XCTAssertEqual(gemini?.label, "Gemini")
        XCTAssertEqual(gemini?.source, "plugin.ai-status.gemini.hook")

        let claude = OmuxAIStatusHookAdapter.observe(
            source: "claude",
            event: "StopFailure",
            payload: #"{"error":"rate_limit"}"#.data(using: .utf8) ?? Data()
        )
        XCTAssertEqual(claude?.state, .error)
        XCTAssertEqual(claude?.label, "Claude")
        XCTAssertEqual(claude?.message, "rate_limit")

        let unsupported = OmuxAIStatusHookAdapter.observe(
            source: "cursor",
            event: "PermissionRequest",
            payload: Data()
        )
        XCTAssertNil(unsupported)
    }

    func testBundledAIStatusHooksSetupAndUninstallPreserveUserEntries() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let codexHome = root.appendingPathComponent("codex", isDirectory: true)
        let hooksURL = codexHome.appendingPathComponent("hooks.json", isDirectory: false)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try """
        {
          "hooks": {
            "PermissionRequest": [
              {
                "type": "command",
                "command": "echo user-owned"
              }
            ]
          }
        }
        """.write(to: hooksURL, atomically: true, encoding: .utf8)

        var output = [String]()
        let plugin = OmuxAIStatusPlugin(environment: ["CODEX_HOME": codexHome.path])

        XCTAssertEqual(
            try plugin.run(
                arguments: ["hooks", "setup", "codex"],
                client: OmuxControlClient(socketPath: "/tmp/unused-\(UUID().uuidString).sock"),
                writeLine: { output.append($0) }
            ),
            0
        )

        let configured = try JSONObject(at: hooksURL)
        let hooks = try XCTUnwrap(configured["hooks"] as? [String: Any])
        let permissionEntries = try XCTUnwrap(hooks["PermissionRequest"] as? [[String: Any]])
        XCTAssertTrue(permissionEntries.contains { ($0["command"] as? String) == "echo user-owned" })
        XCTAssertTrue(permissionEntries.contains { ($0["openmux_ai_status"] as? Bool) == true })
        XCTAssertTrue(
            try String(contentsOf: codexHome.appendingPathComponent("config.toml"), encoding: .utf8)
                .contains("codex_hooks = true")
        )

        XCTAssertEqual(
            try plugin.run(
                arguments: ["hooks", "uninstall", "codex"],
                client: OmuxControlClient(socketPath: "/tmp/unused-\(UUID().uuidString).sock"),
                writeLine: { output.append($0) }
            ),
            0
        )

        let uninstalled = try JSONObject(at: hooksURL)
        let remainingHooks = try XCTUnwrap(uninstalled["hooks"] as? [String: Any])
        let remainingPermissionEntries = try XCTUnwrap(remainingHooks["PermissionRequest"] as? [[String: Any]])
        XCTAssertEqual(remainingPermissionEntries.count, 1)
        XCTAssertEqual(remainingPermissionEntries.first?["command"] as? String, "echo user-owned")
        XCTAssertFalse(
            try String(contentsOf: codexHome.appendingPathComponent("config.toml"), encoding: .utf8)
                .contains("OpenMUX ai-status managed start")
        )
    }

    func testBundledAIStatusHooksRejectUnsupportedVendor() throws {
        var output = [String]()
        let plugin = OmuxAIStatusPlugin(environment: [:])

        XCTAssertEqual(
            try plugin.run(
                arguments: ["hooks", "setup", "cursor"],
                client: OmuxControlClient(socketPath: "/tmp/unused-\(UUID().uuidString).sock"),
                writeLine: { output.append($0) }
            ),
            1
        )

        XCTAssertEqual(output.first, "Unsupported ai-status hook vendor: cursor")
    }

    func testBundledAIStatusHooksSetupAndUninstallGeminiSettings() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let settingsURL = root
            .appendingPathComponent(".gemini", isDirectory: true)
            .appendingPathComponent("settings.json", isDirectory: false)
        try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        {
          "hooks": {
            "PreToolUse": [
              {
                "type": "command",
                "command": "echo gemini-user-owned"
              }
            ]
          }
        }
        """.write(to: settingsURL, atomically: true, encoding: .utf8)

        var output = [String]()
        let plugin = OmuxAIStatusPlugin(environment: ["HOME": root.path])

        XCTAssertEqual(
            try plugin.run(
                arguments: ["hooks", "setup", "gemini"],
                client: OmuxControlClient(socketPath: "/tmp/unused-\(UUID().uuidString).sock"),
                writeLine: { output.append($0) }
            ),
            0
        )

        let configured = try JSONObject(at: settingsURL)
        let hooks = try XCTUnwrap(configured["hooks"] as? [String: Any])
        let preToolUseEntries = try XCTUnwrap(hooks["PreToolUse"] as? [[String: Any]])
        XCTAssertTrue(preToolUseEntries.contains { ($0["command"] as? String) == "echo gemini-user-owned" })
        XCTAssertTrue(preToolUseEntries.contains { ($0["openmux_ai_status_vendor"] as? String) == "gemini" })

        XCTAssertEqual(
            try plugin.run(
                arguments: ["hooks", "uninstall", "gemini"],
                client: OmuxControlClient(socketPath: "/tmp/unused-\(UUID().uuidString).sock"),
                writeLine: { output.append($0) }
            ),
            0
        )

        let uninstalled = try JSONObject(at: settingsURL)
        let remainingHooks = try XCTUnwrap(uninstalled["hooks"] as? [String: Any])
        let remainingPreToolUseEntries = try XCTUnwrap(remainingHooks["PreToolUse"] as? [[String: Any]])
        XCTAssertEqual(remainingPreToolUseEntries.count, 1)
        XCTAssertEqual(remainingPreToolUseEntries.first?["command"] as? String, "echo gemini-user-owned")
    }

    func testBundledAIStatusJSONLAdaptersMapFirstWaveVendors() throws {
        let codexWorking = OmuxAIStatusJSONLAdapter.observe(
            source: "codex",
            line: #"{"type":"turn.started"}"#
        )
        XCTAssertEqual(codexWorking?.state, .working)
        XCTAssertEqual(codexWorking?.source, "plugin.ai-status.codex.jsonl")

        let codexFailed = OmuxAIStatusJSONLAdapter.observe(
            source: "codex",
            line: #"{"type":"turn.failed","message":"failed"}"#
        )
        XCTAssertEqual(codexFailed?.state, .error)
        XCTAssertEqual(codexFailed?.message, "failed")

        let geminiResult = OmuxAIStatusJSONLAdapter.observe(
            source: "gemini",
            line: #"{"type":"result"}"#
        )
        XCTAssertEqual(geminiResult?.state, .idle)

        let claudeLimit = OmuxAIStatusJSONLAdapter.observe(
            source: "claude",
            line: #"{"type":"result","subtype":"rate_limit","message":"try later"}"#
        )
        XCTAssertEqual(claudeLimit?.state, .error)
        XCTAssertEqual(claudeLimit?.message, "try later")

        XCTAssertNil(OmuxAIStatusJSONLAdapter.observe(source: "codex", line: "not-json"))
    }

    func testCLIPaneStatusSupportsAliasesAndClampsProgress() throws {
        let socketPath = "/tmp/omux-pane-status-alias-\(UUID().uuidString).sock"
        let requests = LockedValue<[JSONRPCRequest]>([])
        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            requests.value.append(request)
            return JSONRPCResponse(id: request.id, result: .string("ok"))
        }
        defer { server.stop() }

        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: socketPath),
            writeLine: { _ in }
        )

        XCTAssertEqual(command.run(arguments: ["omux", "pane-status", "--pane", "pane-1", "running"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "pane-status", "--pane", "pane-1", "--state", "input"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "pane-status", "--pane", "pane-1", "--state", "completed"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "pane-status", "--pane", "pane-1", "--state", "failed", "--progress", "140"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "pane-status", "--pane", "pane-1", "--state", "remove"]), 0)

        let states = requests.value.compactMap { request -> String? in
            guard case .object(let params)? = request.params else { return nil }
            guard case .string(let state)? = params["state"] else { return nil }
            return state
        }
        let clampedValue = requests.value.compactMap { request -> Int? in
            guard case .object(let params)? = request.params else { return nil }
            guard case .number(let value)? = params["value"] else { return nil }
            return Int(value)
        }.last

        XCTAssertEqual(states, ["working", "needs-input", "idle", "error", "clear"])
        XCTAssertEqual(clampedValue, 100)
    }

    func testCLIMarkdownPreviewCreatesExtensionPaneWhenEnabled() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let configURL = root.appendingPathComponent("config.toml")
        try """
        schema = 1

        [plugins.markdown-preview]
        enabled = true
        renderer = "builtin"
        theme = "dark"
        presentation = "modal"
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let markdownURL = root.appendingPathComponent("README.md")
        try """
        # Preview

        <script>alert("x")</script>
        """.write(to: markdownURL, atomically: true, encoding: .utf8)

        let socketPath = "/tmp/omux-md-\(UUID().uuidString).sock"
        let requests = LockedValue<[JSONRPCRequest]>([])
        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            requests.value.append(request)
            return JSONRPCResponse(id: request.id, result: .object(["paneID": .string("pane-preview")]))
        }
        defer { server.stop() }

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: socketPath),
            writeLine: { output.append($0) },
            readInputLine: { nil },
            configLoader: OmuxConfigLoader(configURL: configURL),
            themeRegistry: OmuxThemeRegistry(),
            installer: OmuxCLIInstaller()
        )

        XCTAssertEqual(command.run(arguments: ["omux", "markdown-preview", markdownURL.path]), 0)
        XCTAssertEqual(output, [])
        XCTAssertEqual(requests.value.map(\.method), [ControlMethod.createExtensionPane.rawValue])
        guard case .object(let params)? = requests.value.first?.params,
              case .string(OmuxMarkdownPreviewPlugin.pluginID)? = params["pluginID"],
              case .string(markdownURL.path)? = params["source"],
              case .string("html")? = params["contentKind"],
              case .string("ready")? = params["status"],
              case .string("modal")? = params["presentation"],
              case .string(let html)? = params["html"]
        else {
            return XCTFail("expected markdown preview extension-pane create params")
        }
        XCTAssertTrue(html.contains("<h1>Preview</h1>"))
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertFalse(html.contains("alert(&quot;x&quot;)"))
    }

    func testMarkdownPreviewRendererRendersGFMAndConstrainsRawHTML() throws {
        let html = try OmuxMarkdownPreviewRenderer(theme: "light").render(
            markdown: """
            # README

            | Name | Value |
            | --- | --- |
            | Renderer | GFM |

            - [x] Done
            - [ ] Todo

            ~~removed~~

            https://example.com

            ```swift
            let value = 1
            ```

            ![Screenshot](../assets/screen-1.png)

            <p align="center"><img src="logo.png" alt="Logo"></p>
            <img src="x" onerror="alert(1)">
            <a href="javascript:alert(1)">bad</a>
            <script>alert("x")</script>
            """,
            title: "README.md",
            sourcePath: "/tmp/project/docs/README.md"
        )
        let sourceDirectory = URL(fileURLWithPath: "/tmp/project/docs/README.md").deletingLastPathComponent()
        let rawLogoURL = URL(fileURLWithPath: "logo.png", relativeTo: sourceDirectory)
            .standardizedFileURL
            .absoluteString
        let markdownImageURL = URL(fileURLWithPath: "../assets/screen-1.png", relativeTo: sourceDirectory)
            .standardizedFileURL
            .absoluteString
        let unsafeImageURL = URL(fileURLWithPath: "x", relativeTo: sourceDirectory)
            .standardizedFileURL
            .absoluteString

        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains("<th>Name</th>"))
        XCTAssertTrue(html.contains("<td>GFM</td>"))
        XCTAssertTrue(html.contains("type=\"checkbox\""))
        XCTAssertTrue(html.contains("checked"))
        XCTAssertTrue(html.contains("<del>removed</del>"))
        XCTAssertTrue(html.contains("<a href=\"https://example.com\">https://example.com</a>"))
        XCTAssertTrue(html.contains("language-swift"))
        XCTAssertTrue(html.contains("let value = 1"))
        XCTAssertTrue(html.contains("<img src=\"\(markdownImageURL)\" alt=\"Screenshot\""))
        XCTAssertTrue(html.contains("<p align=\"center\"><img src=\"\(rawLogoURL)\" alt=\"Logo\"></p>"))
        XCTAssertTrue(html.contains("<img src=\"\(unsafeImageURL)\">"))
        XCTAssertTrue(html.contains("<a>bad</a>"))
        XCTAssertFalse(html.contains("<script>alert(\"x\")</script>"))
        XCTAssertFalse(html.contains("onerror"))
        XCTAssertFalse(html.contains("javascript:"))
    }

    func testMarkdownPreviewChangeTrackerIgnoresMetadataOnlyChanges() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let markdownURL = root.appendingPathComponent("README.md")
        try "Hello\n".write(to: markdownURL, atomically: true, encoding: .utf8)

        var tracker = MarkdownPreviewChangeTracker()
        XCTAssertEqual(tracker.nextMarkdown(for: markdownURL), "Hello\n")

        try FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: markdownURL.path
        )
        XCTAssertNil(tracker.nextMarkdown(for: markdownURL))

        try "Updated\n".write(to: markdownURL, atomically: true, encoding: .utf8)
        XCTAssertEqual(tracker.nextMarkdown(for: markdownURL), "Updated\n")
    }

    func testCLIMarkdownPreviewUpdatesExistingPane() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let configURL = root.appendingPathComponent("config.toml")
        try """
        schema = 1

        [plugins.markdown-preview]
        enabled = true
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let markdownURL = root.appendingPathComponent("notes.md")
        try "Hello `code`\n".write(to: markdownURL, atomically: true, encoding: .utf8)

        let socketPath = "/tmp/omux-mdu-\(UUID().uuidString).sock"
        let requests = LockedValue<[JSONRPCRequest]>([])
        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            requests.value.append(request)
            return JSONRPCResponse(id: request.id, result: .object(["paneID": .string("pane-existing")]))
        }
        defer { server.stop() }

        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: socketPath),
            writeLine: { _ in },
            readInputLine: { nil },
            configLoader: OmuxConfigLoader(configURL: configURL),
            themeRegistry: OmuxThemeRegistry(),
            installer: OmuxCLIInstaller()
        )

        XCTAssertEqual(command.run(arguments: ["omux", "markdown-preview", markdownURL.path, "--pane", "pane-existing"]), 0)
        XCTAssertEqual(requests.value.map(\.method), [ControlMethod.updateExtensionPane.rawValue])
        guard case .object(let params)? = requests.value.first?.params,
              case .string("pane-existing")? = params["paneID"],
              case .string(let html)? = params["html"]
        else {
            return XCTFail("expected markdown preview update params")
        }
        XCTAssertTrue(html.contains("<code>code</code>"))
    }

    func testCLIMarkdownPreviewAcceptsModalShortcutFlag() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let configURL = root.appendingPathComponent("config.toml")
        try """
        schema = 1

        [plugins.markdown-preview]
        enabled = true
        presentation = "pane-tab"
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let markdownURL = root.appendingPathComponent("README.md")
        try "# Preview\n".write(to: markdownURL, atomically: true, encoding: .utf8)

        let socketPath = "/tmp/omux-mdmodal-\(UUID().uuidString).sock"
        let requests = LockedValue<[JSONRPCRequest]>([])
        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            requests.value.append(request)
            return JSONRPCResponse(id: request.id, result: .object(["paneID": .string("pane-preview")]))
        }
        defer { server.stop() }

        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: socketPath),
            writeLine: { _ in },
            readInputLine: { nil },
            configLoader: OmuxConfigLoader(configURL: configURL),
            themeRegistry: OmuxThemeRegistry(),
            installer: OmuxCLIInstaller()
        )

        XCTAssertEqual(command.run(arguments: ["omux", "markdown-preview", markdownURL.path, "--modal"]), 0)
        guard case .object(let params)? = requests.value.first?.params,
              case .string("modal")? = params["presentation"]
        else {
            return XCTFail("expected markdown preview modal presentation params")
        }
    }

    func testCLIMarkdownPreviewRequiresEnabledPlugin() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let configURL = root.appendingPathComponent("config.toml")
        try """
        schema = 1

        [plugins.markdown-preview]
        enabled = false
        """.write(to: configURL, atomically: true, encoding: .utf8)
        let markdownURL = root.appendingPathComponent("README.md")
        try "# Disabled\n".write(to: markdownURL, atomically: true, encoding: .utf8)

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: root.appendingPathComponent("unused.sock").path(percentEncoded: false)),
            writeLine: { output.append($0) },
            readInputLine: { nil },
            configLoader: OmuxConfigLoader(configURL: configURL),
            themeRegistry: OmuxThemeRegistry(),
            installer: OmuxCLIInstaller()
        )

        XCTAssertEqual(command.run(arguments: ["omux", "markdown-preview", markdownURL.path]), 1)
        XCTAssertTrue(output.contains(where: { $0.contains("Markdown preview plugin is disabled") }))
    }

    func testCLIMarkdownPreviewRejectsMissingFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let configURL = root.appendingPathComponent("config.toml")
        try """
        schema = 1

        [plugins.markdown-preview]
        enabled = true
        """.write(to: configURL, atomically: true, encoding: .utf8)

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: root.appendingPathComponent("unused.sock").path(percentEncoded: false)),
            writeLine: { output.append($0) },
            readInputLine: { nil },
            configLoader: OmuxConfigLoader(configURL: configURL),
            themeRegistry: OmuxThemeRegistry(),
            installer: OmuxCLIInstaller()
        )

        XCTAssertEqual(command.run(arguments: ["omux", "markdown-preview", root.appendingPathComponent("missing.md").path]), 1)
        XCTAssertTrue(output.contains(where: { $0.contains("readable Markdown file not found") }))
    }

    func testCLIExtensionPaneCommandsSendExpectedRequests() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let htmlURL = root.appendingPathComponent("preview.html")
        try "<h1>Preview</h1>".write(to: htmlURL, atomically: true, encoding: .utf8)

        let socketPath = "/tmp/omux-extcli-\(UUID().uuidString).sock"
        let requests = LockedValue<[JSONRPCRequest]>([])
        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            requests.value.append(request)
            return JSONRPCResponse(id: request.id, result: .object(["paneID": .string("pane-preview")]))
        }
        defer { server.stop() }

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: socketPath),
            writeLine: { output.append($0) }
        )

        XCTAssertEqual(command.run(arguments: [
            "omux", "extension-pane", "create",
            "--plugin", "dev.example.preview",
            "--title", "Preview",
            "--source", root.path,
            "--html-file", htmlURL.path,
            "--axis", "rows",
        ]), 0)
        XCTAssertEqual(command.run(arguments: [
            "omux", "extension-pane", "update",
            "--pane", "pane-preview",
            "--plugin", "dev.example.preview",
            "--status", "error",
            "--message", "render failed",
        ]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "extension-pane", "close", "--pane", "pane-preview"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "extension-pane", "update", "--pane", "pane-preview", "--plugin", "dev.example.preview", "--status", "bad"]), 1)

        XCTAssertEqual(requests.value.map(\.method), [
            ControlMethod.createExtensionPane.rawValue,
            ControlMethod.updateExtensionPane.rawValue,
            ControlMethod.closeExtensionPane.rawValue,
        ])
        guard case .object(let createParams)? = requests.value[0].params,
              case .object(let updateParams)? = requests.value[1].params,
              case .object(let closeParams)? = requests.value[2].params,
              case .string("rows")? = createParams["axis"],
              case .string("<h1>Preview</h1>")? = createParams["html"],
              case .string("error")? = updateParams["status"],
              case .string("render failed")? = updateParams["message"],
              case .string("pane-preview")? = closeParams["paneID"]
        else {
            return XCTFail("expected extension-pane request params")
        }
        XCTAssertTrue(output.last?.contains("usage: omux extension-pane update") == true)
    }

    func testCLIRegisteredPluginCommandReceivesArgumentsAndEnvironment() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let pluginDirectory = home.appendingPathComponent("plugins/hello", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
        defer {
            unsetenv("OMUX_HOME")
            try? FileManager.default.removeItem(at: home)
        }
        setenv("OMUX_HOME", home.path, 1)

        let markerURL = home.appendingPathComponent("marker.txt")
        let executableURL = pluginDirectory.appendingPathComponent("plugin")
        try """
        #!/bin/sh
        printf "%s\\n" "$OMUX_PLUGIN_COMMAND" "$1" "$2" "$OMUX_PLUGIN_EXECUTABLE" > "\(markerURL.path)"
        exit 17
        """.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

        let command = OmuxCLICommand(writeLine: { _ in })

        XCTAssertEqual(command.run(arguments: ["omux", "hello", "one", "two"]), 17)
        let marker = try String(contentsOf: markerURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        XCTAssertEqual(marker, ["hello", "one", "two", executableURL.path])
    }

    func testCLIPluginListAndPathInspectRegisteredPlugins() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let pluginsDirectory = home.appendingPathComponent("plugins", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginsDirectory, withIntermediateDirectories: true)
        defer {
            unsetenv("OMUX_HOME")
            try? FileManager.default.removeItem(at: home)
        }
        setenv("OMUX_HOME", home.path, 1)

        let alphaURL = pluginsDirectory.appendingPathComponent("alpha")
        try "#!/bin/sh\n".write(to: alphaURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: alphaURL.path)

        let betaDirectory = pluginsDirectory.appendingPathComponent("beta", isDirectory: true)
        try FileManager.default.createDirectory(at: betaDirectory, withIntermediateDirectories: true)
        let betaURL = betaDirectory.appendingPathComponent("plugin")
        try "#!/bin/sh\n".write(to: betaURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: betaURL.path)

        let ignoredURL = pluginsDirectory.appendingPathComponent("ignored")
        try "#!/bin/sh\n".write(to: ignoredURL, atomically: true, encoding: .utf8)

        var output = [String]()
        let command = OmuxCLICommand(writeLine: { output.append($0) })

        XCTAssertEqual(command.run(arguments: ["omux", "plugin", "path"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "plugin", "list"]), 0)
        XCTAssertEqual(output.first, pluginsDirectory.path)
        XCTAssertEqual(output.dropFirst(), [
            "\(OmuxAIStatusPlugin.commandName)\t\(OmuxAIStatusPlugin.commandDisplayPath)",
            "alpha\t\(alphaURL.path)",
            "beta\t\(betaURL.path)",
            "\(OmuxMarkdownPreviewPlugin.commandName)\t\(OmuxMarkdownPreviewPlugin.commandDisplayPath)",
        ])
    }

    func testCLIPluginDiscoveryUsesCustomRegistryFlag() throws {
        let registry = try makePluginRegistryFixture()
        defer { try? FileManager.default.removeItem(at: registry) }

        var output = [String]()
        let command = OmuxCLICommand(writeLine: { output.append($0) })

        XCTAssertEqual(command.run(arguments: ["omux", "plugins", "discover", "--registry", registry.absoluteString]), 0)
        XCTAssertEqual(output, ["hello\t0.1.0\tHello Pane\t\(registry.absoluteString)"])
    }

    func testCLIPluginDiscoverySupportsJSONOutput() throws {
        let registry = try makePluginRegistryFixture()
        defer { try? FileManager.default.removeItem(at: registry) }

        var output = [String]()
        let command = OmuxCLICommand(writeLine: { output.append($0) })

        XCTAssertEqual(command.run(arguments: ["omux", "plugins", "discover", "--json", "--registry", registry.absoluteString]), 0)
        let json = output.joined(separator: "\n")
        XCTAssertTrue(json.contains("\"id\""))
        XCTAssertTrue(json.contains("\"hello\""))
        XCTAssertTrue(json.contains("\"registry\""))
        XCTAssertTrue(json.contains(registry.lastPathComponent))
    }

    func testCLIPluginInstallWritesLocalPluginAndReceipt() throws {
        let registry = try makePluginRegistryFixture()
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer {
            unsetenv("OMUX_HOME")
            try? FileManager.default.removeItem(at: registry)
            try? FileManager.default.removeItem(at: home)
        }
        setenv("OMUX_HOME", home.path, 1)

        var output = [String]()
        let command = OmuxCLICommand(writeLine: { output.append($0) }, readInputLine: { nil })

        XCTAssertEqual(command.run(arguments: ["omux", "plugins", "install", "hello", "--yes", "--registry", registry.absoluteString]), 0)
        let pluginURL = home.appendingPathComponent("plugins/hello/plugin")
        let receiptURL = home.appendingPathComponent("installed/plugin/hello.json")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: pluginURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: receiptURL.path))
        XCTAssertTrue(output.contains("Installed plugin hello 0.1.0."))
    }

    func testCLIPluginUpdateAndUninstallUseReceipts() throws {
        let registry = try makePluginRegistryFixture()
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer {
            unsetenv("OMUX_HOME")
            try? FileManager.default.removeItem(at: registry)
            try? FileManager.default.removeItem(at: home)
        }
        setenv("OMUX_HOME", home.path, 1)

        var output = [String]()
        let command = OmuxCLICommand(writeLine: { output.append($0) }, readInputLine: { nil })

        XCTAssertEqual(command.run(arguments: ["omux", "plugins", "install", "hello", "--yes", "--registry", registry.absoluteString]), 0)
        try "#!/bin/sh\nexit 7\n".write(to: registry.appendingPathComponent("plugins/hello/plugin"), atomically: true, encoding: .utf8)
        XCTAssertEqual(command.run(arguments: ["omux", "plugins", "update", "hello", "--yes"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "plugins", "uninstall", "hello"]), 0)

        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent("plugins/hello/plugin").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent("installed/plugin/hello.json").path))
        XCTAssertTrue(output.contains("Updated plugin hello to 0.1.0."))
        XCTAssertTrue(output.contains("Uninstalled plugin hello 0.1.0."))
    }

    func testCLIInstallRejectsAmbiguousPackageIDAcrossRegistries() throws {
        let first = try makePluginRegistryFixture()
        let second = try makePluginRegistryFixture()
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }

        var output = [String]()
        let command = OmuxCLICommand(writeLine: { output.append($0) }, readInputLine: { nil })

        XCTAssertEqual(command.run(arguments: [
            "omux", "plugins", "install", "hello", "--yes",
            "--registry", first.absoluteString,
            "--registry", second.absoluteString,
        ]), 1)
        XCTAssertTrue(output.contains("omux error: package id is ambiguous across registries: hello"))
    }

    func testCLIHookInstallUsesExistingHookDirectoryLayout() throws {
        let registry = try makeHookRegistryFixture()
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer {
            unsetenv("OMUX_HOME")
            try? FileManager.default.removeItem(at: registry)
            try? FileManager.default.removeItem(at: home)
        }
        setenv("OMUX_HOME", home.path, 1)

        var output = [String]()
        let command = OmuxCLICommand(writeLine: { output.append($0) }, readInputLine: { nil })

        XCTAssertEqual(command.run(arguments: ["omux", "hooks", "install", "fail-notify", "--yes", "--registry", registry.absoluteString]), 0)
        let hookURL = home.appendingPathComponent("hooks/terminal-command-finished/20-notify")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: hookURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent("installed/hook/fail-notify.json").path))
        XCTAssertTrue(output.contains("Installed hook fail-notify 0.1.0."))
    }

    func testCLIInstallRejectsUnsafePackagePaths() throws {
        let registry = try makePluginRegistryFixture(targetPath: "../evil")
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer {
            unsetenv("OMUX_HOME")
            try? FileManager.default.removeItem(at: registry)
            try? FileManager.default.removeItem(at: home)
        }
        setenv("OMUX_HOME", home.path, 1)

        var output = [String]()
        let command = OmuxCLICommand(writeLine: { output.append($0) }, readInputLine: { nil })

        XCTAssertEqual(command.run(arguments: ["omux", "plugins", "install", "hello", "--yes", "--registry", registry.absoluteString]), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent("evil").path))
        XCTAssertTrue(output.contains(where: { $0.contains("unsafe package path") }))
    }

    func testCLIUninstallRefusesUnmanagedPackage() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer {
            unsetenv("OMUX_HOME")
            try? FileManager.default.removeItem(at: home)
        }
        setenv("OMUX_HOME", home.path, 1)

        var output = [String]()
        let command = OmuxCLICommand(writeLine: { output.append($0) })

        XCTAssertEqual(command.run(arguments: ["omux", "plugins", "uninstall", "hello"]), 1)
        XCTAssertTrue(output.contains("omux error: package is not managed by OpenMUX receipts: hello"))
    }

    func testCLIPluginPickerTogglesMarkdownPreviewAndReloads() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        defer {
            unsetenv("OMUX_HOME")
            try? FileManager.default.removeItem(at: tempHome)
        }
        setenv("OMUX_HOME", tempHome.path, 1)
        let configURL = tempHome.appendingPathComponent("config.toml")
        try OmuxConfigTemplate.starter().write(to: configURL, atomically: true, encoding: .utf8)

        let socketPath = "/tmp/omux-plugin-\(UUID().uuidString).sock"
        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            if request.method == ControlMethod.configReload.rawValue {
                return JSONRPCResponse(id: request.id, result: .object([
                    "applied": .bool(true),
                    "diagnostics": .array([]),
                ]))
            }
            return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 404, message: "unexpected"))
        }
        defer { server.stop() }

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: socketPath),
            writeLine: { output.append($0) },
            readInputLine: { nil },
            configLoader: OmuxConfigLoader(),
            themeRegistry: OmuxThemeRegistry(),
            installer: OmuxCLIInstaller(),
            isInteractivePluginPickerAvailable: { true },
            selectPluginInteractively: { items in
                let markdownPreview = try XCTUnwrap(items.first { $0.commandName == OmuxMarkdownPreviewPlugin.commandName })
                XCTAssertTrue(markdownPreview.isEnabled)
                XCTAssertTrue(markdownPreview.canToggle)
                let aiStatus = try XCTUnwrap(items.first { $0.commandName == OmuxAIStatusPlugin.commandName })
                XCTAssertTrue(aiStatus.isEnabled)
                XCTAssertTrue(aiStatus.canToggle)
                return markdownPreview
            }
        )

        XCTAssertEqual(command.run(arguments: ["omux", "plugins"]), 0)
        let contents = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("[plugins.markdown-preview]"))
        XCTAssertTrue(contents.contains("enabled = false"))
        XCTAssertEqual(output, ["Plugin markdown-preview disabled.", "No diagnostics.", "OpenMUX config reloaded."])
    }

    func testPluginPickerSearchSupportsFuzzyTerms() {
        let items = [
            PluginPickerItem(commandName: "markdown-preview", displayPath: "bundled:dev.fingergun.markdown-preview", isEnabled: true, canToggle: true),
            PluginPickerItem(commandName: "hello-world", displayPath: "/tmp/plugins/hello-world", isEnabled: true, canToggle: false),
            PluginPickerItem(commandName: "session-tools", displayPath: "/tmp/plugins/session-tools/plugin", isEnabled: true, canToggle: false),
        ]

        XCTAssertEqual(
            PluginPickerSearch.filteredItems(items, query: "mdp").map(\.commandName),
            ["markdown-preview"]
        )
        XCTAssertEqual(
            PluginPickerSearch.filteredItems(items, query: "sess").map(\.commandName),
            ["session-tools"]
        )
        XCTAssertEqual(
            PluginPickerSearch.filteredItems(items, query: "external").map(\.commandName),
            ["hello-world", "session-tools"]
        )
    }

    func testCLIBundledAIStatusPluginCannotBeShadowedByExternalPlugin() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let pluginsDirectory = home.appendingPathComponent("plugins", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginsDirectory, withIntermediateDirectories: true)
        defer {
            unsetenv("OMUX_HOME")
            try? FileManager.default.removeItem(at: home)
        }
        setenv("OMUX_HOME", home.path, 1)

        let markerURL = home.appendingPathComponent("should-not-exist.txt")
        let executableURL = pluginsDirectory.appendingPathComponent(OmuxAIStatusPlugin.commandName)
        try """
        #!/bin/sh
        echo shadowed > "\(markerURL.path)"
        exit 42
        """.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

        var output = [String]()
        let command = OmuxCLICommand(writeLine: { output.append($0) })

        XCTAssertEqual(command.run(arguments: ["omux", OmuxAIStatusPlugin.commandName]), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path))
        XCTAssertEqual(output, [OmuxAIStatusPlugin.usage])
    }

    func testCLIBuiltInCommandTakesPrecedenceOverPlugin() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let pluginsDirectory = home.appendingPathComponent("plugins", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginsDirectory, withIntermediateDirectories: true)
        defer {
            unsetenv("OMUX_HOME")
            try? FileManager.default.removeItem(at: home)
        }
        setenv("OMUX_HOME", home.path, 1)

        let markerURL = home.appendingPathComponent("should-not-exist.txt")
        let executableURL = pluginsDirectory.appendingPathComponent("help")
        try """
        #!/bin/sh
        echo shadowed > "\(markerURL.path)"
        exit 42
        """.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

        var output = [String]()
        let command = OmuxCLICommand(writeLine: { output.append($0) })

        XCTAssertEqual(command.run(arguments: ["omux", "help"]), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path))
        XCTAssertTrue(output.first?.contains("OpenMUX CLI") == true)
    }

    func testCLIBundledMarkdownPreviewPluginCannotBeShadowedByExternalPlugin() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let pluginsDirectory = home.appendingPathComponent("plugins", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginsDirectory, withIntermediateDirectories: true)
        defer {
            unsetenv("OMUX_HOME")
            try? FileManager.default.removeItem(at: home)
        }
        setenv("OMUX_HOME", home.path, 1)

        let markerURL = home.appendingPathComponent("should-not-exist.txt")
        let executableURL = pluginsDirectory.appendingPathComponent(OmuxMarkdownPreviewPlugin.commandName)
        try """
        #!/bin/sh
        echo shadowed > "\(markerURL.path)"
        exit 42
        """.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

        var output = [String]()
        let command = OmuxCLICommand(writeLine: { output.append($0) })

        XCTAssertEqual(command.run(arguments: ["omux", OmuxMarkdownPreviewPlugin.commandName]), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path))
        XCTAssertEqual(output, ["usage: omux markdown-preview <file> [--watch] [--pane <id>] [--title <title>] [--axis columns|rows] [--modal|--pane-tab|--presentation pane-tab|modal]"])
    }

    func testCLISplitAcceptsDirectionAndTargetInEitherOrder() throws {
        let socketPath = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "split.sock")
            .path(percentEncoded: false)

        let requests = LockedValue<[RPCValue?]>([])
        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            requests.value.append(request.params)
            return JSONRPCResponse(id: request.id, result: .string("ok"))
        }
        defer { server.stop() }

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: socketPath),
            writeLine: { output.append($0) }
        )

        XCTAssertEqual(command.run(arguments: ["omux", "split", "left", "--focused"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "split", "--pane", "pane-1", "up"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "split", "sideways"]), 1)

        guard case .object(let leftParams)? = requests.value[0],
              case .object(let upParams)? = requests.value[1],
              case .object(let leftTarget)? = leftParams["target"],
              case .object(let upTarget)? = upParams["target"]
        else {
            return XCTFail("expected split params")
        }

        XCTAssertEqual(leftParams["axis"], .string(PaneSplitAxis.columns.rawValue))
        XCTAssertEqual(leftTarget["type"], .string("focused"))
        XCTAssertEqual(upParams["axis"], .string(PaneSplitAxis.rows.rawValue))
        XCTAssertEqual(upTarget["type"], .string("pane"))
        XCTAssertEqual(upTarget["id"], .string("pane-1"))
        XCTAssertEqual(output.last, "usage: omux split [--session <id>|--pane <id>|--tab <id>|--workspace <id>|--focused] [left|right|up|down]")
    }

    func testCLIHistoryRequestsScopesAndFormatsHumanOutput() throws {
        let socketPath = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "h.sock")
            .path(percentEncoded: false)

        let requests = LockedValue<[(method: String, params: RPCValue?)]>([])
        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            requests.value.append((request.method, request.params))
            return JSONRPCResponse(id: request.id, result: .object([
                "maxBytes": .integer(1_048_576),
                "maxLines": .integer(4_000),
                "items": .array([
                    .object([
                        "workspaceID": .string("workspace-1"),
                        "workspaceName": .string("OMUX"),
                        "tabID": .string("tab-1"),
                        "tabTitle": .string("Main"),
                        "paneStackID": .string("stack-1"),
                        "paneID": .string("pane-1"),
                        "paneTitle": .string("omux"),
                        "sessionID": .string("session-1"),
                        "workingDirectory": .string("/tmp/omux"),
                        "text": .string("hello\nworld"),
                        "lineCount": .integer(2),
                        "byteCount": .integer(11),
                        "truncated": .bool(false),
                        "unavailable": .null,
                    ]),
                ]),
            ]))
        }
        defer { server.stop() }

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: socketPath),
            writeLine: { output.append($0) }
        )

        XCTAssertEqual(command.run(arguments: ["omux", "history"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "history", "pane-1"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "history", "all", "--max-lines", "2", "--max-bytes", "50"]), 0)

        XCTAssertEqual(requests.value.map(\.method), Array(repeating: ControlMethod.terminalHistory.rawValue, count: 3))
        XCTAssertTrue(output.joined(separator: "\n").contains("== OMUX (workspace-1) / Main (tab-1) / omux (pane-1)"))
        XCTAssertTrue(output.joined(separator: "\n").contains("cwd: /tmp/omux"))
        XCTAssertTrue(output.joined(separator: "\n").contains("hello\nworld"))

        guard case .object(let noArgParams)? = requests.value[0].params,
              case .object(let paneParams)? = requests.value[1].params,
              case .object(let allParams)? = requests.value[2].params
        else {
            return XCTFail("expected history params")
        }
        XCTAssertEqual(noArgParams["scope"], .string("activeWorkspace"))
        XCTAssertEqual(paneParams["scope"], .string("pane"))
        XCTAssertEqual(paneParams["paneID"], .string("pane-1"))
        XCTAssertEqual(allParams["scope"], .string("all"))
        XCTAssertEqual(allParams["maxLines"], .integer(2))
        XCTAssertEqual(allParams["maxBytes"], .integer(50))
    }

    func testCLIHistorySupportsJSONOutputAndInvalidArguments() throws {
        let socketPath = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "hj.sock")
            .path(percentEncoded: false)

        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            XCTAssertEqual(request.method, ControlMethod.terminalHistory.rawValue)
            return JSONRPCResponse(id: request.id, result: .object([
                "items": .array([]),
            ]))
        }
        defer { server.stop() }

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: socketPath),
            writeLine: { output.append($0) }
        )

        XCTAssertEqual(command.run(arguments: ["omux", "history", "--json", "all"]), 0)
        XCTAssertTrue(output.first?.contains("\"items\" : [") == true)

        output.removeAll()
        XCTAssertEqual(command.run(arguments: ["omux", "history", "--max-lines"]), 1)
        XCTAssertEqual(output, ["usage: omux history [--json] [--max-lines <count>] [--max-bytes <count>] [<pane-id>|all]"])
    }

    func testCLIHistoryClearSupportsScopedTargets() throws {
        let socketPath = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "hc.sock")
            .path(percentEncoded: false)

        let requests = LockedValue<[JSONRPCRequest]>([])
        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            requests.value.append(request)
            return JSONRPCResponse(id: request.id, result: .object([
                "ok": .bool(true),
                "clearedCount": .integer(2),
                "target": .null,
            ]))
        }
        defer { server.stop() }

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: socketPath),
            writeLine: { output.append($0) },
            readInputLine: { nil },
            configLoader: OmuxConfigLoader(),
            themeRegistry: OmuxThemeRegistry(),
            installer: OmuxCLIInstaller(),
            environment: { [:] }
        )

        XCTAssertEqual(command.run(arguments: ["omux", "history", "clear"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "history", "clear", "--workspace", "workspace-1"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "history", "clear", "--pane-tab", "pane-1", "--json"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "history", "clear", "--all", "--pane", "pane-1"]), 1)

        XCTAssertEqual(requests.value.map(\.method), Array(repeating: ControlMethod.clearTerminalHistory.rawValue, count: 3))
        XCTAssertEqual(output[0], "Cleared history for 2 panes.")
        XCTAssertTrue(output[2].contains("\"clearedCount\" : 2"))
        XCTAssertEqual(output[3], "usage: omux history clear [--json] [--all|--session <id>|--pane <id>|--pane-tab <id>|--tab <id>|--workspace <id>|--focused]")

        guard case .object(let allParams)? = requests.value[0].params,
              case .object(let workspaceParams)? = requests.value[1].params,
              case .object(let paneTabParams)? = requests.value[2].params,
              case .object(let workspaceTarget)? = workspaceParams["target"],
              case .object(let paneTabTarget)? = paneTabParams["target"]
        else {
            return XCTFail("expected history clear params")
        }

        XCTAssertEqual(allParams["scope"], .string("all"))
        XCTAssertEqual(workspaceTarget["type"], .string("workspace"))
        XCTAssertEqual(workspaceTarget["id"], .string("workspace-1"))
        XCTAssertEqual(paneTabTarget["type"], .string("pane"))
        XCTAssertEqual(paneTabTarget["id"], .string("pane-1"))
    }

    func testCLIHistoryClearEmitsLocalTerminalClearWhenCurrentOpenMUXPaneIsTargeted() throws {
        let socketPath = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "hc-local.sock")
            .path(percentEncoded: false)

        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            JSONRPCResponse(id: request.id, result: .object([
                "ok": .bool(true),
                "clearedCount": .integer(1),
                "target": .null,
            ]))
        }
        defer { server.stop() }

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: socketPath),
            writeLine: { output.append($0) },
            readInputLine: { nil },
            configLoader: OmuxConfigLoader(),
            themeRegistry: OmuxThemeRegistry(),
            installer: OmuxCLIInstaller(),
            environment: {
                [
                    "OMUX_PANE_ID": "pane-1",
                    "OMUX_SESSION_ID": "session-1",
                ]
            }
        )

        XCTAssertEqual(command.run(arguments: ["omux", "history", "clear", "--pane", "pane-1"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "history", "clear", "--pane", "pane-2"]), 0)

        XCTAssertTrue(output[0].hasPrefix("\u{001B}[H\u{001B}[2J\u{001B}[3J"))
        XCTAssertEqual(output[0].replacingOccurrences(of: "\u{001B}[H\u{001B}[2J\u{001B}[3J", with: ""), "Cleared history for 1 pane.")
        XCTAssertEqual(output[1], "Cleared history for 1 pane.")
    }

    func testCLIPluginRunnerProvidesOMUXCLIPathToPlugins() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let pluginDirectory = home.appendingPathComponent("plugins/echo-cli", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
        defer {
            unsetenv("OMUX_HOME")
            try? FileManager.default.removeItem(at: home)
        }
        setenv("OMUX_HOME", home.path, 1)

        let executableURL = pluginDirectory.appendingPathComponent("plugin")
        let markerURL = home.appendingPathComponent("plugin-cli.txt")
        try """
        #!/bin/sh
        printf "%s\\n" "$OMUX_CLI" "$OMUX_PLUGIN_COMMAND" > "\(markerURL.path)"
        exit 0
        """.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

        let command = OmuxCLICommand(writeLine: { _ in })
        XCTAssertEqual(command.run(arguments: ["omux", "echo-cli"]), 0)

        let marker = try String(contentsOf: markerURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        XCTAssertEqual(marker.count, 2)
        XCTAssertTrue(marker[0] == "omux" || marker[0].hasSuffix("/omux"))
        XCTAssertEqual(marker[1], "echo-cli")
    }

    func testCLIHistoryPrintsUnavailablePane() throws {
        let socketPath = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "hu.sock")
            .path(percentEncoded: false)

        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            JSONRPCResponse(id: request.id, result: .object([
                "items": .array([
                    .object([
                        "workspaceID": .string("workspace-1"),
                        "workspaceName": .string("OMUX"),
                        "tabID": .string("tab-1"),
                        "tabTitle": .string("Main"),
                        "paneStackID": .null,
                        "paneID": .string("pane-1"),
                        "paneTitle": .string("omux"),
                        "sessionID": .string("session-1"),
                        "workingDirectory": .null,
                        "text": .string(""),
                        "lineCount": .integer(0),
                        "byteCount": .integer(0),
                        "truncated": .bool(false),
                        "unavailable": .string("history unavailable"),
                    ]),
                ]),
            ]))
        }
        defer { server.stop() }

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: socketPath),
            writeLine: { output.append($0) }
        )

        XCTAssertEqual(command.run(arguments: ["omux", "history", "pane-1"]), 0)
        XCTAssertTrue(output.contains("unavailable: history unavailable"))
        XCTAssertTrue(output.contains("(no history)"))
    }

    func testCLIPrintsControlPlaneEventsUntilStreamCloses() throws {
        let socketPath = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "events.sock")
            .path(percentEncoded: false)

        let encoder = JSONEncoder()
        let server = LocalControlServer(socketPath: socketPath)
        try server.start(
            handler: { request in
                JSONRPCResponse(id: request.id, error: JSONRPCError(code: 404, message: "unexpected"))
            },
            streamHandler: { descriptor, request in
                guard request.method == ControlMethod.terminalEvents.rawValue else {
                    return false
                }

                let ack = JSONRPCResponse(id: request.id, result: .string("subscribed"))
                try UnixSocketIO.writeLine(try encoder.encode(ack), to: descriptor)

                let event = JSONRPCRequest(
                    id: nil,
                    method: ControlMethod.terminalEvents.rawValue,
                    params: .object([
                        "name": .string("workspace.opened"),
                        "workspaceID": .string("workspace-1"),
                        "tabID": .null,
                        "paneID": .null,
                        "sessionID": .null,
                        "payload": .object([
                            "path": .string("/tmp/demo"),
                        ]),
                    ])
                )
                try UnixSocketIO.writeLine(try encoder.encode(event), to: descriptor)
                return true
            }
        )
        defer { server.stop() }

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: socketPath),
            writeLine: { output.append($0) }
        )

        let exitCode = command.run(arguments: ["omux", "events"])

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(output.count, 1)
        XCTAssertTrue(output[0].contains("\"name\" : \"workspace.opened\""))
        XCTAssertTrue(output[0].contains("\"workspaceID\" : \"workspace-1\""))
    }

    func testCLIConfigDoctorPrintsWarningsAndReturnsZero() throws {
        let socketPath = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "doctor.sock")
            .path(percentEncoded: false)

        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            if request.method == ControlMethod.configDoctor.rawValue {
                return JSONRPCResponse(id: request.id, result: .array([
                    .object([
                        "severity": .string("warning"),
                        "message": .string("managed key overridden"),
                        "filePath": .string("/tmp/config.toml"),
                        "line": .integer(12),
                    ]),
                ]))
            }
            return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 404, message: "unexpected"))
        }
        defer { server.stop() }

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: socketPath),
            writeLine: { output.append($0) }
        )

        let exitCode = command.run(arguments: ["omux", "config", "doctor"])

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(output, ["[warning] /tmp/config.toml:12 managed key overridden"])
    }

    func testCLIConfigReloadPrintsResult() throws {
        let socketPath = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "reload.sock")
            .path(percentEncoded: false)

        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            if request.method == ControlMethod.configReload.rawValue {
                return JSONRPCResponse(id: request.id, result: .object([
                    "applied": .bool(true),
                    "diagnostics": .array([]),
                ]))
            }
            return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 404, message: "unexpected"))
        }
        defer { server.stop() }

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: socketPath),
            writeLine: { output.append($0) }
        )

        let exitCode = command.run(arguments: ["omux", "config", "reload"])

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(output, ["No diagnostics.", "OpenMUX config reloaded."])
    }

    func testCLIConfigGetJSONExportsEffectiveConfigAndDiagnostics() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        defer {
            unsetenv("OMUX_HOME")
            try? FileManager.default.removeItem(at: tempHome)
        }
        setenv("OMUX_HOME", tempHome.path, 1)
        let configURL = tempHome.appendingPathComponent("config.toml")
        try """
        schema = 1
        [theme]
        name = "nord"
        [ui.panes]
        inactive_opacity = 0.7
        """.write(to: configURL, atomically: true, encoding: .utf8)

        var output = [String]()
        let command = OmuxCLICommand(writeLine: { output.append($0) })

        XCTAssertEqual(command.run(arguments: ["omux", "config", "get", "--json"]), 0)
        let export = try JSONDecoder().decode(OmuxConfigExport.self, from: Data(output[0].utf8))
        XCTAssertEqual(export.sourcePath, configURL.path)
        XCTAssertEqual(export.values.themeName, "nord")
        XCTAssertEqual(export.values.ui.panes.inactiveOpacity, 0.7)
        XCTAssertEqual(export.defaults.markdownPreviewRenderer, "builtin")
        XCTAssertEqual(export.defaults.markdownPreviewPresentation, "pane-tab")
        XCTAssertEqual(export.diagnostics, [])
    }

    func testCLIConfigGetJSONReportsDiagnostics() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        defer {
            unsetenv("OMUX_HOME")
            try? FileManager.default.removeItem(at: tempHome)
        }
        setenv("OMUX_HOME", tempHome.path, 1)
        let configURL = tempHome.appendingPathComponent("config.toml")
        try "schema = \"bad\"\n".write(to: configURL, atomically: true, encoding: .utf8)

        var output = [String]()
        let command = OmuxCLICommand(writeLine: { output.append($0) })

        XCTAssertEqual(command.run(arguments: ["omux", "config", "get", "--json"]), 1)
        let export = try JSONDecoder().decode(OmuxConfigExport.self, from: Data(output[0].utf8))
        XCTAssertEqual(export.sourcePath, OmuxConfigPaths.configFileURL.path)
        XCTAssertEqual(export.diagnostics.first?.severity, .error)
        XCTAssertEqual(export.diagnostics.first?.message, "Schema must be an integer.")
    }

    func testCLIConfigApplyJSONWritesBackupAndReloads() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        defer {
            unsetenv("OMUX_HOME")
            try? FileManager.default.removeItem(at: tempHome)
        }
        setenv("OMUX_HOME", tempHome.path, 1)
        let configURL = tempHome.appendingPathComponent("config.toml")
        try OmuxConfigTemplate.starter(themeName: "nord").write(to: configURL, atomically: true, encoding: .utf8)
        let payloadURL = tempHome.appendingPathComponent("apply.json")
        try """
        {
          "themeName": "monokai-soda",
          "ui": {
            "panes": {
              "inactiveOpacity": 0.66
            }
          },
          "plugins": {
            "markdownPreview": {
              "enabled": false
            }
          }
        }
        """.write(to: payloadURL, atomically: true, encoding: .utf8)

        let socketPath = "/tmp/omux-apply-\(UUID().uuidString).sock"
        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            if request.method == ControlMethod.configReload.rawValue {
                return JSONRPCResponse(id: request.id, result: .object([
                    "applied": .bool(true),
                    "diagnostics": .array([]),
                ]))
            }
            return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 404, message: "unexpected"))
        }
        defer { server.stop() }

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: socketPath),
            writeLine: { output.append($0) }
        )

        XCTAssertEqual(command.run(arguments: ["omux", "config", "apply", "--json-file", payloadURL.path]), 0)
        let result = try JSONDecoder().decode(OmuxConfigApplyResult.self, from: Data(output[0].utf8))
        XCTAssertTrue(result.applied)
        XCTAssertEqual(result.path, configURL.path)
        let backupPath = try XCTUnwrap(result.backupPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupPath))
        let contents = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("name = \"monokai-soda\""))
        XCTAssertTrue(contents.contains("inactive_opacity = 0.66"))
        XCTAssertTrue(contents.contains("enabled = false"))
        XCTAssertEqual(output.suffix(2), ["No diagnostics.", "OpenMUX config reloaded."])
    }

    func testCLIConfigApplyJSONRejectsUnsupportedKeysWithoutWriting() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        defer {
            unsetenv("OMUX_HOME")
            try? FileManager.default.removeItem(at: tempHome)
        }
        setenv("OMUX_HOME", tempHome.path, 1)
        let configURL = tempHome.appendingPathComponent("config.toml")
        try OmuxConfigTemplate.starter(themeName: "nord").write(to: configURL, atomically: true, encoding: .utf8)
        let originalContents = try String(contentsOf: configURL, encoding: .utf8)
        let payloadURL = tempHome.appendingPathComponent("apply.json")
        try #"{"ghostty":{"copy-on-select":false}}"#.write(to: payloadURL, atomically: true, encoding: .utf8)

        var output = [String]()
        let command = OmuxCLICommand(writeLine: { output.append($0) })

        XCTAssertEqual(command.run(arguments: ["omux", "config", "apply", "--json-file", payloadURL.path]), 1)
        let result = try JSONDecoder().decode(OmuxConfigApplyResult.self, from: Data(output[0].utf8))
        XCTAssertFalse(result.applied)
        XCTAssertEqual(result.diagnostics.first?.message, "Unsupported config apply key 'ghostty'.")
        XCTAssertEqual(try String(contentsOf: configURL, encoding: .utf8), originalContents)
    }

    func testCLIConfigInitWritesStarterConfigAndRefusesOverwrite() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        defer {
            unsetenv("OMUX_HOME")
            try? FileManager.default.removeItem(at: tempHome)
        }
        setenv("OMUX_HOME", tempHome.path, 1)

        var output = [String]()
        let command = OmuxCLICommand(writeLine: { output.append($0) })

        XCTAssertEqual(command.run(arguments: ["omux", "config", "init"]), 0)
        let configURL = tempHome.appendingPathComponent("config.toml")
        let contents = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("schema = 1"))
        XCTAssertTrue(contents.contains("[theme]"))
        XCTAssertTrue(contents.contains("default_root_path = \"~\""))
        XCTAssertTrue(contents.contains("[keys]"))
        for (chord, action) in OpenMUXKeyBindingRegistry.defaultBindingPairs {
            XCTAssertTrue(contents.contains("\"\(chord.description)\" = \"\(action.rawValue)\""))
        }
        XCTAssertFalse(contents.contains("cmd+shift+backspace"))

        output.removeAll()
        XCTAssertEqual(command.run(arguments: ["omux", "config", "init"]), 1)
        XCTAssertEqual(output, ["omux error: \(configURL.path) already exists"])
    }

    func testCLIConfigInactiveOpacityWritesConfigAndReloads() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        defer {
            unsetenv("OMUX_HOME")
            try? FileManager.default.removeItem(at: tempHome)
        }
        setenv("OMUX_HOME", tempHome.path, 1)
        let configURL = tempHome.appendingPathComponent("config.toml")
        try OmuxConfigTemplate.starter(themeName: "nord").write(to: configURL, atomically: true, encoding: .utf8)

        let socketPath = "/tmp/omux-opacity-\(UUID().uuidString).sock"
        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            if request.method == ControlMethod.configReload.rawValue {
                return JSONRPCResponse(id: request.id, result: .object([
                    "applied": .bool(true),
                    "diagnostics": .array([]),
                ]))
            }
            return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 404, message: "unexpected"))
        }
        defer { server.stop() }

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: socketPath),
            writeLine: { output.append($0) }
        )

        XCTAssertEqual(command.run(arguments: ["omux", "config", "inactive-opacity", "0.72"]), 0)
        let contents = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("[ui.panes]"))
        XCTAssertTrue(contents.contains("inactive_opacity = 0.72"))
        XCTAssertEqual(output, ["Inactive pane opacity set to 0.72.", "No diagnostics.", "OpenMUX config reloaded."])
    }

    func testCLIConfigInactiveOpacityRejectsInvalidValues() throws {
        var output = [String]()
        let command = OmuxCLICommand(writeLine: { output.append($0) })

        XCTAssertEqual(command.run(arguments: ["omux", "config", "inactive-opacity", "1.1"]), 1)
        XCTAssertEqual(output, ["usage: omux config inactive-opacity <0.0-1.0>"])
    }

    func testCLIThemeListPrintsAvailableThemesAndCurrentTheme() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        defer {
            unsetenv("OMUX_HOME")
            try? FileManager.default.removeItem(at: tempHome)
        }
        setenv("OMUX_HOME", tempHome.path, 1)
        try OmuxConfigTemplate.starter(themeName: "nord").write(
            to: tempHome.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )

        var output = [String]()
        let command = OmuxCLICommand(writeLine: { output.append($0) })

        XCTAssertEqual(command.run(arguments: ["omux", "theme", "list"]), 0)
        XCTAssertEqual(output.first, "Available themes:")
        XCTAssertTrue(output.contains(where: { $0.contains("* nord — Nord") }))
        XCTAssertTrue(output.contains(where: { $0.contains("monokai-soda") }))
    }

    func testCLIThemeSetUpdatesConfigAndReloads() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        defer {
            unsetenv("OMUX_HOME")
            try? FileManager.default.removeItem(at: tempHome)
        }
        setenv("OMUX_HOME", tempHome.path, 1)
        try OmuxConfigTemplate.starter(themeName: "monokai-soda").write(
            to: tempHome.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )

        let socketPath = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "theme-reload.sock")
            .path(percentEncoded: false)
        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            if request.method == ControlMethod.configReload.rawValue {
                return JSONRPCResponse(id: request.id, result: .object([
                    "applied": .bool(true),
                    "diagnostics": .array([]),
                ]))
            }
            return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 404, message: "unexpected"))
        }
        defer { server.stop() }

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: socketPath),
            writeLine: { output.append($0) }
        )

        XCTAssertEqual(command.run(arguments: ["omux", "theme", "nord"]), 0)
        let contents = try String(contentsOf: tempHome.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertTrue(contents.contains("name = \"nord\""))
        XCTAssertTrue(contents.contains("[keys]"))
        XCTAssertTrue(contents.contains("\"cmd+shift+w\" = \"pane.remove\""))
        XCTAssertEqual(output, ["Theme set to Nord.", "No diagnostics.", "OpenMUX config reloaded."])
    }

    func testCLIThemePickerSelectsThemeByNumberAndReloads() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        defer {
            unsetenv("OMUX_HOME")
            try? FileManager.default.removeItem(at: tempHome)
        }
        setenv("OMUX_HOME", tempHome.path, 1)
        try OmuxConfigTemplate.starter(themeName: "monokai-soda").write(
            to: tempHome.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )

        let socketPath = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "theme-picker.sock")
            .path(percentEncoded: false)
        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            if request.method == ControlMethod.configReload.rawValue {
                return JSONRPCResponse(id: request.id, result: .object([
                    "applied": .bool(true),
                    "diagnostics": .array([]),
                ]))
            }
            return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 404, message: "unexpected"))
        }
        defer { server.stop() }

        var output = [String]()
        var selectedInput: String?
        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: socketPath),
            writeLine: { output.append($0) },
            readInputLine: {
                selectedInput = output
                    .first(where: { $0.contains(" nord — Nord") })?
                    .split(separator: ".", maxSplits: 1)
                    .first
                    .map(String.init)
                return selectedInput ?? ""
            }
        )

        XCTAssertEqual(command.run(arguments: ["omux", "theme"]), 0)
        XCTAssertNotNil(selectedInput)
        let contents = try String(contentsOf: tempHome.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertTrue(contents.contains("name = \"nord\""))
        XCTAssertEqual(output.first, "Available themes:")
        XCTAssertTrue(output.contains("Select theme number or name:"))
        XCTAssertTrue(output.contains("Theme set to Nord."))
    }

    func testCLIInteractiveThemePickerSelectsThemeAndReloads() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        defer {
            unsetenv("OMUX_HOME")
            try? FileManager.default.removeItem(at: tempHome)
        }
        setenv("OMUX_HOME", tempHome.path, 1)
        try OmuxConfigTemplate.starter(themeName: "monokai-soda").write(
            to: tempHome.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )

        let socketPath = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "itp.sock")
            .path(percentEncoded: false)
        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            if request.method == ControlMethod.configReload.rawValue {
                return JSONRPCResponse(id: request.id, result: .object([
                    "applied": .bool(true),
                    "diagnostics": .array([]),
                ]))
            }
            return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 404, message: "unexpected"))
        }
        defer { server.stop() }

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: socketPath),
            writeLine: { output.append($0) },
            readInputLine: { nil },
            configLoader: OmuxConfigLoader(),
            themeRegistry: OmuxThemeRegistry(),
            installer: OmuxCLIInstaller(),
            isInteractiveThemePickerAvailable: { true },
            selectThemeInteractively: { themes, currentThemeName in
                XCTAssertEqual(currentThemeName, "monokai-soda")
                return themes.first(where: { $0.name == "nord" })
            }
        )

        XCTAssertEqual(command.run(arguments: ["omux", "theme"]), 0)
        let contents = try String(contentsOf: tempHome.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertTrue(contents.contains("name = \"nord\""))
        XCTAssertEqual(output, ["Theme set to Nord.", "No diagnostics.", "OpenMUX config reloaded."])
    }

    func testCLIInteractiveThemePickerCancellationDoesNotModifyConfig() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        defer {
            unsetenv("OMUX_HOME")
            try? FileManager.default.removeItem(at: tempHome)
        }
        setenv("OMUX_HOME", tempHome.path, 1)
        let configURL = tempHome.appendingPathComponent("config.toml")
        try OmuxConfigTemplate.starter(themeName: "monokai-soda").write(
            to: configURL,
            atomically: true,
            encoding: .utf8
        )

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(),
            writeLine: { output.append($0) },
            readInputLine: { nil },
            configLoader: OmuxConfigLoader(),
            themeRegistry: OmuxThemeRegistry(),
            installer: OmuxCLIInstaller(),
            isInteractiveThemePickerAvailable: { true },
            selectThemeInteractively: { _, _ in nil }
        )

        XCTAssertEqual(command.run(arguments: ["omux", "theme"]), 0)
        let contents = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("name = \"monokai-soda\""))
        XCTAssertEqual(output, ["Cancelled."])
    }

    func testCLIAgentSessionsResumeChoiceFallbackWritesSelectedCommand() throws {
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: outputURL) }
        var output = [String]()
        let command = OmuxCLICommand(
            writeLine: { output.append($0) },
            readInputLine: { "2" }
        )

        XCTAssertEqual(command.run(arguments: [
            "omux", "agent-sessions", "resume-choice", "codex:abc",
            "--resume-command", "codex resume 'abc'",
            "--output", outputURL.path,
            "--session-path", "/Users/example/projects/other",
            "--current-path", "/Users/example/projects/omux",
        ]), 0)

        let expectedExecutable: String
        if let executable = CommandLine.arguments.first, executable.isEmpty == false {
            expectedExecutable = "'" + executable.replacingOccurrences(of: "'", with: "'\\''") + "'"
        } else {
            expectedExecutable = "omux"
        }
        XCTAssertEqual(
            try String(contentsOf: outputURL, encoding: .utf8),
            "\(expectedExecutable) agent-sessions resume 'codex:abc' --workspace"
        )
        XCTAssertTrue(output.contains("Agent session path differs."))
        XCTAssertTrue(output.contains("2. Open Matching Workspace — Open the session path as a workspace and resume there"))
    }

    func testCLIInteractiveAgentSessionsResumeChoiceWritesSelectedCommand() throws {
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: outputURL) }
        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: "/tmp/not-used.sock"),
            writeLine: { output.append($0) },
            readInputLine: { nil },
            configLoader: OmuxConfigLoader(),
            themeRegistry: OmuxThemeRegistry(),
            installer: OmuxCLIInstaller(),
            isInteractiveVaultResumeChoicePickerAvailable: { true },
            selectVaultResumeChoiceInteractively: { items, context in
                XCTAssertEqual(context.sessionPath, "/Users/example/projects/other")
                XCTAssertEqual(context.currentPaths, ["/Users/example/projects/omux"])
                return items.first { $0.keyword == "resume" }
            }
        )

        XCTAssertEqual(command.run(arguments: [
            "omux", "agent-sessions", "resume-choice", "codex:abc",
            "--resume-command", "codex resume 'abc'",
            "--output", outputURL.path,
            "--session-path", "/Users/example/projects/other",
            "--current-path", "/Users/example/projects/omux",
        ]), 0)

        XCTAssertEqual(try String(contentsOf: outputURL, encoding: .utf8), "codex resume 'abc'")
        XCTAssertEqual(output, ["Selected: Resume Here"])
    }

    func testThemePickerSearchFiltersThemesByNameOrDisplayName() {
        let themes = [
            pickerTheme(name: "catppuccin", displayName: "Catppuccin"),
            pickerTheme(name: "catppuccin-mocha", displayName: "Catppuccin Mocha"),
            pickerTheme(name: "banana-blueberry", displayName: "Banana Blueberry"),
            pickerTheme(name: "nord", displayName: "Nord"),
            pickerTheme(name: "quantum", displayName: "Quantum"),
        ]

        XCTAssertEqual(
            ThemePickerSearch.filteredThemes(themes, query: "cat").map(\.name),
            ["catppuccin", "catppuccin-mocha"]
        )
        XCTAssertEqual(
            ThemePickerSearch.filteredThemes(themes, query: "blue").map(\.name),
            ["banana-blueberry"]
        )
        XCTAssertEqual(
            ThemePickerSearch.filteredThemes(themes, query: "q").map(\.name),
            ["quantum"]
        )
    }

    func testThemePickerSearchSupportsFuzzyTerms() {
        let themes = [
            pickerTheme(name: "catppuccin-mocha", displayName: "Catppuccin Mocha"),
            pickerTheme(name: "catppuccin-frappe", displayName: "Catppuccin Frappe"),
            pickerTheme(name: "github-dark", displayName: "GitHub Dark"),
        ]

        XCTAssertEqual(
            ThemePickerSearch.filteredThemes(themes, query: "ctm").map(\.name),
            ["catppuccin-mocha"]
        )
        XCTAssertEqual(
            ThemePickerSearch.filteredThemes(themes, query: "git drk").map(\.name),
            ["github-dark"]
        )
    }

    func testInteractiveThemePickerViewportKeepsSelectedThemeVisible() {
        let viewport = ThemePickerViewport.make(itemCount: 28, selectedIndex: 17, terminalRows: 8)

        XCTAssertLessThanOrEqual(viewport.startIndex, 17)
        XCTAssertLessThan(17, viewport.endIndex)
        XCTAssertEqual(viewport.visibleCount, 6)
        XCTAssertEqual(viewport.endIndex - viewport.startIndex, 6)
    }

    func testInteractiveThemePickerViewportClampsNearEnd() {
        let viewport = ThemePickerViewport.make(itemCount: 28, selectedIndex: 27, terminalRows: 8)

        XCTAssertEqual(viewport.startIndex, 22)
        XCTAssertEqual(viewport.endIndex, 28)
        XCTAssertEqual(viewport.visibleCount, 6)
    }

    func testCLIInstallCommandCreatesSymlinkAndPrintsPathHintWhenNeeded() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let tempHome = tempRoot.appendingPathComponent("home", isDirectory: true)
        let binDirectory = tempHome
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        let executableURL = tempRoot.appendingPathComponent("OpenMUX.app/Contents/MacOS/omux", isDirectory: false)

        try FileManager.default.createDirectory(at: executableURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(),
            writeLine: { output.append($0) },
            readInputLine: { nil },
            configLoader: OmuxConfigLoader(),
            themeRegistry: OmuxThemeRegistry(),
            installer: OmuxCLIInstaller(
                environment: ["PATH": "/usr/bin:/bin"],
                executablePath: executableURL.path,
                homeDirectoryURL: tempHome,
                appBundleSearchURLs: []
            )
        )

        XCTAssertEqual(command.run(arguments: ["omux", "install-cli"]), 0)

        let installedURL = binDirectory.appendingPathComponent("omux", isDirectory: false)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: installedURL.path), executableURL.path)
        XCTAssertEqual(output[0], "Installed omux at \(installedURL.path) -> \(executableURL.path)")
        XCTAssertEqual(output[1], "Add this to your shell profile: export PATH=\"\(binDirectory.path):$PATH\"")
    }

    func testCLIInstallCommandSupportsExplicitDestination() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let installDirectory = tempRoot.appendingPathComponent("bin", isDirectory: true)
        let executableURL = tempRoot.appendingPathComponent("OpenMUX.app/Contents/MacOS/omux", isDirectory: false)

        try FileManager.default.createDirectory(at: executableURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let destinationURL = installDirectory.appendingPathComponent("omux", isDirectory: false)
        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(),
            writeLine: { output.append($0) },
            readInputLine: { nil },
            configLoader: OmuxConfigLoader(),
            themeRegistry: OmuxThemeRegistry(),
            installer: OmuxCLIInstaller(
                environment: ["PATH": "\(installDirectory.path):/usr/bin:/bin"],
                executablePath: executableURL.path,
                homeDirectoryURL: tempRoot,
                appBundleSearchURLs: []
            )
        )

        XCTAssertEqual(command.run(arguments: ["omux", "install-cli", destinationURL.path]), 0)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: destinationURL.path), executableURL.path)
        XCTAssertEqual(output, ["Installed omux at \(destinationURL.path) -> \(executableURL.path)"])
    }

    private func pickerTheme(name: String, displayName: String) -> OmuxTheme {
        OmuxTheme(schema: 1, name: name, displayName: displayName, tokens: [:])
    }

    private func makePluginRegistryFixture(targetPath: String = "plugin") throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let package = root.appendingPathComponent("plugins/hello", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try """
        schema = 1

        [packages.hello]
        kind = "plugin"
        name = "Hello Pane"
        description = "Creates a sample extension pane."
        version = "0.1.0"
        path = "plugins/hello/omux-plugin.toml"
        tags = ["demo"]
        """.write(to: root.appendingPathComponent("catalog.toml"), atomically: true, encoding: .utf8)
        try """
        schema = 1
        id = "hello"
        name = "Hello Pane"
        description = "Creates a sample extension pane."
        version = "0.1.0"
        license = "Apache-2.0"
        kind = "plugin"

        [plugin]
        command = "hello"
        entrypoint = "plugin"

        [files.plugin]
        source = "plugin"
        target = "\(targetPath)"
        executable = true
        """.write(to: package.appendingPathComponent("omux-plugin.toml"), atomically: true, encoding: .utf8)
        try "#!/bin/sh\nexit 0\n".write(to: package.appendingPathComponent("plugin"), atomically: true, encoding: .utf8)
        return root
    }

    private func makeHookRegistryFixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let package = root.appendingPathComponent("hooks/fail-notify", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try """
        schema = 1

        [packages.fail-notify]
        kind = "hook"
        name = "Notify on failure"
        description = "Notifies when a command fails."
        version = "0.1.0"
        path = "hooks/fail-notify/omux-hook.toml"
        """.write(to: root.appendingPathComponent("catalog.toml"), atomically: true, encoding: .utf8)
        try """
        schema = 1
        id = "fail-notify"
        name = "Notify on failure"
        description = "Notifies when a command fails."
        version = "0.1.0"
        license = "Apache-2.0"
        kind = "hook"

        [hook]
        name = "terminal-command-finished"
        category = "command"

        [files.handler]
        source = "20-notify"
        target = "20-notify"
        executable = true
        """.write(to: package.appendingPathComponent("omux-hook.toml"), atomically: true, encoding: .utf8)
        try "#!/bin/sh\nexit 0\n".write(to: package.appendingPathComponent("20-notify"), atomically: true, encoding: .utf8)
        return root
    }

    func testCLIInstallCommandPrefersInstalledAppCLIWhenLaunchedFromDevBuild() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let tempHome = tempRoot.appendingPathComponent("home", isDirectory: true)
        let binDirectory = tempHome
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        let devExecutableURL = tempRoot.appendingPathComponent(".build/debug/omux", isDirectory: false)
        let appURL = tempRoot.appendingPathComponent("Applications/OpenMUX.app", isDirectory: true)
        let appExecutableURL = appURL.appendingPathComponent("Contents/MacOS/omux", isDirectory: false)

        try FileManager.default.createDirectory(at: devExecutableURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: appExecutableURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: devExecutableURL, atomically: true, encoding: .utf8)
        try "#!/bin/sh\n".write(to: appExecutableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: devExecutableURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: appExecutableURL.path)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(),
            writeLine: { output.append($0) },
            readInputLine: { nil },
            configLoader: OmuxConfigLoader(),
            themeRegistry: OmuxThemeRegistry(),
            installer: OmuxCLIInstaller(
                environment: ["PATH": "/usr/bin:/bin"],
                executablePath: devExecutableURL.path,
                homeDirectoryURL: tempHome,
                appBundleSearchURLs: [appURL]
            )
        )

        XCTAssertEqual(command.run(arguments: ["omux", "install-cli"]), 0)

        let installedURL = binDirectory.appendingPathComponent("omux", isDirectory: false)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: installedURL.path), appExecutableURL.path)
        XCTAssertEqual(output[0], "Installed omux at \(installedURL.path) -> \(appExecutableURL.path)")
    }
}

private final class LockedValue<Value>: @unchecked Sendable {
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

private func JSONObject(at url: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: url)
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
}
