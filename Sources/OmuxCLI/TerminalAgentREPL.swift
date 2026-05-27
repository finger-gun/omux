import Foundation
import Darwin
import OmuxConfig
import OmuxControlPlane
import OmuxCore
import OmuxHooks
import OmuxTheme

enum TerminalAgentREPLEvent: Equatable {
    case character(Character)
    case enter
    case newline
    case backspace
    case up
    case down
    case pageUp
    case pageDown
    case resize
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
    func supportsStyling() -> Bool
    func render(lines: [String])
}

struct TerminalAgentREPLDefaultDriver: TerminalAgentREPLDriver {
    private final class DriverState {
        var signalSource: DispatchSourceSignal?
        private let lock = NSLock()
        private var resizePending = false

        func markResizePending() {
            lock.lock()
            resizePending = true
            lock.unlock()
        }

        func consumeResizeEvent() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard resizePending else {
                return false
            }
            resizePending = false
            return true
        }
    }

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

    private let state = DriverState()

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

        signal(SIGWINCH, SIG_IGN)
        let signalSource = DispatchSource.makeSignalSource(
            signal: SIGWINCH,
            queue: DispatchQueue(label: "omux.agent.repl.resize")
        )
        signalSource.setEventHandler {
            self.state.markResizePending()
        }
        signalSource.resume()
        state.signalSource = signalSource

        write("\u{1B}[?1049h\u{1B}[?25l\u{1B}[2J\u{1B}[H")
        do {
            let result = try body()
            write("\u{1B}[2J\u{1B}[H\u{1B}[?25h\u{1B}[?1049l")
            signalSource.cancel()
            state.signalSource = nil
            signal(SIGWINCH, SIG_DFL)
            guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &original) == 0 else {
                throw DriverError.unableToRestoreTerminalMode
            }
            return result
        } catch {
            signalSource.cancel()
            state.signalSource = nil
            signal(SIGWINCH, SIG_DFL)
            _ = tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
            write("\u{1B}[2J\u{1B}[H\u{1B}[?25h\u{1B}[?1049l")
            throw error
        }
    }

    func readEvent() -> TerminalAgentREPLEvent {
        if consumeResizeEvent() {
            return .resize
        }

        while true {
            guard let byte = readByte(timeoutMicroseconds: 100_000) else {
                if consumeResizeEvent() {
                    return .resize
                }
                continue
            }

            switch byte {
            case 0x03:
                return .ctrlC
            case 0x0A:
                return .newline
            case 0x0D:
                return .enter
            case 0x08, 0x7F:
                return .backspace
            case 0x1B:
                return readEscapeEvent()
            case 0x20...0x7E:
                guard let scalar = UnicodeScalar(Int(byte)) else {
                    return .other
                }
                return .character(Character(scalar))
            default:
                return .other
            }
        }
    }

    func terminalSize() -> TerminalAgentREPLSize {
        var size = winsize()
        guard ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0, size.ws_row > 0, size.ws_col > 0 else {
            return TerminalAgentREPLSize(rows: 24, columns: 80)
        }
        return TerminalAgentREPLSize(rows: Int(size.ws_row), columns: Int(size.ws_col))
    }

    func supportsStyling() -> Bool {
        true
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

    private func readEscapeEvent() -> TerminalAgentREPLEvent {
        guard let second = readByte(timeoutMicroseconds: 50_000) else {
            return .escape
        }
        guard second == 0x5B else {
            return .escape
        }

        var bytes: [UInt8] = []
        while let next = readByte(timeoutMicroseconds: 50_000) {
            bytes.append(next)
            if (0x40...0x7E).contains(next) {
                break
            }
            if bytes.count >= 16 {
                break
            }
        }
        return Self.parseCSI(bytes)
    }

    private func consumeResizeEvent() -> Bool {
        state.consumeResizeEvent()
    }

    static func parseCSI(_ bytes: [UInt8]) -> TerminalAgentREPLEvent {
        guard let final = bytes.last else {
            return .escape
        }

        switch final {
        case 0x41:
            return .up
        case 0x42:
            return .down
        case 0x7E:
            let body = String(decoding: bytes.dropLast(), as: UTF8.self)
            if body == "5" {
                return .pageUp
            }
            if body == "6" {
                return .pageDown
            }
            if body == "27;2;13" || body == "13;2" {
                return .newline
            }
            return .other
        case 0x75: // kitty CSI u keyboard protocol
            let body = String(decoding: bytes.dropLast(), as: UTF8.self)
            if body == "13;2" {
                return .newline
            }
            return .other
        default:
            return .other
        }
    }

    private func write(_ text: String) {
        FileHandle.standardOutput.write(Data(text.utf8))
    }
}

struct OmuxAgentREPLRequest {
    var systemInstruction: String?
    var verbose: Bool
    var allowReadAnywhere: Bool
    var agentConfiguration: OmuxConfigAgent

    init(
        systemInstruction: String?,
        verbose: Bool,
        allowReadAnywhere: Bool,
        agentConfiguration: OmuxConfigAgent = OmuxConfigAgent()
    ) {
        self.systemInstruction = systemInstruction
        self.verbose = verbose
        self.allowReadAnywhere = allowReadAnywhere
        self.agentConfiguration = agentConfiguration
    }
}

final class OmuxAgentREPLRunner: @unchecked Sendable {
    private static let slashCommands = ["/help", "/clear", "/stats", "/tools", "/compact", "/handoff", "/exit"]
    private static let slashCommandDescriptions: [String: String] = [
        "/help": "show repl help",
        "/clear": "clear visible transcript",
        "/stats": "show context and tool stats",
        "/tools": "list available tools",
        "/compact": "summarize and rebuild session",
        "/handoff": "write a continuation brief",
        "/exit": "leave the repl"
    ]

    private struct RenderPalette {
        let themeName: String
        let themeDisplayName: String
        let backgroundCanvas: ThemeColor
        let backgroundSurface: ThemeColor
        let backgroundElevated: ThemeColor
        let foregroundPrimary: ThemeColor
        let foregroundSecondary: ThemeColor
        let foregroundMuted: ThemeColor
        let borderStrong: ThemeColor
        let borderSubtle: ThemeColor
        let accent: ThemeColor
        let selectionBackground: ThemeColor
        let selectionForeground: ThemeColor
        let success: ThemeColor
        let warning: ThemeColor
        let danger: ThemeColor
        let brightAccent: ThemeColor

        init(theme: OmuxTheme) {
            let tokens = ResolvedThemeTokens(theme: theme)
            self.themeName = theme.name
            self.themeDisplayName = theme.displayName
            self.backgroundCanvas = tokens[.backgroundCanvas]
            self.backgroundSurface = tokens[.backgroundSurface]
            self.backgroundElevated = tokens[.backgroundElevated]
            self.foregroundPrimary = tokens[.foregroundPrimary]
            self.foregroundSecondary = tokens[.foregroundSecondary]
            self.foregroundMuted = tokens[.foregroundMuted]
            self.borderStrong = tokens[.borderStrong]
            self.borderSubtle = tokens[.borderSubtle]
            self.accent = tokens[.accent]
            self.selectionBackground = tokens[.selectionBackground]
            self.selectionForeground = tokens[.selectionForeground]
            self.success = tokens[.ansiGreen]
            self.warning = tokens[.ansiYellow]
            self.danger = tokens[.ansiRed]
            self.brightAccent = tokens[.ansiBrightMagenta]
        }
    }

    private enum Tone {
        case muted
        case strong
        case accent
        case lavender
        case danger
        case success
    }

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
        var totalOutputTokens = 0
        var lastOutputBytes = 0
        var lastTurnOutputBytes = 0
        var lastTurnOutputTokens = 0
        var lastEvent = ""
        var activeToolName: String?
    }

    private struct SlashOverlayState {
        var matches: [String]
        var selectedIndex: Int
    }

    private let writeErrorLine: @Sendable (String) -> Void
    private let request: OmuxAgentREPLRequest
    private let hostContext: String
    private let hostMetadata: OmuxAgentHostContext
    private let workingDirectoryURL: URL
    private let sessionFactory: AnyOmuxAgentChatSessionFactory
    private let observationClient: OmuxAgentObservationClient
    private let driver: any TerminalAgentREPLDriver
    private let lock = NSLock()
    private let palette: RenderPalette

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
    private var pendingAssistantIndex: Int?
    private var slashSelectionIndex = 0
    private let startedAt = Date()

    init(
        writeErrorLine: @escaping @Sendable (String) -> Void,
        request: OmuxAgentREPLRequest,
        hostContext: String,
        hostMetadata: OmuxAgentHostContext = OmuxAgentHostContext(
            currentWorkingDirectory: FileManager.default.currentDirectoryPath,
            fileReadScope: "cwd-only",
            focusedWorkspaceID: nil,
            focusedTabID: nil,
            focusedPaneID: nil,
            focusedSessionID: nil,
            openMUXContextAvailable: false
        ),
        workingDirectoryURL: URL,
        sessionFactory: OmuxAgentChatSessionFactorying,
        observationClient: OmuxAgentObservationClient = OmuxAgentObservationClient(client: OmuxControlClient()),
        driver: any TerminalAgentREPLDriver = TerminalAgentREPLDefaultDriver()
    ) {
        self.writeErrorLine = writeErrorLine
        self.request = request
        self.hostContext = hostContext
        self.hostMetadata = hostMetadata
        self.workingDirectoryURL = workingDirectoryURL
        self.sessionFactory = AnyOmuxAgentChatSessionFactory(sessionFactory)
        self.observationClient = observationClient
        self.driver = driver
        self.palette = Self.loadRenderPalette()
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
            agentConfiguration: request.agentConfiguration,
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
        case .newline:
            insertComposerNewline()
        case .backspace:
            guard input.isEmpty == false else { return }
            input.removeLast()
            clampSlashSelection()
        case .enter:
            submitInputIfNeeded()
        case .character(let character):
            input.append(character)
            clampSlashSelection()
        case .up:
            if updateSlashSelection(delta: -1) == false {
                scrollOffset += 1
            }
        case .down:
            if updateSlashSelection(delta: 1) == false {
                scrollOffset = max(0, scrollOffset - 1)
            }
        case .pageUp:
            scrollOffset += max(1, driver.terminalSize().rows / 2)
        case .pageDown:
            scrollOffset = max(0, scrollOffset - max(1, driver.terminalSize().rows / 2))
        case .resize:
            break
        case .other:
            break
        }
        render()
    }

    private func submitInputIfNeeded() {
        let rawInput = input
        var trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        var promptText = rawInput
        if let selectedSlashCommand = selectedSlashCommand(for: trimmed) {
            trimmed = selectedSlashCommand
            promptText = selectedSlashCommand
        }
        input = ""
        slashSelectionIndex = 0

        if trimmed.hasPrefix("/") {
            runSlashCommand(trimmed)
            render()
            return
        }

        addEntry(kind: .user, text: promptText)
        contextTurns.append(TranscriptEntry(kind: .user, text: promptText))
        let assistantIndex = appendEntry(kind: .assistant, text: "")
        pendingAssistantIndex = assistantIndex
        stateLabel = "thinking"
        render()
        publishObservation(
            eventName: .agentPromptSubmitted,
            hookCategory: .command,
            hookName: "agent-prompt-submitted",
            payload: .object([
                "prompt": .string(promptText),
                "source": .string("repl"),
            ])
        )

        let submittedPrompt = promptText
        let result: Result<String, Error> = waitForResult {
            let value = try await self.session?.send(prompt: submittedPrompt, onPartial: { [weak self] chunk in
                self?.appendAssistantChunk(chunk: chunk)
            }) ?? ""
            return value
        }

        let resolvedAssistantIndex = pendingAssistantIndex ?? assistantIndex
        switch result {
        case .success(let response):
            replaceEntry(at: resolvedAssistantIndex, kind: .assistant, text: response.trimmingCharacters(in: .whitespacesAndNewlines))
            contextTurns.append(TranscriptEntry(kind: .assistant, text: response))
            lastTurnApproxTokens = estimateTurnTokens(prompt: promptText, response: response)
            stateLabel = "ready"
            pendingAssistantIndex = nil
            publishObservation(
                eventName: .agentResponseCompleted,
                hookCategory: .command,
                hookName: "agent-response-completed",
                payload: .object([
                    "response": .string(response),
                    "source": .string("repl"),
                    "approxTokens": .integer(lastTurnApproxTokens),
                ])
            )
        case .failure(let error):
            replaceEntry(at: resolvedAssistantIndex, kind: .error, text: describeOmuxAgentError(error))
            stateLabel = "error"
            pendingAssistantIndex = nil
        }
        render()
    }

    private func insertComposerNewline() {
        if input.isEmpty {
            return
        }
        input.append("\n")
    }

    private func runSlashCommand(_ command: String) {
        publishObservation(
            eventName: .agentSlashCommandInvoked,
            hookCategory: .command,
            hookName: "agent-slash-command-invoked",
            payload: .object([
                "command": .string(command),
            ])
        )
        switch command {
        case "/help":
            addEntry(kind: .note, text: "Commands: /help /clear /stats /tools /compact /handoff /exit. Press Enter to send, Shift-Enter or Ctrl-J for a newline, Up/Down to scroll.")
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
        case "/handoff":
            writeHandoff()
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

    private func writeHandoff() {
        stateLabel = "handoff"
        render()
        let transcriptText = transcript.map { entry in
            "\(entryLabel(for: entry.kind)): \(entry.text)"
        }.joined(separator: "\n\n")

        let result: Result<String, Error> = waitForResult {
            try await self.session?.summarizeForHandoff(transcript: transcriptText) ?? ""
        }

        switch result {
        case .success(let markdown):
            let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else {
                addEntry(kind: .error, text: "Handoff failed: summary was empty.")
                stateLabel = "error"
                return
            }
            do {
                let outputDirectory = workingDirectoryURL.appendingPathComponent(".omux-handoffs", isDirectory: true)
                try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyyMMdd-HHmmss"
                formatter.locale = Locale(identifier: "en_US_POSIX")
                let fileURL = outputDirectory.appendingPathComponent("\(formatter.string(from: Date())).md", isDirectory: false)
                try (trimmed + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
                addEntry(kind: .note, text: "Wrote handoff: \(fileURL.path)")
                publishObservation(
                    eventName: .agentHandoffWritten,
                    hookCategory: .command,
                    hookName: "agent-handoff-written",
                    payload: .object([
                        "path": .string(fileURL.path),
                    ])
                )
                stateLabel = "ready"
            } catch {
                addEntry(kind: .error, text: "Handoff failed: \(error.localizedDescription)")
                stateLabel = "error"
            }
        case .failure(let error):
            addEntry(kind: .error, text: "Handoff failed: \(describeOmuxAgentError(error))")
            stateLabel = "error"
        }
    }

    private func handleToolEvent(_ event: OmuxAgentToolEvent) {
        lock.lock()
        defer { lock.unlock() }
        switch event.phase {
        case .started:
            toolStats.callCount += 1
            toolStats.lastTurnOutputBytes = 0
            toolStats.lastTurnOutputTokens = 0
            toolStats.lastEvent = "\(event.toolName) \(event.detail)"
            toolStats.activeToolName = event.toolName
            stateLabel = "tool"
            insertToolEntry(formatToolEvent(event))
        case .completed:
            toolStats.lastEvent = "\(event.toolName) \(event.detail)"
            toolStats.activeToolName = nil
            if let bytes = event.outputBytes {
                toolStats.totalOutputBytes += bytes
                toolStats.lastOutputBytes = bytes
                toolStats.lastTurnOutputBytes += bytes
            }
            let outputTokens = event.outputText.map { estimateTokens(for: $0) } ?? estimateTokensFromByteCount(event.outputBytes ?? 0)
            toolStats.totalOutputTokens += outputTokens
            toolStats.lastTurnOutputTokens += outputTokens
            stateLabel = "streaming"
            insertToolEntry(formatToolEvent(event))
        case .failed:
            toolStats.lastEvent = "\(event.toolName) failed: \(event.detail)"
            toolStats.activeToolName = nil
            stateLabel = "error"
            insertToolEntry(formatToolEvent(event))
        }
        scrollOffset = 0
        renderLocked()
    }

    private func appendAssistantChunk(chunk: String) {
        lock.lock()
        defer { lock.unlock() }
        let index = pendingAssistantIndex ?? transcript.indices.last ?? 0
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
        let styled = driver.supportsStyling()
        let contentWidth = max(24, size.columns - 4)
        let transcriptLines = flattenedTranscriptLines(width: contentWidth, styled: styled)
        let slashOverlay = slashOverlayState()
        let composer = composerLines(width: size.columns, styled: styled, slashOverlay: slashOverlay)
        let reservedRows = 2 + composer.count + 1
        let visibleRows = max(1, size.rows - reservedRows)
        let visibleTranscript = viewport(lines: transcriptLines, visibleRows: visibleRows)
        let header = headerLines(width: size.columns, styled: styled)
        let footer = footerLine(width: size.columns, transcriptLineCount: transcriptLines.count, visibleRows: visibleRows, styled: styled)

        var lines = header
        lines.append(contentsOf: visibleTranscript)
        while lines.count < header.count + visibleRows {
            lines.append(backgroundFill(width: size.columns, styled: styled))
        }
        lines.append(contentsOf: composer)
        lines.append(footer)
        driver.render(lines: lines)
    }

    private func visibleRows(for size: TerminalAgentREPLSize, composerHeight: Int) -> Int {
        max(1, size.rows - (2 + composerHeight + 1))
    }

    private func flattenedTranscriptLines(width: Int, styled: Bool) -> [String] {
        guard transcript.isEmpty == false else {
            return [backgroundFill(width: width + 4, styled: styled)]
        }

        var lines: [String] = []
        for (index, entry) in transcript.enumerated() {
            if index > 0 {
                lines.append(backgroundFill(width: width + 4, styled: styled))
            }
            let block = renderTranscriptEntry(entry, width: width, styled: styled)
            lines.append(contentsOf: block)
        }
        return lines
    }

    private func viewport(lines: [String], visibleRows: Int) -> [String] {
        guard lines.isEmpty == false else { return [""] }
        let maxOffset = max(0, lines.count - visibleRows)
        let clampedOffset = min(scrollOffset, maxOffset)
        let end = lines.count - clampedOffset
        let start = max(0, end - visibleRows)
        return Array(lines[start..<end])
    }

    private func footerLine(width: Int, transcriptLineCount: Int, visibleRows: Int, styled: Bool) -> String {
        let toolSummary = session?.toolNames.count ?? 0
        let contextTokens = estimateContextTokens()
        let contextWindow = contextWindowSize()
        let workedFor = formatElapsedTime(Date().timeIntervalSince(startedAt))
        let scroll = scrollSummary(lineCount: transcriptLineCount, visibleRows: visibleRows)
        let toolActivity = toolStats.activeToolName.map { "tool \($0)" } ?? "\(toolSummary) tools"
        let title = toned("OpenMux Agent", tone: .strong, styled: styled)
        let pieces = [
            title,
            toned("·", tone: .muted, styled: styled),
            toned(compactPath(), tone: .success, styled: styled),
            chip(stateLabel, tone: stateTone(), styled: styled),
            chip(toolActivity, tone: .lavender, styled: styled),
            chip("ctx ~\(contextTokens)/\(contextWindow)", tone: .muted, styled: styled),
            chip("last ~\(lastTurnApproxTokens)", tone: .muted, styled: styled),
            chip(scroll, tone: .muted, styled: styled),
            chip(workedFor, tone: .strong, styled: styled)
        ]
        return backgroundPad("  " + pieces.joined(separator: "  "), width: width, styled: styled)
    }

    private func renderSlashOverlay(width: Int, styled: Bool, state: SlashOverlayState?) -> [String] {
        guard let state else { return [] }
        let bodyWidth = width - 8
        let visibleCount = 4
        let maxStart = max(0, state.matches.count - visibleCount)
        let start = min(max(0, state.selectedIndex - (visibleCount - 1)), maxStart)
        let visibleMatches = Array(state.matches[start..<min(state.matches.count, start + visibleCount)])
        var lines = [
            panelLine(
                lead: rail(tone: .lavender, styled: styled),
                content: toned("commands", tone: .lavender, styled: styled),
                fillWidth: bodyWidth,
                styled: styled
            )
        ]
        for (offset, command) in visibleMatches.enumerated() {
            let index = start + offset
            let tone: Tone = index == state.selectedIndex ? .accent : .muted
            let description = Self.slashCommandDescriptions[command] ?? ""
            let content = description.isEmpty
                ? toned(command, tone: tone, styled: styled)
                : toned(command, tone: tone, styled: styled)
                    + toned("  \(description)", tone: .muted, styled: styled)
            lines.append(
                panelLine(
                    lead: rail(tone: tone, styled: styled),
                    content: content,
                    fillWidth: bodyWidth,
                    styled: styled
                )
            )
        }
        return lines
    }

    private func composerLines(width: Int, styled: Bool, slashOverlay: SlashOverlayState?) -> [String] {
        let innerWidth = max(16, width - 12)
        let placeholder = "Write a request. Enter sends, Shift-Enter or Ctrl-J adds a newline."
        let composedText = input.isEmpty ? placeholder : input
        let wrappedInput = wrapLine(
            composedText,
            width: innerWidth,
            continuationPrefix: ""
        )
        let visibleInput = Array(wrappedInput.suffix(2))
        let title = toned("compose", tone: .lavender, styled: styled)
        let controls = fit("enter send   shift-enter newline   / commands", width: max(1, innerWidth - 12))
        let top = panelLine(
            lead: rail(tone: .accent, styled: styled),
            content: title + "  " + toned(controls, tone: .muted, styled: styled),
            fillWidth: width - 8,
            styled: styled
        )

        let inputLines = visibleInput.enumerated().map { index, line in
            let prefix = index == 0 ? "▌ " : "  "
            let tone: Tone = input.isEmpty ? .muted : .strong
            return panelLine(
                lead: rail(tone: .accent, styled: styled),
                content: toned(prefix + fit(line, width: innerWidth - prefix.count), tone: tone, styled: styled),
                fillWidth: width - 8,
                styled: styled
            )
        }

        var normalizedInputLines = inputLines
        while normalizedInputLines.count < 2 {
            normalizedInputLines.append(
                panelLine(
                    lead: rail(tone: .accent, styled: styled),
                    content: toned("", tone: .muted, styled: styled),
                    fillWidth: width - 8,
                    styled: styled
                )
            )
        }

        return [backgroundFill(width: width, styled: styled)]
            + renderSlashOverlay(width: width, styled: styled, state: slashOverlay)
            + [top]
            + normalizedInputLines
            + [backgroundFill(width: width, styled: styled)]
    }

    private func scrollSummary(lineCount: Int, visibleRows: Int) -> String {
        guard lineCount > visibleRows else {
            return "bottom"
        }
        let maxOffset = max(0, lineCount - visibleRows)
        let clampedOffset = min(scrollOffset, maxOffset)
        if clampedOffset == 0 {
            return "bottom"
        }
        if clampedOffset == maxOffset {
            return "top"
        }
        return "scroll +\(clampedOffset)"
    }

    private func statsText() -> String {
        "Approx carried context ~\(estimateContextTokens()) / \(contextWindowSize()) model tokens, including system prompt, host context, visible chat state, and tool payloads. Last turn ~\(lastTurnApproxTokens) tokens. Tool calls \(toolStats.callCount). Tool output \(formatBytes(toolStats.totalOutputBytes)) total. Last tool: \(toolStats.lastEvent.isEmpty ? "none" : toolStats.lastEvent)."
    }

    private func estimateContextTokens() -> Int {
        let transcriptText = contextTurns.map(\.text).joined(separator: "\n")
        let systemText = effectiveSystemInstruction() ?? defaultSystemInstruction()
        let summaryText = compactionSummary ?? ""
        return estimateTokens(for: systemText + "\n" + hostContext + "\n" + transcriptText + "\n" + summaryText + "\n" + input) + toolStats.totalOutputTokens
    }

    private func effectiveSystemInstruction() -> String? {
        guard let compactionSummary else {
            return request.systemInstruction
        }
        let base = {
            #if canImport(FoundationModels)
            OmuxSystemAgentGenerator.effectiveSystemInstruction(request.systemInstruction)
            #else
            request.systemInstruction ?? OmuxSystemAgentGenerator.defaultSystemInstruction
            #endif
        }()
        return """
        \(base)

        Compacted prior conversation summary:
        \(compactionSummary)
        """
    }

    private func defaultSystemInstruction() -> String {
        #if canImport(FoundationModels)
        OmuxSystemAgentGenerator.effectiveSystemInstruction(nil)
        #else
        OmuxSystemAgentGenerator.defaultSystemInstruction
        #endif
    }

    private func publishObservation(
        eventName: ControlPlaneActionEventName,
        hookCategory: HookCategory,
        hookName: String,
        payload: OmuxValue
    ) {
        observationClient.publish(
            eventName: eventName,
            hookCategory: hookCategory,
            hookName: hookName,
            context: OmuxAgentObservationContext(
                cwd: workingDirectoryURL.path,
                workspaceID: hostMetadata.focusedWorkspaceID.map(WorkspaceID.init(rawValue:)),
                tabID: hostMetadata.focusedTabID.map(TabID.init(rawValue:)),
                paneID: hostMetadata.focusedPaneID.map(PaneID.init(rawValue:)),
                sessionID: hostMetadata.focusedSessionID.map(SessionID.init(rawValue:))
            ),
            payload: payload
        )
    }

    private func estimateTokens(for text: String) -> Int {
        if let counted = session?.tokenCount(for: text) {
            return counted
        }
        let utf8Count = text.utf8.count
        guard utf8Count > 0 else { return 0 }
        return max(1, Int(ceil(Double(utf8Count) / 4.0)))
    }

    private func estimateTokensFromByteCount(_ byteCount: Int) -> Int {
        guard byteCount > 0 else { return 0 }
        return max(1, Int(ceil(Double(byteCount) / 4.0)))
    }

    private func estimateTurnTokens(prompt: String, response: String) -> Int {
        estimateTokens(for: prompt + "\n" + response) + toolStats.lastTurnOutputTokens
    }

    private func contextWindowSize() -> Int {
        session?.contextWindowSize ?? 4096
    }

    private func compactPath() -> String {
        let homePath = NSHomeDirectory()
        if workingDirectoryURL.path == homePath {
            return "~"
        }
        if workingDirectoryURL.path.hasPrefix(homePath + "/") {
            return "~" + String(workingDirectoryURL.path.dropFirst(homePath.count))
        }
        return workingDirectoryURL.path
    }

    private func entryLabel(for kind: EntryKind) -> String {
        switch kind {
        case .user:
            return "You"
        case .assistant:
            return "Agent"
        case .note:
            return "Note"
        case .error:
            return "Error"
        case .tool:
            return "Tool"
        }
    }

    private func renderTranscriptEntry(_ entry: TranscriptEntry, width: Int, styled: Bool) -> [String] {
        let label = entryLabel(for: entry.kind)
        let contentWidth = max(12, width - 8)

        switch entry.kind {
        case .assistant:
            let title = toned(label.uppercased(), tone: .lavender, styled: styled)
            let lines = wrapLine(entry.text, width: contentWidth, continuationPrefix: "")
            return panelBlock(
                title: title,
                lines: lines,
                tone: .strong,
                width: width + 4,
                styled: styled
            )
        case .user:
            let title = toned("YOU", tone: .accent, styled: styled)
            let lines = wrapLine(entry.text, width: contentWidth, continuationPrefix: "  ")
            return panelBlock(
                title: title,
                lines: lines,
                tone: .accent,
                width: width + 4,
                styled: styled
            )
        case .note, .error, .tool:
            let titleTone: Tone = entry.kind == .error ? .danger : .muted
            let bodyTone: Tone = entry.kind == .error ? .danger : .muted
            let lines = wrapLine(entry.text, width: contentWidth, continuationPrefix: "")
            return panelBlock(
                title: toned(label.uppercased(), tone: titleTone, styled: styled),
                lines: lines,
                tone: bodyTone,
                width: width + 4,
                styled: styled
            )
        }
    }

    private func headerLines(width: Int, styled: Bool) -> [String] {
        let title = toned("omux agent", tone: .strong, styled: styled)
        let subtitle = toned("interactive local agent", tone: .muted, styled: styled)
        return [
            backgroundPad("  \(title)", width: width, styled: styled),
            backgroundPad("  \(subtitle)", width: width, styled: styled)
        ]
    }

    private func panelBlock(title: String, lines: [String], tone: Tone, width: Int, styled: Bool) -> [String] {
        let paddedWidth = max(16, width - 8)
        var rendered = [panelLine(lead: rail(tone: tone, styled: styled), content: title, fillWidth: paddedWidth, styled: styled)]
        for line in lines {
            rendered.append(
                panelLine(
                    lead: rail(tone: tone, styled: styled),
                    content: toned(fit(line, width: paddedWidth), tone: tone == .accent ? .strong : tone, styled: styled),
                    fillWidth: paddedWidth,
                    styled: styled
                )
            )
        }
        return rendered
    }

    private func panelLine(lead: String, content: String, fillWidth: Int, styled: Bool) -> String {
        let plain = fit(stripANSI(content), width: max(1, fillWidth))
        let styledContent: String
        if styled {
            styledContent = content + String(repeating: " ", count: max(0, fillWidth - plainTextLength(stripANSI(content))))
        } else {
            styledContent = plain
        }
        return backgroundPad("  \(lead) \(styledContent)  ", width: fillWidth + 6, styled: styled)
    }

    private func backgroundFill(width: Int, styled: Bool) -> String {
        backgroundPad("", width: width, styled: styled)
    }

    private func backgroundPad(_ text: String, width: Int, styled: Bool) -> String {
        let safeWidth = max(1, width)
        let plainText = stripANSI(text)
        let plainLength = plainText.count
        if styled == false {
            return fit(plainText, width: safeWidth)
        }

        if plainLength > safeWidth {
            let clipped = fit(plainText, width: safeWidth)
            return ansi(fg: palette.foregroundPrimary, bg: palette.backgroundCanvas, bold: false) + clipped + ansiReset()
        }

        let padded = text + String(repeating: " ", count: safeWidth - plainLength)
        return ansi(fg: palette.foregroundPrimary, bg: palette.backgroundCanvas, bold: false) + padded + ansiReset()
    }

    private func rail(tone: Tone, styled: Bool) -> String {
        toned("▌", tone: tone, styled: styled)
    }

    private func chip(_ text: String, tone: Tone, styled: Bool) -> String {
        let plain = " \(text) "
        guard styled else { return plain }
        switch tone {
        case .muted:
            return ansi(fg: palette.foregroundSecondary, bg: palette.backgroundElevated, bold: false) + plain + ansiReset()
        case .strong:
            return ansi(fg: palette.foregroundPrimary, bg: palette.backgroundElevated, bold: true) + plain + ansiReset()
        case .accent:
            return ansi(fg: palette.backgroundCanvas, bg: palette.accent, bold: true) + plain + ansiReset()
        case .lavender:
            return ansi(fg: palette.selectionForeground, bg: palette.selectionBackground, bold: true) + plain + ansiReset()
        case .danger:
            return ansi(fg: palette.backgroundCanvas, bg: palette.danger, bold: true) + plain + ansiReset()
        case .success:
            return ansi(fg: palette.backgroundCanvas, bg: palette.success, bold: true) + plain + ansiReset()
        }
    }

    private func toned(_ text: String, tone: Tone, styled: Bool) -> String {
        guard styled else { return text }
        switch tone {
        case .muted:
            return ansi(fg: palette.foregroundMuted, bg: nil, bold: false) + text + ansiReset()
        case .strong:
            return ansi(fg: palette.foregroundPrimary, bg: nil, bold: false) + text + ansiReset()
        case .accent:
            return ansi(fg: palette.accent, bg: nil, bold: true) + text + ansiReset()
        case .lavender:
            return ansi(fg: palette.brightAccent, bg: nil, bold: true) + text + ansiReset()
        case .danger:
            return ansi(fg: palette.danger, bg: nil, bold: true) + text + ansiReset()
        case .success:
            return ansi(fg: palette.success, bg: nil, bold: true) + text + ansiReset()
        }
    }

    private func stateTone() -> Tone {
        switch stateLabel {
        case "error":
            return .danger
        case "ready":
            return .success
        case "thinking", "streaming", "tool", "compacting", "connecting":
            return .accent
        default:
            return .muted
        }
    }

    private func ansi(fg: ThemeColor?, bg: ThemeColor?, bold: Bool) -> String {
        var codes: [String] = []
        if bold {
            codes.append("1")
        }
        if let fg {
            codes.append("38;2;\(fg.red);\(fg.green);\(fg.blue)")
        }
        if let bg {
            codes.append("48;2;\(bg.red);\(bg.green);\(bg.blue)")
        }
        if codes.isEmpty {
            codes.append("0")
        }
        return "\u{1B}[\(codes.joined(separator: ";"))m"
    }

    private func ansiReset() -> String {
        "\u{1B}[0m"
    }

    private static func loadRenderPalette() -> RenderPalette {
        let evaluation = OmuxConfigurationEvaluator().evaluate()
        if let theme = evaluation.theme {
            return RenderPalette(theme: theme)
        }

        let registry = OmuxThemeRegistry()
        if let theme = registry.loadTheme(named: "monokai-soda").theme {
            return RenderPalette(theme: theme)
        }

        let (themes, _) = registry.loadBuiltInThemes()
        if let theme = themes.first {
            return RenderPalette(theme: theme)
        }

        return RenderPalette(
            theme: OmuxTheme(
                schema: 1,
                name: "fallback",
                displayName: "Fallback",
                tokens: [
                    .backgroundCanvas: ThemeColor(red: 0x1f, green: 0x1d, blue: 0x2e),
                    .backgroundSurface: ThemeColor(red: 0x26, green: 0x23, blue: 0x39),
                    .backgroundElevated: ThemeColor(red: 0x2f, green: 0x2b, blue: 0x47),
                    .foregroundPrimary: ThemeColor(red: 0xee, green: 0xee, blue: 0xf6),
                    .foregroundSecondary: ThemeColor(red: 0xc3, green: 0xc1, blue: 0xd9),
                    .foregroundMuted: ThemeColor(red: 0x9c, green: 0x98, blue: 0xb5),
                    .borderSubtle: ThemeColor(red: 0x39, green: 0x36, blue: 0x54),
                    .borderStrong: ThemeColor(red: 0x55, green: 0x51, blue: 0x77),
                    .accent: ThemeColor(red: 0xca, green: 0x9e, blue: 0xff),
                    .cursor: ThemeColor(red: 0xf6, green: 0xf6, blue: 0xff),
                    .cursorText: ThemeColor(red: 0x1f, green: 0x1d, blue: 0x2e),
                    .selectionBackground: ThemeColor(red: 0x3b, green: 0x33, blue: 0x57),
                    .selectionForeground: ThemeColor(red: 0xfa, green: 0xf9, blue: 0xff),
                    .ansiBlack: ThemeColor(red: 0x1f, green: 0x1d, blue: 0x2e),
                    .ansiRed: ThemeColor(red: 0xf3, green: 0x8b, blue: 0xa8),
                    .ansiGreen: ThemeColor(red: 0xa6, green: 0xe3, blue: 0xa1),
                    .ansiYellow: ThemeColor(red: 0xf9, green: 0xe2, blue: 0xaf),
                    .ansiBlue: ThemeColor(red: 0x89, green: 0xb4, blue: 0xfa),
                    .ansiMagenta: ThemeColor(red: 0xf5, green: 0xc2, blue: 0xe7),
                    .ansiCyan: ThemeColor(red: 0x94, green: 0xe2, blue: 0xd5),
                    .ansiWhite: ThemeColor(red: 0xee, green: 0xee, blue: 0xf6),
                    .ansiBrightBlack: ThemeColor(red: 0x6c, green: 0x70, blue: 0x86),
                    .ansiBrightRed: ThemeColor(red: 0xf3, green: 0x8b, blue: 0xa8),
                    .ansiBrightGreen: ThemeColor(red: 0xa6, green: 0xe3, blue: 0xa1),
                    .ansiBrightYellow: ThemeColor(red: 0xf9, green: 0xe2, blue: 0xaf),
                    .ansiBrightBlue: ThemeColor(red: 0x89, green: 0xb4, blue: 0xfa),
                    .ansiBrightMagenta: ThemeColor(red: 0xca, green: 0x9e, blue: 0xff),
                    .ansiBrightCyan: ThemeColor(red: 0x94, green: 0xe2, blue: 0xd5),
                    .ansiBrightWhite: ThemeColor(red: 0xfa, green: 0xf9, blue: 0xff),
                ]
            )
        )
    }

    private func stripANSI(_ text: String) -> String {
        var scalars: [UnicodeScalar] = []
        var iterator = text.unicodeScalars.makeIterator()
        while let scalar = iterator.next() {
            if scalar == "\u{1B}" {
                if let next = iterator.next(), next == "[" {
                    while let inner = iterator.next() {
                        if inner.value >= 0x40 && inner.value <= 0x7E {
                            break
                        }
                    }
                    continue
                }
            }
            scalars.append(scalar)
        }
        return String(String.UnicodeScalarView(scalars))
    }

    private func plainTextLength(_ text: String) -> Int {
        stripANSI(text).count
    }

    private func formatToolEvent(_ event: OmuxAgentToolEvent) -> String {
        switch event.phase {
        case .started:
            return "tool: \(event.toolName) · \(event.detail)"
        case .completed:
            if let bytes = event.outputBytes {
                return "tool: \(event.toolName) done · \(event.detail) · \(formatBytes(bytes))"
            }
            return "tool: \(event.toolName) done · \(event.detail)"
        case .failed:
            return "tool: \(event.toolName) failed · \(event.detail)"
        }
    }

    private func insertToolEntry(_ text: String) {
        let entry = TranscriptEntry(kind: .tool, text: text)
        if let pendingAssistantIndex, transcript.indices.contains(pendingAssistantIndex) {
            transcript.insert(entry, at: pendingAssistantIndex)
            self.pendingAssistantIndex = pendingAssistantIndex + 1
        } else {
            transcript.append(entry)
        }
    }

    private func slashOverlayState() -> SlashOverlayState? {
        guard input.hasPrefix("/"), input.contains("\n") == false else {
            return nil
        }
        let query = input.trimmingCharacters(in: .whitespaces)
        let matches = Self.slashCommands.filter { command in
            query == "/" || command.hasPrefix(query) || fuzzyMatches(query.dropFirst(), in: command.dropFirst())
        }
        guard matches.isEmpty == false else {
            return nil
        }
        return SlashOverlayState(matches: matches, selectedIndex: min(slashSelectionIndex, matches.count - 1))
    }

    private func updateSlashSelection(delta: Int) -> Bool {
        guard let state = slashOverlayState() else { return false }
        slashSelectionIndex = max(0, min(state.matches.count - 1, state.selectedIndex + delta))
        return true
    }

    private func clampSlashSelection() {
        guard let state = slashOverlayState() else {
            slashSelectionIndex = 0
            return
        }
        slashSelectionIndex = min(slashSelectionIndex, state.matches.count - 1)
    }

    private func selectedSlashCommand(for trimmedInput: String) -> String? {
        guard trimmedInput.hasPrefix("/"), let state = slashOverlayState() else {
            return nil
        }
        if Self.slashCommands.contains(trimmedInput) {
            return trimmedInput
        }
        return state.matches[state.selectedIndex]
    }

    private func fuzzyMatches<S: StringProtocol>(_ query: S, in candidate: S) -> Bool {
        var remaining = query[...]
        for character in candidate where remaining.first == character {
            remaining.removeFirst()
            if remaining.isEmpty {
                return true
            }
        }
        return remaining.isEmpty
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

    private func formatElapsedTime(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded(.down)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
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
