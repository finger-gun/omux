import Foundation

public enum CommandPaletteQueryMode: String, Equatable, Sendable {
    case workspace
    case command
}

public struct CommandPaletteParsedQuery: Equatable, Sendable {
    public let rawText: String
    public let mode: CommandPaletteQueryMode
    public let matchingText: String

    public init(rawText: String) {
        self.rawText = rawText
        if rawText.first == ">" {
            mode = .command
            matchingText = String(rawText.dropFirst())
        } else {
            mode = .workspace
            matchingText = rawText
        }
    }
}

public enum CommandPaletteCategory: String, Equatable, Sendable {
    case workspace = "Workspace"
    case action = "Action"
    case cli = "omux"
}

public enum CommandPaletteInvocationTarget: Equatable, Sendable {
    case workspace(WorkspaceID)
    case action(OpenMUXKeyBindingAction)
    case cliCommand(String)
}

public struct CommandPaletteResult: Equatable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let category: CommandPaletteCategory
    public let matchText: String
    public let aliases: [String]
    public let shortcutLabel: String?
    public let isEnabled: Bool
    public let disabledReason: String?
    public let invocationTarget: CommandPaletteInvocationTarget

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        category: CommandPaletteCategory,
        matchText: String,
        aliases: [String] = [],
        shortcutLabel: String? = nil,
        isEnabled: Bool = true,
        disabledReason: String? = nil,
        invocationTarget: CommandPaletteInvocationTarget
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.category = category
        self.matchText = matchText
        self.aliases = aliases
        self.shortcutLabel = shortcutLabel
        self.isEnabled = isEnabled
        self.disabledReason = disabledReason
        self.invocationTarget = invocationTarget
    }
}

public struct CommandPaletteWorkspace: Equatable, Sendable {
    public let id: WorkspaceID
    public let displayName: String
    public let path: String?
    public let visibleOrder: Int
    public let isActive: Bool

    public init(
        id: WorkspaceID,
        displayName: String,
        path: String? = nil,
        visibleOrder: Int,
        isActive: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.path = path
        self.visibleOrder = visibleOrder
        self.isActive = isActive
    }
}

public struct CommandPaletteCommand: Equatable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let category: CommandPaletteCategory
    public let matchText: String
    public let aliases: [String]
    public let shortcutLabel: String?
    public let requiresArguments: Bool
    public let hasSafeDefaultTarget: Bool
    public let isEnabled: Bool
    public let disabledReason: String?
    public let invocationTarget: CommandPaletteInvocationTarget

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        category: CommandPaletteCategory,
        matchText: String,
        aliases: [String] = [],
        shortcutLabel: String? = nil,
        requiresArguments: Bool = false,
        hasSafeDefaultTarget: Bool = true,
        isEnabled: Bool = true,
        disabledReason: String? = nil,
        invocationTarget: CommandPaletteInvocationTarget
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.category = category
        self.matchText = matchText
        self.aliases = aliases
        self.shortcutLabel = shortcutLabel
        self.requiresArguments = requiresArguments
        self.hasSafeDefaultTarget = hasSafeDefaultTarget
        self.isEnabled = isEnabled
        self.disabledReason = disabledReason
        self.invocationTarget = invocationTarget
    }

    public var isPaletteVisible: Bool {
        category == .cli || requiresArguments == false || hasSafeDefaultTarget
    }
}

public enum CommandPaletteSearch {
    public static func workspaceResults(
        query: String,
        workspaces: [CommandPaletteWorkspace]
    ) -> [CommandPaletteResult] {
        rankedMatches(query: query, items: workspaces) { workspace in
            [workspace.displayName, workspace.path].compactMap { $0 }
        }
        .map { match in
            let workspace = match.item
            return CommandPaletteResult(
                id: "workspace:\(workspace.id.rawValue)",
                title: workspace.displayName,
                subtitle: workspace.path,
                category: .workspace,
                matchText: [workspace.displayName, workspace.path].compactMap { $0 }.joined(separator: " "),
                aliases: workspace.path.map { [$0] } ?? [],
                isEnabled: true,
                invocationTarget: .workspace(workspace.id)
            )
        }
    }

    public static func commandResults(
        query: String,
        commands: [CommandPaletteCommand]
    ) -> [CommandPaletteResult] {
        let visibleCommands = commands.filter { $0.isPaletteVisible }
        return rankedMatches(query: query, items: visibleCommands) { command in
            [command.title, command.matchText] + command.aliases
        }
        .map { match in
            let command = match.item
            return CommandPaletteResult(
                id: command.id,
                title: command.title,
                subtitle: command.subtitle,
                category: command.category,
                matchText: command.matchText,
                aliases: command.aliases,
                shortcutLabel: command.shortcutLabel,
                isEnabled: command.isEnabled,
                disabledReason: command.disabledReason,
                invocationTarget: command.invocationTarget
            )
        }
    }

    private static func rankedMatches<Item>(
        query: String,
        items: [Item],
        searchableText: (Item) -> [String]
    ) -> [(item: Item, score: Int, index: Int)] {
        let normalizedQuery = normalize(query)
        return items.enumerated().compactMap { index, item in
            guard normalizedQuery.isEmpty == false else {
                return (item, 0, index)
            }

            let score = searchableText(item)
                .map { matchScore(query: normalizedQuery, candidate: normalize($0)) }
                .min()
            guard let score else { return nil }
            return (item, score, index)
        }
        .filter { normalizedQuery.isEmpty || $0.score < Int.max }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            return lhs.index < rhs.index
        }
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
    }

    private static func matchScore(query: String, candidate: String) -> Int {
        guard candidate.isEmpty == false else { return Int.max }
        if candidate == query { return 0 }
        if candidate.hasPrefix(query) { return 10 }
        if candidate.contains(query) { return 20 }

        let queryParts = query.split(separator: " ")
        if queryParts.allSatisfy({ candidate.contains($0) }) {
            return 30
        }
        return Int.max
    }
}

public extension Workspace {
    func commandPaletteWorkspace(visibleOrder: Int, activeWorkspaceID: WorkspaceID?) -> CommandPaletteWorkspace {
        CommandPaletteWorkspace(
            id: id,
            displayName: name,
            path: rootPath.isEmpty ? nil : rootPath,
            visibleOrder: visibleOrder,
            isActive: id == activeWorkspaceID
        )
    }
}
