import AppKit
import OmuxCore

struct SidebarItem {
    enum Kind {
        case workspace
        case terminal
    }

    enum Action {
        case workspace(WorkspaceID)
        case pane(PaneID)
    }

    let kind: Kind
    let identifier: String
    let icon: OmuxRenderedIcon?
    let progress: PaneProgress?
    let title: String
    let subtitle: String?
    let detail: String?
    let subtitleAccentPrefixLength: Int?
    let isActive: Bool
    let isExpanded: Bool?
    let action: Action
    let contextMenuProvider: (() -> NSMenu)?

    init(
        kind: Kind,
        identifier: String,
        icon: OmuxRenderedIcon?,
        progress: PaneProgress?,
        title: String,
        subtitle: String?,
        detail: String? = nil,
        subtitleAccentPrefixLength: Int? = nil,
        isActive: Bool,
        isExpanded: Bool? = nil,
        action: Action,
        contextMenuProvider: (() -> NSMenu)?
    ) {
        self.kind = kind
        self.identifier = identifier
        self.icon = icon
        self.progress = progress
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.subtitleAccentPrefixLength = subtitleAccentPrefixLength
        self.isActive = isActive
        self.isExpanded = isExpanded
        self.action = action
        self.contextMenuProvider = contextMenuProvider
    }

    var workspaceID: WorkspaceID? {
        guard case .workspace(let workspaceID) = action else {
            return nil
        }
        return workspaceID
    }

    var rowHeight: CGFloat {
        switch kind {
        case .workspace:
            return 28
        case .terminal:
            if detail != nil {
                return 50
            }
            if subtitle == nil {
                return 26
            }
            return 34
        }
    }
}
