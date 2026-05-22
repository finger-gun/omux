import Foundation
import OmuxConfig

public enum VaultAgentKind: Codable, Hashable, Sendable {
    case codex
    case copilot
    case gemini
    case custom
    case external(String)

    public static let allCases: [VaultAgentKind] = [
        .codex,
        .copilot,
        .gemini,
        .custom,
    ]

    public init?(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }
        switch trimmed {
        case "codex":
            self = .codex
        case "copilot":
            self = .copilot
        case "gemini":
            self = .gemini
        case "custom":
            self = .custom
        default:
            self = .external(trimmed)
        }
    }

    public var rawValue: String {
        switch self {
        case .codex:
            return "codex"
        case .copilot:
            return "copilot"
        case .gemini:
            return "gemini"
        case .custom:
            return "custom"
        case .external(let name):
            return name
        }
    }

    public init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        guard let value = VaultAgentKind(rawValue: rawValue) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Agent kind must be a non-empty string.")
            )
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        guard let canonical = VaultAgentKind(rawValue: rawValue) else {
            throw EncodingError.invalidValue(
                self,
                EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Agent kind must be a non-empty string.")
            )
        }
        var container = encoder.singleValueContainer()
        try container.encode(canonical.rawValue)
    }
}

public enum VaultGrouping: String, Codable, Sendable {
    case agent
    case directory
}

public enum VaultResumeDestination: String, Codable, Sendable {
    case focused
    case newPaneTab = "new-pane-tab"
    case split
    case workspace
}

public struct VaultSessionSummary: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: String
    public let agent: VaultAgentKind
    public let sourceKind: String
    public let sourcePath: String?
    public let title: String
    public let workingDirectory: String?
    public let model: String?
    public let gitBranch: String?
    public let prURL: String?
    public let modifiedAt: Date
    public let previewAvailable: Bool
    public let resumeAvailable: Bool

    public init(
        id: String,
        agent: VaultAgentKind,
        sourceKind: String,
        sourcePath: String? = nil,
        title: String,
        workingDirectory: String? = nil,
        model: String? = nil,
        gitBranch: String? = nil,
        prURL: String? = nil,
        modifiedAt: Date,
        previewAvailable: Bool = false,
        resumeAvailable: Bool = false
    ) {
        self.id = id
        self.agent = agent
        self.sourceKind = sourceKind
        self.sourcePath = sourcePath
        self.title = title
        self.workingDirectory = workingDirectory
        self.model = model
        self.gitBranch = gitBranch
        self.prURL = prURL
        self.modifiedAt = modifiedAt
        self.previewAvailable = previewAvailable
        self.resumeAvailable = resumeAvailable
    }
}

public struct VaultResumeSnapshot: Codable, Equatable, Sendable {
    public let kind: VaultAgentKind
    public let sessionID: String
    public let workingDirectory: String?
    public let launchCommand: [String]?
    public let resumeCommand: String?
    public let registrationID: String?
    public let metadata: [String: String]

    public init(
        kind: VaultAgentKind,
        sessionID: String,
        workingDirectory: String?,
        launchCommand: [String]? = nil,
        resumeCommand: String?,
        registrationID: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.kind = kind
        self.sessionID = sessionID
        self.workingDirectory = workingDirectory
        self.launchCommand = launchCommand
        self.resumeCommand = resumeCommand
        self.registrationID = registrationID
        self.metadata = metadata
    }
}

public struct VaultTranscriptTurn: Codable, Equatable, Sendable, Identifiable {
    public var id: String { turnID }
    public let sessionID: String
    public let turnID: String
    public let role: String
    public let text: String
    public let ordinal: Int
    public let modifiedAt: Date

    public init(sessionID: String, turnID: String, role: String, text: String, ordinal: Int, modifiedAt: Date) {
        self.sessionID = sessionID
        self.turnID = turnID
        self.role = role
        self.text = text
        self.ordinal = ordinal
        self.modifiedAt = modifiedAt
    }
}

public struct VaultIndexedSession: Sendable {
    public let summary: VaultSessionSummary
    public let resumeSnapshot: VaultResumeSnapshot?
    public let turns: [VaultTranscriptTurn]

    public init(summary: VaultSessionSummary, resumeSnapshot: VaultResumeSnapshot?, turns: [VaultTranscriptTurn]) {
        self.summary = summary
        self.resumeSnapshot = resumeSnapshot
        self.turns = turns
    }
}

public struct VaultSearchRequest: Codable, Equatable, Sendable {
    public let query: String
    public let agents: [VaultAgentKind]?
    public let workingDirectory: String?
    public let workingDirectoryPrefixes: [String]?
    public let offset: Int
    public let limit: Int

    public init(
        query: String = "",
        agents: [VaultAgentKind]? = nil,
        workingDirectory: String? = nil,
        workingDirectoryPrefixes: [String]? = nil,
        offset: Int = 0,
        limit: Int = 50
    ) {
        self.query = query
        self.agents = agents
        self.workingDirectory = workingDirectory
        self.workingDirectoryPrefixes = workingDirectoryPrefixes
        self.offset = max(0, offset)
        self.limit = min(max(1, limit), 500)
    }
}

public struct VaultSearchResponse: Codable, Equatable, Sendable {
    public let sessions: [VaultSessionSummary]
    public let totalCount: Int

    public init(sessions: [VaultSessionSummary], totalCount: Int) {
        self.sessions = sessions
        self.totalCount = totalCount
    }
}

public struct VaultPreview: Codable, Equatable, Sendable {
    public let session: VaultSessionSummary
    public let turns: [VaultTranscriptTurn]
    public let truncated: Bool

    public init(session: VaultSessionSummary, turns: [VaultTranscriptTurn], truncated: Bool) {
        self.session = session
        self.turns = turns
        self.truncated = truncated
    }
}

public struct VaultExportBundle: Codable, Equatable, Sendable {
    public let version: Int
    public let exportedAt: Date
    public let sessions: [VaultSessionSummary]
    public let resumeSnapshots: [String: VaultResumeSnapshot]
    public let turns: [String: [VaultTranscriptTurn]]

    public init(
        version: Int = 1,
        exportedAt: Date = Date(),
        sessions: [VaultSessionSummary],
        resumeSnapshots: [String: VaultResumeSnapshot],
        turns: [String: [VaultTranscriptTurn]]
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.sessions = sessions
        self.resumeSnapshots = resumeSnapshots
        self.turns = turns
    }
}

public struct VaultConfiguration: Equatable, Sendable {
    public struct ExternalAdapterConfiguration: Equatable, Sendable {
        public let id: String
        public let agent: VaultAgentKind
        public let executablePath: String
        public let arguments: [String]
        public let sourceKind: String
        public let resumeCommand: String?

        public init(
            id: String,
            agent: VaultAgentKind,
            executablePath: String,
            arguments: [String],
            sourceKind: String,
            resumeCommand: String? = nil
        ) {
            self.id = id
            self.agent = agent
            self.executablePath = executablePath
            self.arguments = arguments
            self.sourceKind = sourceKind
            self.resumeCommand = resumeCommand
        }
    }

    public struct ExternalAdapterSetting: Equatable, Sendable {
        public let enabled: Bool?
        public let resumeCommand: String?

        public init(enabled: Bool? = nil, resumeCommand: String? = nil) {
            self.enabled = enabled
            self.resumeCommand = resumeCommand
        }
    }

    public static let defaultIncludedAgents = VaultAgentKind.allCases.filter { $0 != .custom }

    public var enabled: Bool
    public var previewEnabled: Bool
    public var indexOnLaunch: Bool
    public var collapsedToggleVisible: Bool
    public var includedAgents: [VaultAgentKind]
    public var excludedPaths: [String]
    public var maxPreviewBytes: Int
    public var sidebarRowsPerAgent: Int
    public var externalAdaptersEnabled: Bool
    public var agentHomes: [VaultAgentKind: String]
    public var resumeCommands: [VaultAgentKind: String]
    public var externalAdapters: [ExternalAdapterConfiguration]
    public var externalAdapterSettings: [String: ExternalAdapterSetting]

    public init(
        enabled: Bool = true,
        previewEnabled: Bool = true,
        indexOnLaunch: Bool = true,
        collapsedToggleVisible: Bool = true,
        includedAgents: [VaultAgentKind] = Self.defaultIncludedAgents,
        excludedPaths: [String] = [],
        maxPreviewBytes: Int = 1_048_576,
        sidebarRowsPerAgent: Int = 10,
        externalAdaptersEnabled: Bool = true,
        agentHomes: [VaultAgentKind: String] = [:],
        resumeCommands: [VaultAgentKind: String] = [:],
        externalAdapters: [ExternalAdapterConfiguration] = [],
        externalAdapterSettings: [String: ExternalAdapterSetting] = [:]
    ) {
        self.enabled = enabled
        self.previewEnabled = previewEnabled
        self.indexOnLaunch = indexOnLaunch
        self.collapsedToggleVisible = collapsedToggleVisible
        self.includedAgents = includedAgents
        self.excludedPaths = excludedPaths
        self.maxPreviewBytes = maxPreviewBytes
        self.sidebarRowsPerAgent = max(1, sidebarRowsPerAgent)
        self.externalAdaptersEnabled = externalAdaptersEnabled
        self.agentHomes = agentHomes
        self.resumeCommands = resumeCommands
        self.externalAdapters = externalAdapters
        self.externalAdapterSettings = externalAdapterSettings
    }

    public init(config: OmuxConfigAgentSessions) {
        var included = config.includedAgents.compactMap(VaultAgentKind.init(rawValue:))
        var homes: [VaultAgentKind: String] = [:]
        var commands: [VaultAgentKind: String] = [:]
        var externalAdapterSettings: [String: ExternalAdapterSetting] = [:]
        for (name, agentConfig) in config.agents {
            guard let agent = VaultAgentKind(rawValue: name) else {
                continue
            }
            if agentConfig.enabled == false {
                included.removeAll { $0 == agent }
            } else if agentConfig.enabled == true, included.contains(agent) == false {
                included.append(agent)
            }
            if let home = agentConfig.home {
                homes[agent] = home
            }
            if let command = agentConfig.resumeCommand {
                commands[agent] = command
            }
        }
        for (adapterID, adapterConfig) in config.externalAdapters {
            externalAdapterSettings[adapterID] = ExternalAdapterSetting(
                enabled: adapterConfig.enabled,
                resumeCommand: adapterConfig.resumeCommand
            )
        }
        self.init(
            enabled: config.enabled,
            previewEnabled: config.previewEnabled,
            indexOnLaunch: config.indexOnLaunch,
            collapsedToggleVisible: config.collapsedToggleVisible,
            includedAgents: included,
            excludedPaths: config.excludedPaths,
            maxPreviewBytes: config.maxPreviewBytes,
            sidebarRowsPerAgent: config.sidebarRowsPerAgent,
            externalAdaptersEnabled: config.externalAdaptersEnabled,
            agentHomes: homes,
            resumeCommands: commands,
            externalAdapterSettings: externalAdapterSettings
        )
    }

    public func home(for agent: VaultAgentKind) -> URL {
        let override = agentHomes[agent]
        switch agent {
        case .codex:
            return resolveHome(override ?? "~/.codex")
        case .copilot:
            if let env = ProcessInfo.processInfo.environment["COPILOT_HOME"], env.isEmpty == false {
                return resolveHome(override ?? env)
            }
            return resolveHome(override ?? "~/.copilot")
        case .gemini:
            return resolveHome(override ?? "~/.gemini")
        case .custom:
            return resolveHome(override ?? "~")
        case .external:
            return resolveHome(override ?? "~")
        }
    }

    public func resumeCommand(for agent: VaultAgentKind, sessionID: String) -> String? {
        let template = resumeCommands[agent] ?? Self.defaultResumeCommandTemplate(agent)
        return template?.replacingOccurrences(of: "{session_id}", with: shellQuoted(sessionID))
    }

    public func resumeCommandTemplate(for agent: VaultAgentKind) -> String? {
        resumeCommands[agent] ?? Self.defaultResumeCommandTemplate(agent)
    }

    private static func defaultResumeCommandTemplate(_ agent: VaultAgentKind) -> String? {
        switch agent {
        case .codex:
            return "codex resume {session_id}"
        case .copilot:
            return "copilot --resume {session_id}"
        case .gemini:
            return "gemini --resume {session_id}"
        case .custom:
            return nil
        case .external:
            return nil
        }
    }

    private func resolveHome(_ path: String) -> URL {
        let expanded: String
        if path == "~" {
            expanded = FileManager.default.homeDirectoryForCurrentUser.path
        } else if path.hasPrefix("~/") {
            expanded = FileManager.default.homeDirectoryForCurrentUser.path + String(path.dropFirst())
        } else {
            expanded = path
        }
        return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private func shellQuoted(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
