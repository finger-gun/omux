import Foundation
import OmuxCore

struct WorkspaceLookupLocation: Sendable {
    let workspaceIndex: Int
    let tabIndex: Int?
    let floatingPaneModalIndex: Int?
    let paneIndex: Int
}

struct WorkspacePaneResolution: Sendable {
    let workspace: Workspace
    let tab: Tab?
    let floatingPaneModal: FloatingPaneModal?
    let pane: Pane
}

protocol WorkspaceStateIndexing {
    mutating func invalidate()
    mutating func paneLocation(for paneID: PaneID, in workspaces: [Workspace]) -> WorkspaceLookupLocation?
    mutating func sessionLocation(for sessionID: SessionID, in workspaces: [Workspace]) -> WorkspaceLookupLocation?
    mutating func workspaceIndex(for workspaceID: WorkspaceID, in workspaces: [Workspace]) -> Int?
    mutating func tabLocation(for tabID: TabID, in workspaces: [Workspace]) -> (workspaceIndex: Int, tabIndex: Int)?
    mutating func activeWorkspaceIndex(activeWorkspaceID: WorkspaceID?, in workspaces: [Workspace]) -> Int?
    mutating func paneResolution(at location: WorkspaceLookupLocation, in workspaces: [Workspace]) -> WorkspacePaneResolution?
}

struct WorkspaceLookupIndexStore: WorkspaceStateIndexing {
    private var workspaceIndexByID: [WorkspaceID: Int] = [:]
    private var tabLocationByID: [TabID: (workspaceIndex: Int, tabIndex: Int)] = [:]
    private var paneLocationByID: [PaneID: WorkspaceLookupLocation] = [:]
    private var sessionLocationByID: [SessionID: WorkspaceLookupLocation] = [:]
    private var isDirty = true

    mutating func invalidate() {
        isDirty = true
    }

    mutating func paneLocation(
        for paneID: PaneID,
        in workspaces: [Workspace]
    ) -> WorkspaceLookupLocation? {
        ensureIndexes(in: workspaces)
        guard let location = paneLocationByID[paneID],
              paneResolution(at: location, in: workspaces)?.pane.id == paneID
        else {
            invalidate()
            ensureIndexes(in: workspaces)
            guard let rebuilt = paneLocationByID[paneID],
                  paneResolution(at: rebuilt, in: workspaces)?.pane.id == paneID
            else {
                return nil
            }
            return rebuilt
        }
        return location
    }

    mutating func sessionLocation(
        for sessionID: SessionID,
        in workspaces: [Workspace]
    ) -> WorkspaceLookupLocation? {
        ensureIndexes(in: workspaces)
        guard let location = sessionLocationByID[sessionID],
              paneResolution(at: location, in: workspaces)?.pane.terminalSession?.id == sessionID
        else {
            invalidate()
            ensureIndexes(in: workspaces)
            guard let rebuilt = sessionLocationByID[sessionID],
                  paneResolution(at: rebuilt, in: workspaces)?.pane.terminalSession?.id == sessionID
            else {
                return nil
            }
            return rebuilt
        }
        return location
    }

    mutating func workspaceIndex(
        for workspaceID: WorkspaceID,
        in workspaces: [Workspace]
    ) -> Int? {
        ensureIndexes(in: workspaces)
        guard let index = workspaceIndexByID[workspaceID],
              workspaces.indices.contains(index),
              workspaces[index].id == workspaceID
        else {
            invalidate()
            ensureIndexes(in: workspaces)
            guard let rebuilt = workspaceIndexByID[workspaceID],
                  workspaces.indices.contains(rebuilt),
                  workspaces[rebuilt].id == workspaceID
            else {
                return nil
            }
            return rebuilt
        }
        return index
    }

    mutating func tabLocation(
        for tabID: TabID,
        in workspaces: [Workspace]
    ) -> (workspaceIndex: Int, tabIndex: Int)? {
        ensureIndexes(in: workspaces)
        guard let location = tabLocationByID[tabID],
              workspaces.indices.contains(location.workspaceIndex),
              workspaces[location.workspaceIndex].tabs.indices.contains(location.tabIndex),
              workspaces[location.workspaceIndex].tabs[location.tabIndex].id == tabID
        else {
            invalidate()
            ensureIndexes(in: workspaces)
            guard let rebuilt = tabLocationByID[tabID],
                  workspaces.indices.contains(rebuilt.workspaceIndex),
                  workspaces[rebuilt.workspaceIndex].tabs.indices.contains(rebuilt.tabIndex),
                  workspaces[rebuilt.workspaceIndex].tabs[rebuilt.tabIndex].id == tabID
            else {
                return nil
            }
            return rebuilt
        }
        return location
    }

    mutating func activeWorkspaceIndex(
        activeWorkspaceID: WorkspaceID?,
        in workspaces: [Workspace]
    ) -> Int? {
        guard let activeWorkspaceID else {
            return nil
        }
        return workspaceIndex(for: activeWorkspaceID, in: workspaces)
    }

    mutating func paneResolution(
        at location: WorkspaceLookupLocation,
        in workspaces: [Workspace]
    ) -> WorkspacePaneResolution? {
        guard workspaces.indices.contains(location.workspaceIndex) else {
            return nil
        }

        let workspace = workspaces[location.workspaceIndex]
        if let tabIndex = location.tabIndex {
            guard workspace.tabs.indices.contains(tabIndex) else {
                return nil
            }
            let tab = workspace.tabs[tabIndex]
            guard tab.panes.indices.contains(location.paneIndex) else {
                return nil
            }
            let pane = tab.panes[location.paneIndex]
            return WorkspacePaneResolution(workspace: workspace, tab: tab, floatingPaneModal: nil, pane: pane)
        }

        if let floatingPaneModalIndex = location.floatingPaneModalIndex {
            guard workspace.floatingPaneModals.indices.contains(floatingPaneModalIndex) else {
                return nil
            }
            let modal = workspace.floatingPaneModals[floatingPaneModalIndex]
            guard modal.paneStack.panes.indices.contains(location.paneIndex) else {
                return nil
            }
            let pane = modal.paneStack.panes[location.paneIndex]
            return WorkspacePaneResolution(workspace: workspace, tab: nil, floatingPaneModal: modal, pane: pane)
        }

        return nil
    }

    private mutating func ensureIndexes(in workspaces: [Workspace]) {
        guard isDirty else {
            return
        }
        rebuildIndexes(in: workspaces)
    }

    private mutating func rebuildIndexes(in workspaces: [Workspace]) {
        workspaceIndexByID.removeAll(keepingCapacity: true)
        tabLocationByID.removeAll(keepingCapacity: true)
        paneLocationByID.removeAll(keepingCapacity: true)
        sessionLocationByID.removeAll(keepingCapacity: true)

        for (workspaceIndex, workspace) in workspaces.enumerated() {
            workspaceIndexByID[workspace.id] = workspaceIndex
            for (tabIndex, tab) in workspace.tabs.enumerated() {
                tabLocationByID[tab.id] = (workspaceIndex: workspaceIndex, tabIndex: tabIndex)
                for (paneIndex, pane) in tab.panes.enumerated() {
                    let location = WorkspaceLookupLocation(
                        workspaceIndex: workspaceIndex,
                        tabIndex: tabIndex,
                        floatingPaneModalIndex: nil,
                        paneIndex: paneIndex
                    )
                    paneLocationByID[pane.id] = location
                    if let sessionID = pane.terminalSession?.id {
                        sessionLocationByID[sessionID] = location
                    }
                }
            }

            for (modalIndex, modal) in workspace.floatingPaneModals.enumerated() {
                for (paneIndex, pane) in modal.paneStack.panes.enumerated() {
                    let location = WorkspaceLookupLocation(
                        workspaceIndex: workspaceIndex,
                        tabIndex: nil,
                        floatingPaneModalIndex: modalIndex,
                        paneIndex: paneIndex
                    )
                    paneLocationByID[pane.id] = location
                    if let sessionID = pane.terminalSession?.id {
                        sessionLocationByID[sessionID] = location
                    }
                }
            }
        }

        isDirty = false
    }
}
