import Foundation
import OmuxCore

public enum ControlPlaneTerminalEventName: String, Codable, CaseIterable, Sendable {
    case workingDirectoryChanged = "terminal.cwdChanged"
    case titleChanged = "terminal.titleChanged"
    case tabTitleChanged = "terminal.tabTitleChanged"
    case openURL = "terminal.openURL"
    case desktopNotification = "terminal.desktopNotification"
    case bell = "terminal.bell"
    case commandFinished = "terminal.commandFinished"
    case progressReported = "terminal.progressReported"
    case childExited = "terminal.childExited"
    case rendererHealthChanged = "terminal.rendererHealthChanged"
}

public struct ControlPlaneTerminalEvent: Equatable, Codable, Sendable {
    public let name: ControlPlaneTerminalEventName
    public let workspaceID: WorkspaceID?
    public let tabID: TabID?
    public let paneID: PaneID
    public let sessionID: SessionID
    public let payload: OmuxValue

    public init(
        name: ControlPlaneTerminalEventName,
        workspaceID: WorkspaceID? = nil,
        tabID: TabID? = nil,
        paneID: PaneID,
        sessionID: SessionID,
        payload: OmuxValue
    ) {
        self.name = name
        self.workspaceID = workspaceID
        self.tabID = tabID
        self.paneID = paneID
        self.sessionID = sessionID
        self.payload = payload
    }

    public var rpcValue: RPCValue {
        .object([
            "name": .string(name.rawValue),
            "workspaceID": workspaceID.map { .string($0.rawValue) } ?? .null,
            "tabID": tabID.map { .string($0.rawValue) } ?? .null,
            "paneID": .string(paneID.rawValue),
            "sessionID": .string(sessionID.rawValue),
            "payload": RPCValue(payload),
        ])
    }
}
