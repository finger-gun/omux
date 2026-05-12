import Foundation
import OmuxConfig

enum PluginMenuContributionTarget: Equatable {
    case plugin(command: String, arguments: [String], executableURL: URL)
    case builtin(String)
}

struct PluginMenuContribution: Equatable {
    let pluginID: String
    let location: String
    let title: String
    let target: PluginMenuContributionTarget
}

struct PluginMenuContributionDiagnostic: Equatable {
    let pluginID: String
    let message: String
}

struct PluginMenuContributionResult: Equatable {
    let contributions: [PluginMenuContribution]
    let diagnostics: [PluginMenuContributionDiagnostic]
}

struct PluginMenuContributionRegistry {
    let pluginsDirectoryURL: URL
    let fileManager: FileManager

    init(
        pluginsDirectoryURL: URL = OmuxConfigPaths.pluginsDirectoryURL,
        fileManager: FileManager = .default
    ) {
        self.pluginsDirectoryURL = pluginsDirectoryURL
        self.fileManager = fileManager
    }

    func contributions() -> [PluginMenuContribution] {
        load().contributions
    }

    func load() -> PluginMenuContributionResult {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: pluginsDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return PluginMenuContributionResult(contributions: [], diagnostics: [])
        }

        let results: [PluginMenuContributionResult] = entries
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { contributions(fromPluginDirectory: $0) }
        let loadedContributions = results.flatMap { $0.contributions }
            .sorted {
                if $0.location != $1.location { return $0.location < $1.location }
                if $0.title != $1.title { return $0.title < $1.title }
                return $0.pluginID < $1.pluginID
            }
        return PluginMenuContributionResult(
            contributions: loadedContributions,
            diagnostics: results.flatMap { $0.diagnostics }
        )
    }

    private func contributions(fromPluginDirectory pluginDirectoryURL: URL) -> PluginMenuContributionResult {
        let manifestURL = pluginDirectoryURL.appendingPathComponent("omux-plugin.toml")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return PluginMenuContributionResult(contributions: [], diagnostics: [])
        }
        let parseResult = OmuxTOMLParser.parse(fileAt: manifestURL)
        guard let document = parseResult.document, parseResult.diagnostics.isEmpty else {
            return PluginMenuContributionResult(contributions: [], diagnostics: [
                PluginMenuContributionDiagnostic(pluginID: pluginDirectoryURL.lastPathComponent, message: "invalid plugin manifest")
            ])
        }

        let pluginID = document.value(for: "id")?.stringValue ?? pluginDirectoryURL.lastPathComponent
        let commandName = document.value(in: "plugin", for: "command")?.stringValue ?? pluginID
        let entrypoint = document.value(in: "plugin", for: "entrypoint")?.stringValue ?? "plugin"
        let executableURL = pluginDirectoryURL.appendingPathComponent(entrypoint)
        let menuTables = document.tableNames
            .filter { $0.hasPrefix("menu.") }
            .sorted()

        var diagnostics: [PluginMenuContributionDiagnostic] = []
        let contributions = menuTables.compactMap { tableName -> PluginMenuContribution? in
            let location = document.value(in: tableName, for: "location")?.stringValue
                ?? Self.location(from: tableName)
            guard let title = document.value(in: tableName, for: "title")?.stringValue,
                  title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                  location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            else {
                diagnostics.append(PluginMenuContributionDiagnostic(pluginID: pluginID, message: "invalid menu item in \(tableName)"))
                return nil
            }

            if let builtin = document.value(in: tableName, for: "builtin")?.stringValue {
                guard Self.allowedBuiltins.contains(builtin) else {
                    diagnostics.append(PluginMenuContributionDiagnostic(pluginID: pluginID, message: "unsupported builtin target '\(builtin)' in \(tableName)"))
                    return nil
                }
                return PluginMenuContribution(pluginID: pluginID, location: location, title: title, target: .builtin(builtin))
            }

            let command = document.value(in: tableName, for: "command")?.stringValue ?? commandName
            guard command == commandName else {
                diagnostics.append(PluginMenuContributionDiagnostic(pluginID: pluginID, message: "menu command '\(command)' does not match plugin command '\(commandName)'"))
                return nil
            }
            guard isExecutableFile(executableURL) else {
                diagnostics.append(PluginMenuContributionDiagnostic(pluginID: pluginID, message: "menu command executable is missing or not executable"))
                return nil
            }
            let arguments = stringArray(document.value(in: tableName, for: "arguments")) ?? []
            return PluginMenuContribution(
                pluginID: pluginID,
                location: location,
                title: title,
                target: .plugin(command: command, arguments: arguments, executableURL: executableURL)
            )
        }
        return PluginMenuContributionResult(contributions: contributions, diagnostics: diagnostics)
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

    private func stringArray(_ value: OmuxTOMLValue?) -> [String]? {
        guard case .array(let values) = value else { return nil }
        return values.compactMap(\.stringValue)
    }

    private static let allowedBuiltins = Set(["config.open", "config.reload"])

    private static func location(from tableName: String) -> String {
        let parts = tableName.split(separator: ".")
        guard parts.count >= 2 else {
            return "Plugins"
        }
        return parts[1]
            .split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
