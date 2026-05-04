import Darwin
import Foundation

public struct OmuxCLIInstaller {
    public struct Result {
        public let installedPath: String
        public let sourcePath: String
        public let pathHintDirectory: String?

        public init(installedPath: String, sourcePath: String, pathHintDirectory: String?) {
            self.installedPath = installedPath
            self.sourcePath = sourcePath
            self.pathHintDirectory = pathHintDirectory
        }
    }

    enum InstallerError: Error, LocalizedError {
        case missingExecutablePath
        case executableNotFound(String)

        var errorDescription: String? {
            switch self {
            case .missingExecutablePath:
                return "unable to determine the omux executable path"
            case .executableNotFound(let path):
                return "omux executable is not available at \(path)"
            }
        }
    }

    private let fileManager: FileManager
    private let environment: [String: String]
    private let executablePath: String?
    private let homeDirectoryURL: URL
    private let appBundleSearchURLs: [URL]

    public init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        executablePath: String? = nil,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        appBundleSearchURLs: [URL]? = nil
    ) {
        self.fileManager = fileManager
        self.environment = environment
        self.executablePath = executablePath ?? Self.currentExecutablePath()
        self.homeDirectoryURL = homeDirectoryURL
        self.appBundleSearchURLs = appBundleSearchURLs ?? Self.defaultAppBundleSearchURLs(homeDirectoryURL: homeDirectoryURL)
    }

    public func install(destinationPath: String? = nil) throws -> Result {
        let sourceURL = try installSourceURL()
        guard fileManager.fileExists(atPath: sourceURL.path), fileManager.isExecutableFile(atPath: sourceURL.path) else {
            throw InstallerError.executableNotFound(sourceURL.path)
        }

        let installURL = destinationURL(for: destinationPath)
        let installDirectoryURL = installURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: installDirectoryURL, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: installURL.path) || fileManager.destinationOfSymbolicLinkIsReachable(at: installURL) {
            try fileManager.removeItem(at: installURL)
        }

        try fileManager.createSymbolicLink(at: installURL, withDestinationURL: sourceURL)

        let installDirectoryPath = installDirectoryURL.standardizedFileURL.path
        let pathHintDirectory = isDirectoryOnPath(installDirectoryPath) ? nil : installDirectoryPath

        return Result(
            installedPath: installURL.path,
            sourcePath: sourceURL.path,
            pathHintDirectory: pathHintDirectory
        )
    }

    public func defaultUserInstallPath() -> String {
        homeDirectoryURL
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("omux", isDirectory: false)
            .path
    }

    private func destinationURL(for destinationPath: String?) -> URL {
        if let destinationPath, destinationPath.isEmpty == false {
            return expandedURL(for: destinationPath)
        }

        for directory in preferredInstallDirectories() where isDirectoryOnPath(directory.path) {
            return directory.appendingPathComponent("omux", isDirectory: false)
        }

        return URL(fileURLWithPath: defaultUserInstallPath())
    }

    private func preferredInstallDirectories() -> [URL] {
        [
            homeDirectoryURL.appendingPathComponent(".local", isDirectory: true).appendingPathComponent("bin", isDirectory: true),
            homeDirectoryURL.appendingPathComponent("bin", isDirectory: true),
            URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
        ]
    }

    private func expandedURL(for path: String) -> URL {
        if path == "~" || path.hasPrefix("~/") {
            let suffix = String(path.dropFirst())
            return homeDirectoryURL.appendingPathComponent(suffix, isDirectory: false).standardizedFileURL
        }
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    private func installSourceURL() throws -> URL {
        guard let executablePath, executablePath.isEmpty == false else {
            throw InstallerError.missingExecutablePath
        }

        let executableURL = URL(fileURLWithPath: executablePath).standardizedFileURL
        if let appCLIURL = Self.appBundleCLIURL(containingExecutableAt: executableURL),
           fileManager.fileExists(atPath: appCLIURL.path) {
            return appCLIURL
        }

        for appURL in appBundleSearchURLs {
            let cliURL = appURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("MacOS", isDirectory: true)
                .appendingPathComponent("omux", isDirectory: false)
                .standardizedFileURL
            if fileManager.fileExists(atPath: cliURL.path), fileManager.isExecutableFile(atPath: cliURL.path) {
                return cliURL
            }
        }

        return executableURL.resolvingSymlinksInPath().standardizedFileURL
    }

    private static func defaultAppBundleSearchURLs(homeDirectoryURL: URL) -> [URL] {
        [
            URL(fileURLWithPath: "/Applications/OpenMUX.app", isDirectory: true),
            homeDirectoryURL
                .appendingPathComponent("Applications", isDirectory: true)
                .appendingPathComponent("OpenMUX.app", isDirectory: true),
        ]
    }

    private static func appBundleCLIURL(containingExecutableAt executableURL: URL) -> URL? {
        var components = executableURL.standardizedFileURL.pathComponents
        guard let appIndex = components.lastIndex(where: { $0.hasSuffix(".app") }) else {
            return nil
        }
        components = Array(components.prefix(appIndex + 1))
        return URL(fileURLWithPath: NSString.path(withComponents: components), isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent("omux", isDirectory: false)
            .standardizedFileURL
    }

    private func isDirectoryOnPath(_ directoryPath: String) -> Bool {
        let pathValue = environment["PATH"] ?? ""
        let normalized = URL(fileURLWithPath: directoryPath).standardizedFileURL.path
        return pathValue
            .split(separator: ":")
            .map(String.init)
            .contains { candidate in
                URL(fileURLWithPath: candidate).standardizedFileURL.path == normalized
            }
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

private extension FileManager {
    func destinationOfSymbolicLinkIsReachable(at url: URL) -> Bool {
        (try? destinationOfSymbolicLink(atPath: url.path)) != nil
    }
}
