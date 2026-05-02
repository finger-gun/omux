import Foundation
import OmuxCore

public enum HookCategory: String, CaseIterable, Codable, Sendable {
    case lifecycle
    case session
    case command
    case ui
    case input
}

public struct HookInvocation: Codable, Equatable, Sendable {
    public let category: HookCategory
    public let name: String
    public let workspaceID: WorkspaceID?
    public let tabID: TabID?
    public let paneID: PaneID?
    public let sessionID: SessionID?
    public let payload: OmuxValue
    public let occurredAt: Date

    public init(
        category: HookCategory,
        name: String,
        workspaceID: WorkspaceID? = nil,
        tabID: TabID? = nil,
        paneID: PaneID? = nil,
        sessionID: SessionID? = nil,
        payload: OmuxValue = .object([:]),
        occurredAt: Date = Date()
    ) {
        self.category = category
        self.name = name
        self.workspaceID = workspaceID
        self.tabID = tabID
        self.paneID = paneID
        self.sessionID = sessionID
        self.payload = payload
        self.occurredAt = occurredAt
    }
}

public struct HookDescriptor: Equatable, Sendable {
    public let category: HookCategory
    public let name: String?
    public let executableURL: URL
    public let arguments: [String]
    public let environment: [String: String]

    public init(
        category: HookCategory,
        name: String? = nil,
        executableURL: URL,
        arguments: [String] = [],
        environment: [String: String] = [:]
    ) {
        self.category = category
        self.name = name
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
    }

    public func matches(_ invocation: HookInvocation) -> Bool {
        guard category == invocation.category else {
            return false
        }

        if let name {
            return name == invocation.name
        }

        return true
    }
}

public final class HookRegistry {
    private let lock = NSLock()
    private var descriptors: [HookDescriptor]

    public init(descriptors: [HookDescriptor] = []) {
        self.descriptors = descriptors
    }

    public func register(_ descriptor: HookDescriptor) {
        lock.lock()
        descriptors.append(descriptor)
        lock.unlock()
    }

    public func matchingDescriptors(for invocation: HookInvocation) -> [HookDescriptor] {
        lock.lock()
        defer { lock.unlock() }
        return descriptors.filter { $0.matches(invocation) }
    }
}

public enum UserHookDirectoryDiscovery {
    public static func descriptors(
        in hooksDirectoryURL: URL,
        fileManager: FileManager = .default
    ) -> [HookDescriptor] {
        guard isDirectory(hooksDirectoryURL, fileManager: fileManager) else {
            return []
        }

        let hookDirectories = directoryContents(
            at: hooksDirectoryURL,
            fileManager: fileManager,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        .filter { isActiveEntry($0) && isDirectory($0, fileManager: fileManager) }
        .sortedByLastPathComponent()

        return hookDirectories.flatMap { hookDirectory in
            descriptors(forHookDirectory: hookDirectory, fileManager: fileManager)
        }
    }

    public static func registry(
        in hooksDirectoryURL: URL,
        fileManager: FileManager = .default
    ) -> HookRegistry {
        HookRegistry(descriptors: descriptors(in: hooksDirectoryURL, fileManager: fileManager))
    }

    private static func descriptors(
        forHookDirectory hookDirectory: URL,
        fileManager: FileManager
    ) -> [HookDescriptor] {
        let hookName = hookDirectory.lastPathComponent
        let handlers = directoryContents(
            at: hookDirectory,
            fileManager: fileManager,
            includingPropertiesForKeys: [.isRegularFileKey]
        )
        .filter { isActiveExecutableRegularFile($0, fileManager: fileManager) }
        .sortedByLastPathComponent()

        return handlers.flatMap { handler in
            HookCategory.allCases.map { category in
                HookDescriptor(category: category, name: hookName, executableURL: handler)
            }
        }
    }

    private static func directoryContents(
        at url: URL,
        fileManager: FileManager,
        includingPropertiesForKeys keys: [URLResourceKey]
    ) -> [URL] {
        (try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: []
        )) ?? []
    }

    private static func isActiveExecutableRegularFile(_ url: URL, fileManager: FileManager) -> Bool {
        isActiveEntry(url)
            && isRegularFile(url, fileManager: fileManager)
            && fileManager.isExecutableFile(atPath: url.path(percentEncoded: false))
    }

    private static func isActiveEntry(_ url: URL) -> Bool {
        url.lastPathComponent.hasPrefix(".") == false
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private static func isRegularFile(_ url: URL, fileManager: FileManager) -> Bool {
        let path = url.path(percentEncoded: false)
        guard fileManager.fileExists(atPath: path) else {
            return false
        }

        let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
        return values?.isRegularFile == true
    }
}

private extension Array where Element == URL {
    func sortedByLastPathComponent() -> [URL] {
        sorted { lhs, rhs in
            lhs.lastPathComponent < rhs.lastPathComponent
        }
    }
}

public protocol HookProcessLaunching: Sendable {
    func launch(executableURL: URL, arguments: [String], environment: [String: String], input: Data) throws
}

public enum HookExecutionMode: Sendable {
    case synchronous
    case asynchronous
}

public enum ProcessHookLauncherError: Error, CustomStringConvertible, Equatable {
    case nonZeroExit(executablePath: String, status: Int32)

    public var description: String {
        switch self {
        case .nonZeroExit(let executablePath, let status):
            return "\(executablePath) exited with status \(status)"
        }
    }
}

public struct ProcessHookLauncher: HookProcessLaunching {
    public init() {}

    public func launch(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        input: Data
    ) throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        process.environment = HookProcessEnvironment.merged(with: environment)

        let stdinPipe = Pipe()
        process.standardInput = stdinPipe
        try process.run()
        stdinPipe.fileHandleForWriting.write(input)
        try stdinPipe.fileHandleForWriting.close()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw ProcessHookLauncherError.nonZeroExit(
                executablePath: executableURL.path(percentEncoded: false),
                status: process.terminationStatus
            )
        }
    }
}

private enum HookProcessEnvironment {
    static func merged(with environment: [String: String]) -> [String: String] {
        var mergedEnvironment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        mergedEnvironment["PATH"] = enrichedPath(from: mergedEnvironment["PATH"])
        return mergedEnvironment
    }

    private static func enrichedPath(from inheritedPath: String?) -> String {
        let inheritedComponents = inheritedPath?
            .split(separator: ":")
            .map(String.init) ?? []
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let appExecutableDirectory = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .path(percentEncoded: false)

        let preferredComponents = [
            appExecutableDirectory,
            homeDirectory
                .appendingPathComponent(".local", isDirectory: true)
                .appendingPathComponent("bin", isDirectory: true)
                .path(percentEncoded: false),
            homeDirectory
                .appendingPathComponent("bin", isDirectory: true)
                .path(percentEncoded: false),
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ].compactMap { $0 }

        var seen = Set<String>()
        return (preferredComponents + inheritedComponents)
            .filter { component in
                seen.insert(component).inserted
            }
            .joined(separator: ":")
    }
}

public final class ExternalHookRunner {
    private let registry: HookRegistry
    private let launcher: any HookProcessLaunching
    private let warningHandler: @Sendable (String) -> Void
    private let executionMode: HookExecutionMode
    private let executionQueue = DispatchQueue(label: "dev.fingergun.omux.hooks")
    private let encoder = JSONEncoder()

    public init(
        registry: HookRegistry = HookRegistry(),
        launcher: any HookProcessLaunching = ProcessHookLauncher(),
        executionMode: HookExecutionMode = .synchronous,
        warningHandler: @escaping @Sendable (String) -> Void = { message in
            fputs("warning: \(message)\n", stderr)
        }
    ) {
        self.registry = registry
        self.launcher = launcher
        self.warningHandler = warningHandler
        self.executionMode = executionMode
        self.encoder.outputFormatting = [.sortedKeys]
    }

    public var hookRegistry: HookRegistry {
        registry
    }

    public func emit(_ invocation: HookInvocation) throws {
        let descriptors = registry.matchingDescriptors(for: invocation)
        guard descriptors.isEmpty == false else {
            return
        }

        let payload = try encoder.encode(invocation)
        switch executionMode {
        case .synchronous:
            run(descriptors: descriptors, payload: payload)
        case .asynchronous:
            executionQueue.async { [launcher, warningHandler] in
                Self.run(
                    descriptors: descriptors,
                    payload: payload,
                    launcher: launcher,
                    warningHandler: warningHandler
                )
            }
        }
    }

    private func run(descriptors: [HookDescriptor], payload: Data) {
        Self.run(
            descriptors: descriptors,
            payload: payload,
            launcher: launcher,
            warningHandler: warningHandler
        )
    }

    private static func run(
        descriptors: [HookDescriptor],
        payload: Data,
        launcher: any HookProcessLaunching,
        warningHandler: @Sendable (String) -> Void
    ) {
        for descriptor in descriptors {
            do {
                try launcher.launch(
                    executableURL: descriptor.executableURL,
                    arguments: descriptor.arguments,
                    environment: descriptor.environment,
                    input: payload
                )
            } catch {
                warningHandler(
                    "failed to run hook \(descriptor.name ?? descriptor.category.rawValue) at "
                        + "\(descriptor.executableURL.path(percentEncoded: false)): \(error)"
                )
            }
        }
    }
}
