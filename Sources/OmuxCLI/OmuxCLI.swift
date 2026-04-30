import Foundation
import OmuxControlPlane
import OmuxCore

public struct OmuxCLICommand {
    private let client: OmuxControlClient
    private let writeLine: (String) -> Void

    public init(
        client: OmuxControlClient = OmuxControlClient(),
        writeLine: @escaping (String) -> Void = { print($0) }
    ) {
        self.client = client
        self.writeLine = writeLine
    }

    @discardableResult
    public func run(arguments: [String]) -> Int32 {
        let commandArguments = Array(arguments.dropFirst())
        guard let command = commandArguments.first else {
            writeLine(Self.usage)
            return 1
        }

        do {
            switch command {
            case "list":
                let response = try client.request(method: .listWorkspaces)
                writeLine(response.result?.prettyPrinted ?? "[]")
            case "tab":
                let response = try client.request(method: .createTab)
                writeLine(response.result?.prettyPrinted ?? "")
            case "split":
                let axis = splitAxis(from: commandArguments.dropFirst())
                let response = try client.request(
                    method: .splitPane,
                    params: .object(["axis": .string(axis.rawValue)])
                )
                writeLine(response.result?.prettyPrinted ?? "")
            case "pane-tab":
                let response = try client.request(method: .createPaneTab)
                writeLine(response.result?.prettyPrinted ?? "")
            case "pane-tab-focus":
                guard commandArguments.count >= 2 else {
                    writeLine("usage: omux pane-tab-focus <pane-id>")
                    return 1
                }

                let response = try client.request(
                    method: .focusPaneTab,
                    params: .object(["paneID": .string(commandArguments[1])])
                )
                writeLine(response.result?.prettyPrinted ?? "")
            case "pane-tab-close":
                let params: RPCValue?
                if commandArguments.count >= 2 {
                    params = .object(["paneID": .string(commandArguments[1])])
                } else {
                    params = nil
                }

                let response = try client.request(method: .closePaneTab, params: params)
                writeLine(response.result?.prettyPrinted ?? "")
            case "open":
                guard commandArguments.count >= 2 else {
                    writeLine("usage: omux open <path>")
                    return 1
                }

                let path = commandArguments[1]
                let response = try client.request(
                    method: .openWorkspace,
                    params: .object(["path": .string(path)])
                )
                writeLine(response.result?.prettyPrinted ?? "")
            case "focus":
                guard commandArguments.count >= 2 else {
                    writeLine("usage: omux focus <session-id>")
                    return 1
                }

                let response = try client.request(
                    method: .focusSession,
                    params: .object(["sessionID": .string(commandArguments[1])])
                )
                writeLine(response.result?.prettyPrinted ?? "")
            case "run":
                guard commandArguments.count >= 3 else {
                    writeLine("usage: omux run <session-id> <command>")
                    return 1
                }

                let sessionID = commandArguments[1]
                let command = commandArguments.dropFirst(2).joined(separator: " ")
                let response = try client.request(
                    method: .runCommand,
                    params: .object([
                        "sessionID": .string(sessionID),
                        "command": .string(command),
                    ])
                )
                writeLine(response.result?.prettyPrinted ?? "")
            case "notify":
                guard commandArguments.count >= 2 else {
                    writeLine("usage: omux notify <title> [body]")
                    return 1
                }

                let body = commandArguments.dropFirst(2).joined(separator: " ")
                let response = try client.request(
                    method: .sendNotification,
                    params: .object([
                        "title": .string(commandArguments[1]),
                        "body": .string(body),
                    ])
                )
                writeLine(response.result?.prettyPrinted ?? "")
            case "restore":
                guard commandArguments.count >= 2 else {
                    writeLine("usage: omux restore <workspace-id>")
                    return 1
                }

                let response = try client.request(
                    method: .restoreLayout,
                    params: .object(["workspaceID": .string(commandArguments[1])])
                )
                writeLine(response.result?.prettyPrinted ?? "")
            case "help", "--help", "-h":
                writeLine(Self.usage)
            default:
                writeLine(Self.usage)
                return 1
            }
        } catch {
            writeLine("omux error: \(error)")
            return 1
        }

        return 0
    }

    public static let usage = """
    OpenMUX CLI

    Commands:
      omux list
      omux open <path>
      omux tab
      omux split [right|down]
      omux pane-tab
      omux pane-tab-focus <pane-id>
      omux pane-tab-close [pane-id]
      omux focus <session-id>
      omux run <session-id> <command>
      omux notify <title> [body]
      omux restore <workspace-id>
    """

    private func splitAxis(from arguments: ArraySlice<String>) -> PaneSplitAxis {
        guard let value = arguments.first?.lowercased() else {
            return .columns
        }

        switch value {
        case "down", "vertical":
            return .rows
        default:
            return .columns
        }
    }
}
