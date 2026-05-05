import Foundation
import OmuxCore

struct TerminalSidebarMetadata: Equatable {
    let icon: OmuxSemanticIcon
    let title: String
    let subtitle: String?
}

final class TerminalSidebarMetadataResolver {
    private struct GitInfo {
        let branchName: String?
    }

    private var gitInfoByPath: [String: GitInfo?] = [:]

    func metadata(for pane: Pane, icon: OmuxSemanticIcon) -> TerminalSidebarMetadata {
        let path = pane.terminalState.reportedWorkingDirectory ?? pane.session.workingDirectory
        let abbreviatedPath = abbreviate(path: path)
        let preferredPaneTitle = preferredPaneTitle(for: pane, abbreviatedPath: abbreviatedPath)

        guard let gitInfo = resolveGitInfo(for: path) else {
            return TerminalSidebarMetadata(
                icon: icon,
                title: preferredPaneTitle ?? abbreviatedPath,
                subtitle: preferredPaneTitle == nil ? nil : abbreviatedPath
            )
        }

        if let preferredPaneTitle {
            let subtitle = gitAwareSubtitle(
                branchName: gitInfo.branchName,
                abbreviatedPath: abbreviatedPath,
                preferredTitle: preferredPaneTitle
            )
            return TerminalSidebarMetadata(
                icon: icon,
                title: preferredPaneTitle,
                subtitle: subtitle
            )
        }

        let metadataTitle: String
        if let branchName = gitInfo.branchName {
            metadataTitle = branchName
        } else {
            metadataTitle = abbreviatedPath
        }

        return TerminalSidebarMetadata(
            icon: icon,
            title: metadataTitle,
            subtitle: abbreviatedPath
        )
    }

    private func resolveGitInfo(for path: String) -> GitInfo? {
        if let cached = gitInfoByPath[path] {
            return cached
        }

        guard runGit(["-C", path, "rev-parse", "--show-toplevel"]) != nil else {
            gitInfoByPath[path] = nil
            return nil
        }

        let symbolicBranch = runGit(["-C", path, "symbolic-ref", "--quiet", "--short", "HEAD"])
        let detachedBranch = runGit(["-C", path, "rev-parse", "--short", "HEAD"]).map { "detached \($0)" }
        let gitInfo = GitInfo(branchName: symbolicBranch ?? detachedBranch)
        gitInfoByPath[path] = gitInfo
        return gitInfo
    }

    private func runGit(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return nil
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? nil : output
    }

    private func abbreviate(path: String) -> String {
        let homeDirectory = NSHomeDirectory()
        guard path.hasPrefix(homeDirectory) else {
            return path
        }
        let suffix = path.dropFirst(homeDirectory.count)
        return suffix.isEmpty ? "~" : "~\(suffix)"
    }

    private func preferredPaneTitle(for pane: Pane, abbreviatedPath: String) -> String? {
        let title = pane.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.isEmpty == false else {
            return nil
        }

        let normalizedPath = pane.session.workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultPathTitle = URL(fileURLWithPath: normalizedPath).lastPathComponent
        let fallbackTitles = Set(["OpenMUX", "Shell"])

        guard title != normalizedPath,
              title != abbreviatedPath,
              title != defaultPathTitle,
              fallbackTitles.contains(title) == false
        else {
            return nil
        }

        return title
    }

    private func gitAwareSubtitle(
        branchName: String?,
        abbreviatedPath: String,
        preferredTitle: String
    ) -> String {
        guard let branchName, branchName != preferredTitle else {
            return abbreviatedPath
        }

        return "\(branchName) · \(abbreviatedPath)"
    }
}
