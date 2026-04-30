import Foundation
import OmuxControlPlane

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
      omux focus <session-id>
      omux notify <title> [body]
      omux restore <workspace-id>
    """
}
