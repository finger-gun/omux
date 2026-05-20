import Foundation
import OmuxConfig
import OmuxCore

struct WorkspaceShellEnvironment {
    var isolateShellHistory: Bool
    var stateDirectoryURL: URL
    var fileManager: FileManager

    init(
        isolateShellHistory: Bool = OmuxConfigWorkspace.defaultIsolateShellHistory,
        stateDirectoryURL: URL = OmuxConfigPaths.baseDirectoryURL.appendingPathComponent("state", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.isolateShellHistory = isolateShellHistory
        self.stateDirectoryURL = stateDirectoryURL
        self.fileManager = fileManager
    }

    func applyingWorkspaceContext(
        to session: SessionDescriptor,
        workspaceID: WorkspaceID,
        workspaceRootPath: String
    ) -> SessionDescriptor {
        let historyPath = historyFileURL(for: workspaceID).path
        var environment = session.environment
        environment[OpenMUXWorkspaceEnvironment.workspaceIDKey] = workspaceID.rawValue
        environment[OpenMUXWorkspaceEnvironment.workspaceRootKey] = workspaceRootPath
        environment[OpenMUXWorkspaceEnvironment.workspaceHistoryKey] = historyPath
        if isolateShellHistory {
            environment[OpenMUXWorkspaceEnvironment.shellHistoryFileKey] = historyPath
        }

        return SessionDescriptor(
            id: session.id,
            shell: session.shell,
            workingDirectory: session.workingDirectory,
            environment: environment
        )
    }

    func prepareHistoryStorage(for workspaceID: WorkspaceID) {
        guard isolateShellHistory else {
            return
        }
        try? fileManager.createDirectory(
            at: historyFileURL(for: workspaceID).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    func historyFileURL(for workspaceID: WorkspaceID) -> URL {
        stateDirectoryURL
            .appendingPathComponent("workspaces", isDirectory: true)
            .appendingPathComponent(safePathComponent(workspaceID.rawValue), isDirectory: true)
            .appendingPathComponent("shell-history", isDirectory: false)
    }

    private func safePathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let component = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return component.isEmpty ? "workspace" : component
    }
}
