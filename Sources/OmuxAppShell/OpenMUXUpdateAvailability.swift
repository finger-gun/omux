import Foundation
import OmuxCore

struct OpenMUXUpdateAvailability: Equatable {
    let version: String
}

@MainActor
final class OpenMUXUpdateAvailabilityChecker {
    private static let lastCheckKey = "OpenMUXUpdateAvailabilityChecker.lastCheck"
    private static let lastCheckedInstalledVersionKey = "OpenMUXUpdateAvailabilityChecker.lastCheckedInstalledVersion"

    private unowned let controller: WorkspaceController
    private let versionProvider: OpenMUXVersionProvider
    private let latestRelease: () async throws -> OpenMUXRelease
    private let defaults: UserDefaults
    private let now: () -> Date
    private let interval: TimeInterval

    init(
        controller: WorkspaceController,
        versionProvider: OpenMUXVersionProvider = OpenMUXVersionProvider(),
        latestRelease: @escaping () async throws -> OpenMUXRelease = {
            try await OpenMUXGitHubReleaseClient().latestRelease()
        },
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        interval: TimeInterval = 24 * 60 * 60
    ) {
        self.controller = controller
        self.versionProvider = versionProvider
        self.latestRelease = latestRelease
        self.defaults = defaults
        self.now = now
        self.interval = interval
    }

    func checkIfDue() async {
        let currentTime = now()

        do {
            let installedVersionString = try versionProvider.currentVersion()
            guard let installedVersion = OpenMUXSemanticVersion(parsing: installedVersionString) else {
                return
            }
            if let lastCheck = defaults.object(forKey: Self.lastCheckKey) as? Date,
               defaults.string(forKey: Self.lastCheckedInstalledVersionKey) == installedVersion.description,
               currentTime.timeIntervalSince(lastCheck) < interval {
                return
            }

            let release = try await latestRelease()
            defaults.set(currentTime, forKey: Self.lastCheckKey)
            defaults.set(installedVersion.description, forKey: Self.lastCheckedInstalledVersionKey)
            guard release.version > installedVersion else {
                controller.setUpdateAvailability(nil)
                return
            }
            controller.setUpdateAvailability(OpenMUXUpdateAvailability(version: release.version.description))
        } catch {
            return
        }
    }
}
