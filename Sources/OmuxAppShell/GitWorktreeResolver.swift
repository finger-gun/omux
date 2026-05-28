import Foundation

// MARK: - Helpers

/// A lock-protected data buffer that can be safely captured in @Sendable closures.
private final class LockedBuffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ chunk: Data) {
        lock.withLock { data.append(chunk) }
    }

    var snapshot: Data {
        lock.withLock { data }
    }
}

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
        let (exitCode, stdout, stderr) = runGitFull(args)
        if exitCode == 0 {
            return .success(stdout)
        }
        let message = stderr.isEmpty ? (stdout.isEmpty ? "git worktree add failed" : stdout) : stderr
        return .failure(GitWorktreeError.gitError(message))
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

    /// Runs git once, returns (terminationStatus, stdout, stderr) with async pipe draining
    /// to avoid deadlock when output exceeds the OS pipe buffer.
    private static func runGitFull(_ arguments: [String]) -> (Int32, String, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        let outBuffer = LockedBuffer()
        let errBuffer = LockedBuffer()
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            outBuffer.append(chunk)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            errBuffer.append(chunk)
        }
        do {
            let finished = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in finished.signal() }
            try process.run()
            finished.wait()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            return (-1, "", "")
        }
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        let outTail = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errTail = errorPipe.fileHandleForReading.readDataToEndOfFile()
        if !outTail.isEmpty { outBuffer.append(outTail) }
        if !errTail.isEmpty { errBuffer.append(errTail) }
        let stdout = String(decoding: outBuffer.snapshot, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = String(decoding: errBuffer.snapshot, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return (process.terminationStatus, stdout, stderr)
    }

    private static func runGit(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        let outBuffer = LockedBuffer()
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            outBuffer.append(chunk)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { _ in }
        do {
            let finished = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in finished.signal() }
            try process.run()
            finished.wait()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            return nil
        }
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        // Drain any remaining bytes after termination.
        let tail = outputPipe.fileHandleForReading.readDataToEndOfFile()
        if !tail.isEmpty { outBuffer.append(tail) }
        guard process.terminationStatus == 0 else { return nil }
        let output = String(decoding: outBuffer.snapshot, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? nil : output
    }

    /// Runs git and returns stderr output (used to surface error messages).
    private static func runGitRaw(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        let errBuffer = LockedBuffer()
        outputPipe.fileHandleForReading.readabilityHandler = { _ in }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            errBuffer.append(chunk)
        }
        do {
            let finished = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in finished.signal() }
            try process.run()
            finished.wait()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            return nil
        }
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        let tail = errorPipe.fileHandleForReading.readDataToEndOfFile()
        if !tail.isEmpty { errBuffer.append(tail) }
        let output = String(decoding: errBuffer.snapshot, as: UTF8.self)
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
