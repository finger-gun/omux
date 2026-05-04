import Foundation
import OmuxCore

public enum ControlPlaneTerminalEventName: String, Codable, CaseIterable, Sendable {
    case workingDirectoryChanged = "terminal.cwdChanged"
    case titleChanged = "terminal.titleChanged"
    case tabTitleChanged = "terminal.tabTitleChanged"
    case openURL = "terminal.openURL"
    case desktopNotification = "terminal.desktopNotification"
    case bell = "terminal.bell"
    case inputSent = "terminal.inputSent"
    case commandFinished = "terminal.commandFinished"
    case progressReported = "terminal.progressReported"
    case childExited = "terminal.childExited"
    case rendererHealthChanged = "terminal.rendererHealthChanged"
}

public enum ControlPlaneActionEventName: String, Codable, CaseIterable, Sendable {
    case workspaceOpened = "workspace.opened"
    case tabCreated = "tab.created"
    case paneSplit = "pane.split"
    case paneTabCreated = "paneTab.created"
    case paneTabFocused = "paneTab.focused"
    case paneTabClosed = "paneTab.closed"
    case sessionFocused = "session.focused"
    case commandStarted = "command.started"
    case notificationRaised = "notification.raised"
    case workspaceRestored = "workspace.restored"
}

public struct ControlPlaneEvent: Equatable, Codable, Sendable {
    public let name: String
    public let workspaceID: WorkspaceID?
    public let tabID: TabID?
    public let paneID: PaneID?
    public let sessionID: SessionID?
    public let payload: OmuxValue

    public init(
        name: String,
        workspaceID: WorkspaceID? = nil,
        tabID: TabID? = nil,
        paneID: PaneID? = nil,
        sessionID: SessionID? = nil,
        payload: OmuxValue = .object([:])
    ) {
        self.name = name
        self.workspaceID = workspaceID
        self.tabID = tabID
        self.paneID = paneID
        self.sessionID = sessionID
        self.payload = payload
    }

    public init(
        name: ControlPlaneTerminalEventName,
        workspaceID: WorkspaceID? = nil,
        tabID: TabID? = nil,
        paneID: PaneID? = nil,
        sessionID: SessionID? = nil,
        payload: OmuxValue = .object([:])
    ) {
        self.init(
            name: name.rawValue,
            workspaceID: workspaceID,
            tabID: tabID,
            paneID: paneID,
            sessionID: sessionID,
            payload: payload
        )
    }

    public init(
        name: ControlPlaneActionEventName,
        workspaceID: WorkspaceID? = nil,
        tabID: TabID? = nil,
        paneID: PaneID? = nil,
        sessionID: SessionID? = nil,
        payload: OmuxValue = .object([:])
    ) {
        self.init(
            name: name.rawValue,
            workspaceID: workspaceID,
            tabID: tabID,
            paneID: paneID,
            sessionID: sessionID,
            payload: payload
        )
    }

    public var rpcValue: RPCValue {
        .object([
            "name": .string(name),
            "workspaceID": workspaceID.map { .string($0.rawValue) } ?? .null,
            "tabID": tabID.map { .string($0.rawValue) } ?? .null,
            "paneID": paneID.map { .string($0.rawValue) } ?? .null,
            "sessionID": sessionID.map { .string($0.rawValue) } ?? .null,
            "payload": RPCValue(payload),
        ])
    }
}

public typealias ControlPlaneTerminalEvent = ControlPlaneEvent
