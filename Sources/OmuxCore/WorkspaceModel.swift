import Foundation

public struct SessionDescriptor: Equatable, Codable, Sendable {
    public let id: SessionID
    public var shell: String
    public var workingDirectory: String
    public var environment: [String: String]

    public init(
        id: SessionID = SessionID(),
        shell: String,
        workingDirectory: String,
        environment: [String: String] = [:]
    ) {
        self.id = id
        self.shell = shell
        self.workingDirectory = workingDirectory
        self.environment = environment
    }
}

public struct Pane: Equatable, Codable, Sendable {
    public let id: PaneID
    public var title: String
    public var session: SessionDescriptor

    public init(id: PaneID = PaneID(), title: String, session: SessionDescriptor) {
        self.id = id
        self.title = title
        self.session = session
    }
}

public struct Tab: Equatable, Codable, Sendable {
    public let id: TabID
    public var title: String
    public var panes: [Pane]
    public var focusedPaneID: PaneID

    public init(
        id: TabID = TabID(),
        title: String,
        panes: [Pane],
        focusedPaneID: PaneID
    ) {
        self.id = id
        self.title = title
        self.panes = panes
        self.focusedPaneID = focusedPaneID
    }

    public mutating func focusPane(_ paneID: PaneID) {
        guard panes.contains(where: { $0.id == paneID }) else {
            return
        }

        focusedPaneID = paneID
    }
}

public struct Workspace: Equatable, Codable, Sendable {
    public let id: WorkspaceID
    public var name: String
    public var rootPath: String
    public var tabs: [Tab]
    public var focusedTabID: TabID

    public init(
        id: WorkspaceID = WorkspaceID(),
        name: String,
        rootPath: String,
        tabs: [Tab],
        focusedTabID: TabID
    ) {
        self.id = id
        self.name = name
        self.rootPath = rootPath
        self.tabs = tabs
        self.focusedTabID = focusedTabID
    }

    public var focusedTab: Tab? {
        tabs.first(where: { $0.id == focusedTabID })
    }

    @discardableResult
    public mutating func focus(sessionID: SessionID) -> Bool {
        for tabIndex in tabs.indices {
            if let paneIndex = tabs[tabIndex].panes.firstIndex(where: { $0.session.id == sessionID }) {
                focusedTabID = tabs[tabIndex].id
                tabs[tabIndex].focusedPaneID = tabs[tabIndex].panes[paneIndex].id
                return true
            }
        }

        return false
    }
}

public struct WorkspaceSummary: Equatable, Codable, Sendable {
    public let id: WorkspaceID
    public let name: String
    public let rootPath: String
    public let tabCount: Int
    public let paneCount: Int

    public init(workspace: Workspace) {
        self.id = workspace.id
        self.name = workspace.name
        self.rootPath = workspace.rootPath
        self.tabCount = workspace.tabs.count
        self.paneCount = workspace.tabs.reduce(into: 0) { $0 += $1.panes.count }
    }
}

public enum NotificationSeverity: String, Codable, Sendable {
    case info
    case warning
    case error
}

public struct NotificationRequest: Equatable, Codable, Sendable {
    public var title: String
    public var body: String
    public var severity: NotificationSeverity

    public init(title: String, body: String, severity: NotificationSeverity = .info) {
        self.title = title
        self.body = body
        self.severity = severity
    }
}
