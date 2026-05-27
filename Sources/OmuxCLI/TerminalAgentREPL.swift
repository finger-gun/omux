import Foundation
import Darwin

enum TerminalAgentREPLEvent: Equatable {
    case character(Character)
    case enter
    case backspace
    case up
    case down
    case pageUp
    case pageDown
    case escape
    case ctrlC
    case other
}

struct TerminalAgentREPLSize: Equatable {
    var rows: Int
    var columns: Int
}

protocol TerminalAgentREPLDriver {
    func isAvailable() -> Bool
    func runScreen<Result>(_ body: () throws -> Result) throws -> Result
    func readEvent() -> TerminalAgentREPLEvent
    func terminalSize() -> TerminalAgentREPLSize
    func render(lines: [String])
}

struct TerminalAgentREPLDefaultDriver: TerminalAgentREPLDriver {
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

    func runScreen<Result>(_ body: () throws -> Result) throws -> Result {
        var original = termios()
        guard tcgetattr(STDIN_FILENO, &original) == 0 else {
            throw DriverError.unableToReadTerminalAttributes
        }

        var raw = original
        cfmakeraw(&raw)
        guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == 0 else {
            throw DriverError.unableToEnterRawMode
        }

        write("\u{1B}[?1049h\u{1B}[?25l\u{1B}[2J\u{1B}[H")
        do {
            let result = try body()
            write("\u{1B}[2J\u{1B}[H\u{1B}[?25h\u{1B}[?1049l")
            guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &original) == 0 else {
                throw DriverError.unableToRestoreTerminalMode
            }
            return result
        } catch {
            _ = tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
            write("\u{1B}[2J\u{1B}[H\u{1B}[?25h\u{1B}[?1049l")
            throw error
        }
    }

    func readEvent() -> TerminalAgentREPLEvent {
        guard let byte = readByte() else {
            return .escape
        }

        switch byte {
        case 0x03:
            return .ctrlC
        case 0x0A, 0x0D:
            return .enter
        case 0x08, 0x7F:
            return .backspace
        case 0x1B:
            guard let second = readByte(timeoutMicroseconds: 50_000) else {
                return .escape
            }
            guard second == 0x5B else {
                return .escape
            }
            guard let third = readByte(timeoutMicroseconds: 50_000) else {
                return .escape
            }
            switch third {
            case 0x41:
                return .up
            case 0x42:
                return .down
            case 0x35:
                _ = readByte(timeoutMicroseconds: 50_000)
                return .pageUp
            case 0x36:
                _ = readByte(timeoutMicroseconds: 50_000)
                return .pageDown
            default:
                return .other
            }
        case 0x20...0x7E:
            guard let scalar = UnicodeScalar(Int(byte)) else {
                return .other
            }
            return .character(Character(scalar))
        default:
            return .other
        }
    }

    func terminalSize() -> TerminalAgentREPLSize {
        var size = winsize()
        guard ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0, size.ws_row > 0, size.ws_col > 0 else {
            return TerminalAgentREPLSize(rows: 24, columns: 80)
        }
        return TerminalAgentREPLSize(rows: Int(size.ws_row), columns: Int(size.ws_col))
    }

    func render(lines: [String]) {
        write("\u{1B}[H")
        let frame = lines.map { "\u{1B}[2K\r\($0)" }.joined(separator: "\r\n")
        write(frame)
        write("\u{1B}[J")
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
            defer { _ = fcntl(STDIN_FILENO, F_SETFL, flags) }

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

struct OmuxAgentREPLRequest {
    var systemInstruction: String?
    var verbose: Bool
    var allowReadAnywhere: Bool
}

final class OmuxAgentREPLRunner: @unchecked Sendable {
    private final class AsyncResultBox<T>: @unchecked Sendable {
        var result: Result<T, Error>?
    }

    private enum EntryKind {
        case user
        case assistant
        case note
        case error
        case tool
    }

    private struct TranscriptEntry {
        var kind: EntryKind
        var text: String
    }

    private struct ToolStats {
        var callCount = 0
        var totalOutputBytes = 0
        var lastOutputBytes = 0
        var lastEvent = ""
    }

    private let writeErrorLine: @Sendable (String) -> Void
    private let request: OmuxAgentREPLRequest
    private let hostContext: String
    private let workingDirectoryURL: URL
    private let sessionFactory: AnyOmuxAgentChatSessionFactory
    private let driver: any TerminalAgentREPLDriver
    private let lock = NSLock()

    private var session: AnyOmuxAgentChatSession?
    private var transcript: [TranscriptEntry] = []
    private var contextTurns: [TranscriptEntry] = []
    private var input = ""
    private var stateLabel = "starting"
    private var scrollOffset = 0
    private var shouldExit = false
    private var toolStats = ToolStats()
    private var compactionSummary: String?
    private var lastTurnApproxTokens = 0

    init(
        writeErrorLine: @escaping @Sendable (String) -> Void,
        request: OmuxAgentREPLRequest,
        hostContext: String,
        workingDirectoryURL: URL,
        sessionFactory: OmuxAgentChatSessionFactorying,
        driver: any TerminalAgentREPLDriver = TerminalAgentREPLDefaultDriver()
    ) {
        self.writeErrorLine = writeErrorLine
        self.request = request
        self.hostContext = hostContext
        self.workingDirectoryURL = workingDirectoryURL
        self.sessionFactory = AnyOmuxAgentChatSessionFactory(sessionFactory)
        self.driver = driver
    }

    func run() -> Int32 {
        do {
            return try driver.runScreen {
                try initializeSession()
                render()
                while shouldExit == false {
                    handle(event: driver.readEvent())
                }
                return 0
            }
        } catch {
            writeErrorLine("[omux agent] REPL setup failed: \(error.localizedDescription)")
            return 1
        }
    }

    private func initializeSession() throws {
        stateLabel = "connecting"
        render()
        let verboseHandler = makeVerboseHandler()
        let toolEventHandler: @Sendable (OmuxAgentToolEvent) -> Void = { [weak self] event in
            self?.handleToolEvent(event)
        }
        let createdSession = try sessionFactory.makeSession(
            systemInstruction: effectiveSystemInstruction(),
            hostContext: hostContext,
            workingDirectoryURL: workingDirectoryURL,
            allowReadAnywhere: request.allowReadAnywhere,
            onVerbose: verboseHandler,
            onToolEvent: toolEventHandler
        )
        session = createdSession
        stateLabel = "ready"
    }

    private func makeVerboseHandler() -> (@Sendable (String) -> Void)? {
        guard request.verbose else { return nil }
        let writeErrorLine = self.writeErrorLine
        return { message in
            writeErrorLine("[omux agent] \(message)")
        }
    }

    private func handle(event: TerminalAgentREPLEvent) {
        switch event {
        case .ctrlC, .escape:
            shouldExit = true
        case .backspace:
            guard input.isEmpty == false else { return }
            input.removeLast()
        case .enter:
            submitInputIfNeeded()
        case .character(let character):
            input.append(character)
        case .up:
            scrollOffset += 1
        case .down:
            scrollOffset = max(0, scrollOffset - 1)
        case .pageUp:
            scrollOffset += max(1, driver.terminalSize().rows / 2)
        case .pageDown:
            scrollOffset = max(0, scrollOffset - max(1, driver.terminalSize().rows / 2))
        case .other:
            break
        }
        render()
    }

    private func submitInputIfNeeded() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        input = ""

        if trimmed.hasPrefix("/") {
            runSlashCommand(trimmed)
            render()
            return
        }

        addEntry(kind: .user, text: trimmed)
        contextTurns.append(TranscriptEntry(kind: .user, text: trimmed))
        let assistantIndex = appendEntry(kind: .assistant, text: "")
        stateLabel = "thinking"
        render()

        let result: Result<String, Error> = waitForResult {
            let value = try await self.session?.send(prompt: trimmed, onPartial: { [weak self] chunk in
                self?.appendAssistantChunk(index: assistantIndex, chunk: chunk)
            }) ?? ""
            return value
        }

        switch result {
        case .success(let response):
            replaceEntry(at: assistantIndex, kind: .assistant, text: response.trimmingCharacters(in: .whitespacesAndNewlines))
            contextTurns.append(TranscriptEntry(kind: .assistant, text: response))
            lastTurnApproxTokens = estimateTokens(for: trimmed + "\n" + response)
            stateLabel = "ready"
        case .failure(let error):
            replaceEntry(at: assistantIndex, kind: .error, text: describeOmuxAgentError(error))
            stateLabel = "error"
        }
        render()
    }

    private func runSlashCommand(_ command: String) {
        switch command {
        case "/help":
            addEntry(kind: .note, text: "Commands: /help /clear /stats /tools /compact /exit")
        case "/clear":
            transcript.removeAll()
            addEntry(kind: .note, text: "Cleared visible transcript. Session context is still active.")
        case "/stats":
            addEntry(kind: .note, text: statsText())
        case "/tools":
            let tools = session?.toolNames.joined(separator: ", ") ?? "(unavailable)"
            addEntry(kind: .note, text: "Tools: \(tools)")
        case "/compact":
            compactSession()
        case "/exit":
            shouldExit = true
        default:
            addEntry(kind: .error, text: "Unknown command: \(command)")
        }
    }

    private func compactSession() {
        stateLabel = "compacting"
        render()
        let transcriptText = contextTurns.map { entry in
            "\(entryLabel(for: entry.kind)): \(entry.text)"
        }.joined(separator: "\n\n")

        let result: Result<String, Error> = waitForResult {
            try await self.session?.summarizeForCompaction(transcript: transcriptText) ?? ""
        }

        switch result {
        case .success(let summary):
            let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedSummary.isEmpty == false else {
                addEntry(kind: .error, text: "Compaction produced an empty summary.")
                stateLabel = "error"
                return
            }
            compactionSummary = trimmedSummary
            let preservedEntries = Array(transcript.suffix(6))
            transcript = [.init(kind: .note, text: "Compacted prior conversation: \(trimmedSummary)")] + preservedEntries
            contextTurns.removeAll()
            do {
                try initializeSession()
                stateLabel = "ready"
            } catch {
                addEntry(kind: .error, text: describeOmuxAgentError(error))
                stateLabel = "error"
            }
        case .failure(let error):
            addEntry(kind: .error, text: "Compaction failed: \(describeOmuxAgentError(error))")
            stateLabel = "error"
        }
    }

    private func handleToolEvent(_ event: OmuxAgentToolEvent) {
        lock.lock()
        defer { lock.unlock() }
        switch event.phase {
        case .started:
            toolStats.callCount += 1
            toolStats.lastEvent = "\(event.toolName) \(event.detail)"
            stateLabel = "calling tool"
        case .completed:
            toolStats.lastEvent = "\(event.toolName) \(event.detail)"
            if let bytes = event.outputBytes {
                toolStats.totalOutputBytes += bytes
                toolStats.lastOutputBytes = bytes
            }
            stateLabel = "streaming"
        case .failed:
            toolStats.lastEvent = "\(event.toolName) failed: \(event.detail)"
            stateLabel = "error"
        }
        transcript.append(.init(kind: .tool, text: "tool \(event.toolName): \(event.phase) \(event.detail)"))
        scrollOffset = 0
        renderLocked()
    }

    private func appendAssistantChunk(index: Int, chunk: String) {
        lock.lock()
        defer { lock.unlock() }
        guard transcript.indices.contains(index) else { return }
        transcript[index].text += chunk
        stateLabel = "streaming"
        scrollOffset = 0
        renderLocked()
    }

    private func appendEntry(kind: EntryKind, text: String) -> Int {
        transcript.append(TranscriptEntry(kind: kind, text: text))
        scrollOffset = 0
        return transcript.count - 1
    }

    private func addEntry(kind: EntryKind, text: String) {
        lock.lock()
        defer { lock.unlock() }
        _ = appendEntry(kind: kind, text: text)
    }

    private func replaceEntry(at index: Int, kind: EntryKind, text: String) {
        lock.lock()
        defer { lock.unlock() }
        guard transcript.indices.contains(index) else { return }
        transcript[index] = TranscriptEntry(kind: kind, text: text)
        scrollOffset = 0
    }

    private func render() {
        lock.lock()
        defer { lock.unlock() }
        renderLocked()
    }

    private func renderLocked() {
        let size = driver.terminalSize()
        let transcriptLines = flattenedTranscriptLines(width: size.columns)
        let header = fit("omux agent  /help  /clear  /stats  /tools  /compact  /exit", width: size.columns)
        let footer = footerLine(width: size.columns)
        let prompt = wrapLine(
            input.isEmpty ? "> " : "> \(input)",
            width: size.columns,
            continuationPrefix: "  "
        )
        let reservedRows = 1 + prompt.count + 2
        let visibleRows = max(1, size.rows - reservedRows)
        let visibleTranscript = viewport(lines: transcriptLines, visibleRows: visibleRows)

        var lines = [header]
        lines.append(contentsOf: visibleTranscript)
        while lines.count < 1 + visibleRows {
            lines.append("")
        }
        lines.append(String(repeating: "-", count: max(1, size.columns)))
        lines.append(contentsOf: prompt.map { fit($0, width: size.columns) })
        lines.append(fit(footer, width: size.columns))
        driver.render(lines: lines)
    }

    private func flattenedTranscriptLines(width: Int) -> [String] {
        guard transcript.isEmpty == false else {
            return [
                fit("Ask about this repo, terminal history, or OpenMUX actions.", width: width),
                fit("Press Enter to send. Use Up/Down to scroll, /compact when context gets tight.", width: width),
            ]
        }

        return transcript.flatMap { entry in
            let prefix = "\(entryLabel(for: entry.kind)) "
            let continuationPrefix = String(repeating: " ", count: prefix.count)
            let wrapped = wrapLine(
                prefix + entry.text,
                width: width,
                continuationPrefix: continuationPrefix
            )
            return wrapped.isEmpty ? [prefix] : wrapped
        }
    }

    private func viewport(lines: [String], visibleRows: Int) -> [String] {
        guard lines.isEmpty == false else { return [""] }
        let maxOffset = max(0, lines.count - visibleRows)
        let clampedOffset = min(scrollOffset, maxOffset)
        let end = lines.count - clampedOffset
        let start = max(0, end - visibleRows)
        return Array(lines[start..<end])
    }

    private func footerLine(width: Int) -> String {
        let toolSummary = session?.toolNames.count ?? 0
        let contextTokens = estimateContextTokens()
        let usage = "state \(stateLabel) | tools \(toolSummary) | ctx ~\(contextTokens)/4096 | turn ~\(lastTurnApproxTokens) | tool \(formatBytes(toolStats.lastOutputBytes))"
        return fit(usage, width: width)
    }

    private func statsText() -> String {
        "Approx context ~\(estimateContextTokens()) tokens. Tool calls \(toolStats.callCount). Tool output \(formatBytes(toolStats.totalOutputBytes)) total. Last tool: \(toolStats.lastEvent.isEmpty ? "none" : toolStats.lastEvent)."
    }

    private func estimateContextTokens() -> Int {
        let transcriptText = contextTurns.map(\.text).joined(separator: "\n")
        let summaryText = compactionSummary ?? ""
        return estimateTokens(for: transcriptText + "\n" + summaryText + "\n" + input)
    }

    private func effectiveSystemInstruction() -> String? {
        guard let compactionSummary else {
            return request.systemInstruction
        }
        let base = OmuxSystemAgentGenerator.effectiveSystemInstruction(request.systemInstruction)
        return """
        \(base)

        Compacted prior conversation summary:
        \(compactionSummary)
        """
    }

    private func estimateTokens(for text: String) -> Int {
        let utf8Count = text.utf8.count
        guard utf8Count > 0 else { return 0 }
        return max(1, Int(ceil(Double(utf8Count) / 4.0)))
    }

    private func entryLabel(for kind: EntryKind) -> String {
        switch kind {
        case .user:
            return "You:"
        case .assistant:
            return "Agent:"
        case .note:
            return "Note:"
        case .error:
            return "Error:"
        case .tool:
            return "Tool:"
        }
    }

    private func wrapLine(_ text: String, width: Int, continuationPrefix: String = "") -> [String] {
        let safeWidth = max(10, width)
        let rawLines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var wrappedLines: [String] = []

        for rawLine in rawLines {
            if rawLine.isEmpty {
                wrappedLines.append("")
                continue
            }

            var remaining = rawLine[...]
            var isFirstSegment = true
            while remaining.isEmpty == false {
                let prefix = isFirstSegment ? "" : continuationPrefix
                let availableWidth = max(1, safeWidth - prefix.count)
                if remaining.count <= availableWidth {
                    wrappedLines.append(prefix + remaining)
                    break
                }

                let segmentEnd = remaining.index(remaining.startIndex, offsetBy: availableWidth)
                let candidate = remaining[..<segmentEnd]
                let breakIndex = candidate.lastIndex(where: \.isWhitespace) ?? candidate.endIndex

                if breakIndex == candidate.startIndex {
                    wrappedLines.append(prefix + candidate)
                    remaining = remaining[segmentEnd...]
                } else {
                    let segment = remaining[..<breakIndex]
                    wrappedLines.append(prefix + segment.trimmingCharacters(in: .whitespaces))
                    remaining = remaining[breakIndex...].drop(while: \.isWhitespace)
                }
                isFirstSegment = false
            }
        }

        return wrappedLines
    }

    private func fit(_ text: String, width: Int) -> String {
        let clipped = String(text.prefix(max(1, width)))
        if clipped.count < width {
            return clipped + String(repeating: " ", count: width - clipped.count)
        }
        return clipped
    }

    private func formatBytes(_ bytes: Int) -> String {
        guard bytes > 0 else { return "0 B" }
        if bytes >= 1_048_576 {
            return String(format: "%.1f MB", Double(bytes) / 1_048_576)
        }
        if bytes >= 1_024 {
            return String(format: "%.1f KB", Double(bytes) / 1_024)
        }
        return "\(bytes) B"
    }

    private func waitForResult<T>(_ operation: @escaping @Sendable () async throws -> T) -> Result<T, Error> {
        let semaphore = DispatchSemaphore(value: 0)
        let box = AsyncResultBox<T>()
        Task {
            do {
                box.result = .success(try await operation())
            } catch {
                box.result = .failure(error)
            }
            semaphore.signal()
        }
        semaphore.wait()
        return box.result!
    }
}
