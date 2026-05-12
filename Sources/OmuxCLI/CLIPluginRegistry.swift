import Foundation
import OmuxConfig
import OmuxMarkdownPreviewPlugin

struct OmuxCLIPlugin: Equatable {
    let commandName: String
    let executableURL: URL
}

struct OmuxBundledCLIPlugin: Equatable {
    let commandName: String
    let displayPath: String
}

enum OmuxRegisteredCLIPlugin: Equatable {
    case bundled(OmuxBundledCLIPlugin)
    case external(OmuxCLIPlugin)

    var commandName: String {
        switch self {
        case .bundled(let plugin):
            return plugin.commandName
        case .external(let plugin):
            return plugin.commandName
        }
    }

    var displayPath: String {
        switch self {
        case .bundled(let plugin):
            return plugin.displayPath
        case .external(let plugin):
            return plugin.executableURL.path
        }
    }
}

struct OmuxCLIPluginRegistry {
    let pluginsDirectoryURL: URL
    let fileManager: FileManager
    let bundledPlugins: [OmuxBundledCLIPlugin]

    init(
        pluginsDirectoryURL: URL = OmuxConfigPaths.pluginsDirectoryURL,
        fileManager: FileManager = .default,
        bundledPlugins: [OmuxBundledCLIPlugin] = [
            OmuxBundledCLIPlugin(
                commandName: OmuxMarkdownPreviewPlugin.commandName,
                displayPath: OmuxMarkdownPreviewPlugin.commandDisplayPath
            ),
        ]
    ) {
        self.pluginsDirectoryURL = pluginsDirectoryURL
        self.fileManager = fileManager
        self.bundledPlugins = bundledPlugins
    }

    func registration(named commandName: String) -> OmuxRegisteredCLIPlugin? {
        if let bundledPlugin = bundledPlugins.first(where: { $0.commandName == commandName }) {
            return .bundled(bundledPlugin)
        }

        return externalPlugin(named: commandName).map(OmuxRegisteredCLIPlugin.external)
    }

    func plugins() -> [OmuxRegisteredCLIPlugin] {
        let bundled = bundledPlugins.map(OmuxRegisteredCLIPlugin.bundled)
        let external = externalPlugins()
            .filter { externalPlugin in
                bundledPlugins.contains(where: { $0.commandName == externalPlugin.commandName }) == false
            }
            .map(OmuxRegisteredCLIPlugin.external)

        return (bundled + external).sorted { $0.commandName < $1.commandName }
    }

    private func externalPlugin(named commandName: String) -> OmuxCLIPlugin? {
        guard Self.isValidCommandName(commandName) else {
            return nil
        }

        let directExecutableURL = pluginsDirectoryURL.appendingPathComponent(commandName, isDirectory: false)
        if isExecutableFile(directExecutableURL) {
            return OmuxCLIPlugin(commandName: commandName, executableURL: directExecutableURL)
        }

        let directoryExecutableURL = pluginsDirectoryURL
            .appendingPathComponent(commandName, isDirectory: true)
            .appendingPathComponent("plugin", isDirectory: false)
        if isExecutableFile(directoryExecutableURL) {
            return OmuxCLIPlugin(commandName: commandName, executableURL: directoryExecutableURL)
        }

        return nil
    }

    private func externalPlugins() -> [OmuxCLIPlugin] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: pluginsDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isExecutableKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return entries
            .compactMap { externalPlugin(named: $0.lastPathComponent) }
            .sorted { $0.commandName < $1.commandName }
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

    static func isValidCommandName(_ value: String) -> Bool {
        guard value.isEmpty == false,
              value.first != "-"
        else {
            return false
        }

        return value.allSatisfy { character in
            character.isLetter || character.isNumber || character == "-" || character == "_"
        }
    }
}

struct OmuxCLIPluginRunner {
    func run(
        plugin: OmuxCLIPlugin,
        arguments: [String],
        environment: [String: String]
    ) throws -> Int32 {
        let process = Process()
        process.executableURL = plugin.executableURL
        process.arguments = arguments
        var pluginEnvironment = environment.merging([
            "OMUX_PLUGIN_COMMAND": plugin.commandName,
            "OMUX_PLUGIN_EXECUTABLE": plugin.executableURL.path,
            "OMUX_PLUGINS_DIR": plugin.executableURL.deletingLastPathComponent().path,
        ]) { current, _ in current }
        if pluginEnvironment["OMUX_CLI"] == nil,
           let executableURL = Bundle.main.executableURL,
           FileManager.default.isExecutableFile(atPath: executableURL.path) {
            pluginEnvironment["OMUX_CLI"] = executableURL.path
        }
        process.environment = pluginEnvironment

        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
