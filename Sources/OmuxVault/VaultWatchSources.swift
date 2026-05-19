import Foundation

public struct VaultWatchSource: Equatable, Hashable, Sendable {
    public let agent: VaultAgentKind
    public let url: URL

    public init(agent: VaultAgentKind, url: URL) {
        self.agent = agent
        self.url = url.standardizedFileURL
    }
}

public enum VaultWatchSourceFactory {
    public static func sources(
        configuration: VaultConfiguration,
        fileManager: FileManager = .default,
        includeMissing: Bool = false
    ) -> [VaultWatchSource] {
        guard configuration.enabled else {
            return []
        }

        var sources: [VaultWatchSource] = []
        for agent in configuration.includedAgents where agent != .custom {
            for url in candidateSourceRoots(for: agent, configuration: configuration) {
                if includeMissing || fileManager.fileExists(atPath: url.path) {
                    sources.append(VaultWatchSource(agent: agent, url: url))
                }
            }
        }
        return deduplicate(sources)
    }

    private static func candidateSourceRoots(for agent: VaultAgentKind, configuration: VaultConfiguration) -> [URL] {
        let home = configuration.home(for: agent)
        switch agent {
        case .codex:
            return [home]
        case .claude:
            return [home.appendingPathComponent("projects", isDirectory: true)]
        case .opencode:
            return [home]
        case .pi:
            return [home]
        case .rovodev:
            return [home]
        case .copilot:
            return [home]
        case .gemini:
            return [home.appendingPathComponent("tmp", isDirectory: true)]
        case .custom:
            return []
        }
    }

    private static func deduplicate(_ sources: [VaultWatchSource]) -> [VaultWatchSource] {
        var seen = Set<String>()
        return sources.filter { source in
            let key = "\(source.agent.rawValue):\(source.url.path)"
            return seen.insert(key).inserted
        }
    }
}
