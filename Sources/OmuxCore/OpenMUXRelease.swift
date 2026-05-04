import Foundation

public struct OpenMUXReleaseAsset: Equatable, Sendable {
    public let name: String
    public let downloadURL: URL
    public let size: Int?

    public init(name: String, downloadURL: URL, size: Int? = nil) {
        self.name = name
        self.downloadURL = downloadURL
        self.size = size
    }
}

public struct OpenMUXRelease: Equatable, Sendable {
    public let tagName: String
    public let version: OpenMUXSemanticVersion
    public let assets: [OpenMUXReleaseAsset]
    public let isPrerelease: Bool

    public init(
        tagName: String,
        version: OpenMUXSemanticVersion,
        assets: [OpenMUXReleaseAsset],
        isPrerelease: Bool = false
    ) {
        self.tagName = tagName
        self.version = version
        self.assets = assets
        self.isPrerelease = isPrerelease
    }

    public var expectedAppArchiveName: String {
        "OpenMUX-\(version)-macos-unsigned.zip"
    }

    public var appArchiveAsset: OpenMUXReleaseAsset? {
        assets.first { $0.name == expectedAppArchiveName }
    }

    public var checksumAsset: OpenMUXReleaseAsset? {
        assets.first { $0.name == "checksums.txt" }
    }
}

public enum OpenMUXReleaseMetadataError: Error, LocalizedError, Equatable {
    case invalidJSON
    case missingTagName
    case invalidVersion(String)
    case missingAssets
    case invalidAsset(String)
    case missingRequiredAsset(String)

    public var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "release metadata is not valid JSON"
        case .missingTagName:
            return "release metadata is missing tag_name"
        case .invalidVersion(let value):
            return "release tag is not a semantic version: \(value)"
        case .missingAssets:
            return "release metadata is missing assets"
        case .invalidAsset(let name):
            return "release asset is missing a valid download URL: \(name)"
        case .missingRequiredAsset(let name):
            return "release is missing required asset: \(name)"
        }
    }
}

public enum OpenMUXReleaseMetadataParser {
    public static func parseLatestRelease(data: Data) throws -> OpenMUXRelease {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenMUXReleaseMetadataError.invalidJSON
        }
        guard let tagName = object["tag_name"] as? String else {
            throw OpenMUXReleaseMetadataError.missingTagName
        }
        guard let version = OpenMUXSemanticVersion(parsing: tagName) else {
            throw OpenMUXReleaseMetadataError.invalidVersion(tagName)
        }
        guard let rawAssets = object["assets"] as? [[String: Any]] else {
            throw OpenMUXReleaseMetadataError.missingAssets
        }

        let assets = try rawAssets.map { assetObject in
            let name = assetObject["name"] as? String ?? "(unnamed)"
            let rawURL = assetObject["browser_download_url"] as? String
                ?? assetObject["url"] as? String
            guard let rawURL, let url = URL(string: rawURL) else {
                throw OpenMUXReleaseMetadataError.invalidAsset(name)
            }
            return OpenMUXReleaseAsset(
                name: name,
                downloadURL: url,
                size: assetObject["size"] as? Int
            )
        }

        let release = OpenMUXRelease(
            tagName: tagName,
            version: version,
            assets: assets,
            isPrerelease: object["prerelease"] as? Bool ?? false
        )
        guard release.appArchiveAsset != nil else {
            throw OpenMUXReleaseMetadataError.missingRequiredAsset(release.expectedAppArchiveName)
        }
        guard release.checksumAsset != nil else {
            throw OpenMUXReleaseMetadataError.missingRequiredAsset("checksums.txt")
        }
        return release
    }
}

public struct OpenMUXGitHubReleaseClient: Sendable {
    public let endpoint: URL
    private let fetchData: @Sendable (URL) async throws -> Data

    public init(
        endpoint: URL = URL(string: "https://api.github.com/repos/finger-gun/omux/releases/latest")!,
        fetchData: @escaping @Sendable (URL) async throws -> Data = { url in
            let (data, _) = try await URLSession.shared.data(from: url)
            return data
        }
    ) {
        self.endpoint = endpoint
        self.fetchData = fetchData
    }

    public func latestRelease() async throws -> OpenMUXRelease {
        try OpenMUXReleaseMetadataParser.parseLatestRelease(data: try await fetchData(endpoint))
    }
}
