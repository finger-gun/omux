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
        } else {
            environment.removeValue(forKey: OpenMUXWorkspaceEnvironment.shellHistoryFileKey)
        }

        return SessionDescriptor(
            id: session.id,
            shell: session.shell,
            workingDirectory: session.workingDirectory,
            environment: environment
        )
    }

    func launchSession(
        from session: SessionDescriptor,
        workspaceID: WorkspaceID,
        workspaceRootPath: String
    ) -> SessionDescriptor {
        let workspaceSession = applyingWorkspaceContext(
            to: session,
            workspaceID: workspaceID,
            workspaceRootPath: workspaceRootPath
        )

        guard isolateShellHistory,
              workspaceSession.shellURL?.lastPathComponent == "zsh",
              installZshHistoryIsolationFiles()
        else {
            return workspaceSession
        }

        var environment = workspaceSession.environment
        let workspaceZDOTDIR = zshDirectoryURL.path
        environment["OMUX_ORIGINAL_ZDOTDIR"] = originalZDOTDIR(
            from: environment,
            workspaceZDOTDIR: workspaceZDOTDIR
        )
        environment["OMUX_WORKSPACE_ZDOTDIR"] = workspaceZDOTDIR
        environment["ZDOTDIR"] = workspaceZDOTDIR
        return SessionDescriptor(
            id: workspaceSession.id,
            shell: workspaceSession.shell,
            workingDirectory: workspaceSession.workingDirectory,
            environment: environment
        )
    }

    func prepareHistoryStorage(for workspaceID: WorkspaceID) throws {
        guard isolateShellHistory else {
            return
        }
        try fileManager.createDirectory(
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

    private var shellIntegrationDirectoryURL: URL {
        stateDirectoryURL.appendingPathComponent("shell-integration", isDirectory: true)
    }

    private var zshDirectoryURL: URL {
        shellIntegrationDirectoryURL.appendingPathComponent("zsh", isDirectory: true)
    }

    private func installZshHistoryIsolationFiles() -> Bool {
        do {
            try fileManager.createDirectory(
                at: zshDirectoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            for fileName in [".zshenv", ".zprofile", ".zshrc", ".zlogin"] {
                try Self.zshStartupScript(fileName: fileName).write(
                    to: zshDirectoryURL.appendingPathComponent(fileName, isDirectory: false),
                    atomically: true,
                    encoding: .utf8
                )
            }
            return true
        } catch {
            fputs("warning: failed to prepare workspace zsh history isolation: \(error)\n", stderr)
            return false
        }
    }

    private static func zshStartupScript(fileName: String) -> String {
        let reassertZDOTDIR = """
        if [[ -n "${OMUX_WORKSPACE_ZDOTDIR:-}" ]]; then
          export ZDOTDIR="$OMUX_WORKSPACE_ZDOTDIR"
        fi
        """
        let enforceHistory = fileName == ".zshrc" || fileName == ".zlogin"
            ? "\nif [[ -n \"${OMUX_WORKSPACE_HISTORY:-}\" ]]; then\n  export HISTFILE=\"$OMUX_WORKSPACE_HISTORY\"\nfi\n"
            : ""
        return """
        if [[ -n "${OMUX_ORIGINAL_ZDOTDIR:-}" && "${OMUX_ORIGINAL_ZDOTDIR}" != "${OMUX_WORKSPACE_ZDOTDIR:-}" && -r "${OMUX_ORIGINAL_ZDOTDIR}/\(fileName)" ]]; then
          source "${OMUX_ORIGINAL_ZDOTDIR}/\(fileName)"
        fi
        \(reassertZDOTDIR)
        \(enforceHistory)
        """
    }

    private func originalZDOTDIR(
        from environment: [String: String],
        workspaceZDOTDIR: String
    ) -> String {
        if let originalZDOTDIR = environment["OMUX_ORIGINAL_ZDOTDIR"], originalZDOTDIR.isEmpty == false {
            return originalZDOTDIR
        }

        let candidate = environment["ZDOTDIR"]
            ?? ProcessInfo.processInfo.environment["ZDOTDIR"]
        let inheritedWorkspaceZDOTDIR = environment["OMUX_WORKSPACE_ZDOTDIR"]
            ?? ProcessInfo.processInfo.environment["OMUX_WORKSPACE_ZDOTDIR"]
        if let candidate,
           candidate.isEmpty == false,
           candidate != workspaceZDOTDIR,
           candidate != inheritedWorkspaceZDOTDIR {
            return candidate
        }

        return environment["HOME"]
            ?? ProcessInfo.processInfo.environment["HOME"]
            ?? FileManager.default.homeDirectoryForCurrentUser.path
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

private extension SessionDescriptor {
    var shellURL: URL? {
        let trimmed = shell.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else {
            return nil
        }
        return URL(fileURLWithPath: trimmed)
    }
}
