import Foundation
import OmuxConfig
import OmuxCore

enum ExtensionPaneActionError: Error, CustomStringConvertible, Equatable {
    case invalidRequest(String)
    case paneNotFound
    case pluginMismatch(expected: String, actual: String)
    case pluginNotFound(String)
    case pluginFailed(status: Int32, output: String)

    var description: String {
        switch self {
        case .invalidRequest(let message):
            return message
        case .paneNotFound:
            return "extension pane not found"
        case .pluginMismatch(let expected, let actual):
            return "extension pane is owned by '\(expected)', not '\(actual)'"
        case .pluginNotFound(let pluginID):
            return "plugin '\(pluginID)' is not installed"
        case .pluginFailed(let status, let output):
            let suffix = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return suffix.isEmpty ? "plugin action failed with status \(status)" : "plugin action failed with status \(status): \(suffix)"
        }
    }
}

final class ExtensionPaneActionService: @unchecked Sendable {
    typealias PluginProcessRunner = @Sendable (_ executableURL: URL, _ commandName: String, _ request: ExtensionPaneActionRequest) throws -> ExtensionPaneActionResponse

    private let controller: WorkspaceController
    private let pluginsDirectoryURL: URL
    private let fileManager: FileManager
    private let runner: PluginProcessRunner

    init(
        controller: WorkspaceController,
        pluginsDirectoryURL: URL = OmuxConfigPaths.pluginsDirectoryURL,
        fileManager: FileManager = .default,
        runner: PluginProcessRunner? = nil
    ) {
        self.controller = controller
        self.pluginsDirectoryURL = pluginsDirectoryURL
        self.fileManager = fileManager
        self.runner = runner ?? Self.runPluginAction
    }

    func dispatch(_ request: ExtensionPaneActionRequest) throws -> ExtensionPaneActionResponse {
        if let validationError = request.validationError {
            throw ExtensionPaneActionError.invalidRequest(validationError)
        }
        if ["run-shell", "shell", "execute"].contains(request.action) {
            throw ExtensionPaneActionError.invalidRequest("unsupported extension pane action")
        }

        guard let pane = controller.allWorkspaces().lazy.flatMap({ $0.tabs.flatMap(\.panes) }).first(where: { $0.id == request.paneID }),
              let descriptor = pane.extensionPane
        else {
            throw ExtensionPaneActionError.paneNotFound
        }

        guard descriptor.pluginID == request.pluginID else {
            throw ExtensionPaneActionError.pluginMismatch(expected: descriptor.pluginID, actual: request.pluginID)
        }

        guard descriptor.actionsEnabled else {
            throw ExtensionPaneActionError.invalidRequest("extension pane actions are not enabled")
        }

        guard let plugin = externalPlugin(named: request.pluginID) else {
            throw ExtensionPaneActionError.pluginNotFound(request.pluginID)
        }

        return try runner(plugin.executableURL, plugin.commandName, request)
    }

    private func externalPlugin(named commandName: String) -> (commandName: String, executableURL: URL)? {
        guard Self.isValidCommandName(commandName) else {
            return nil
        }

        let directExecutableURL = pluginsDirectoryURL.appendingPathComponent(commandName, isDirectory: false)
        if isExecutableFile(directExecutableURL) {
            return (commandName, directExecutableURL)
        }

        let directoryExecutableURL = pluginsDirectoryURL
            .appendingPathComponent(commandName, isDirectory: true)
            .appendingPathComponent("plugin", isDirectory: false)
        if isExecutableFile(directoryExecutableURL) {
            return (commandName, directoryExecutableURL)
        }

        return nil
    }

    private func isExecutableFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue == false
        else {
            return false
        }
        return fileManager.isExecutableFile(atPath: url.path)
    }

    private static func isValidCommandName(_ value: String) -> Bool {
        guard value.isEmpty == false,
              value.first != "-"
        else {
            return false
        }

        return value.allSatisfy { character in
            character.isLetter || character.isNumber || character == "-" || character == "_"
        }
    }

    private static func runPluginAction(
        executableURL: URL,
        commandName: String,
        request: ExtensionPaneActionRequest
    ) throws -> ExtensionPaneActionResponse {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["__omux_action"]
        process.environment = ProcessInfo.processInfo.environment.merging(pluginEnvironment(
            commandName: commandName,
            executableURL: executableURL,
            request: request
        )) { current, _ in current }

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        stdin.fileHandleForWriting.write(try JSONEncoder().encode(request))
        try stdin.fileHandleForWriting.close()
        process.waitUntilExit()

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw ExtensionPaneActionError.pluginFailed(
                status: process.terminationStatus,
                output: errorOutput.isEmpty ? output : errorOutput
            )
        }

        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedOutput.isEmpty {
            return ExtensionPaneActionResponse(success: true)
        }

        return try JSONDecoder().decode(ExtensionPaneActionResponse.self, from: Data(trimmedOutput.utf8))
    }

    private static func pluginEnvironment(
        commandName: String,
        executableURL: URL,
        request: ExtensionPaneActionRequest
    ) -> [String: String] {
        var environment: [String: String] = [
            "OMUX_PLUGIN_COMMAND": commandName,
            "OMUX_PLUGIN_EXECUTABLE": executableURL.path,
            "OMUX_PLUGINS_DIR": executableURL.deletingLastPathComponent().path,
            "OMUX_EXTENSION_PANE_ID": request.paneID.rawValue,
            "OMUX_EXTENSION_PANE_ACTION": request.action,
        ]
        let existingPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = [
            existingPath,
            "\(NSHomeDirectory())/.local/bin",
            "\(NSHomeDirectory())/bin",
            "/Applications/OpenMUX.app/Contents/MacOS",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
        ].joined(separator: ":")
        if let bundledCLIURL = bundledCLIURL() {
            environment["OMUX_CLI"] = bundledCLIURL.path
        }
        return environment
    }

    private static func bundledCLIURL() -> URL? {
        let bundleURL = Bundle.main.bundleURL
        let candidates = [
            bundleURL.appendingPathComponent("Contents/MacOS/omux", isDirectory: false),
            URL(fileURLWithPath: "/Applications/OpenMUX.app/Contents/MacOS/omux", isDirectory: false),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
