import Foundation
import OmuxCore

public enum ControlPlaneTerminalTarget: Equatable, Sendable {
    case session(SessionID)
    case pane(PaneID)
    case tab(TabID)
    case workspace(WorkspaceID)
    case focused

    public var rpcValue: RPCValue {
        switch self {
        case .session(let id):
            return .object(["type": .string("session"), "id": .string(id.rawValue)])
        case .pane(let id):
            return .object(["type": .string("pane"), "id": .string(id.rawValue)])
        case .tab(let id):
            return .object(["type": .string("tab"), "id": .string(id.rawValue)])
        case .workspace(let id):
            return .object(["type": .string("workspace"), "id": .string(id.rawValue)])
        case .focused:
            return .object(["type": .string("focused")])
        }
    }

    public init?(rpcValue: RPCValue?) {
        guard let rpcValue else {
            return nil
        }

        guard case .object(let object) = rpcValue else {
            return nil
        }

        if let explicitTarget = object["target"],
           case .object(let targetObject) = explicitTarget {
            self.init(targetObject: targetObject)
            return
        }

        self.init(targetObject: object)
    }

    public init?(targetObject object: [String: RPCValue]) {
        if case .string(let id)? = object["sessionID"] {
            self = .session(SessionID(rawValue: id))
            return
        }
        if case .string(let id)? = object["paneID"] {
            self = .pane(PaneID(rawValue: id))
            return
        }
        if case .string(let id)? = object["tabID"] {
            self = .tab(TabID(rawValue: id))
            return
        }
        if case .string(let id)? = object["workspaceID"] {
            self = .workspace(WorkspaceID(rawValue: id))
            return
        }
        if case .bool(true)? = object["focused"] {
            self = .focused
            return
        }

        guard case .string(let type)? = object["type"] ?? object["kind"] else {
            return nil
        }

        switch type {
        case "session":
            guard case .string(let id)? = object["id"] else { return nil }
            self = .session(SessionID(rawValue: id))
        case "pane":
            guard case .string(let id)? = object["id"] else { return nil }
            self = .pane(PaneID(rawValue: id))
        case "tab":
            guard case .string(let id)? = object["id"] else { return nil }
            self = .tab(TabID(rawValue: id))
        case "workspace":
            guard case .string(let id)? = object["id"] else { return nil }
            self = .workspace(WorkspaceID(rawValue: id))
        case "focused":
            self = .focused
        default:
            return nil
        }
    }
}

public struct ControlPlaneTerminalContext: Equatable, Sendable {
    public let workspaceID: WorkspaceID
    public let tabID: TabID?
    public let paneStackID: PaneStackID?
    public let paneID: PaneID
    public let sessionID: SessionID

    public init(
        workspaceID: WorkspaceID,
        tabID: TabID? = nil,
        paneStackID: PaneStackID? = nil,
        paneID: PaneID,
        sessionID: SessionID
    ) {
        self.workspaceID = workspaceID
        self.tabID = tabID
        self.paneStackID = paneStackID
        self.paneID = paneID
        self.sessionID = sessionID
    }

    public var rpcValue: RPCValue {
        .object(rpcObject)
    }

    public var rpcObject: [String: RPCValue] {
        [
            "workspaceID": .string(workspaceID.rawValue),
            "tabID": tabID.map { .string($0.rawValue) } ?? .null,
            "paneStackID": paneStackID.map { .string($0.rawValue) } ?? .null,
            "paneID": .string(paneID.rawValue),
            "sessionID": .string(sessionID.rawValue),
        ]
    }
}

public struct ControlPlaneActionResult: Equatable, Sendable {
    public let ok: Bool
    public let target: ControlPlaneTerminalContext?
    public let created: ControlPlaneTerminalContext?
    public let workspace: RPCValue?
    public let extra: [String: RPCValue]

    public init(
        ok: Bool = true,
        target: ControlPlaneTerminalContext? = nil,
        created: ControlPlaneTerminalContext? = nil,
        workspace: RPCValue? = nil,
        extra: [String: RPCValue] = [:]
    ) {
        self.ok = ok
        self.target = target
        self.created = created
        self.workspace = workspace
        self.extra = extra
    }

    public var rpcValue: RPCValue {
        var object = extra
        object["ok"] = .bool(ok)
        object["target"] = target?.rpcValue ?? .null
        object["created"] = created?.rpcValue ?? .null
        object["workspace"] = workspace ?? .null

        if let target {
            for (key, value) in target.rpcObject where object[key] == nil {
                object[key] = value
            }
        }

        return .object(object)
    }
}

public enum ControlPlaneHistoryScope: Equatable, Sendable {
    case activeWorkspace
    case pane(PaneID)
    case all

    public var rpcValue: RPCValue {
        switch self {
        case .activeWorkspace:
            return .object(["scope": .string("activeWorkspace")])
        case .pane(let paneID):
            return .object([
                "scope": .string("pane"),
                "paneID": .string(paneID.rawValue),
            ])
        case .all:
            return .object(["scope": .string("all")])
        }
    }

    public init?(rpcObject object: [String: RPCValue]) {
        if case .string(let paneID)? = object["paneID"] {
            self = .pane(PaneID(rawValue: paneID))
            return
        }

        guard case .string(let scope)? = object["scope"] ?? object["type"] else {
            self = .activeWorkspace
            return
        }

        switch scope {
        case "activeWorkspace", "current":
            self = .activeWorkspace
        case "all":
            self = .all
        case "pane":
            guard case .string(let paneID)? = object["id"] else {
                return nil
            }
            self = .pane(PaneID(rawValue: paneID))
        default:
            return nil
        }
    }
}

public struct ControlPlaneHistoryRequest: Equatable, Sendable {
    public let scope: ControlPlaneHistoryScope
    public let maxBytes: Int
    public let maxLines: Int

    public init(
        scope: ControlPlaneHistoryScope = .activeWorkspace,
        maxBytes: Int = PaneScrollbackSnapshot.defaultMaxBytes,
        maxLines: Int = PaneScrollbackSnapshot.defaultMaxLines
    ) {
        self.scope = scope
        self.maxBytes = max(0, maxBytes)
        self.maxLines = max(0, maxLines)
    }

    public init?(rpcValue: RPCValue?) {
        guard let rpcValue else {
            self.init()
            return
        }

        guard case .object(let object) = rpcValue else {
            return nil
        }

        guard let scope = ControlPlaneHistoryScope(rpcObject: object) else {
            return nil
        }

        self.init(
            scope: scope,
            maxBytes: object["maxBytes"]?.integerValue ?? PaneScrollbackSnapshot.defaultMaxBytes,
            maxLines: object["maxLines"]?.integerValue ?? PaneScrollbackSnapshot.defaultMaxLines
        )
    }

    public var rpcValue: RPCValue {
        var object: [String: RPCValue]
        if case .object(let scopeObject) = scope.rpcValue {
            object = scopeObject
        } else {
            object = [:]
        }
        object["maxBytes"] = .integer(maxBytes)
        object["maxLines"] = .integer(maxLines)
        return .object(object)
    }
}

public struct ControlPlanePaneHistoryItem: Equatable, Sendable {
    public let workspaceID: WorkspaceID
    public let workspaceName: String
    public let tabID: TabID
    public let tabTitle: String
    public let paneStackID: PaneStackID?
    public let paneID: PaneID
    public let paneTitle: String
    public let sessionID: SessionID
    public let workingDirectory: String?
    public let text: String
    public let lineCount: Int
    public let byteCount: Int
    public let truncated: Bool
    public let unavailable: String?

    public init(
        workspaceID: WorkspaceID,
        workspaceName: String,
        tabID: TabID,
        tabTitle: String,
        paneStackID: PaneStackID?,
        paneID: PaneID,
        paneTitle: String,
        sessionID: SessionID,
        workingDirectory: String?,
        text: String,
        truncated: Bool,
        unavailable: String? = nil
    ) {
        self.workspaceID = workspaceID
        self.workspaceName = workspaceName
        self.tabID = tabID
        self.tabTitle = tabTitle
        self.paneStackID = paneStackID
        self.paneID = paneID
        self.paneTitle = paneTitle
        self.sessionID = sessionID
        self.workingDirectory = workingDirectory
        self.text = text
        self.lineCount = text.isEmpty ? 0 : text.split(separator: "\n", omittingEmptySubsequences: false).count
        self.byteCount = text.utf8.count
        self.truncated = truncated
        self.unavailable = unavailable
    }

    public var rpcValue: RPCValue {
        .object([
            "workspaceID": .string(workspaceID.rawValue),
            "workspaceName": .string(workspaceName),
            "tabID": .string(tabID.rawValue),
            "tabTitle": .string(tabTitle),
            "paneStackID": paneStackID.map { .string($0.rawValue) } ?? .null,
            "paneID": .string(paneID.rawValue),
            "paneTitle": .string(paneTitle),
            "sessionID": .string(sessionID.rawValue),
            "workingDirectory": workingDirectory.map(RPCValue.string) ?? .null,
            "text": .string(text),
            "lineCount": .integer(lineCount),
            "byteCount": .integer(byteCount),
            "truncated": .bool(truncated),
            "unavailable": unavailable.map(RPCValue.string) ?? .null,
        ])
    }
}

public struct ControlPlaneHistoryResponse: Equatable, Sendable {
    public let scope: ControlPlaneHistoryScope
    public let maxBytes: Int
    public let maxLines: Int
    public let items: [ControlPlanePaneHistoryItem]

    public init(
        scope: ControlPlaneHistoryScope,
        maxBytes: Int,
        maxLines: Int,
        items: [ControlPlanePaneHistoryItem]
    ) {
        self.scope = scope
        self.maxBytes = maxBytes
        self.maxLines = maxLines
        self.items = items
    }

    public var rpcValue: RPCValue {
        var scopeObject: [String: RPCValue]
        if case .object(let object) = scope.rpcValue {
            scopeObject = object
        } else {
            scopeObject = [:]
        }
        scopeObject["maxBytes"] = .integer(maxBytes)
        scopeObject["maxLines"] = .integer(maxLines)

        return .object([
            "scope": .object(scopeObject),
            "maxBytes": .integer(maxBytes),
            "maxLines": .integer(maxLines),
            "items": .array(items.map(\.rpcValue)),
        ])
    }
}

private extension RPCValue {
    var integerValue: Int? {
        switch self {
        case .number(let value):
            guard value.isFinite else { return nil }
            return Int(value)
        default:
            return nil
        }
    }
}
