import Foundation

public struct GhosttyPinnedDependency: Equatable, Sendable {
    public let repositoryURL: URL
    public let vendorDirectory: URL
    public let pinnedReferenceFile: URL
    public let expectedReference: String
    public let buildScript: URL

    public init(
        repositoryURL: URL,
        vendorDirectory: URL,
        pinnedReferenceFile: URL,
        expectedReference: String,
        buildScript: URL
    ) {
        self.repositoryURL = repositoryURL
        self.vendorDirectory = vendorDirectory
        self.pinnedReferenceFile = pinnedReferenceFile
        self.expectedReference = expectedReference
        self.buildScript = buildScript
    }

    public static func foundationDefault(
        repositoryRoot: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) -> GhosttyPinnedDependency {
        let vendorDirectory = repositoryRoot.appending(path: "Vendor/ghostty")
        let pinnedReferenceFile = vendorDirectory.appending(path: "PINNED_REF")
        let buildScript = repositoryRoot.appending(path: "Scripts/build-ghostty.sh")

        return GhosttyPinnedDependency(
            repositoryURL: URL(string: "https://github.com/ghostty-org/ghostty.git")!,
            vendorDirectory: vendorDirectory,
            pinnedReferenceFile: pinnedReferenceFile,
            expectedReference: "ghostty-embed-snapshot-2026-04-30",
            buildScript: buildScript
        )
    }
}
