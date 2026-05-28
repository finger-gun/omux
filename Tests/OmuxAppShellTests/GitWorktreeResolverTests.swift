import XCTest
@testable import OmuxAppShell

// Integration tests for GitWorktreeResolver.
// Each test creates an isolated temporary git repository so that the real
// `git` binary is exercised and no mocking of the git runner is needed.

final class GitWorktreeResolverTests: XCTestCase {

    // MARK: - Helpers

    private func makeTemporaryRepo(name: String = UUID().uuidString) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitWorktreeResolverTests-\(name)", isDirectory: true)
            .resolvingSymlinksInPath()
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git(["init", "-b", "main"], in: root)
        try git(["config", "user.email", "test@example.com"], in: root)
        try git(["config", "user.name", "Test User"], in: root)
        try git(["commit", "--allow-empty", "-m", "init"], in: root)
        return root
    }

    /// Returns a resolved temporary URL (resolves /private/var symlink on macOS).
    private func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("GitWorktreeResolverTests-\(name)", isDirectory: false)
            .resolvingSymlinksInPath()
    }

    /// Resolves symlinks in a path string (handles /private/var vs /var on macOS).
    private func realPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    @discardableResult
    private func git(_ args: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = directory
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "GitTestHelper",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "git \(args.joined(separator: " ")) failed: \(output)"]
            )
        }
        return output
    }

    // MARK: - listWorktrees

    func testListWorktreesReturnsSingleMainWorktree() throws {
        let repo = try makeTemporaryRepo(name: "single")
        defer { try? FileManager.default.removeItem(at: repo) }

        let worktrees = GitWorktreeResolver.listWorktrees(in: repo.path)

        XCTAssertEqual(worktrees.count, 1)
        let wt = try XCTUnwrap(worktrees.first)
        XCTAssertTrue(wt.isMainWorktree)
        XCTAssertEqual(wt.branch, "main")
        XCTAssertEqual(realPath(wt.path), realPath(repo.path))
    }

    func testListWorktreesReturnsEmptyForNonGitDirectory() throws {
        let nonGit = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitWorktreeResolverTests-nongit", isDirectory: true)
        try FileManager.default.createDirectory(at: nonGit, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: nonGit) }

        let worktrees = GitWorktreeResolver.listWorktrees(in: nonGit.path)
        XCTAssertTrue(worktrees.isEmpty)
    }

    func testListWorktreesIncludesLinkedWorktree() throws {
        let repo = try makeTemporaryRepo(name: "linked")
        defer { try? FileManager.default.removeItem(at: repo) }

        let linkedPath = temporaryURL("linked-wt")
        defer { try? FileManager.default.removeItem(at: linkedPath) }

        try git(["worktree", "add", "-b", "feature/x", linkedPath.path], in: repo)

        let worktrees = GitWorktreeResolver.listWorktrees(in: repo.path)

        XCTAssertEqual(worktrees.count, 2)
        let main = try XCTUnwrap(worktrees.first { $0.isMainWorktree })
        let linked = try XCTUnwrap(worktrees.first { !$0.isMainWorktree })
        XCTAssertEqual(main.branch, "main")
        XCTAssertEqual(linked.branch, "feature/x")
        XCTAssertEqual(realPath(linked.path), realPath(linkedPath.path))
    }

    func testListWorktreesMarksDetachedHeadWithNilBranch() throws {
        let repo = try makeTemporaryRepo(name: "detached")
        defer { try? FileManager.default.removeItem(at: repo) }

        // Get the current commit hash.
        let sha = try git(["rev-parse", "HEAD"], in: repo).trimmingCharacters(in: .whitespacesAndNewlines)
        let detachedPath = temporaryURL("detached-wt")
        defer { try? FileManager.default.removeItem(at: detachedPath) }

        try git(["worktree", "add", "--detach", detachedPath.path, sha], in: repo)

        let worktrees = GitWorktreeResolver.listWorktrees(in: repo.path)

        XCTAssertEqual(worktrees.count, 2)
        let detached = try XCTUnwrap(worktrees.first { !$0.isMainWorktree })
        XCTAssertNil(detached.branch, "Detached HEAD worktree should have nil branch")
    }

    func testListWorktreesOnlyFirstEntryIsMainWorktree() throws {
        let repo = try makeTemporaryRepo(name: "main-flag")
        defer { try? FileManager.default.removeItem(at: repo) }

        let wt1 = temporaryURL("wt1")
        let wt2 = temporaryURL("wt2")
        defer {
            try? FileManager.default.removeItem(at: wt1)
            try? FileManager.default.removeItem(at: wt2)
        }

        try git(["worktree", "add", "-b", "branch-a", wt1.path], in: repo)
        try git(["worktree", "add", "-b", "branch-b", wt2.path], in: repo)

        let worktrees = GitWorktreeResolver.listWorktrees(in: repo.path)

        XCTAssertEqual(worktrees.count, 3)
        let mainCount = worktrees.filter(\.isMainWorktree).count
        XCTAssertEqual(mainCount, 1, "Exactly one worktree should be flagged as the main worktree")
        XCTAssertTrue(worktrees[0].isMainWorktree)
        XCTAssertFalse(worktrees[1].isMainWorktree)
        XCTAssertFalse(worktrees[2].isMainWorktree)
    }

    // MARK: - listBranches

    func testListBranchesReturnsMainBranch() throws {
        let repo = try makeTemporaryRepo(name: "branches-main")
        defer { try? FileManager.default.removeItem(at: repo) }

        let branches = GitWorktreeResolver.listBranches(in: repo.path)
        XCTAssertEqual(branches, ["main"])
    }

    func testListBranchesReturnsAllLocalBranches() throws {
        let repo = try makeTemporaryRepo(name: "branches-multi")
        defer { try? FileManager.default.removeItem(at: repo) }

        try git(["branch", "feature/a"], in: repo)
        try git(["branch", "feature/b"], in: repo)

        let branches = GitWorktreeResolver.listBranches(in: repo.path)
        XCTAssertTrue(branches.contains("main"))
        XCTAssertTrue(branches.contains("feature/a"))
        XCTAssertTrue(branches.contains("feature/b"))
        XCTAssertEqual(branches.count, 3)
    }

    func testListBranchesReturnsEmptyForNonGitDirectory() throws {
        let nonGit = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitWorktreeResolverTests-branches-nongit", isDirectory: true)
        try FileManager.default.createDirectory(at: nonGit, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: nonGit) }

        let branches = GitWorktreeResolver.listBranches(in: nonGit.path)
        XCTAssertTrue(branches.isEmpty)
    }

    // MARK: - defaultWorktreePath

    func testDefaultWorktreePathGeneratesSiblingDirectory() throws {
        let repo = try makeTemporaryRepo(name: "path-gen")
        defer { try? FileManager.default.removeItem(at: repo) }

        let path = GitWorktreeResolver.defaultWorktreePath(branch: "feature/new", in: repo.path)

        // The generated path should be a sibling of the repo root named "<repo>-worktrees/<branch>".
        XCTAssertTrue(
            path.hasSuffix("GitWorktreeResolverTests-path-gen-worktrees/feature/new"),
            "Expected path to end with 'GitWorktreeResolverTests-path-gen-worktrees/feature/new', got: \(path)"
        )
    }

    func testDefaultWorktreePathEncodesSlashesInBranch() throws {
        let repo = try makeTemporaryRepo(name: "path-slash")
        defer { try? FileManager.default.removeItem(at: repo) }

        let path = GitWorktreeResolver.defaultWorktreePath(branch: "user/feature/x", in: repo.path)
        XCTAssertTrue(path.hasSuffix("/user/feature/x"), "Branch path components should be preserved as path segments")
    }

    func testDefaultWorktreePathFallsBackToDirectoryForNonGitDir() throws {
        let nonGit = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitWorktreeResolverTests-path-fallback", isDirectory: true)
            .standardizedFileURL
        try FileManager.default.createDirectory(at: nonGit, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: nonGit) }

        let path = GitWorktreeResolver.defaultWorktreePath(branch: "my-branch", in: nonGit.path)
        XCTAssertEqual(path, nonGit.appendingPathComponent("my-branch").path)
    }

    // MARK: - GitWorktreeError

    func testGitWorktreeErrorDescriptionContainsMessage() {
        let error = GitWorktreeError.gitError("something went wrong")
        XCTAssertEqual(error.errorDescription, "something went wrong")
    }

    // MARK: - GitWorktree model

    func testGitWorktreeEquality() {
        let a = GitWorktree(path: "/foo", branch: "main", isMainWorktree: true, isCurrentRepo: false)
        let b = GitWorktree(path: "/foo", branch: "main", isMainWorktree: true, isCurrentRepo: false)
        let c = GitWorktree(path: "/bar", branch: "main", isMainWorktree: true, isCurrentRepo: false)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
