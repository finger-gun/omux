import Foundation
import OmuxCore

struct OpenMUXUpdateAvailability: Equatable {
    let version: String
}

@MainActor
final class OpenMUXUpdateAvailabilityChecker {
    private static let lastCheckKey = "OpenMUXUpdateAvailabilityChecker.lastCheck"

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
        if let lastCheck = defaults.object(forKey: Self.lastCheckKey) as? Date,
           currentTime.timeIntervalSince(lastCheck) < interval {
            return
        }
        defaults.set(currentTime, forKey: Self.lastCheckKey)

        do {
            let installedVersionString = try versionProvider.currentVersion()
            guard let installedVersion = OpenMUXSemanticVersion(parsing: installedVersionString) else {
                return
            }
            let release = try await latestRelease()
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
