import Foundation
import XCTest
@testable import OmuxCLI
@testable import OmuxControlPlane

final class OmuxCLITests: XCTestCase {
    func testCLIUsesPublicControlPlane() throws {
        let socketPath = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "cli.sock")
            .path(percentEncoded: false)

        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            switch request.method {
            case ControlMethod.listWorkspaces.rawValue:
                return JSONRPCResponse(id: request.id, result: .array([
                    .object([
                        "id": .string("workspace-1"),
                        "name": .string("demo"),
                        "rootPath": .string("/tmp/demo"),
                    ]),
                ]))
            default:
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 404, message: "unexpected"))
            }
        }
        defer { server.stop() }

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: socketPath),
            writeLine: { output.append($0) }
        )

        let exitCode = command.run(arguments: ["omux", "list"])

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(output.count, 1)
        XCTAssertTrue(output[0].contains("demo"))
        XCTAssertTrue(output[0].contains("/tmp/demo"))
    }

    func testCLISupportsTabSplitAndRunCommands() throws {
        let socketPath = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "commands.sock")
            .path(percentEncoded: false)

        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            JSONRPCResponse(id: request.id, result: .string(request.method))
        }
        defer { server.stop() }

        let client = OmuxControlClient(socketPath: socketPath)
        var output = [String]()
        let command = OmuxCLICommand(client: client, writeLine: { output.append($0) })

        XCTAssertEqual(command.run(arguments: ["omux", "tab"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "split"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "run", "session-1", "pwd"]), 0)

        XCTAssertEqual(output, [
            ControlMethod.createTab.rawValue,
            ControlMethod.splitPane.rawValue,
            ControlMethod.runCommand.rawValue,
        ])
    }
}
