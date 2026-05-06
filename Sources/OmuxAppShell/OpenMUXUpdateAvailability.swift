import Foundation
import OmuxCore

struct OpenMUXUpdateAvailability: Equatable {
    let version: String
}

@MainActor
final class OpenMUXUpdateAvailabilityChecker {
    private unowned let controller: WorkspaceController
    private let versionProvider: OpenMUXVersionProvider
    private let latestRelease: () async throws -> OpenMUXRelease

    init(
        controller: WorkspaceController,
        versionProvider: OpenMUXVersionProvider = OpenMUXVersionProvider(),
        latestRelease: @escaping () async throws -> OpenMUXRelease = {
            try await OpenMUXGitHubReleaseClient().latestRelease()
        }
    ) {
        self.controller = controller
        self.versionProvider = versionProvider
        self.latestRelease = latestRelease
    }

    func check() async {
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
