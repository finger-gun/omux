import Foundation
import OmuxCore

struct TerminalSidebarMetadata: Equatable {
    let title: String
    let subtitle: String?
}

final class TerminalSidebarMetadataResolver {
    private struct GitInfo {
        let branchName: String?
    }

    private var gitInfoByPath: [String: GitInfo?] = [:]

    func metadata(for pane: Pane) -> TerminalSidebarMetadata {
        let path = pane.session.workingDirectory
        guard let gitInfo = resolveGitInfo(for: path) else {
            return TerminalSidebarMetadata(
                title: abbreviate(path: path),
                subtitle: nil
            )
        }

        let title: String
        if let branchName = gitInfo.branchName {
            title = branchName
        } else {
            title = abbreviate(path: path)
        }

        return TerminalSidebarMetadata(
            title: title,
            subtitle: abbreviate(path: path)
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
}
