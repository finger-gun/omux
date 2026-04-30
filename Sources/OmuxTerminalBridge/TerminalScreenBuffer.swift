import Foundation

final class TerminalScreenBuffer: @unchecked Sendable {
    private enum ParserState {
        case ground
        case escape
        case csi(String)
        case osc
    }

    private var lines: [[Character]] = [[]]
    private var cursorRow = 0
    private var cursorColumn = 0
    private var parserState: ParserState = .ground
    private let maximumScrollbackLines = 2_000

    var renderedText: String {
        lines.map { String($0) }.joined(separator: "\n")
    }

    func apply(_ data: Data) {
        let text = String(decoding: data, as: UTF8.self)
        for scalar in text.unicodeScalars {
            process(scalar)
        }
        trimScrollbackIfNeeded()
    }

    private func process(_ scalar: UnicodeScalar) {
        switch parserState {
        case .ground:
            processGround(scalar)
        case .escape:
            processEscape(scalar)
        case .csi(let buffer):
            processCSI(scalar, buffer: buffer)
        case .osc:
            processOSC(scalar)
        }
    }

    private func processGround(_ scalar: UnicodeScalar) {
        switch scalar.value {
        case 0x1B:
            parserState = .escape
        case 0x0D:
            cursorColumn = 0
        case 0x0A:
            cursorRow += 1
            ensureCursorVisible()
        case 0x08, 0x7F:
            cursorColumn = max(0, cursorColumn - 1)
        case 0x09:
            insertPrintable(" ")
            insertPrintable(" ")
            insertPrintable(" ")
            insertPrintable(" ")
        case 0x00...0x1F:
            return
        default:
            insertPrintable(Character(scalar))
        }
    }

    private func processEscape(_ scalar: UnicodeScalar) {
        switch Character(scalar) {
        case "[":
            parserState = .csi("")
        case "]":
            parserState = .osc
        default:
            parserState = .ground
        }
    }

    private func processCSI(_ scalar: UnicodeScalar, buffer: String) {
        let value = scalar.value
        if (0x40...0x7E).contains(value) {
            handleCSI(final: Character(scalar), params: buffer)
            parserState = .ground
            return
        }

        parserState = .csi(buffer + String(scalar))
    }

    private func processOSC(_ scalar: UnicodeScalar) {
        if scalar.value == 0x07 || scalar.value == 0x1B {
            parserState = .ground
        }
    }

    private func handleCSI(final: Character, params: String) {
        let cleanParams = params.replacingOccurrences(of: "?", with: "")
        let numbers = cleanParams
            .split(separator: ";", omittingEmptySubsequences: false)
            .map { Int($0) ?? 0 }

        switch final {
        case "m":
            return
        case "K":
            let mode = numbers.first ?? 0
            clearLine(mode: mode)
        case "G":
            cursorColumn = max(0, (numbers.first ?? 1) - 1)
            ensureCursorVisible()
        case "C":
            cursorColumn += max(1, numbers.first ?? 1)
            ensureCursorVisible()
        case "D":
            cursorColumn = max(0, cursorColumn - max(1, numbers.first ?? 1))
        case "A":
            cursorRow = max(0, cursorRow - max(1, numbers.first ?? 1))
        case "B":
            cursorRow += max(1, numbers.first ?? 1)
            ensureCursorVisible()
        case "H", "f":
            let row = max(1, numbers.first ?? 1) - 1
            let column = max(1, numbers.dropFirst().first ?? 1) - 1
            cursorRow = row
            cursorColumn = column
            ensureCursorVisible()
        case "J":
            if numbers.first == 2 {
                lines = [[]]
                cursorRow = 0
                cursorColumn = 0
            }
        default:
            return
        }
    }

    private func clearLine(mode: Int) {
        ensureCursorVisible()
        switch mode {
        case 1:
            if cursorColumn < lines[cursorRow].count {
                lines[cursorRow].removeFirst(min(cursorColumn + 1, lines[cursorRow].count))
            } else {
                lines[cursorRow] = []
            }
            cursorColumn = 0
        case 2:
            lines[cursorRow] = []
            cursorColumn = 0
        default:
            if cursorColumn < lines[cursorRow].count {
                lines[cursorRow].removeSubrange(cursorColumn...)
            }
        }
    }

    private func insertPrintable(_ character: Character) {
        ensureCursorVisible()
        padLineIfNeeded()

        if cursorColumn < lines[cursorRow].count {
            lines[cursorRow][cursorColumn] = character
        } else {
            lines[cursorRow].append(character)
        }

        cursorColumn += 1
    }

    private func ensureCursorVisible() {
        while cursorRow >= lines.count {
            lines.append([])
        }
    }

    private func padLineIfNeeded() {
        if cursorColumn > lines[cursorRow].count {
            lines[cursorRow].append(contentsOf: Array(repeating: " " as Character, count: cursorColumn - lines[cursorRow].count))
        }
    }

    private func trimScrollbackIfNeeded() {
        guard lines.count > maximumScrollbackLines else {
            return
        }

        let overflow = lines.count - maximumScrollbackLines
        lines.removeFirst(overflow)
        cursorRow = max(0, cursorRow - overflow)
    }
}
