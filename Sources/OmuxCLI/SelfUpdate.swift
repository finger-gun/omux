import AppKit
import CryptoKit
import Foundation
import OmuxCore

struct OmuxSelfUpdateOutcome: Equatable {
    enum State: Equatable {
        case alreadyCurrent(String)
        case handedOff(version: String, logPath: String)
        case cancelled
    }

    let state: State
}

protocol OmuxRunningApplicationManaging {
    func runningApplications(bundleIdentifier: String) -> [OmuxRunningApplication]
    func terminate(bundleIdentifier: String)
}

struct OmuxRunningApplication: Equatable {
    let processIdentifier: pid_t
}

struct DefaultOmuxRunningApplicationManager: OmuxRunningApplicationManaging {
    func runningApplications(bundleIdentifier: String) -> [OmuxRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .map { OmuxRunningApplication(processIdentifier: $0.processIdentifier) }
    }

    func terminate(bundleIdentifier: String) {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier) {
            app.terminate()
        }
    }
}

struct OmuxUpdateManifest: Codable, Equatable {
    let stagedAppPath: String
    let targetAppPath: String
    let backupAppPath: String
    let logPath: String
    let stagingRootPath: String
    let bundleIdentifier: String
    let version: String
    let reopenAfterInstall: Bool
    let terminationTimeoutSeconds: TimeInterval
}

final class OmuxSelfUpdater {
    enum UpdateError: Error, LocalizedError, Equatable {
        case invalidInstalledVersion(String)
        case latestReleaseUnavailable(String)
        case missingReleaseAsset(String)
        case checksumMissing(String)
        case checksumMismatch(expected: String, actual: String)
        case invalidStagedBundle(String)
        case noWritableInstallTarget
        case missingExecutablePath
        case helperLaunchFailed(String)
        case helperTimedOut

        var errorDescription: String? {
            switch self {
            case .invalidInstalledVersion(let version):
                return "installed OpenMUX version is not semantic: \(version)"
            case .latestReleaseUnavailable(let message):
                return "unable to fetch latest OpenMUX release: \(message)"
            case .missingReleaseAsset(let name):
                return "latest release is missing required asset: \(name)"
            case .checksumMissing(let name):
                return "checksums.txt does not contain an entry for \(name)"
            case .checksumMismatch(let expected, let actual):
                return "checksum mismatch for app archive: expected \(expected), got \(actual)"
            case .invalidStagedBundle(let message):
                return "downloaded app archive is invalid: \(message)"
            case .noWritableInstallTarget:
                return "no writable OpenMUX.app install target found"
            case .missingExecutablePath:
                return "unable to determine current omux executable path"
            case .helperLaunchFailed(let message):
                return "failed to start update helper: \(message)"
            case .helperTimedOut:
                return "OpenMUX did not quit before the update timeout"
            }
        }
    }

    private let versionProvider: OpenMUXVersionProvider
    private let latestRelease: () throws -> OpenMUXRelease
    private let fileManager: FileManager
    private let homeDirectoryURL: URL
    private let temporaryDirectoryURL: URL
    private let executablePath: String?
    private let appManager: OmuxRunningApplicationManaging
    private let download: (URL, URL) throws -> Void
    private let launchDetachedHelper: (URL, URL) throws -> Void
    private let writeLine: (String) -> Void
    private let readInputLine: () -> String?

    init(
        versionProvider: OpenMUXVersionProvider = OpenMUXVersionProvider(),
        latestRelease: @escaping () throws -> OpenMUXRelease = OmuxSelfUpdater.fetchLatestRelease,
        fileManager: FileManager = .default,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        temporaryDirectoryURL: URL = FileManager.default.temporaryDirectory,
        executablePath: String? = OmuxSelfUpdater.currentExecutablePath(),
        appManager: OmuxRunningApplicationManaging = DefaultOmuxRunningApplicationManager(),
        download: @escaping (URL, URL) throws -> Void = OmuxSelfUpdater.download,
        launchDetachedHelper: @escaping (URL, URL) throws -> Void = OmuxSelfUpdater.launchDetachedHelper,
        writeLine: @escaping (String) -> Void,
        readInputLine: @escaping () -> String?
    ) {
        self.versionProvider = versionProvider
        self.latestRelease = latestRelease
        self.fileManager = fileManager
        self.homeDirectoryURL = homeDirectoryURL
        self.temporaryDirectoryURL = temporaryDirectoryURL
        self.executablePath = executablePath
        self.appManager = appManager
        self.download = download
        self.launchDetachedHelper = launchDetachedHelper
        self.writeLine = writeLine
        self.readInputLine = readInputLine
    }

    func runUpdate() throws -> OmuxSelfUpdateOutcome {
        let installedVersionString = try versionProvider.currentVersion()
        guard let installedVersion = OpenMUXSemanticVersion(parsing: installedVersionString) else {
            throw UpdateError.invalidInstalledVersion(installedVersionString)
        }

        let release: OpenMUXRelease
        do {
            release = try latestRelease()
        } catch {
            throw UpdateError.latestReleaseUnavailable(error.localizedDescription)
        }

        guard release.version > installedVersion else {
            writeLine("OpenMUX \(installedVersion) is already up to date.")
            return OmuxSelfUpdateOutcome(state: .alreadyCurrent(installedVersion.description))
        }

        guard let appAsset = release.appArchiveAsset else {
            throw UpdateError.missingReleaseAsset(release.expectedAppArchiveName)
        }
        guard let checksumAsset = release.checksumAsset else {
            throw UpdateError.missingReleaseAsset("checksums.txt")
        }

        let stagingRoot = temporaryDirectoryURL
            .appendingPathComponent("openmux-update-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        let downloadsURL = stagingRoot.appendingPathComponent("downloads", isDirectory: true)
        let unpackURL = stagingRoot.appendingPathComponent("unpacked", isDirectory: true)
        try fileManager.createDirectory(at: downloadsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: unpackURL, withIntermediateDirectories: true)

        do {
            let archiveURL = downloadsURL.appendingPathComponent(appAsset.name, isDirectory: false)
            let checksumURL = downloadsURL.appendingPathComponent(checksumAsset.name, isDirectory: false)
            writeLine("Downloading OpenMUX \(release.version)...")
            try download(appAsset.downloadURL, archiveURL)
            try download(checksumAsset.downloadURL, checksumURL)
            try verifyChecksum(archiveURL: archiveURL, checksumURL: checksumURL)

            try unarchiveApp(archiveURL: archiveURL, destinationURL: unpackURL)
            let stagedAppURL = unpackURL.appendingPathComponent("OpenMUX.app", isDirectory: true)
            try validateBundle(at: stagedAppURL, version: release.version.description)
            let targetURL = try selectInstallTarget()
            let manifestURL = try prepareHelperManifest(
                stagingRoot: stagingRoot,
                stagedAppURL: stagedAppURL,
                targetURL: targetURL,
                version: release.version.description
            )

            if appManager.runningApplications(bundleIdentifier: Self.bundleIdentifier).isEmpty == false {
                writeLine("Close OpenMUX to install \(release.version) to \(targetURL.path)? [Y/n]")
                let answer = readInputLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
                if answer == "n" || answer == "no" {
                    try? fileManager.removeItem(at: stagingRoot)
                    writeLine("Update cancelled.")
                    return OmuxSelfUpdateOutcome(state: .cancelled)
                }
            }

            let helperURL = try copyHelperExecutable(to: stagingRoot)
            try launchDetachedHelper(helperURL, manifestURL)
            writeLine("Installing OpenMUX \(release.version). Progress log: \(manifestURL.deletingLastPathComponent().appendingPathComponent("update.log").path)")
            return OmuxSelfUpdateOutcome(
                state: .handedOff(
                    version: release.version.description,
                    logPath: manifestURL.deletingLastPathComponent().appendingPathComponent("update.log").path
                )
            )
        } catch {
            try? fileManager.removeItem(at: stagingRoot)
            throw error
        }
    }

    func runHelper(manifestPath: String) -> Int32 {
        do {
            let manifestURL = URL(fileURLWithPath: manifestPath)
            let data = try Data(contentsOf: manifestURL)
            let manifest = try JSONDecoder().decode(OmuxUpdateManifest.self, from: data)
            try runHelper(manifest: manifest)
            return 0
        } catch {
            return 1
        }
    }

    func runHelper(manifest: OmuxUpdateManifest) throws {
        let logURL = URL(fileURLWithPath: manifest.logPath)
        let logger = HelperLogger(logURL: logURL)
        logger.write("Starting OpenMUX update to \(manifest.version)")

        appManager.terminate(bundleIdentifier: manifest.bundleIdentifier)
        let deadline = Date().addingTimeInterval(manifest.terminationTimeoutSeconds)
        while Date() < deadline {
            if appManager.runningApplications(bundleIdentifier: manifest.bundleIdentifier).isEmpty {
                break
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        guard appManager.runningApplications(bundleIdentifier: manifest.bundleIdentifier).isEmpty else {
            logger.write("OpenMUX did not quit before timeout")
            throw UpdateError.helperTimedOut
        }

        let stagedAppURL = URL(fileURLWithPath: manifest.stagedAppPath, isDirectory: true)
        let targetAppURL = URL(fileURLWithPath: manifest.targetAppPath, isDirectory: true)
        let backupAppURL = URL(fileURLWithPath: manifest.backupAppPath, isDirectory: true)
        do {
            if fileManager.fileExists(atPath: backupAppURL.path) {
                try fileManager.removeItem(at: backupAppURL)
            }
            if fileManager.fileExists(atPath: targetAppURL.path) {
                try fileManager.moveItem(at: targetAppURL, to: backupAppURL)
            }
            try fileManager.moveItem(at: stagedAppURL, to: targetAppURL)
            try validateBundle(at: targetAppURL, version: manifest.version)
            if fileManager.fileExists(atPath: backupAppURL.path) {
                try fileManager.removeItem(at: backupAppURL)
            }
            logger.write("Installed \(targetAppURL.path)")
            if manifest.reopenAfterInstall {
                NSWorkspace.shared.open(targetAppURL)
            }
            try? fileManager.removeItem(at: URL(fileURLWithPath: manifest.stagingRootPath, isDirectory: true))
        } catch {
            logger.write("Install failed: \(error.localizedDescription)")
            if fileManager.fileExists(atPath: targetAppURL.path) {
                try? fileManager.removeItem(at: targetAppURL)
            }
            if fileManager.fileExists(atPath: backupAppURL.path) {
                try? fileManager.moveItem(at: backupAppURL, to: targetAppURL)
            }
            throw error
        }
    }

    private static func fetchLatestRelease() throws -> OpenMUXRelease {
        let endpoint = URL(string: "https://api.github.com/repos/finger-gun/omux/releases/latest")!
        return try OpenMUXReleaseMetadataParser.parseLatestRelease(data: Data(contentsOf: endpoint))
    }

    private func verifyChecksum(archiveURL: URL, checksumURL: URL) throws {
        let checksums = try String(contentsOf: checksumURL, encoding: .utf8)
        let expected = checksumValue(for: archiveURL.lastPathComponent, in: checksums)
        guard let expected else {
            throw UpdateError.checksumMissing(archiveURL.lastPathComponent)
        }
        let actual = try sha256HexDigest(fileURL: archiveURL)
        guard expected.lowercased() == actual.lowercased() else {
            throw UpdateError.checksumMismatch(expected: expected, actual: actual)
        }
    }

    private func checksumValue(for fileName: String, in checksums: String) -> String? {
        for line in checksums.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count >= 2, parts.last == fileName else {
                continue
            }
            return parts[0]
        }
        return nil
    }

    private func sha256HexDigest(fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func unarchiveApp(archiveURL: URL, destinationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archiveURL.path, destinationURL.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.invalidStagedBundle("ditto failed to unarchive \(archiveURL.lastPathComponent)")
        }
    }

    private func validateBundle(at appURL: URL, version: String) throws {
        let infoURL = appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Info.plist", isDirectory: false)
        guard let info = NSDictionary(contentsOf: infoURL) as? [String: Any] else {
            throw UpdateError.invalidStagedBundle("missing Info.plist")
        }
        guard info["CFBundleIdentifier"] as? String == Self.bundleIdentifier else {
            throw UpdateError.invalidStagedBundle("unexpected bundle identifier")
        }
        guard info["CFBundleShortVersionString"] as? String == version else {
            throw UpdateError.invalidStagedBundle("unexpected bundle version")
        }
    }

    private func selectInstallTarget() throws -> URL {
        if let current = versionProvider.currentAppBundleURL(),
           isWritableAppTarget(current) {
            return current
        }

        let systemTarget = URL(fileURLWithPath: "/Applications/OpenMUX.app", isDirectory: true)
        if isWritableAppTarget(systemTarget) {
            return systemTarget
        }

        let userApplications = homeDirectoryURL.appendingPathComponent("Applications", isDirectory: true)
        try? fileManager.createDirectory(at: userApplications, withIntermediateDirectories: true)
        let userTarget = userApplications.appendingPathComponent("OpenMUX.app", isDirectory: true)
        if isWritableAppTarget(userTarget) {
            return userTarget
        }

        throw UpdateError.noWritableInstallTarget
    }

    private func isWritableAppTarget(_ targetURL: URL) -> Bool {
        let parentURL = targetURL.deletingLastPathComponent()
        return fileManager.fileExists(atPath: parentURL.path)
            && fileManager.isWritableFile(atPath: parentURL.path)
    }

    private func prepareHelperManifest(
        stagingRoot: URL,
        stagedAppURL: URL,
        targetURL: URL,
        version: String
    ) throws -> URL {
        let helperStateURL = stagingRoot.appendingPathComponent("helper", isDirectory: true)
        try fileManager.createDirectory(at: helperStateURL, withIntermediateDirectories: true)
        let manifest = OmuxUpdateManifest(
            stagedAppPath: stagedAppURL.path,
            targetAppPath: targetURL.path,
            backupAppPath: helperStateURL.appendingPathComponent("OpenMUX.app.backup", isDirectory: true).path,
            logPath: helperStateURL.appendingPathComponent("update.log", isDirectory: false).path,
            stagingRootPath: stagingRoot.path,
            bundleIdentifier: Self.bundleIdentifier,
            version: version,
            reopenAfterInstall: true,
            terminationTimeoutSeconds: 30
        )
        let manifestURL = helperStateURL.appendingPathComponent("manifest.json", isDirectory: false)
        try JSONEncoder().encode(manifest).write(to: manifestURL, options: .atomic)
        return manifestURL
    }

    private func copyHelperExecutable(to stagingRoot: URL) throws -> URL {
        guard let executablePath else {
            throw UpdateError.missingExecutablePath
        }
        let helperURL = stagingRoot.appendingPathComponent("omux-update-helper", isDirectory: false)
        if fileManager.fileExists(atPath: helperURL.path) {
            try fileManager.removeItem(at: helperURL)
        }
        try fileManager.copyItem(at: URL(fileURLWithPath: executablePath), to: helperURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperURL.path)
        return helperURL
    }

    private static func download(from url: URL, to destinationURL: URL) throws {
        let data = try Data(contentsOf: url)
        try data.write(to: destinationURL, options: .atomic)
    }

    private static func launchDetachedHelper(helperURL: URL, manifestURL: URL) throws {
        let command = "nohup \(shellQuote(helperURL.path)) __update-helper \(shellQuote(manifestURL.path)) >/dev/null 2>&1 &"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.helperLaunchFailed("nohup exited with status \(process.terminationStatus)")
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func currentExecutablePath() -> String? {
        var size: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &size)

        var buffer = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&buffer, &size) == 0 else {
            return nil
        }

        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return URL(fileURLWithPath: String(decoding: bytes, as: UTF8.self)).resolvingSymlinksInPath().path
    }

    static let bundleIdentifier = "dev.fingergun.omux"
}

private final class HelperLogger {
    private let logURL: URL
    private let lock = NSLock()

    init(logURL: URL) {
        self.logURL = logURL
    }

    func write(_ message: String) {
        lock.lock()
        defer { lock.unlock() }

        let line = "[\(Date())] \(message)\n"
        if FileManager.default.fileExists(atPath: logURL.path),
           let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        } else {
            try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? line.write(to: logURL, atomically: true, encoding: .utf8)
        }
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
