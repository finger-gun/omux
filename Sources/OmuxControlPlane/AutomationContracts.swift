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
