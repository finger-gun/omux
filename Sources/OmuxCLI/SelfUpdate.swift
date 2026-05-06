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

struct OmuxDownloadProgress: Equatable {
    let bytesDownloaded: Int64
    let totalBytes: Int64?
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
        case appRelaunchFailed(String)
        case downloadFailed(String)

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
            case .appRelaunchFailed(let message):
                return "installed OpenMUX did not relaunch successfully: \(message)"
            case .downloadFailed(let message):
                return "download failed: \(message)"
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
    private let download: (URL, URL, @escaping (OmuxDownloadProgress) -> Void) throws -> Void
    private let launchDetachedHelper: (URL, URL) throws -> Void
    private let openApplication: (URL) -> Bool
    private let now: () -> Date
    private let sleep: (TimeInterval) -> Void
    private let relaunchTimeoutSeconds: TimeInterval
    private let relaunchStabilitySeconds: TimeInterval
    private let writeProgress: (String) -> Void
    private let finishProgress: () -> Void
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
        download: @escaping (URL, URL, @escaping (OmuxDownloadProgress) -> Void) throws -> Void = OmuxSelfUpdater.downloadFile,
        launchDetachedHelper: @escaping (URL, URL) throws -> Void = OmuxSelfUpdater.launchDetachedHelper,
        openApplication: @escaping (URL) -> Bool = OmuxSelfUpdater.openInstalledApplication,
        now: @escaping () -> Date = Date.init,
        sleep: @escaping (TimeInterval) -> Void = Thread.sleep(forTimeInterval:),
        relaunchTimeoutSeconds: TimeInterval = 10,
        relaunchStabilitySeconds: TimeInterval = 2,
        writeProgress: ((String) -> Void)? = nil,
        finishProgress: (() -> Void)? = nil,
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
        self.openApplication = openApplication
        self.now = now
        self.sleep = sleep
        self.relaunchTimeoutSeconds = relaunchTimeoutSeconds
        self.relaunchStabilitySeconds = relaunchStabilitySeconds
        self.writeProgress = writeProgress ?? writeLine
        self.finishProgress = finishProgress ?? {}
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
            let progressReporter = OmuxDownloadProgressReporter(
                label: "OpenMUX \(release.version)",
                writeProgress: writeProgress,
                finishProgress: finishProgress
            )
            try download(appAsset.downloadURL, archiveURL) { progress in
                progressReporter.report(progress)
            }
            progressReporter.finish()
            try download(checksumAsset.downloadURL, checksumURL) { _ in }
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
        let deadline = now().addingTimeInterval(manifest.terminationTimeoutSeconds)
        while now() < deadline {
            if appManager.runningApplications(bundleIdentifier: manifest.bundleIdentifier).isEmpty {
                break
            }
            sleep(0.25)
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
            logger.write("Installed \(targetAppURL.path)")
            if manifest.reopenAfterInstall {
                try reopenInstalledApp(
                    at: targetAppURL,
                    bundleIdentifier: manifest.bundleIdentifier,
                    logger: logger
                )
            }
            if fileManager.fileExists(atPath: backupAppURL.path) {
                try fileManager.removeItem(at: backupAppURL)
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

    private func reopenInstalledApp(
        at targetAppURL: URL,
        bundleIdentifier: String,
        logger: HelperLogger
    ) throws {
        logger.write("Relaunching \(targetAppURL.path)")
        guard openApplication(targetAppURL) else {
            logger.write("Relaunch request was rejected")
            throw UpdateError.appRelaunchFailed("Launch Services rejected \(targetAppURL.path)")
        }

        let launchDeadline = now().addingTimeInterval(relaunchTimeoutSeconds)
        while now() < launchDeadline {
            if appManager.runningApplications(bundleIdentifier: bundleIdentifier).isEmpty == false {
                break
            }
            sleep(0.25)
        }

        guard appManager.runningApplications(bundleIdentifier: bundleIdentifier).isEmpty == false else {
            logger.write("Relaunch did not produce a running OpenMUX app")
            throw UpdateError.appRelaunchFailed("OpenMUX did not appear after relaunch")
        }

        if relaunchStabilitySeconds > 0 {
            sleep(relaunchStabilitySeconds)
        }

        guard appManager.runningApplications(bundleIdentifier: bundleIdentifier).isEmpty == false else {
            logger.write("Relaunched OpenMUX exited before stability check completed")
            throw UpdateError.appRelaunchFailed("OpenMUX exited immediately after relaunch")
        }

        logger.write("Relaunched OpenMUX successfully")
    }

    private static func openInstalledApplication(at appURL: URL) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        let result = LockedBox(false)
        NSWorkspace.shared.openApplication(
            at: appURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { runningApplication, error in
            result.value = runningApplication != nil && error == nil
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 10)
        return result.value
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
        let executableURL = URL(fileURLWithPath: executablePath).standardizedFileURL
        let helperURL = stagingRoot.appendingPathComponent("omux-update-helper", isDirectory: false)
        if fileManager.fileExists(atPath: helperURL.path) {
            try fileManager.removeItem(at: helperURL)
        }
        try fileManager.copyItem(at: executableURL, to: helperURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperURL.path)
        try copyResourceBundlesForHelper(fromExecutableAt: executableURL, to: stagingRoot)
        return helperURL
    }

    private func copyResourceBundlesForHelper(fromExecutableAt executableURL: URL, to stagingRoot: URL) throws {
        let executableDirectoryURL = executableURL.deletingLastPathComponent()
        var candidateDirectories = [executableDirectoryURL]
        if executableDirectoryURL.lastPathComponent == "MacOS",
           executableDirectoryURL.deletingLastPathComponent().lastPathComponent == "Contents" {
            candidateDirectories.append(
                executableDirectoryURL
                    .deletingLastPathComponent()
                    .appendingPathComponent("Resources", isDirectory: true)
            )
        }

        var copiedBundleNames = Set<String>()
        for directoryURL in candidateDirectories {
            guard let bundleURLs = try? fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for bundleURL in bundleURLs where bundleURL.pathExtension == "bundle" {
                guard copiedBundleNames.insert(bundleURL.lastPathComponent).inserted else {
                    continue
                }
                let destinationURL = stagingRoot.appendingPathComponent(bundleURL.lastPathComponent, isDirectory: true)
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.copyItem(at: bundleURL, to: destinationURL)
            }
        }
    }

    private static func downloadFile(
        from url: URL,
        to destinationURL: URL,
        progress: @escaping (OmuxDownloadProgress) -> Void
    ) throws {
        let temporaryURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(destinationURL.lastPathComponent).\(UUID().uuidString).download", isDirectory: false)
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: temporaryURL.path) {
            try FileManager.default.removeItem(at: temporaryURL)
        }
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        do {
            if url.isFileURL {
                try copyLocalFile(from: url, to: temporaryURL, progress: progress)
            } else {
                try downloadRemoteFile(from: url, to: temporaryURL, progress: progress)
            }
            try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }

    private static func copyLocalFile(
        from sourceURL: URL,
        to destinationURL: URL,
        progress: (OmuxDownloadProgress) -> Void
    ) throws {
        let totalBytes = try sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init)
        _ = FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
        let input = try FileHandle(forReadingFrom: sourceURL)
        let output = try FileHandle(forWritingTo: destinationURL)
        defer {
            try? input.close()
            try? output.close()
        }

        var bytesDownloaded: Int64 = 0
        while let data = try input.read(upToCount: 64 * 1024), data.isEmpty == false {
            try output.write(contentsOf: data)
            bytesDownloaded += Int64(data.count)
            progress(OmuxDownloadProgress(bytesDownloaded: bytesDownloaded, totalBytes: totalBytes))
        }

        if bytesDownloaded == 0 {
            progress(OmuxDownloadProgress(bytesDownloaded: 0, totalBytes: totalBytes))
        }
    }

    private static func downloadRemoteFile(
        from sourceURL: URL,
        to destinationURL: URL,
        progress: @escaping (OmuxDownloadProgress) -> Void
    ) throws {
        let delegate = try OmuxURLSessionDownloadDelegate(destinationURL: destinationURL, progress: progress)
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: queue)
        let task = session.dataTask(with: sourceURL)
        task.resume()
        delegate.waitUntilComplete()
        session.finishTasksAndInvalidate()
        try delegate.getResult()
    }

    private static func launchDetachedHelper(helperURL: URL, manifestURL: URL) throws {
        let bootstrapLogURL = manifestURL.deletingLastPathComponent().appendingPathComponent("update.log", isDirectory: false)
        let command = "nohup \(shellQuote(helperURL.path)) __update-helper \(shellQuote(manifestURL.path)) >>\(shellQuote(bootstrapLogURL.path)) 2>&1 &"
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

private final class OmuxDownloadProgressReporter {
    private static let progressBarWidth = 20
    private static let unknownTotalStepBytes: Int64 = 5 * 1024 * 1024

    private let label: String
    private let writeProgress: (String) -> Void
    private let finishProgress: () -> Void
    private var lastProgress: OmuxDownloadProgress?
    private var lastRenderedBytes: Int64?
    private var lastRenderedTotalBytes: Int64?
    private var lastPercentBucket: Int?
    private var lastUnknownBucket: Int64?
    private var didRender = false

    init(
        label: String,
        writeProgress: @escaping (String) -> Void,
        finishProgress: @escaping () -> Void
    ) {
        self.label = label
        self.writeProgress = writeProgress
        self.finishProgress = finishProgress
    }

    func report(_ progress: OmuxDownloadProgress) {
        lastProgress = progress
        guard shouldRender(progress) else {
            return
        }
        render(progress)
    }

    func finish() {
        if let lastProgress,
           lastRenderedBytes != lastProgress.bytesDownloaded
            || lastRenderedTotalBytes != lastProgress.totalBytes {
            render(lastProgress)
        }
        if didRender {
            finishProgress()
        }
    }

    private func shouldRender(_ progress: OmuxDownloadProgress) -> Bool {
        guard let totalBytes = progress.totalBytes, totalBytes > 0 else {
            let bucket = progress.bytesDownloaded / Self.unknownTotalStepBytes
            if bucket != lastUnknownBucket || progress.bytesDownloaded == 0 {
                lastUnknownBucket = bucket
                return true
            }
            return false
        }

        let percent = Self.percentage(downloaded: progress.bytesDownloaded, total: totalBytes)
        let bucket = percent / 5
        if bucket != lastPercentBucket || progress.bytesDownloaded >= totalBytes {
            lastPercentBucket = bucket
            return true
        }
        return false
    }

    private func render(_ progress: OmuxDownloadProgress) {
        lastRenderedBytes = progress.bytesDownloaded
        lastRenderedTotalBytes = progress.totalBytes
        didRender = true
        writeProgress(Self.renderedLine(label: label, progress: progress))
    }

    private static func renderedLine(label: String, progress: OmuxDownloadProgress) -> String {
        guard let totalBytes = progress.totalBytes, totalBytes > 0 else {
            return "\(label) \(formatByteCount(progress.bytesDownloaded)) downloaded"
        }

        let percent = percentage(downloaded: progress.bytesDownloaded, total: totalBytes)
        let bar = progressBar(downloaded: progress.bytesDownloaded, total: totalBytes)
        return "\(label) [\(bar)] \(percent)% \(formatByteCount(progress.bytesDownloaded)) / \(formatByteCount(totalBytes))"
    }

    private static func progressBar(downloaded: Int64, total: Int64) -> String {
        let clampedFraction = min(max(Double(downloaded) / Double(total), 0), 1)
        var filledWidth = Int((clampedFraction * Double(progressBarWidth)).rounded(.down))
        if downloaded >= total {
            filledWidth = progressBarWidth
        }
        return String(repeating: "#", count: filledWidth)
            + String(repeating: "-", count: progressBarWidth - filledWidth)
    }

    private static func percentage(downloaded: Int64, total: Int64) -> Int {
        let clampedFraction = min(max(Double(downloaded) / Double(total), 0), 1)
        return Int((clampedFraction * 100).rounded(.down))
    }

    private static func formatByteCount(_ bytes: Int64) -> String {
        guard bytes >= 1024 else {
            return "\(bytes) B"
        }

        let units = ["KB", "MB", "GB", "TB"]
        var value = Double(bytes) / 1024
        var unitIndex = 0
        while value >= 1024, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        return "\(String(format: "%.1f", value)) \(units[unitIndex])"
    }
}

private final class OmuxURLSessionDownloadDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private let fileHandle: FileHandle
    private let progress: (OmuxDownloadProgress) -> Void
    private var bytesDownloaded: Int64 = 0
    private var totalBytes: Int64?
    private var result: Result<Void, Error>?

    init(destinationURL: URL, progress: @escaping (OmuxDownloadProgress) -> Void) throws {
        self.progress = progress
        _ = FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
        self.fileHandle = try FileHandle(forWritingTo: destinationURL)
        super.init()
    }

    func waitUntilComplete() {
        semaphore.wait()
    }

    func getResult() throws {
        switch lockedResult() {
        case .success:
            return
        case .failure(let error):
            throw error
        case nil:
            throw OmuxSelfUpdater.UpdateError.downloadFailed("download did not complete")
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let httpResponse = response as? HTTPURLResponse,
           (200..<300).contains(httpResponse.statusCode) == false {
            setResult(.failure(OmuxSelfUpdater.UpdateError.downloadFailed("HTTP \(httpResponse.statusCode)")))
            completionHandler(.cancel)
            return
        }

        if response.expectedContentLength > 0 {
            totalBytes = response.expectedContentLength
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            try fileHandle.write(contentsOf: data)
            bytesDownloaded += Int64(data.count)
            progress(OmuxDownloadProgress(bytesDownloaded: bytesDownloaded, totalBytes: totalBytes))
        } catch {
            setResult(.failure(error))
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? fileHandle.close()
        if let error {
            setResult(.failure(error))
        } else if lockedResult() == nil {
            setResult(.success(()))
        }
        semaphore.signal()
    }

    private func setResult(_ newResult: Result<Void, Error>) {
        lock.lock()
        if result == nil {
            result = newResult
        }
        lock.unlock()
    }

    private func lockedResult() -> Result<Void, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return result
    }
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
