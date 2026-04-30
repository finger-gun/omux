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

public struct PaneStack: Equatable, Codable, Sendable {
    public let id: PaneStackID
    public var panes: [Pane]
    public var focusedPaneID: PaneID

    public init(
        id: PaneStackID = PaneStackID(),
        panes: [Pane],
        focusedPaneID: PaneID
    ) {
        self.id = id
        self.panes = panes
        self.focusedPaneID = focusedPaneID
    }

    public var focusedPane: Pane? {
        panes.first(where: { $0.id == focusedPaneID })
    }

    @discardableResult
    public mutating func focusPane(_ paneID: PaneID) -> Bool {
        guard panes.contains(where: { $0.id == paneID }) else {
            return false
        }

        focusedPaneID = paneID
        return true
    }

    public mutating func appendPane(_ pane: Pane, focus: Bool = true) {
        panes.append(pane)
        if focus {
            focusedPaneID = pane.id
        }
    }

    public mutating func closePane(id paneID: PaneID) -> Pane? {
        guard panes.count > 1,
              let index = panes.firstIndex(where: { $0.id == paneID })
        else {
            return nil
        }

        let removedPane = panes.remove(at: index)
        if focusedPaneID == removedPane.id {
            let nextIndex = min(index, panes.count - 1)
            focusedPaneID = panes[nextIndex].id
        }
        return removedPane
    }
}

public enum PaneSplitAxis: String, Codable, Sendable {
    case columns
    case rows
}

public indirect enum TabLayoutNode: Equatable, Codable, Sendable {
    case paneStack(PaneStack)
    case split(axis: PaneSplitAxis, children: [TabLayoutNode])

    public var panes: [Pane] {
        switch self {
        case .paneStack(let paneStack):
            return paneStack.panes
        case .split(_, let children):
            return children.flatMap(\.panes)
        }
    }

    public var paneStacks: [PaneStack] {
        switch self {
        case .paneStack(let paneStack):
            return [paneStack]
        case .split(_, let children):
            return children.flatMap(\.paneStacks)
        }
    }

    public func pane(id: PaneID) -> Pane? {
        switch self {
        case .paneStack(let paneStack):
            return paneStack.panes.first(where: { $0.id == id })
        case .split(_, let children):
            for child in children {
                if let pane = child.pane(id: id) {
                    return pane
                }
            }
            return nil
        }
    }

    public func paneStack(id: PaneStackID) -> PaneStack? {
        switch self {
        case .paneStack(let paneStack):
            return paneStack.id == id ? paneStack : nil
        case .split(_, let children):
            for child in children {
                if let paneStack = child.paneStack(id: id) {
                    return paneStack
                }
            }
            return nil
        }
    }

    public func paneStack(containingPaneID paneID: PaneID) -> PaneStack? {
        switch self {
        case .paneStack(let paneStack):
            return paneStack.panes.contains(where: { $0.id == paneID }) ? paneStack : nil
        case .split(_, let children):
            for child in children {
                if let paneStack = child.paneStack(containingPaneID: paneID) {
                    return paneStack
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
    public mutating func focusPane(_ paneID: PaneID) -> Bool {
        switch self {
        case .paneStack(var paneStack):
            guard paneStack.focusPane(paneID) else {
                return false
            }

            self = .paneStack(paneStack)
            return true

        case .split(let axis, var children):
            for index in children.indices {
                if children[index].focusPane(paneID) {
                    self = .split(axis: axis, children: children)
                    return true
                }
            }
            return false
        }
    }

    @discardableResult
    public mutating func createPane(
        inStack stackID: PaneStackID,
        pane: Pane,
        focus: Bool = true
    ) -> Bool {
        switch self {
        case .paneStack(var paneStack):
            guard paneStack.id == stackID else {
                return false
            }

            paneStack.appendPane(pane, focus: focus)
            self = .paneStack(paneStack)
            return true

        case .split(let axis, var children):
            for index in children.indices {
                if children[index].createPane(inStack: stackID, pane: pane, focus: focus) {
                    self = .split(axis: axis, children: children)
                    return true
                }
            }
            return false
        }
    }

    public mutating func closePane(
        inStack stackID: PaneStackID,
        paneID: PaneID
    ) -> Pane? {
        switch self {
        case .paneStack(var paneStack):
            guard paneStack.id == stackID,
                  let removedPane = paneStack.closePane(id: paneID)
            else {
                return nil
            }

            self = .paneStack(paneStack)
            return removedPane

        case .split(let axis, var children):
            for index in children.indices {
                if let removedPane = children[index].closePane(inStack: stackID, paneID: paneID) {
                    self = .split(axis: axis, children: children)
                    return removedPane
                }
            }
            return nil
        }
    }

    @discardableResult
    public mutating func split(
        stackID: PaneStackID,
        axis: PaneSplitAxis,
        adding paneStack: PaneStack
    ) -> Bool {
        switch self {
        case .paneStack(let existingPaneStack):
            guard existingPaneStack.id == stackID else {
                return false
            }

            self = .split(axis: axis, children: [.paneStack(existingPaneStack), .paneStack(paneStack)])
            return true

        case .split(let existingAxis, var children):
            for index in children.indices {
                if children[index].split(stackID: stackID, axis: axis, adding: paneStack) {
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

    @discardableResult
    public mutating func focusPane(_ paneID: PaneID) -> Bool {
        guard rootLayout.focusPane(paneID) else {
            return false
        }

        focusedPaneID = paneID
        return true
    }

    public var panes: [Pane] {
        rootLayout.panes
    }

    public var paneStacks: [PaneStack] {
        rootLayout.paneStacks
    }

    public var focusedPane: Pane? {
        rootLayout.pane(id: focusedPaneID)
    }

    public var focusedPaneStack: PaneStack? {
        rootLayout.paneStack(containingPaneID: focusedPaneID)
    }

    @discardableResult
    public mutating func createPaneInFocusedStack(_ pane: Pane, focus: Bool = true) -> Bool {
        guard let stackID = focusedPaneStack?.id,
              rootLayout.createPane(inStack: stackID, pane: pane, focus: focus)
        else {
            return false
        }

        if focus {
            focusedPaneID = pane.id
        }
        return true
    }

    public mutating func closeFocusedPane() -> Pane? {
        closePane(focusedPaneID)
    }

    public mutating func closePane(_ paneID: PaneID) -> Pane? {
        guard let stackID = rootLayout.paneStack(containingPaneID: paneID)?.id,
              let removedPane = rootLayout.closePane(inStack: stackID, paneID: paneID)
        else {
            return nil
        }

        if let updatedStack = rootLayout.paneStack(id: stackID) {
            focusedPaneID = updatedStack.focusedPaneID
        }
        return removedPane
    }

    @discardableResult
    public mutating func splitFocusedPane(_ pane: Pane, axis: PaneSplitAxis, focus: Bool = true) -> Bool {
        guard let focusedStackID = focusedPaneStack?.id else {
            return false
        }

        let newStack = PaneStack(panes: [pane], focusedPaneID: pane.id)
        guard rootLayout.split(stackID: focusedStackID, axis: axis, adding: newStack) else {
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

        return panes.dropFirst().reduce(.paneStack(PaneStack(panes: [firstPane], focusedPaneID: firstPane.id))) {
            partialResult, pane in
            .split(
                axis: .columns,
                children: [
                    partialResult,
                    .paneStack(PaneStack(panes: [pane], focusedPaneID: pane.id)),
                ]
            )
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

    public var focusedPaneStack: PaneStack? {
        focusedTab?.focusedPaneStack
    }

    @discardableResult
    public mutating func focus(sessionID: SessionID) -> Bool {
        for tabIndex in tabs.indices {
            if let pane = tabs[tabIndex].panes.first(where: { $0.session.id == sessionID }) {
                focusedTabID = tabs[tabIndex].id
                return tabs[tabIndex].focusPane(pane.id)
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
                return tabs[tabIndex].focusPane(paneID)
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
    public mutating func createPaneInFocusedStack(_ pane: Pane) -> Bool {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == focusedTabID }) else {
            return false
        }

        return tabs[tabIndex].createPaneInFocusedStack(pane)
    }

    public mutating func closeFocusedPane() -> Pane? {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == focusedTabID }) else {
            return nil
        }

        return tabs[tabIndex].closeFocusedPane()
    }

    public mutating func closePane(_ paneID: PaneID) -> Pane? {
        for tabIndex in tabs.indices {
            if tabs[tabIndex].panes.contains(where: { $0.id == paneID }) {
                focusedTabID = tabs[tabIndex].id
                return tabs[tabIndex].closePane(paneID)
            }
        }

        return nil
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
