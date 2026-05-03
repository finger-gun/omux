import Foundation

public struct JSONRPCRequest: Codable, Equatable, Sendable {
    public let jsonrpc: String
    public let id: String?
    public let method: String
    public let params: RPCValue?

    public init(id: String? = UUID().uuidString, method: String, params: RPCValue? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct JSONRPCError: Error, Codable, Equatable, Sendable {
    public let code: Int
    public let message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
}

public struct JSONRPCResponse: Codable, Equatable, Sendable {
    public let jsonrpc: String
    public let id: String?
    public let result: RPCValue?
    public let error: JSONRPCError?

    public init(id: String?, result: RPCValue? = nil, error: JSONRPCError? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
        self.error = error
    }
}

public enum ControlMethod: String, Sendable {
    case openWorkspace = "workspace.open"
    case listWorkspaces = "workspace.list"
    case createTab = "workspace.createTab"
    case splitPane = "workspace.splitPane"
    case createPaneTab = "paneStack.createTab"
    case focusPaneTab = "paneStack.focusTab"
    case focusNextPaneTab = "paneStack.focusNextTab"
    case focusPreviousPaneTab = "paneStack.focusPreviousTab"
    case closePaneTab = "paneStack.closeTab"
    case focusNextPane = "pane.focusNext"
    case focusPreviousPane = "pane.focusPrevious"
    case focusSession = "session.focus"
    case runCommand = "session.runCommand"
    case sendText = "session.sendText"
    case listSessions = "session.list"
    case listPanes = "pane.list"
    case terminalHistory = "terminal.history"
    case sendNotification = "notification.send"
    case restoreLayout = "workspace.restore"
    case configDoctor = "config.doctor"
    case configReload = "config.reload"
    case terminalEvents = "terminal.events"
}
