import Foundation
import OmuxCore

struct TerminalSidebarMetadata: Equatable {
    let icon: OmuxSemanticIcon
    let title: String
    let subtitle: String?
    let path: String?
    let abbreviatedPath: String?
    let gitBranch: String?
    let isGitRepo: Bool
    let isWorktree: Bool
}

final class TerminalSidebarMetadataResolver {
    private struct GitInfo {
        let branchName: String?
        let isWorktree: Bool
    }

    private var gitInfoByPath: [String: GitInfo?] = [:]
    private let gitInfoLock = NSLock()

    func metadata(for pane: Pane, icon: OmuxSemanticIcon = .terminal) -> TerminalSidebarMetadata {
        guard let session = pane.terminalSession else {
            return TerminalSidebarMetadata(
                icon: icon,
                title: pane.displayTitle,
                subtitle: pane.extensionPane?.pluginID,
                path: nil,
                abbreviatedPath: nil,
                gitBranch: nil,
                isGitRepo: false,
                isWorktree: false
            )
        }

        let path = pane.terminalState.reportedWorkingDirectory ?? session.workingDirectory
        let abbreviatedPath = abbreviate(path: path)
        let gitInfo = resolveGitInfo(for: path)
        let subtitle = gitAwareSubtitle(
            branchName: gitInfo?.branchName,
            abbreviatedPath: abbreviatedPath
        )

        return TerminalSidebarMetadata(
            icon: icon,
            title: pane.displayTitle,
            subtitle: subtitle,
            path: path,
            abbreviatedPath: abbreviatedPath,
            gitBranch: gitInfo?.branchName,
            isGitRepo: gitInfo != nil,
            isWorktree: gitInfo?.isWorktree == true
        )
    }

    private func resolveGitInfo(for path: String) -> GitInfo? {
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        gitInfoLock.lock()
        let cached = gitInfoByPath[normalizedPath]
        gitInfoLock.unlock()
        if let cached {
            guard let cached else {
                return nil
            }
            return GitInfo(
                branchName: currentBranchName(for: normalizedPath),
                isWorktree: cached.isWorktree
            )
        }

        guard runGit(["-C", normalizedPath, "rev-parse", "--show-toplevel"]) != nil else {
            gitInfoLock.lock()
            gitInfoByPath[normalizedPath] = .some(nil)
            gitInfoLock.unlock()
            return nil
        }

        let gitDir = runGit(["-C", normalizedPath, "rev-parse", "--git-dir"])
        let gitCommonDir = runGit(["-C", normalizedPath, "rev-parse", "--git-common-dir"])
        let isWorktree = Self.resolvedGitDirectoryPath(gitDir, relativeTo: normalizedPath)
            != Self.resolvedGitDirectoryPath(gitCommonDir, relativeTo: normalizedPath)
        gitInfoLock.lock()
        gitInfoByPath[normalizedPath] = GitInfo(branchName: nil, isWorktree: isWorktree)
        gitInfoLock.unlock()
        return GitInfo(
            branchName: currentBranchName(for: normalizedPath),
            isWorktree: isWorktree
        )
    }

    private func currentBranchName(for path: String) -> String? {
        if let symbolicBranch = runGit(["-C", path, "symbolic-ref", "--quiet", "--short", "HEAD"]) {
            return symbolicBranch
        }
        return runGit(["-C", path, "rev-parse", "--short", "HEAD"]).map { "detached \($0)" }
    }

    private static func resolvedGitDirectoryPath(_ path: String?, relativeTo workingDirectory: String) -> String? {
        guard let path else {
            return nil
        }
        return URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: workingDirectory, isDirectory: true))
            .standardizedFileURL
            .path
    }

    private func runGit(_ arguments: [String]) -> String? {
        final class PipeBuffer: @unchecked Sendable {
            private let lock = NSLock()
            private var data = Data()

            func append(_ chunk: Data) {
                lock.lock()
                data.append(chunk)
                lock.unlock()
            }

            func snapshot() -> Data {
                lock.lock()
                defer { lock.unlock() }
                return data
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        let finished = DispatchSemaphore(value: 0)
        let drainGroup = DispatchGroup()
        let outputBuffer = PipeBuffer()
        let errorBuffer = PipeBuffer()

        do {
            drainGroup.enter()
            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    drainGroup.leave()
                    return
                }
                outputBuffer.append(chunk)
            }
            drainGroup.enter()
            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    drainGroup.leave()
                    return
                }
                errorBuffer.append(chunk)
            }
            process.terminationHandler = { _ in
                finished.signal()
            }
            try process.run()
            finished.wait()
            drainGroup.wait()
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else {
            return nil
        }

        let output = String(decoding: outputBuffer.snapshot(), as: UTF8.self)
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

    private func gitAwareSubtitle(
        branchName: String?,
        abbreviatedPath: String
    ) -> String {
        guard let branchName else {
            return abbreviatedPath
        }

        return "\(branchName) - \(abbreviatedPath)"
    }
}
