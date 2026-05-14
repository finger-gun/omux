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

final class OmuxSelfUpdater {
    enum UpdateError: Swift.Error, LocalizedError, Equatable {
        case invalidInstalledVersion(String)
        case latestReleaseUnavailable(String)
        case installFailed(OmuxAppReleaseInstaller.Error)

        var errorDescription: String? {
            switch self {
            case .invalidInstalledVersion(let version):
                return "installed OpenMUX version is not semantic: \(version)"
            case .latestReleaseUnavailable(let message):
                return "unable to fetch latest OpenMUX release: \(message)"
            case .installFailed(let error):
                return error.errorDescription
            }
        }
    }

    private let versionProvider: OpenMUXVersionProvider
    private let latestRelease: () throws -> OpenMUXRelease
    private let appManager: OmuxRunningApplicationManaging
    private let installer: OmuxAppReleaseInstaller
    private let writeLine: (String) -> Void
    private let readInputLine: () -> String?

    init(
        versionProvider: OpenMUXVersionProvider = OpenMUXVersionProvider(),
        latestRelease: @escaping () throws -> OpenMUXRelease = OmuxSelfUpdater.fetchLatestRelease,
        fileManager: FileManager = .default,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        temporaryDirectoryURL: URL = FileManager.default.temporaryDirectory,
        executablePath: String? = OmuxAppReleaseInstaller.currentExecutablePath(),
        appManager: OmuxRunningApplicationManaging = DefaultOmuxRunningApplicationManager(),
        download: @escaping (URL, URL, @escaping (OmuxDownloadProgress) -> Void) throws -> Void = OmuxAppReleaseInstaller.downloadFile,
        launchDetachedHelper: @escaping (URL, URL) throws -> Void = OmuxAppReleaseInstaller.launchDetachedHelper,
        openApplication: @escaping (URL) -> Bool = OmuxAppReleaseInstaller.openInstalledApplication,
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
        self.appManager = appManager
        self.installer = OmuxAppReleaseInstaller(
            fileManager: fileManager,
            homeDirectoryURL: homeDirectoryURL,
            temporaryDirectoryURL: temporaryDirectoryURL,
            executablePath: executablePath,
            appManager: appManager,
            download: download,
            launchDetachedHelper: launchDetachedHelper,
            openApplication: openApplication,
            now: now,
            sleep: sleep,
            relaunchTimeoutSeconds: relaunchTimeoutSeconds,
            relaunchStabilitySeconds: relaunchStabilitySeconds,
            writeProgress: writeProgress ?? writeLine,
            finishProgress: finishProgress ?? {}
        )
        self.writeLine = writeLine
        self.readInputLine = readInputLine
    }

    func runUpdate(allowReinstallLatest: Bool = false) throws -> OmuxSelfUpdateOutcome {
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

        let isReleaseNewer = release.version > installedVersion
        guard isReleaseNewer || allowReinstallLatest else {
            writeLine("OpenMUX \(installedVersion) is already up to date.")
            return OmuxSelfUpdateOutcome(state: .alreadyCurrent(installedVersion.description))
        }
        if isReleaseNewer == false {
            writeLine("Debug update: reinstalling OpenMUX \(release.version) over installed OpenMUX \(installedVersion).")
        }

        do {
            writeLine("Downloading OpenMUX \(release.version)...")
            let preparedInstall = try installer.prepareReleaseInstall(
                release: release,
                preferredTargetURL: versionProvider.currentAppBundleURL(),
                progressLabel: "OpenMUX \(release.version)"
            )
            do {
                if allowReinstallLatest {
                    let action = appManager.runningApplications(bundleIdentifier: OmuxAppReleaseInstaller.bundleIdentifier).isEmpty
                        ? "Install"
                        : "Close OpenMUX, install"
                    writeLine("\(action) OpenMUX \(release.version) to \(preparedInstall.targetAppURL.path) and relaunch? [y/N]")
                    let answer = readInputLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
                    guard answer == "y" || answer == "yes" else {
                        installer.discardPreparedInstall(preparedInstall)
                        writeLine("Debug update cancelled.")
                        return OmuxSelfUpdateOutcome(state: .cancelled)
                    }
                }

                if allowReinstallLatest == false &&
                    appManager.runningApplications(bundleIdentifier: OmuxAppReleaseInstaller.bundleIdentifier).isEmpty == false {
                    writeLine("Close OpenMUX to install \(release.version) to \(preparedInstall.targetAppURL.path)? [Y/n]")
                    let answer = readInputLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
                    if answer == "n" || answer == "no" {
                        installer.discardPreparedInstall(preparedInstall)
                        writeLine("Update cancelled.")
                        return OmuxSelfUpdateOutcome(state: .cancelled)
                    }
                }

                let handoff = try installer.handOffPreparedInstall(preparedInstall, reopenAfterInstall: true)
                writeLine("Installing OpenMUX \(release.version). Progress log: \(handoff.logPath)")
                return OmuxSelfUpdateOutcome(
                    state: .handedOff(
                        version: handoff.version,
                        logPath: handoff.logPath
                    )
                )
            } catch {
                installer.discardPreparedInstall(preparedInstall)
                throw error
            }
        } catch {
            if let installError = error as? OmuxAppReleaseInstaller.Error {
                throw UpdateError.installFailed(installError)
            }
            throw error
        }
    }

    func runHelper(manifestPath: String) -> Int32 {
        installer.runHelper(manifestPath: manifestPath)
    }

    func runHelper(manifest: OmuxUpdateManifest) throws {
        do {
            try installer.runHelper(manifest: manifest)
        } catch let installError as OmuxAppReleaseInstaller.Error {
            throw UpdateError.installFailed(installError)
        }
    }

    private static func fetchLatestRelease() throws -> OpenMUXRelease {
        let endpoint = URL(string: "https://api.github.com/repos/finger-gun/omux/releases/latest")!
        return try OpenMUXReleaseMetadataParser.parseLatestRelease(data: Data(contentsOf: endpoint))
    }
}
