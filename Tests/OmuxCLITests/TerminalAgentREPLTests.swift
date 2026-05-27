import Foundation
import XCTest
@testable import OmuxCLI

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
        XCTAssertTrue(driver.renderedText.contains("Tools: read_file, grep_files"))
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
        XCTAssertTrue(driver.renderedText.contains("Ask about this repo"))
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
        XCTAssertTrue(driver.renderedText.contains("You: hello"))
        XCTAssertTrue(driver.renderedText.contains("Agent: This is a long assistant"))
    }
}

private final class FakeSession: OmuxAgentChatSessioning {
    let toolNames = ["read_file", "grep_files"]
    var sentPrompts: [String] = []
    var summaryRequests: [String] = []
    var response = "done"

    func send(prompt: String, onPartial: @escaping @Sendable (String) -> Void) async throws -> String {
        sentPrompts.append(prompt)
        onPartial(response)
        return response
    }

    func summarizeForCompaction(transcript: String) async throws -> String {
        summaryRequests.append(transcript)
        return "short summary"
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
        _ = onToolEvent
        makeCount += 1
        return AnyOmuxAgentChatSession(session)
    }
}

private final class FakeDriver: TerminalAgentREPLDriver {
    private var events: [TerminalAgentREPLEvent]
    private let size: TerminalAgentREPLSize
    private(set) var renderedText = ""

    init(events: [TerminalAgentREPLEvent], size: TerminalAgentREPLSize = .init(rows: 20, columns: 80)) {
        self.events = events
        self.size = size
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
        size
    }

    func render(lines: [String]) {
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
