import Foundation
import Darwin

enum TerminalInteractivePickerKey: Equatable {
    case up
    case down
    case enter
    case cancel
    case backspace
    case character(Character)
    case other
}

protocol TerminalInteractivePickerDriver {
    func isAvailable() -> Bool
    func withRawMode<Result>(_ body: () throws -> Result) throws -> Result
    func readKey() -> TerminalInteractivePickerKey
    func terminalRowCount() -> Int
    func draw(lines: [String], previousLineCount: Int) -> Int
    func clearRenderedLines(_ lineCount: Int)
    func setCursorVisible(_ isVisible: Bool)
}

struct TerminalInteractivePickerDefaultDriver: TerminalInteractivePickerDriver {
    enum DriverError: Error, LocalizedError {
        case unableToReadTerminalAttributes
        case unableToEnterRawMode
        case unableToRestoreTerminalMode

        var errorDescription: String? {
            switch self {
            case .unableToReadTerminalAttributes:
                return "unable to read terminal attributes"
            case .unableToEnterRawMode:
                return "unable to enter raw terminal mode"
            case .unableToRestoreTerminalMode:
                return "unable to restore terminal mode"
            }
        }
    }

    func isAvailable() -> Bool {
        isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1
    }

    func withRawMode<Result>(_ body: () throws -> Result) throws -> Result {
        var original = termios()
        guard tcgetattr(STDIN_FILENO, &original) == 0 else {
            throw DriverError.unableToReadTerminalAttributes
        }

        var raw = original
        cfmakeraw(&raw)
        guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == 0 else {
            throw DriverError.unableToEnterRawMode
        }

        do {
            let result = try body()
            guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &original) == 0 else {
                throw DriverError.unableToRestoreTerminalMode
            }
            return result
        } catch {
            _ = tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
            throw error
        }
    }

    func readKey() -> TerminalInteractivePickerKey {
        guard let byte = readByte() else {
            return .cancel
        }

        switch byte {
        case 0x03:
            return .cancel
        case 0x0A, 0x0D:
            return .enter
        case 0x08, 0x7F:
            return .backspace
        case 0x1B:
            guard let second = readByte(timeoutMicroseconds: 50_000) else {
                return .cancel
            }
            guard second == 0x5B, let third = readByte(timeoutMicroseconds: 50_000) else {
                return .cancel
            }
            if third == 0x41 {
                return .up
            }
            if third == 0x42 {
                return .down
            }
            return .other
        case 0x6A:
            return .down
        case 0x6B:
            return .up
        case 0x20...0x7E:
            guard let scalar = UnicodeScalar(Int(byte)) else {
                return .other
            }
            return .character(Character(scalar))
        default:
            return .other
        }
    }

    func terminalRowCount() -> Int {
        var size = winsize()
        guard ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0, size.ws_row > 0 else {
            return 24
        }
        return Int(size.ws_row)
    }

    func draw(lines: [String], previousLineCount: Int) -> Int {
        clearRenderedLines(previousLineCount)
        write(lines.map { "\u{1B}[2K\r\($0)" }.joined(separator: "\n") + "\n")
        return lines.count
    }

    func clearRenderedLines(_ lineCount: Int) {
        guard lineCount > 0 else {
            return
        }

        write("\u{1B}[\(lineCount)A")
        for index in 0..<lineCount {
            write("\u{1B}[2K\r")
            if index < lineCount - 1 {
                write("\u{1B}[1B")
            }
        }
        write("\u{1B}[\(lineCount - 1)A")
    }

    func setCursorVisible(_ isVisible: Bool) {
        write(isVisible ? "\u{1B}[?25h" : "\u{1B}[?25l")
    }

    private func readByte(timeoutMicroseconds: Int? = nil) -> UInt8? {
        if let timeoutMicroseconds {
            let flags = fcntl(STDIN_FILENO, F_GETFL, 0)
            guard flags >= 0 else {
                return nil
            }
            guard fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK) >= 0 else {
                return nil
            }
            defer {
                _ = fcntl(STDIN_FILENO, F_SETFL, flags)
            }

            let deadline = Date().addingTimeInterval(Double(timeoutMicroseconds) / 1_000_000)
            while Date() < deadline {
                var byte: UInt8 = 0
                let count = Darwin.read(STDIN_FILENO, &byte, 1)
                if count == 1 {
                    return byte
                }
                if errno != EAGAIN && errno != EWOULDBLOCK {
                    return nil
                }
                usleep(1_000)
            }
            return nil
        }

        var byte: UInt8 = 0
        let count = Darwin.read(STDIN_FILENO, &byte, 1)
        return count == 1 ? byte : nil
    }

    private func write(_ text: String) {
        FileHandle.standardOutput.write(Data(text.utf8))
    }
}

struct TerminalInteractivePickerSearchMatcher {
    static func matches(term: String, in candidate: String) -> Bool {
        if candidate.contains(term) {
            return true
        }

        var remaining = term[...]
        for character in candidate where remaining.first == character {
            remaining.removeFirst()
            if remaining.isEmpty {
                return true
            }
        }
        return remaining.isEmpty
    }
}

struct TerminalInteractivePickerRenderState<Item> {
    let items: [Item]
    let totalItemCount: Int
    let selectedIndex: Int
    let searchQuery: String
    let viewport: ThemePickerViewport
}

struct TerminalInteractivePickerEngine<Item> {
    enum EngineError: Error, LocalizedError {
        case terminalUnavailable

        var errorDescription: String? {
            switch self {
            case .terminalUnavailable:
                return "interactive terminal is not available"
            }
        }
    }

    private let allItems: [Item]
    private let initialSelectedIndex: Int
    private let filterItems: ([Item], String) -> [Item]
    private let renderLines: (TerminalInteractivePickerRenderState<Item>) -> [String]
    private let driver: any TerminalInteractivePickerDriver

    init(
        allItems: [Item],
        initialSelectedIndex: Int,
        filterItems: @escaping ([Item], String) -> [Item],
        renderLines: @escaping (TerminalInteractivePickerRenderState<Item>) -> [String],
        driver: any TerminalInteractivePickerDriver = TerminalInteractivePickerDefaultDriver()
    ) {
        self.allItems = allItems
        self.initialSelectedIndex = initialSelectedIndex
        self.filterItems = filterItems
        self.renderLines = renderLines
        self.driver = driver
    }

    static func isAvailable() -> Bool {
        TerminalInteractivePickerDefaultDriver().isAvailable()
    }

    func select() throws -> Item? {
        guard driver.isAvailable() else {
            throw EngineError.terminalUnavailable
        }
        guard allItems.isEmpty == false else {
            return nil
        }

        var selectedIndex = min(max(0, initialSelectedIndex), allItems.count - 1)
        var query = ""
        var filteredItems = filterItems(allItems, query)
        var renderedLineCount = 0

        return try driver.withRawMode {
            driver.setCursorVisible(false)
            defer {
                driver.clearRenderedLines(renderedLineCount)
                driver.setCursorVisible(true)
            }

            renderedLineCount = render(filteredItems: filteredItems, selectedIndex: selectedIndex, query: query, previousLineCount: renderedLineCount)
            while true {
                switch driver.readKey() {
                case .up:
                    guard filteredItems.isEmpty == false else {
                        continue
                    }
                    selectedIndex = selectedIndex == 0 ? filteredItems.count - 1 : selectedIndex - 1
                case .down:
                    guard filteredItems.isEmpty == false else {
                        continue
                    }
                    selectedIndex = selectedIndex == filteredItems.count - 1 ? 0 : selectedIndex + 1
                case .enter:
                    guard filteredItems.isEmpty == false else {
                        continue
                    }
                    return filteredItems[selectedIndex]
                case .cancel:
                    return nil
                case .backspace:
                    guard query.isEmpty == false else {
                        continue
                    }
                    query.removeLast()
                    filteredItems = filterItems(allItems, query)
                    selectedIndex = min(selectedIndex, max(0, filteredItems.count - 1))
                case .character(let character):
                    query.append(character)
                    filteredItems = filterItems(allItems, query)
                    selectedIndex = 0
                case .other:
                    continue
                }

                renderedLineCount = render(filteredItems: filteredItems, selectedIndex: selectedIndex, query: query, previousLineCount: renderedLineCount)
            }
        }
    }

    private func render(
        filteredItems: [Item],
        selectedIndex: Int,
        query: String,
        previousLineCount: Int
    ) -> Int {
        let viewport = ThemePickerViewport.make(
            itemCount: filteredItems.count,
            selectedIndex: selectedIndex,
            terminalRows: driver.terminalRowCount(),
            reservedRows: 3
        )
        return driver.draw(
            lines: renderLines(
                TerminalInteractivePickerRenderState(
                    items: filteredItems,
                    totalItemCount: allItems.count,
                    selectedIndex: selectedIndex,
                    searchQuery: query,
                    viewport: viewport
                )
            ),
            previousLineCount: previousLineCount
        )
    }
}
