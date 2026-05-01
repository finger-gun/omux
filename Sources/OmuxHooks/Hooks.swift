import Foundation
import OmuxCore

public enum HookCategory: String, Codable, Sendable {
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

public protocol HookProcessLaunching {
    func launch(executableURL: URL, arguments: [String], environment: [String: String], input: Data) throws
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

        if environment.isEmpty == false {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }

        let stdinPipe = Pipe()
        process.standardInput = stdinPipe
        try process.run()
        stdinPipe.fileHandleForWriting.write(input)
        try stdinPipe.fileHandleForWriting.close()
        process.waitUntilExit()
    }
}

public final class ExternalHookRunner {
    private let registry: HookRegistry
    private let launcher: any HookProcessLaunching
    private let encoder = JSONEncoder()

    public init(
        registry: HookRegistry = HookRegistry(),
        launcher: any HookProcessLaunching = ProcessHookLauncher()
    ) {
        self.registry = registry
        self.launcher = launcher
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
        for descriptor in descriptors {
            try launcher.launch(
                executableURL: descriptor.executableURL,
                arguments: descriptor.arguments,
                environment: descriptor.environment,
                input: payload
            )
        }
    }
}
