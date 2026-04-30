import Foundation
import XCTest
@testable import OmuxControlPlane

final class OmuxControlPlaneTests: XCTestCase {
    func testJSONRPCRoundTripOverUnixSocket() throws {
        let socketPath = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "control.sock")
            .path(percentEncoded: false)

        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            JSONRPCResponse(id: request.id, result: .object([
                "method": .string(request.method),
                "status": .string("ok"),
            ]))
        }
        defer { server.stop() }

        let client = OmuxControlClient(socketPath: socketPath)
        let response = try client.request(method: .listWorkspaces)

        XCTAssertEqual(
            response.result,
            .object([
                "method": .string(ControlMethod.listWorkspaces.rawValue),
                "status": .string("ok"),
            ])
        )
    }
}
