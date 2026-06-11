import Foundation
import OmuxConfig
import OmuxCore

enum WorkspaceRootPathCalculator {
    static func standardizedPath(_ path: String?) -> String? {
        guard let path else {
            return nil
        }
        let resolvedPath = OmuxWorkspacePathResolver.resolve(path) ?? path
        let trimmedPath = resolvedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPath.isEmpty == false else {
            return nil
        }
        return URL(fileURLWithPath: trimmedPath, isDirectory: true).standardizedFileURL.path
    }

    static func terminalPaths(in workspace: Workspace) -> [String] {
        let panes = workspace.tabs.flatMap(\.panes) + workspace.floatingPaneModals.flatMap(\.panes)
        var seen = Set<String>()
        return panes.compactMap { pane in
            standardizedPath(pane.terminalState.reportedWorkingDirectory ?? pane.terminalSession?.workingDirectory)
        }
        .filter { seen.insert($0).inserted }
    }

    static func automaticRootPath(for workspace: Workspace) -> String? {
        highestCommonPath(for: terminalPaths(in: workspace))
    }

    static func highestCommonPath(for paths: [String]) -> String? {
        let standardizedPaths = paths.compactMap(standardizedPath)
        guard let firstPath = standardizedPaths.first else {
            return nil
        }

        var commonComponents = URL(fileURLWithPath: firstPath, isDirectory: true)
            .standardizedFileURL
            .pathComponents
        for path in standardizedPaths.dropFirst() {
            let components = URL(fileURLWithPath: path, isDirectory: true)
                .standardizedFileURL
                .pathComponents
            var sharedPrefixCount = 0
            while sharedPrefixCount < commonComponents.count,
                  sharedPrefixCount < components.count,
                  commonComponents[sharedPrefixCount] == components[sharedPrefixCount] {
                sharedPrefixCount += 1
            }
            commonComponents = Array(commonComponents.prefix(sharedPrefixCount))
            if commonComponents.isEmpty {
                return nil
            }
        }

        return NSString.path(withComponents: commonComponents)
    }

    static func contains(path: String, withinRoot rootPath: String) -> Bool {
        guard let candidatePath = standardizedPath(path),
              let standardizedRootPath = standardizedPath(rootPath)
        else {
            return false
        }
        return candidatePath == standardizedRootPath || candidatePath.hasPrefix(standardizedRootPath + "/")
    }
}
