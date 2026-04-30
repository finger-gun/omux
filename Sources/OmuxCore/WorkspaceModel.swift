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

public enum PaneSplitAxis: String, Codable, Sendable {
    case columns
    case rows
}

public indirect enum TabLayoutNode: Equatable, Codable, Sendable {
    case pane(Pane)
    case split(axis: PaneSplitAxis, children: [TabLayoutNode])

    public var panes: [Pane] {
        switch self {
        case .pane(let pane):
            return [pane]
        case .split(_, let children):
            return children.flatMap(\.panes)
        }
    }

    public func pane(id: PaneID) -> Pane? {
        switch self {
        case .pane(let pane):
            return pane.id == id ? pane : nil
        case .split(_, let children):
            for child in children {
                if let pane = child.pane(id: id) {
                    return pane
                }
            }
            return nil
        }
    }

    public func containsPane(id: PaneID) -> Bool {
        pane(id: id) != nil
    }

    public func containsSession(id: SessionID) -> Bool {
        panes.contains(where: { $0.session.id == id })
    }

    @discardableResult
    public mutating func split(
        paneID: PaneID,
        axis: PaneSplitAxis,
        adding pane: Pane
    ) -> Bool {
        switch self {
        case .pane(let existingPane):
            guard existingPane.id == paneID else {
                return false
            }

            self = .split(axis: axis, children: [.pane(existingPane), .pane(pane)])
            return true

        case .split(let existingAxis, var children):
            for index in children.indices {
                if children[index].split(paneID: paneID, axis: axis, adding: pane) {
                    self = .split(axis: existingAxis, children: children)
                    return true
                }
            }
            return false
        }
    }
}

public struct Tab: Equatable, Codable, Sendable {
    public let id: TabID
    public var title: String
    public var rootLayout: TabLayoutNode
    public var focusedPaneID: PaneID

    public init(
        id: TabID = TabID(),
        title: String,
        panes: [Pane],
        focusedPaneID: PaneID
    ) {
        self.id = id
        self.title = title
        self.rootLayout = Self.makeInitialLayout(from: panes)
        self.focusedPaneID = focusedPaneID
    }

    public mutating func focusPane(_ paneID: PaneID) {
        guard rootLayout.containsPane(id: paneID) else {
            return
        }

        focusedPaneID = paneID
    }

    public var panes: [Pane] {
        rootLayout.panes
    }

    public var focusedPane: Pane? {
        rootLayout.pane(id: focusedPaneID)
    }

    @discardableResult
    public mutating func splitFocusedPane(_ pane: Pane, axis: PaneSplitAxis, focus: Bool = true) -> Bool {
        guard rootLayout.split(paneID: focusedPaneID, axis: axis, adding: pane) else {
            return false
        }

        if focus {
            focusedPaneID = pane.id
        }
        return true
    }

    private static func makeInitialLayout(from panes: [Pane]) -> TabLayoutNode {
        guard let firstPane = panes.first else {
            return .split(axis: .columns, children: [])
        }

        return panes.dropFirst().reduce(.pane(firstPane)) { partialResult, pane in
            .split(axis: .columns, children: [partialResult, .pane(pane)])
        }
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

    public var focusedPane: Pane? {
        focusedTab?.focusedPane
    }

    @discardableResult
    public mutating func focus(sessionID: SessionID) -> Bool {
        for tabIndex in tabs.indices {
            if let pane = tabs[tabIndex].panes.first(where: { $0.session.id == sessionID }) {
                focusedTabID = tabs[tabIndex].id
                tabs[tabIndex].focusedPaneID = pane.id
                return true
            }
        }

        return false
    }

    @discardableResult
    public mutating func focus(tabID: TabID) -> Bool {
        guard tabs.contains(where: { $0.id == tabID }) else {
            return false
        }

        focusedTabID = tabID
        return true
    }

    @discardableResult
    public mutating func focus(paneID: PaneID) -> Bool {
        for tabIndex in tabs.indices {
            if tabs[tabIndex].panes.contains(where: { $0.id == paneID }) {
                focusedTabID = tabs[tabIndex].id
                tabs[tabIndex].focusedPaneID = paneID
                return true
            }
        }

        return false
    }

    public mutating func appendTab(_ tab: Tab, focus: Bool = true) {
        tabs.append(tab)
        if focus {
            focusedTabID = tab.id
        }
    }

    @discardableResult
    public mutating func appendPaneToFocusedTab(_ pane: Pane, axis: PaneSplitAxis? = nil) -> Bool {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == focusedTabID }) else {
            return false
        }

        return tabs[tabIndex].splitFocusedPane(pane, axis: axis ?? .columns)
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
