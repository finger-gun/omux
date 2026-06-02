import Foundation
import XCTest
@testable import OmuxCLI
@testable import OmuxConfig

final class TerminalAgentREPLTests: XCTestCase {
    func testSlashCommandsAreHostHandled() {
        let session = FakeSession()
        let factory = FakeFactory(session: session)
        let driver = FakeDriver(events: .text("/tools\n/exit\n"))
        let runner = OmuxAgentREPLRunner(
            writeErrorLine: { _ in },
            request: OmuxAgentREPLRequest(systemInstruction: nil, verbose: false, allowReadAnywhere: false),
            hostContext: "Host context:\ncurrentWorkingDirectory: /tmp",
            workingDirectoryURL: URL(fileURLWithPath: "/tmp", isDirectory: true),
            sessionFactory: factory,
            driver: driver
        )

        XCTAssertEqual(runner.run(), 0)
        XCTAssertEqual(session.sentPrompts, [])
        XCTAssertTrue(driver.renderedText.contains("Tools:"))
        XCTAssertTrue(driver.renderedText.contains("read_file"))
        XCTAssertTrue(driver.renderedText.contains("grep_files"))
    }

    func testCompactRebuildsSessionAndRequestsSummary() {
        let session = FakeSession()
        session.response = "answer"
        let factory = FakeFactory(session: session)
        let driver = FakeDriver(events: .text("hello\n/compact\n/exit\n"))
        let runner = OmuxAgentREPLRunner(
            writeErrorLine: { _ in },
            request: OmuxAgentREPLRequest(systemInstruction: nil, verbose: false, allowReadAnywhere: false),
            hostContext: "Host context:\ncurrentWorkingDirectory: /tmp",
            workingDirectoryURL: URL(fileURLWithPath: "/tmp", isDirectory: true),
            sessionFactory: factory,
            driver: driver
        )

        XCTAssertEqual(runner.run(), 0)
        XCTAssertEqual(session.sentPrompts, ["hello"])
        XCTAssertEqual(session.summaryRequests.count, 1)
        XCTAssertEqual(factory.makeCount, 2)
        XCTAssertTrue(driver.renderedText.contains("Compacted prior conversation"))
    }

    func testEmptyStateRendersGuidance() {
        let session = FakeSession()
        let factory = FakeFactory(session: session)
        let driver = FakeDriver(events: .text("/exit\n"), size: .init(rows: 16, columns: 40))
        let runner = OmuxAgentREPLRunner(
            writeErrorLine: { _ in },
            request: OmuxAgentREPLRequest(systemInstruction: nil, verbose: false, allowReadAnywhere: false),
            hostContext: "Host context:\ncurrentWorkingDirectory: /tmp",
            workingDirectoryURL: URL(fileURLWithPath: "/tmp", isDirectory: true),
            sessionFactory: factory,
            driver: driver
        )

        XCTAssertEqual(runner.run(), 0)
        XCTAssertTrue(driver.renderedText.contains("OpenMux Agent"))
        XCTAssertTrue(driver.renderedText.contains("compose"))
    }

    func testRenderingDoesNotCallModelTokenCounter() {
        let session = FakeSession()
        let factory = FakeFactory(session: session)
        let driver = FakeDriver(events: .text("typing without submitting"), size: .init(rows: 16, columns: 80))
        let runner = OmuxAgentREPLRunner(
            writeErrorLine: { _ in },
            request: OmuxAgentREPLRequest(systemInstruction: nil, verbose: false, allowReadAnywhere: false),
            hostContext: "Host context:\ncurrentWorkingDirectory: /tmp",
            workingDirectoryURL: URL(fileURLWithPath: "/tmp", isDirectory: true),
            sessionFactory: factory,
            driver: driver
        )

        XCTAssertEqual(runner.run(), 0)
        XCTAssertEqual(session.tokenCountCalls, 0)
        XCTAssertGreaterThan(driver.renderCount, 1)
    }

    func testWrappedTranscriptRenderCleanly() {
        let session = FakeSession()
        session.response = "This is a long assistant response that should wrap onto another visual line in the transcript."
        let factory = FakeFactory(session: session)
        let driver = FakeDriver(events: .text("hello\n/exit\n"), size: .init(rows: 16, columns: 40))
        let runner = OmuxAgentREPLRunner(
            writeErrorLine: { _ in },
            request: OmuxAgentREPLRequest(systemInstruction: nil, verbose: false, allowReadAnywhere: false),
            hostContext: "Host context:\ncurrentWorkingDirectory: /tmp",
            workingDirectoryURL: URL(fileURLWithPath: "/tmp", isDirectory: true),
            sessionFactory: factory,
            driver: driver
        )

        XCTAssertEqual(runner.run(), 0)
        XCTAssertTrue(driver.renderedText.contains("This is a long assistant"))
        XCTAssertTrue(driver.renderedText.contains("AGENT"))
    }

    func testModifiedEnterCSIParsesAsComposerNewline() {
        XCTAssertEqual(
            TerminalAgentREPLDefaultDriver.parseCSI(Array("27;2;13~".utf8)),
            .newline
        )
        XCTAssertEqual(
            TerminalAgentREPLDefaultDriver.parseCSI(Array("13;2~".utf8)),
            .newline
        )
        XCTAssertEqual(
            TerminalAgentREPLDefaultDriver.parseCSI(Array("13;2u".utf8)),
            .newline
        )
    }

    func testCSIArrowAndPagingParsingStillWorks() {
        XCTAssertEqual(TerminalAgentREPLDefaultDriver.parseCSI([0x41]), .up)
        XCTAssertEqual(TerminalAgentREPLDefaultDriver.parseCSI([0x42]), .down)
        XCTAssertEqual(TerminalAgentREPLDefaultDriver.parseCSI([0x43]), .right)
        XCTAssertEqual(TerminalAgentREPLDefaultDriver.parseCSI([0x44]), .left)
        XCTAssertEqual(TerminalAgentREPLDefaultDriver.parseCSI(Array("1;3D".utf8)), .wordLeft)
        XCTAssertEqual(TerminalAgentREPLDefaultDriver.parseCSI(Array("1;3C".utf8)), .wordRight)
        XCTAssertEqual(TerminalAgentREPLDefaultDriver.parseCSI(Array("1;9D".utf8)), .lineStart)
        XCTAssertEqual(TerminalAgentREPLDefaultDriver.parseCSI(Array("1;9C".utf8)), .lineEnd)
        XCTAssertEqual(TerminalAgentREPLDefaultDriver.parseCSI(Array("1;2D".utf8)), .selectLeft)
        XCTAssertEqual(TerminalAgentREPLDefaultDriver.parseCSI(Array("1;2C".utf8)), .selectRight)
        XCTAssertEqual(TerminalAgentREPLDefaultDriver.parseCSI(Array("1;4D".utf8)), .selectWordLeft)
        XCTAssertEqual(TerminalAgentREPLDefaultDriver.parseCSI(Array("1;4C".utf8)), .selectWordRight)
        XCTAssertEqual(TerminalAgentREPLDefaultDriver.parseCSI(Array("1;10D".utf8)), .selectLineStart)
        XCTAssertEqual(TerminalAgentREPLDefaultDriver.parseCSI(Array("1;10C".utf8)), .selectLineEnd)
        XCTAssertEqual(TerminalAgentREPLDefaultDriver.parseCSI([0x48]), .lineStart)
        XCTAssertEqual(TerminalAgentREPLDefaultDriver.parseCSI([0x46]), .lineEnd)
        XCTAssertEqual(TerminalAgentREPLDefaultDriver.parseCSI(Array("5~".utf8)), .pageUp)
        XCTAssertEqual(TerminalAgentREPLDefaultDriver.parseCSI(Array("6~".utf8)), .pageDown)
        XCTAssertEqual(TerminalAgentREPLDefaultDriver.parseCSI(Array("127;5u".utf8)), .deleteWordBackward)
        XCTAssertEqual(TerminalAgentREPLDefaultDriver.parseCSI(Array("127;9u".utf8)), .deleteLineBackward)
    }

    func testResizeEventTriggersImmediateRerender() {
        let session = FakeSession()
        let factory = FakeFactory(session: session)
        let driver = FakeDriver(
            events: [.resize, .escape],
            sizes: [.init(rows: 20, columns: 80), .init(rows: 12, columns: 32)]
        )
        let runner = OmuxAgentREPLRunner(
            writeErrorLine: { _ in },
            request: OmuxAgentREPLRequest(systemInstruction: nil, verbose: false, allowReadAnywhere: false),
            hostContext: "Host context:\ncurrentWorkingDirectory: /tmp",
            workingDirectoryURL: URL(fileURLWithPath: "/tmp", isDirectory: true),
            sessionFactory: factory,
            driver: driver
        )

        XCTAssertEqual(runner.run(), 0)
        XCTAssertGreaterThanOrEqual(driver.renderCount, 3)
        XCTAssertTrue(driver.renderedText.contains("OpenMux Agent"))
    }

    func testToolActivityRendersInlineTranscriptRows() {
        let session = FakeSession()
        session.response = "assistant reply"
        session.toolEvents = [
            .init(toolName: "grep_files", phase: .started, detail: "pattern=status", outputBytes: nil, outputText: nil),
            .init(toolName: "grep_files", phase: .completed, detail: "matches=3", outputBytes: 128, outputText: "MATCHES: 3")
        ]
        let factory = FakeFactory(session: session)
        let driver = FakeDriver(events: .text("find it\n/exit\n"), size: .init(rows: 32, columns: 100))
        let runner = OmuxAgentREPLRunner(
            writeErrorLine: { _ in },
            request: OmuxAgentREPLRequest(systemInstruction: nil, verbose: false, allowReadAnywhere: false),
            hostContext: "Host context:\ncurrentWorkingDirectory: /tmp",
            workingDirectoryURL: URL(fileURLWithPath: "/tmp", isDirectory: true),
            sessionFactory: factory,
            driver: driver
        )

        XCTAssertEqual(runner.run(), 0)
        let toolDone = driver.renderedText.range(of: "grep_files done")
        let answer = driver.renderedText.range(of: "assistant reply")
        XCTAssertNotNil(toolDone)
        XCTAssertNotNil(answer)
        if let toolDone, let answer {
            XCTAssertLessThan(toolDone.lowerBound, answer.lowerBound)
        }
    }

    func testPromptSubmissionPreservesRawWhitespace() {
        let session = FakeSession()
        session.response = "done"
        let factory = FakeFactory(session: session)
        let driver = FakeDriver(
            events: [
                .character(" "),
                .character(" "),
                .character("h"),
                .character("e"),
                .character("l"),
                .character("l"),
                .character("o"),
                .newline,
                .character("w"),
                .character("o"),
                .character("r"),
                .character("l"),
                .character("d"),
                .character(" "),
                .character(" "),
                .enter,
                .escape,
            ]
        )
        let runner = OmuxAgentREPLRunner(
            writeErrorLine: { _ in },
            request: OmuxAgentREPLRequest(systemInstruction: nil, verbose: false, allowReadAnywhere: false),
            hostContext: "Host context:\ncurrentWorkingDirectory: /tmp",
            workingDirectoryURL: URL(fileURLWithPath: "/tmp", isDirectory: true),
            sessionFactory: factory,
            driver: driver
        )

        XCTAssertEqual(runner.run(), 0)
        XCTAssertEqual(session.sentPrompts, ["  hello\nworld  "])
    }

    func testComposerSupportsCursorEditingWithinInput() {
        let session = FakeSession()
        session.response = "done"
        let factory = FakeFactory(session: session)
        let driver = FakeDriver(events: [.character("a"), .character("c"), .left, .character("b"), .enter, .escape])
        let runner = OmuxAgentREPLRunner(
            writeErrorLine: { _ in },
            request: OmuxAgentREPLRequest(systemInstruction: nil, verbose: false, allowReadAnywhere: false),
            hostContext: "Host context:\ncurrentWorkingDirectory: /tmp",
            workingDirectoryURL: URL(fileURLWithPath: "/tmp", isDirectory: true),
            sessionFactory: factory,
            driver: driver
        )

        XCTAssertEqual(runner.run(), 0)
        XCTAssertEqual(session.sentPrompts, ["abc"])
    }

    func testComposerRendersCursorAtCurrentInputPosition() {
        let session = FakeSession()
        let factory = FakeFactory(session: session)
        let driver = FakeDriver(events: [.character("a"), .character("b"), .left, .escape], size: .init(rows: 16, columns: 80))
        let runner = OmuxAgentREPLRunner(
            writeErrorLine: { _ in },
            request: OmuxAgentREPLRequest(systemInstruction: nil, verbose: false, allowReadAnywhere: false),
            hostContext: "Host context:\ncurrentWorkingDirectory: /tmp",
            workingDirectoryURL: URL(fileURLWithPath: "/tmp", isDirectory: true),
            sessionFactory: factory,
            driver: driver
        )

        XCTAssertEqual(runner.run(), 0)
        XCTAssertTrue(driver.renderedText.contains("a▌b"))
    }

    func testComposerSupportsWordAndLineNavigationEditing() {
        let session = FakeSession()
        session.response = "done"
        let factory = FakeFactory(session: session)
        let driver = FakeDriver(events: [
            .character("f"), .character("o"), .character("o"),
            .character(" "), .character("b"), .character("a"), .character("r"),
            .wordLeft, .character("X"), .lineStart, .character(">"), .lineEnd, .character("<"),
            .enter, .escape
        ])
        let runner = OmuxAgentREPLRunner(
            writeErrorLine: { _ in },
            request: OmuxAgentREPLRequest(systemInstruction: nil, verbose: false, allowReadAnywhere: false),
            hostContext: "Host context:\ncurrentWorkingDirectory: /tmp",
            workingDirectoryURL: URL(fileURLWithPath: "/tmp", isDirectory: true),
            sessionFactory: factory,
            driver: driver
        )

        XCTAssertEqual(runner.run(), 0)
        XCTAssertEqual(session.sentPrompts, [">foo Xbar<"])
    }

    func testComposerSupportsWordAndLineDeletion() {
        let session = FakeSession()
        session.response = "done"
        let factory = FakeFactory(session: session)
        let driver = FakeDriver(events: [
            .character("a"), .character("l"), .character("p"), .character("h"), .character("a"),
            .character(" "), .character("b"), .character("e"), .character("t"), .character("a"),
            .deleteWordBackward,
            .character("g"), .character("a"), .character("m"), .character("m"), .character("a"),
            .deleteLineBackward,
            .character("o"), .character("k"),
            .enter, .escape
        ])
        let runner = OmuxAgentREPLRunner(
            writeErrorLine: { _ in },
            request: OmuxAgentREPLRequest(systemInstruction: nil, verbose: false, allowReadAnywhere: false),
            hostContext: "Host context:\ncurrentWorkingDirectory: /tmp",
            workingDirectoryURL: URL(fileURLWithPath: "/tmp", isDirectory: true),
            sessionFactory: factory,
            driver: driver
        )

        XCTAssertEqual(runner.run(), 0)
        XCTAssertEqual(session.sentPrompts, ["ok"])
    }

    func testComposerSupportsShiftSelectionReplacement() {
        let session = FakeSession()
        session.response = "done"
        let factory = FakeFactory(session: session)
        let driver = FakeDriver(events: [
            .character("h"), .character("e"), .character("l"), .character("l"), .character("o"),
            .lineStart, .selectWordRight, .character("H"), .enter, .escape
        ])
        let runner = OmuxAgentREPLRunner(
            writeErrorLine: { _ in },
            request: OmuxAgentREPLRequest(systemInstruction: nil, verbose: false, allowReadAnywhere: false),
            hostContext: "Host context:\ncurrentWorkingDirectory: /tmp",
            workingDirectoryURL: URL(fileURLWithPath: "/tmp", isDirectory: true),
            sessionFactory: factory,
            driver: driver
        )

        XCTAssertEqual(runner.run(), 0)
        XCTAssertEqual(session.sentPrompts, ["H"])
    }

    func testComposerKeepsCursorVisibleDuringKeyboardSelection() {
        let session = FakeSession()
        let factory = FakeFactory(session: session)
        let driver = FakeDriver(events: [.character("t"), .character("e"), .character("s"), .character("t"), .lineStart, .selectWordRight, .escape], size: .init(rows: 16, columns: 80))
        let runner = OmuxAgentREPLRunner(
            writeErrorLine: { _ in },
            request: OmuxAgentREPLRequest(systemInstruction: nil, verbose: false, allowReadAnywhere: false),
            hostContext: "Host context:\ncurrentWorkingDirectory: /tmp",
            workingDirectoryURL: URL(fileURLWithPath: "/tmp", isDirectory: true),
            sessionFactory: factory,
            driver: driver
        )

        XCTAssertEqual(runner.run(), 0)
        XCTAssertTrue(driver.renderedText.contains("test▌") || driver.renderedText.contains("▌test"))
        XCTAssertFalse(driver.renderedText.contains("["))
        XCTAssertFalse(driver.renderedText.contains("]"))
    }

    func testStyledRenderKeepsFooterStatusAndPathVisible() {
        let session = FakeSession()
        let factory = FakeFactory(session: session)
        let driver = FakeDriver(events: .text("/exit\n"), size: .init(rows: 18, columns: 100), styled: true)
        let runner = OmuxAgentREPLRunner(
            writeErrorLine: { _ in },
            request: OmuxAgentREPLRequest(systemInstruction: nil, verbose: false, allowReadAnywhere: false),
            hostContext: "Host context:\ncurrentWorkingDirectory: /tmp/project",
            workingDirectoryURL: URL(fileURLWithPath: "/tmp/project", isDirectory: true),
            sessionFactory: factory,
            driver: driver
        )

        XCTAssertEqual(runner.run(), 0)
        let rendered = driver.renderedText
        XCTAssertTrue(rendered.contains("interactive local agent"))
        XCTAssertTrue(rendered.contains("/tmp/project") || rendered.contains("~/"))
        XCTAssertTrue(rendered.contains("ctx ~"))
        XCTAssertTrue(rendered.contains("OpenMux Agent"))
    }

    func testContextEstimateIncludesToolOutputPayloads() {
        let baselineSession = FakeSession()
        baselineSession.response = "done"
        let baselineFactory = FakeFactory(session: baselineSession)
        let baselineDriver = FakeDriver(events: .text("hello\n/exit\n"))
        let baselineRunner = OmuxAgentREPLRunner(
            writeErrorLine: { _ in },
            request: OmuxAgentREPLRequest(systemInstruction: nil, verbose: false, allowReadAnywhere: false),
            hostContext: "Host context:\ncurrentWorkingDirectory: /tmp",
            workingDirectoryURL: URL(fileURLWithPath: "/tmp", isDirectory: true),
            sessionFactory: baselineFactory,
            driver: baselineDriver
        )

        XCTAssertEqual(baselineRunner.run(), 0)
        let baselineContext = extractApproxContext(from: baselineDriver.renderedText)

        let toolSession = FakeSession()
        toolSession.response = "done"
        toolSession.toolEvents = [
            .init(toolName: "grep_files", phase: .started, detail: "pattern=hello", outputBytes: nil, outputText: nil),
            .init(toolName: "grep_files", phase: .completed, detail: "matches=4", outputBytes: 4096, outputText: String(repeating: "x", count: 4096))
        ]
        let toolFactory = FakeFactory(session: toolSession)
        let toolDriver = FakeDriver(events: .text("hello\n/exit\n"))
        let toolRunner = OmuxAgentREPLRunner(
            writeErrorLine: { _ in },
            request: OmuxAgentREPLRequest(systemInstruction: nil, verbose: false, allowReadAnywhere: false),
            hostContext: "Host context:\ncurrentWorkingDirectory: /tmp",
            workingDirectoryURL: URL(fileURLWithPath: "/tmp", isDirectory: true),
            sessionFactory: toolFactory,
            driver: toolDriver
        )

        XCTAssertEqual(toolRunner.run(), 0)
        let toolContext = extractApproxContext(from: toolDriver.renderedText)
        XCTAssertGreaterThan(toolContext, baselineContext)
    }

    func testSlashOverlayCanCompleteCommandOnEnter() {
        let session = FakeSession()
        session.response = "answer"
        let factory = FakeFactory(session: session)
        let driver = FakeDriver(events: [.character("/"), .character("c"), .character("o"), .character("m"), .enter, .escape])
        let runner = OmuxAgentREPLRunner(
            writeErrorLine: { _ in },
            request: OmuxAgentREPLRequest(systemInstruction: nil, verbose: false, allowReadAnywhere: false),
            hostContext: "Host context:\ncurrentWorkingDirectory: /tmp",
            workingDirectoryURL: URL(fileURLWithPath: "/tmp", isDirectory: true),
            sessionFactory: factory,
            driver: driver
        )

        XCTAssertEqual(runner.run(), 0)
        XCTAssertEqual(session.summaryRequests.count, 1)
        XCTAssertEqual(factory.makeCount, 2)
        XCTAssertTrue(driver.renderedText.contains("Compacted prior conversation"))
    }

    func testSlashOverlayScrollsToKeepSelectionVisible() {
        let session = FakeSession()
        let factory = FakeFactory(session: session)
        let driver = FakeDriver(events: [.character("/"), .down, .down, .down, .down, .down, .escape], size: .init(rows: 24, columns: 90))
        let runner = OmuxAgentREPLRunner(
            writeErrorLine: { _ in },
            request: OmuxAgentREPLRequest(systemInstruction: nil, verbose: false, allowReadAnywhere: false),
            hostContext: "Host context:\ncurrentWorkingDirectory: /tmp",
            workingDirectoryURL: URL(fileURLWithPath: "/tmp", isDirectory: true),
            sessionFactory: factory,
            driver: driver
        )

        XCTAssertEqual(runner.run(), 0)
        XCTAssertTrue(driver.renderedText.contains("/handoff"))
        XCTAssertTrue(driver.renderedText.contains("/compact"))
        XCTAssertFalse(driver.renderedText.contains("/help"))
    }

    func testHandoffWritesMarkdownFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let session = FakeSession()
        session.response = "answer"
        let factory = FakeFactory(session: session)
        let driver = FakeDriver(events: .text("hello\n/handoff\n/exit\n"))
        let runner = OmuxAgentREPLRunner(
            writeErrorLine: { _ in },
            request: OmuxAgentREPLRequest(systemInstruction: nil, verbose: false, allowReadAnywhere: false),
            hostContext: "Host context:\ncurrentWorkingDirectory: \(root.path)",
            workingDirectoryURL: root,
            sessionFactory: factory,
            driver: driver
        )

        XCTAssertEqual(runner.run(), 0)
        let handoffDirectory = root.appendingPathComponent(".omux-handoffs", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(at: handoffDirectory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        let contents = try String(contentsOf: files[0], encoding: .utf8)
        XCTAssertTrue(contents.contains("# Title"))
        XCTAssertTrue(contents.contains("## Suggested Next Prompt"))
        XCTAssertTrue(driver.renderedText.contains("Wrote handoff:"))
    }

    func testToolsCommandReflectsConfigFilteredTools() {
        let session = FakeSession()
        let driver = FakeDriver(events: .text("/tools\n/exit\n"))
        let runner = OmuxAgentREPLRunner(
            writeErrorLine: { _ in },
            request: OmuxAgentREPLRequest(
                systemInstruction: nil,
                verbose: false,
                allowReadAnywhere: false,
                agentConfiguration: OmuxConfigAgent(
                    enabled: true,
                    skillsEnabled: false,
                    tools: .init(
                        readTerminalHistory: false,
                        listDirectory: true,
                        runOmuxCLI: false,
                        readFile: true,
                        grepFiles: false,
                        listSkills: false,
                        readSkill: false
                    )
                )
            ),
            hostContext: "Host context:\ncurrentWorkingDirectory: /tmp",
            workingDirectoryURL: URL(fileURLWithPath: "/tmp", isDirectory: true),
            sessionFactory: FakeFactory(session: session),
            driver: driver
        )

        XCTAssertEqual(runner.run(), 0)
        XCTAssertTrue(driver.renderedText.contains("list_directory"))
        XCTAssertTrue(driver.renderedText.contains("read_file"))
        XCTAssertFalse(driver.renderedText.contains("list_skills"))
        XCTAssertFalse(driver.renderedText.contains("read_terminal_history"))
    }
}

private final class FakeSession: OmuxAgentChatSessioning {
    var toolNames = ["read_file", "grep_files"]
    let contextWindowSize: Int? = 4096
    var sentPrompts: [String] = []
    var summaryRequests: [String] = []
    var response = "done"
    var toolEvents: [OmuxAgentToolEvent] = []
    var toolEventHandler: (@Sendable (OmuxAgentToolEvent) -> Void)?
    private(set) var tokenCountCalls = 0

    func configureFromAgentConfiguration(_ configuration: OmuxConfigAgent) {
        var names: [String] = []
        let tools = configuration.tools
        if tools.readTerminalHistory { names.append("read_terminal_history") }
        if tools.listDirectory { names.append("list_directory") }
        if tools.runOmuxCLI { names.append("run_omux_cli") }
        if tools.readFile { names.append("read_file") }
        if tools.grepFiles { names.append("grep_files") }
        if tools.listSkills { names.append("list_skills") }
        if tools.readSkill { names.append("read_skill") }
        toolNames = names
    }

    func send(prompt: String, onPartial: @escaping @Sendable (String) -> Void) async throws -> String {
        sentPrompts.append(prompt)
        for event in toolEvents {
            toolEventHandler?(event)
        }
        onPartial(response)
        return response
    }

    func summarizeForCompaction(transcript: String) async throws -> String {
        summaryRequests.append(transcript)
        return "short summary"
    }

    func summarizeForHandoff(transcript: String) async throws -> String {
        summaryRequests.append(transcript)
        return """
        # Title
        ## Current Goal
        continue
        ## Key Facts Learned
        fact
        ## Files, Paths, and Commands
        path
        ## Tool Activity Summary
        tool
        ## Open Issues or Questions
        none
        ## Suggested Next Prompt
        next
        """
    }

    func tokenCount(for text: String) -> Int? {
        tokenCountCalls += 1
        return max(1, text.utf8.count / 4)
    }
}

private final class FakeFactory: OmuxAgentChatSessionFactorying {
    let session: FakeSession
    var makeCount = 0

    init(session: FakeSession) {
        self.session = session
    }

    func makeSession(
        systemInstruction: String?,
        hostContext: String,
        agentConfiguration: OmuxConfigAgent,
        workingDirectoryURL: URL,
        allowReadAnywhere: Bool,
        onVerbose: (@Sendable (String) -> Void)?,
        onToolEvent: (@Sendable (OmuxAgentToolEvent) -> Void)?
    ) throws -> AnyOmuxAgentChatSession {
        _ = systemInstruction
        _ = hostContext
        _ = workingDirectoryURL
        _ = allowReadAnywhere
        _ = onVerbose
        session.configureFromAgentConfiguration(agentConfiguration)
        session.toolEventHandler = onToolEvent
        makeCount += 1
        return AnyOmuxAgentChatSession(session)
    }
}

private final class FakeDriver: TerminalAgentREPLDriver {
    private var events: [TerminalAgentREPLEvent]
    private let sizes: [TerminalAgentREPLSize]
    private let styled: Bool
    private var sizeIndex = 0
    private(set) var renderedText = ""
    private(set) var renderCount = 0

    init(
        events: [TerminalAgentREPLEvent],
        size: TerminalAgentREPLSize = .init(rows: 20, columns: 80),
        sizes: [TerminalAgentREPLSize]? = nil,
        styled: Bool = false
    ) {
        self.events = events
        self.sizes = sizes ?? [size]
        self.styled = styled
    }

    func isAvailable() -> Bool { true }

    func runScreen<Result>(_ body: () throws -> Result) throws -> Result {
        try body()
    }

    func readEvent() -> TerminalAgentREPLEvent {
        if events.isEmpty {
            return .escape
        }
        return events.removeFirst()
    }

    func terminalSize() -> TerminalAgentREPLSize {
        let current = sizes[min(sizeIndex, sizes.count - 1)]
        if sizeIndex < sizes.count - 1 {
            sizeIndex += 1
        }
        return current
    }

    func supportsStyling() -> Bool {
        styled
    }

    func render(lines: [String]) {
        renderCount += 1
        renderedText = lines.joined(separator: "\n")
    }
}

private extension Array where Element == TerminalAgentREPLEvent {
    static func text(_ text: String) -> [TerminalAgentREPLEvent] {
        text.map { character in
            switch character {
            case "\n":
                return .enter
            default:
                return .character(character)
            }
        }
    }
}

private func extractApproxContext(from renderedText: String) -> Int {
    let pattern = #"ctx ~([0-9]+)"#
    let regex = try! NSRegularExpression(pattern: pattern)
    let range = NSRange(renderedText.startIndex..<renderedText.endIndex, in: renderedText)
    guard
        let match = regex.firstMatch(in: renderedText, range: range),
        let valueRange = Range(match.range(at: 1), in: renderedText)
    else {
        XCTFail("missing context estimate in rendered text: \(renderedText)")
        return 0
    }
    return Int(renderedText[valueRange]) ?? 0
}
