import Foundation

// MARK: - Model

struct GitWorktree: Equatable {
    let path: String
    let branch: String?       // nil = detached HEAD
    let isMainWorktree: Bool
    let isCurrentRepo: Bool   // true when this is the focused pane's own worktree
}

// MARK: - Resolver

enum GitWorktreeResolver {

    // MARK: List worktrees

    static func listWorktrees(in directory: String) -> [GitWorktree] {
        guard let output = runGit(["-C", directory, "worktree", "list", "--porcelain"]) else {
            return []
        }

        // Resolve the focused pane's own repo root so we can flag isCurrentRepo.
        let repoRoot = runGit(["-C", directory, "rev-parse", "--show-toplevel"])

        var worktrees: [GitWorktree] = []
        // Entries are separated by blank lines.
        let entries = output.components(separatedBy: "\n\n")
        var isFirst = true
        for entry in entries {
            guard entry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                continue
            }
            var path: String?
            var branch: String?
            for line in entry.components(separatedBy: "\n") {
                if line.hasPrefix("worktree ") {
                    path = String(line.dropFirst("worktree ".count))
                } else if line.hasPrefix("branch refs/heads/") {
                    branch = String(line.dropFirst("branch refs/heads/".count))
                }
                // bare / detached / prunable are intentionally ignored for the branch field.
            }
            guard let resolvedPath = path else { continue }
            let isCurrentRepo = (repoRoot == resolvedPath)
            worktrees.append(GitWorktree(
                path: resolvedPath,
                branch: branch,
                isMainWorktree: isFirst,
                isCurrentRepo: isCurrentRepo
            ))
            isFirst = false
        }
        return worktrees
    }

    // MARK: List branches

    static func listBranches(in directory: String) -> [String] {
        guard let output = runGit(["-C", directory, "branch", "--list", "--format=%(refname:short)"]) else {
            return []
        }
        return output
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

    // MARK: Add worktree

    @discardableResult
    static func addWorktree(
        branch: String,
        fromRef: String?,
        at path: String,
        in directory: String
    ) -> Result<String, Error> {
        var args = ["-C", directory, "worktree", "add", "-b", branch, path]
        if let fromRef {
            args.append(fromRef)
        }
        if let output = runGit(args) {
            return .success(output)
        }
        if let errorOutput = runGitRaw(["-C", directory, "worktree", "add", "-b", branch, path] + (fromRef.map { [$0] } ?? [])) {
            return .failure(GitWorktreeError.gitError(errorOutput))
        }
        return .failure(GitWorktreeError.gitError("git worktree add failed"))
    }

    // MARK: Remove worktree

    @discardableResult
    static func removeWorktree(at path: String, in directory: String) -> Result<Void, Error> {
        if runGitStatus(["-C", directory, "worktree", "remove", path]) {
            return .success(())
        }
        return .failure(GitWorktreeError.gitError("git worktree remove failed"))
    }

    // MARK: Default worktree path

    /// Generates a sibling-of-repo-root path for a new worktree branch.
    /// Pattern: <repo-parent>/<repo-name>-worktrees/<branch>
    static func defaultWorktreePath(branch: String, in directory: String) -> String {
        guard let repoRoot = runGit(["-C", directory, "rev-parse", "--show-toplevel"]) else {
            return (directory as NSString).appendingPathComponent(branch)
        }
        let repoName = (repoRoot as NSString).lastPathComponent
        let parentDir = (repoRoot as NSString).deletingLastPathComponent
        let worktreesDir = (parentDir as NSString).appendingPathComponent("\(repoName)-worktrees")
        return (worktreesDir as NSString).appendingPathComponent(branch)
    }

    // MARK: Private git runner

    private static func runGit(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        do {
            let finished = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in finished.signal() }
            try process.run()
            finished.wait()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? nil : output
    }

    /// Runs git but returns stderr on failure.
    private static func runGitRaw(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = errorPipe
        do {
            let finished = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in finished.signal() }
            try process.run()
            finished.wait()
        } catch {
            return nil
        }
        let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? nil : output
    }

    private static func runGitStatus(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            let finished = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in finished.signal() }
            try process.run()
            finished.wait()
        } catch {
            return false
        }
        return process.terminationStatus == 0
    }
}

// MARK: - Errors

enum GitWorktreeError: LocalizedError {
    case gitError(String)

    var errorDescription: String? {
        switch self {
        case .gitError(let msg): return msg
        }
    }
}
