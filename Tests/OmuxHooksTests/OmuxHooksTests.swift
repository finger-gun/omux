import Foundation
import XCTest
@testable import OmuxHooks

final class OmuxHooksTests: XCTestCase {
    func testExternalHookRunnerExecutesProcessWithJSONPayload() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let outputURL = tempDirectory.appending(path: "payload.json")
        let scriptURL = tempDirectory.appending(path: "capture.sh")
        let script = """
        #!/bin/sh
        cat > "$1"
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path(percentEncoded: false)
        )

        let registry = HookRegistry()
        registry.register(
            HookDescriptor(
                category: .lifecycle,
                name: "workspace-opened",
                executableURL: scriptURL,
                arguments: [outputURL.path(percentEncoded: false)]
            )
        )

        let runner = ExternalHookRunner(registry: registry)
        try runner.emit(
            HookInvocation(
                category: .lifecycle,
                name: "workspace-opened",
                metadata: ["path": "/tmp/project"]
            )
        )

        let payload = try Data(contentsOf: outputURL)
        let invocation = try JSONDecoder().decode(HookInvocation.self, from: payload)

        XCTAssertEqual(invocation.name, "workspace-opened")
        XCTAssertEqual(invocation.metadata["path"], "/tmp/project")
    }
}
