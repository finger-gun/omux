import Darwin
import Foundation

public struct OpenMUXSemanticVersion: Comparable, CustomStringConvertible, Equatable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(parsing rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let version = trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let major = Int(parts[0]),
              let minor = Int(parts[1]),
              let patch = Int(parts[2]),
              major >= 0,
              minor >= 0,
              patch >= 0
        else {
            return nil
        }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public var description: String {
        "\(major).\(minor).\(patch)"
    }

    public static func < (lhs: OpenMUXSemanticVersion, rhs: OpenMUXSemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

public struct OpenMUXVersionProvider {
    public enum VersionError: Error, LocalizedError {
        case unavailable

        public var errorDescription: String? {
            "unable to determine OpenMUX version"
        }
    }

    private let fileManager: FileManager
    private let bundle: Bundle
    private let executablePath: String?
    private let currentDirectoryPath: String

    public init(
        fileManager: FileManager = .default,
        bundle: Bundle = .main,
        executablePath: String? = nil,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath
    ) {
        self.fileManager = fileManager
        self.bundle = bundle
        self.executablePath = executablePath ?? Self.currentExecutablePath()
        self.currentDirectoryPath = currentDirectoryPath
    }

    public func currentVersion() throws -> String {
        if let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String,
           Self.isSemanticVersion(version) {
            return version
        }

        if let executablePath,
           let appBundleURL = Self.appBundleURL(containingExecutableAt: URL(fileURLWithPath: executablePath)) {
            let infoURL = appBundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Info.plist", isDirectory: false)
            if let version = Self.bundleShortVersion(at: infoURL),
               Self.isSemanticVersion(version) {
                return version
            }
        }

        let candidateDirectories = versionSearchDirectories()
        for directory in candidateDirectories {
            if let version = versionInAncestors(startingAt: directory) {
                return version
            }
        }

        throw VersionError.unavailable
    }

    public func currentAppBundleURL() -> URL? {
        guard let executablePath else {
            return nil
        }
        return Self.appBundleURL(containingExecutableAt: URL(fileURLWithPath: executablePath))
    }

    private func versionSearchDirectories() -> [URL] {
        var directories: [URL] = []
        if let executablePath {
            directories.append(URL(fileURLWithPath: executablePath).deletingLastPathComponent())
        }
        if let resourceURL = bundle.resourceURL {
            directories.append(resourceURL)
        }
        directories.append(URL(fileURLWithPath: currentDirectoryPath, isDirectory: true))
        return directories
    }

    private func versionInAncestors(startingAt startURL: URL) -> String? {
        var directory = startURL.standardizedFileURL
        var visited = Set<String>()
        while visited.insert(directory.path).inserted {
            let versionURL = directory.appendingPathComponent("VERSION", isDirectory: false)
            if let version = try? String(contentsOf: versionURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
               Self.isSemanticVersion(version) {
                return version
            }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path {
                break
            }
            directory = parent
        }
        return nil
    }

    public static func appBundleURL(containingExecutableAt executableURL: URL) -> URL? {
        let standardized = executableURL.standardizedFileURL
        var components = standardized.pathComponents
        guard let appIndex = components.lastIndex(where: { $0.hasSuffix(".app") }) else {
            return nil
        }
        components = Array(components.prefix(appIndex + 1))
        return URL(fileURLWithPath: NSString.path(withComponents: components), isDirectory: true)
    }

    private static func bundleShortVersion(at infoURL: URL) -> String? {
        guard let dictionary = NSDictionary(contentsOf: infoURL) as? [String: Any] else {
            return nil
        }
        return dictionary["CFBundleShortVersionString"] as? String
    }

    private static func isSemanticVersion(_ value: String) -> Bool {
        OpenMUXSemanticVersion(parsing: value) != nil
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
}
