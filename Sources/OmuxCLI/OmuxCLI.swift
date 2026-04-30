import Foundation
import OmuxControlPlane
import OmuxConfig
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
            case "config":
                return runConfigCommand(arguments: Array(commandArguments.dropFirst()))
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
      omux config doctor
      omux config reload
      omux config init
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

    private func runConfigCommand(arguments: [String]) -> Int32 {
        guard let subcommand = arguments.first else {
            writeLine("usage: omux config <doctor|reload|init>")
            return 1
        }

        do {
            switch subcommand {
            case "doctor":
                let response = try client.request(method: .configDoctor)
                guard response.error == nil else {
                    writeLine("omux error: \(response.error!.message)")
                    return 1
                }
                let diagnostics = response.result?.arrayValue?.compactMap(OmuxConfigDiagnostic.init(rpcValue:)) ?? []
                return printDiagnosticsAndReturnCode(diagnostics)
            case "reload":
                let response = try client.request(method: .configReload)
                guard response.error == nil else {
                    writeLine("omux error: \(response.error!.message)")
                    return 1
                }
                let object = response.result?.objectValue ?? [:]
                let diagnostics = object["diagnostics"]?.arrayValue?.compactMap(OmuxConfigDiagnostic.init(rpcValue:)) ?? []
                let exitCode = printDiagnosticsAndReturnCode(diagnostics)
                if let applied = object["applied"]?.boolValue {
                    writeLine(applied ? "OpenMUX config reloaded." : "OpenMUX config unchanged.")
                }
                return exitCode
            case "init":
                let configURL = OmuxConfigPaths.configFileURL
                if FileManager.default.fileExists(atPath: configURL.path) {
                    writeLine("omux error: \(configURL.path) already exists")
                    return 1
                }

                try FileManager.default.createDirectory(
                    at: OmuxConfigPaths.baseDirectoryURL,
                    withIntermediateDirectories: true
                )
                try OmuxConfigTemplate.starter().write(to: configURL, atomically: true, encoding: .utf8)
                writeLine("Wrote \(configURL.path)")
                return 0
            default:
                writeLine("usage: omux config <doctor|reload|init>")
                return 1
            }
        } catch {
            writeLine("omux error: \(error)")
            return 1
        }
    }

    private func printDiagnosticsAndReturnCode(_ diagnostics: [OmuxConfigDiagnostic]) -> Int32 {
        if diagnostics.isEmpty {
            writeLine("No diagnostics.")
            return 0
        }

        for diagnostic in diagnostics {
            let location: String
            if let filePath = diagnostic.filePath, let line = diagnostic.line {
                location = " \(filePath):\(line)"
            } else if let filePath = diagnostic.filePath {
                location = " \(filePath)"
            } else {
                location = ""
            }
            writeLine("[\(diagnostic.severity.rawValue)]\(location) \(diagnostic.message)")
        }

        return diagnostics.contains(where: { $0.severity.isError }) ? 1 : 0
    }
}

private extension RPCValue {
    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }

    var intValue: Int? {
        if case .number(let value) = self {
            return Int(exactly: value)
        }
        return nil
    }

    var objectValue: [String: RPCValue]? {
        if case .object(let value) = self {
            return value
        }
        return nil
    }

    var arrayValue: [RPCValue]? {
        if case .array(let value) = self {
            return value
        }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let value) = self {
            return value
        }
        return nil
    }
}

private extension OmuxConfigDiagnostic {
    init?(rpcValue: RPCValue) {
        guard case .object(let object) = rpcValue,
              let severityRawValue = object["severity"]?.stringValue,
              let severity = OmuxConfigDiagnosticSeverity(rawValue: severityRawValue),
              let message = object["message"]?.stringValue
        else {
            return nil
        }

        let filePath = object["filePath"]?.stringValue
        let line = object["line"]?.intValue
        self.init(severity: severity, message: message, filePath: filePath, line: line)
    }
}
