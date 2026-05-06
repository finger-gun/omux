import AppKit
import Foundation
import OmuxCore

public struct TerminalTextActivationRequest: Equatable, Sendable {
    public let paneID: PaneID
    public let location: CGPoint
    public let viewSize: CGSize
    public let terminalSize: TerminalSize
    public let modifiers: KeyModifiers

    public init(
        paneID: PaneID,
        location: CGPoint,
        viewSize: CGSize,
        terminalSize: TerminalSize,
        modifiers: KeyModifiers
    ) {
        self.paneID = paneID
        self.location = location
        self.viewSize = viewSize
        self.terminalSize = terminalSize
        self.modifiers = modifiers
    }
}

public struct TerminalTextActivationHit: Equatable, Sendable {
    public let token: String
    public let row: Int
    public let column: Int

    public init(token: String, row: Int, column: Int) {
        self.token = token
        self.row = row
        self.column = column
    }
}

public struct TerminalTextActivationContext: Equatable, Sendable {
    public let request: TerminalTextActivationRequest
    public let hit: TerminalTextActivationHit
    public let cwd: String?
    public let resolvedPath: String?

    public init(
        request: TerminalTextActivationRequest,
        hit: TerminalTextActivationHit,
        cwd: String?,
        resolvedPath: String?
    ) {
        self.request = request
        self.hit = hit
        self.cwd = cwd
        self.resolvedPath = resolvedPath
    }
}

public enum TerminalTextActivationResolver {
    public static func hit(
        in text: String,
        request: TerminalTextActivationRequest
    ) -> TerminalTextActivationHit? {
        guard request.viewSize.width > 0,
              request.viewSize.height > 0,
              request.terminalSize.columns > 0,
              request.terminalSize.rows > 0
        else {
            return nil
        }

        let columnWidth = request.viewSize.width / CGFloat(request.terminalSize.columns)
        let rowHeight = request.viewSize.height / CGFloat(request.terminalSize.rows)
        let column = max(0, min(request.terminalSize.columns - 1, Int(request.location.x / max(columnWidth, 1))))
        let row = max(0, min(
            request.terminalSize.rows - 1,
            Int((request.viewSize.height - request.location.y) / max(rowHeight, 1))
        ))

        var lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        if lines.last == "" {
            lines.removeLast()
        }
        guard lines.isEmpty == false else {
            return nil
        }

        let visibleStart = max(0, lines.count - request.terminalSize.rows)
        let visibleLineCount = min(lines.count, request.terminalSize.rows)
        let contentTopRow = max(0, request.terminalSize.rows - visibleLineCount)
        guard row >= contentTopRow else {
            return nil
        }
        let lineIndex = min(visibleStart + (row - contentTopRow), lines.count - 1)
        if let token = token(in: lines[lineIndex], column: column, tolerance: 2) {
            return TerminalTextActivationHit(token: token, row: row, column: column)
        }
        return nil
    }

    public static func resolvedLocalPath(token: String, cwd: String?) -> String? {
        let candidates = pathCandidates(for: token)
        for candidate in candidates {
            if let resolved = resolve(candidate: candidate, cwd: cwd) {
                return resolved
            }
        }
        return nil
    }

    private static func token(in line: String, column: Int, tolerance: Int) -> String? {
        let characters = Array(line)
        guard characters.isEmpty == false else {
            return nil
        }

        let clampedColumn = min(max(column, 0), characters.count - 1)
        let candidateOffsets = [0] + (1...max(0, tolerance)).flatMap { [-$0, $0] }
        guard let tokenColumn = candidateOffsets
            .map({ clampedColumn + $0 })
            .first(where: { characters.indices.contains($0) && isTokenCharacter(characters[$0]) })
        else {
            return nil
        }

        var start = tokenColumn
        while start > 0, isTokenCharacter(characters[start - 1]) {
            start -= 1
        }

        var end = tokenColumn
        while end + 1 < characters.count, isTokenCharacter(characters[end + 1]) {
            end += 1
        }

        return trimToken(String(characters[start...end]))
    }

    private static func isTokenCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            CharacterSet.whitespacesAndNewlines.contains(scalar) == false
                && CharacterSet(charactersIn: "\"'`()[]{}<>").contains(scalar) == false
        }
    }

    private static func trimToken(_ token: String) -> String? {
        let trimmed = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`()[]{}<>"))
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func pathCandidates(for token: String) -> [String] {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return []
        }

        var candidates = [trimmed]
        let suffixPattern = #":\d+(?::\d+)?$"#
        if let expression = try? NSRegularExpression(pattern: suffixPattern) {
            let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            let stripped = expression.stringByReplacingMatches(in: trimmed, range: range, withTemplate: "")
            if stripped != trimmed {
                candidates.insert(stripped, at: 0)
            }
        }
        return candidates
    }

    private static func resolve(candidate: String, cwd: String?) -> String? {
        if candidate.hasPrefix("http://") || candidate.hasPrefix("https://") || candidate.hasPrefix("mailto:") {
            return nil
        }

        if candidate.hasPrefix("file://"), let url = URL(string: candidate), url.isFileURL {
            return url.standardizedFileURL.path
        }

        if candidate.hasPrefix("~") {
            return NSString(string: candidate).expandingTildeInPath
        }

        if candidate.hasPrefix("/") {
            return URL(fileURLWithPath: candidate).standardizedFileURL.path
        }

        guard let cwd, cwd.isEmpty == false else {
            return nil
        }
        return URL(fileURLWithPath: cwd)
            .appendingPathComponent(candidate)
            .standardizedFileURL
            .path
    }
}
