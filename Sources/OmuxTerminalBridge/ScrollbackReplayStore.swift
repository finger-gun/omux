import Foundation
import OmuxCore

public struct TerminalScrollbackReplay: Equatable, Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public var environment: [String: String] {
        [ScrollbackReplayStore.environmentKey: fileURL.path]
    }
}

public struct TerminalScrollbackReplayLaunch: Equatable, Sendable {
    public let session: SessionDescriptor
    public let wrapperURL: URL

    public init(session: SessionDescriptor, wrapperURL: URL) {
        self.session = session
        self.wrapperURL = wrapperURL
    }
}

public enum TerminalScrollbackTextSanitizer {
    public static func sanitizedForReplayOrPersistence(_ text: String) -> String {
        let unsafeSequences = [
            "\u{001B}[?1049h",
            "\u{001B}[?1049l",
            "\u{001B}[?1047h",
            "\u{001B}[?1047l",
            "\u{001B}[?1048h",
            "\u{001B}[?1048l",
        ]
        let withoutUnsafeSequences = unsafeSequences.reduce(text) { result, sequence in
            result.replacingOccurrences(of: sequence, with: "")
        }
        return droppingTrailingPromptLine(deduplicatedTailPromptLines(withoutUnsafeSequences))
    }

    private static func deduplicatedTailPromptLines(_ text: String, tailLineLimit: Int = 80) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count > 1 else {
            return text
        }

        let tailStart = max(0, lines.count - tailLineLimit)
        let prefix = lines[..<tailStart]
        let tail = Array(lines[tailStart...])
        let duplicateKeys = duplicateShellNoiseLineKeys(in: tail)
        var seen = Set<String>()
        var deduplicatedReversed: [String] = []

        for line in tail.reversed() {
            let key = replayDuplicateComparisonKey(for: line)
            if duplicateKeys.contains(key) {
                guard seen.insert(key).inserted else {
                    continue
                }
            }
            deduplicatedReversed.append(line)
        }

        return (Array(prefix) + Array(deduplicatedReversed.reversed())).joined(separator: "\n")
    }

    private static func duplicateShellNoiseLineKeys(in lines: [String]) -> Set<String> {
        var counts: [String: Int] = [:]
        var isShellNoise: [String: Bool] = [:]
        for line in lines {
            let key = replayDuplicateComparisonKey(for: line)
            guard key.isEmpty == false else {
                continue
            }
            counts[key, default: 0] += 1
            isShellNoise[key, default: false] = isShellNoise[key, default: false]
                || line.contains("\u{001B}")
                || isShellStartupOrPromptLine(key)
        }
        return Set(counts.compactMap { key, count in
            count > 1 && isShellNoise[key] == true ? key : nil
        })
    }

    private static func isShellStartupOrPromptLine(_ line: String) -> Bool {
        if line.hasPrefix("Last login:") {
            return true
        }
        if line.contains("][$!?]") || line.contains("[\u{e0a0} ") {
            return true
        }
        if line.hasPrefix("("), line.hasSuffix(")]") {
            return true
        }
        if [" $", " %", " >", " #"].contains(where: line.hasSuffix) {
            return true
        }
        return false
    }

    private static func droppingTrailingPromptLine(_ text: String) -> String {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.isEmpty == false else {
            return text
        }

        while lines.last == "" {
            lines.removeLast()
        }
        guard let lastLine = lines.last else {
            return ""
        }
        let key = replayDuplicateComparisonKey(for: lastLine)
        guard key.isEmpty == false, isShellStartupOrPromptLine(key), key.hasPrefix("Last login:") == false else {
            return text
        }
        lines.removeLast()
        return lines.joined(separator: "\n")
    }

    private static func replayDuplicateComparisonKey(for line: String) -> String {
        let stripped = ansiStripped(line).trimmingCharacters(in: .whitespaces)
        guard stripped.isEmpty == false else {
            return ""
        }
        if stripped.hasPrefix("Last login:") {
            return "Last login:"
        }
        return stripped
    }

    private static func ansiStripped(_ line: String) -> String {
        var result = ""
        var iterator = line.makeIterator()
        while let character = iterator.next() {
            guard character == "\u{001B}" else {
                result.append(character)
                continue
            }

            guard let next = iterator.next() else {
                break
            }

            switch next {
            case "[":
                while let parameter = iterator.next() {
                    guard let scalar = parameter.unicodeScalars.first else {
                        continue
                    }
                    if scalar.value >= 0x40, scalar.value <= 0x7E {
                        break
                    }
                }
            case "]":
                while let parameter = iterator.next() {
                    if parameter == "\u{0007}" {
                        break
                    }
                    if parameter == "\u{001B}" {
                        _ = iterator.next()
                        break
                    }
                }
            default:
                continue
            }
        }
        return result
    }
}

public final class ScrollbackReplayStore: @unchecked Sendable {
    public static let environmentKey = "OMUX_RESTORE_SCROLLBACK_FILE"

    private let directoryURL: URL
    private let fileManager: FileManager

    public init(
        directoryURL: URL,
        fileManager: FileManager = .default
    ) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
    }

    public func prepareReplay(
        for scrollback: PaneScrollbackSnapshot?,
        maxBytes: Int = PaneScrollbackSnapshot.defaultMaxBytes,
        maxLines: Int = PaneScrollbackSnapshot.defaultMaxLines
    ) -> TerminalScrollbackReplay? {
        guard let scrollback,
              let bounded = PaneScrollbackSnapshot.bounded(
                  text: scrollback.text,
                  maxBytes: maxBytes,
                  maxLines: maxLines
              )
        else {
            return nil
        }

        let fileURL = directoryURL.appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: false)
            .appendingPathExtension("ansi")
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let replayText = Self.sanitizedReplayText(bounded.text)
            guard replayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                return nil
            }
            try Data(replayText.utf8).write(to: fileURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            return TerminalScrollbackReplay(fileURL: fileURL)
        } catch {
            fputs("warning: failed to prepare scrollback replay file \(fileURL.path): \(error)\n", stderr)
            return nil
        }
    }

    public func removeReplayFile(_ fileURL: URL) {
        guard fileURL.standardizedFileURL.path.hasPrefix(directoryURL.standardizedFileURL.path + "/"),
              fileManager.fileExists(atPath: fileURL.path)
        else {
            return
        }

        do {
            try fileManager.removeItem(at: fileURL)
        } catch {
            fputs("warning: failed to remove scrollback replay file \(fileURL.path): \(error)\n", stderr)
        }
    }

    public func cleanupStaleFiles(olderThan cutoff: Date) {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for fileURL in files where fileURL.pathExtension == "ansi" {
            let modified = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            guard modified < cutoff else {
                continue
            }
            removeReplayFile(fileURL)
        }
    }

    private static func sanitizedReplayText(_ text: String) -> String {
        TerminalScrollbackTextSanitizer.sanitizedForReplayOrPersistence(text)
    }
}

public final class ScrollbackReplayWrapperStore: @unchecked Sendable {
    public static let wrapperFileName = "restore-scrollback.sh"
    public static let script = """
    #!/bin/sh
    if [ -n "$OMUX_RESTORE_SCROLLBACK_FILE" ] && [ -r "$OMUX_RESTORE_SCROLLBACK_FILE" ]; then
      cat "$OMUX_RESTORE_SCROLLBACK_FILE"
      rm -f "$OMUX_RESTORE_SCROLLBACK_FILE"
    fi
    printf '\\033[0m'
    printf '\\033[?25h'
    printf '\\n'
    exec "${SHELL:-/bin/sh}" -l
    """

    private let directoryURL: URL
    private let fileManager: FileManager

    public init(
        directoryURL: URL,
        fileManager: FileManager = .default
    ) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
    }

    public func prepareLaunch(
        baseSession: SessionDescriptor,
        replay: TerminalScrollbackReplay
    ) -> TerminalScrollbackReplayLaunch? {
        do {
            let wrapperURL = try installWrapper()
            var environment = baseSession.environment
            environment.merge(replay.environment) { _, replayValue in replayValue }
            environment["SHELL"] = baseSession.shell
            let session = SessionDescriptor(
                id: baseSession.id,
                shell: "/bin/sh \(Self.shellQuoted(wrapperURL.path))",
                workingDirectory: baseSession.workingDirectory,
                environment: environment
            )
            return TerminalScrollbackReplayLaunch(session: session, wrapperURL: wrapperURL)
        } catch {
            fputs("warning: failed to prepare scrollback replay wrapper: \(error)\n", stderr)
            return nil
        }
    }

    public func installWrapper() throws -> URL {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let wrapperURL = directoryURL.appendingPathComponent(Self.wrapperFileName, isDirectory: false)
        try Self.script.write(to: wrapperURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: wrapperURL.path)
        return wrapperURL
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
