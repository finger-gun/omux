import Darwin
import Foundation

public enum UnixSocketError: Error {
    case invalidPath(String)
    case socketCreationFailed(Int32)
    case bindFailed(Int32)
    case listenFailed(Int32)
    case connectFailed(Int32)
    case writeFailed(Int32)
    case readFailed(Int32)
    case acceptFailed(Int32)
}

enum UnixSocketAddress {
    static func withAddress<R>(
        path: String,
        _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> R
    ) throws -> R {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        let utf8Path = Array(path.utf8)
        let maxLength = MemoryLayout.size(ofValue: address.sun_path)
        guard utf8Path.count < maxLength else {
            throw UnixSocketError.invalidPath(path)
        }

        withUnsafeMutableBytes(of: &address.sun_path) { rawBuffer in
            rawBuffer.initializeMemory(as: UInt8.self, repeating: 0)
            for (index, byte) in utf8Path.enumerated() {
                rawBuffer[index] = byte
            }
        }

        let length = socklen_t(MemoryLayout<sa_family_t>.size + utf8Path.count + 1)
        return try withUnsafePointer(to: &address) { pointer in
            try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                try body(sockaddrPointer, length)
            }
        }
    }
}

public enum UnixSocketIO {
    public static func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return
            }

            var totalBytesWritten = 0
            while totalBytesWritten < data.count {
                let bytesWritten = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: totalBytesWritten),
                    data.count - totalBytesWritten
                )

                if bytesWritten < 0 {
                    throw UnixSocketError.writeFailed(errno)
                }

                totalBytesWritten += bytesWritten
            }
        }
    }

    public static func readToEnd(from descriptor: Int32) throws -> Data {
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while true {
            let bytesRead = Darwin.read(descriptor, &buffer, buffer.count)
            if bytesRead < 0 {
                throw UnixSocketError.readFailed(errno)
            }

            if bytesRead == 0 {
                break
            }

            result.append(buffer, count: bytesRead)
        }

        return result
    }

    public static func writeLine(_ data: Data, to descriptor: Int32) throws {
        var framed = data
        framed.append(0x0A)
        try writeAll(framed, to: descriptor)
    }

    public static func readLine(from descriptor: Int32) throws -> Data? {
        var result = Data()
        var byte: UInt8 = 0

        while true {
            let bytesRead = Darwin.read(descriptor, &byte, 1)
            if bytesRead < 0 {
                throw UnixSocketError.readFailed(errno)
            }

            if bytesRead == 0 {
                return result.isEmpty ? nil : result
            }

            if byte == 0x0A {
                return result
            }

            result.append(byte)
        }
    }
}

public enum ControlPlaneSocket {
    public static func defaultPath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appending(path: ".omux/control.sock")
            .path(percentEncoded: false)
    }
}

public final class OmuxControlClient {
    private let socketPath: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(socketPath: String = ControlPlaneSocket.defaultPath()) {
        self.socketPath = socketPath
    }

    public func request(method: ControlMethod, params: RPCValue? = nil) throws -> JSONRPCResponse {
        try send(JSONRPCRequest(method: method.rawValue, params: params))
    }

    public func send(_ request: JSONRPCRequest) throws -> JSONRPCResponse {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw UnixSocketError.socketCreationFailed(errno)
        }
        defer { Darwin.close(descriptor) }

        try UnixSocketAddress.withAddress(path: socketPath) { address, length in
            let result = Darwin.connect(descriptor, address, length)
            if result != 0 {
                throw UnixSocketError.connectFailed(errno)
            }
        }

        let data = try encoder.encode(request)
        try UnixSocketIO.writeAll(data, to: descriptor)
        _ = Darwin.shutdown(descriptor, SHUT_WR)
        let responseData = try UnixSocketIO.readToEnd(from: descriptor)
        return try decoder.decode(JSONRPCResponse.self, from: responseData)
    }

    public func streamTerminalEvents(
        onEvent: (RPCValue) throws -> Void
    ) throws {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw UnixSocketError.socketCreationFailed(errno)
        }
        defer { Darwin.close(descriptor) }

        try UnixSocketAddress.withAddress(path: socketPath) { address, length in
            let result = Darwin.connect(descriptor, address, length)
            if result != 0 {
                throw UnixSocketError.connectFailed(errno)
            }
        }

        let request = JSONRPCRequest(method: ControlMethod.terminalEvents.rawValue)
        let data = try encoder.encode(request)
        try UnixSocketIO.writeAll(data, to: descriptor)
        _ = Darwin.shutdown(descriptor, SHUT_WR)

        guard let responseData = try UnixSocketIO.readLine(from: descriptor) else {
            throw UnixSocketError.readFailed(ECONNRESET)
        }

        let response = try decoder.decode(JSONRPCResponse.self, from: responseData)
        if let error = response.error {
            throw error
        }

        while let line = try UnixSocketIO.readLine(from: descriptor) {
            guard line.isEmpty == false else {
                continue
            }

            let request = try decoder.decode(JSONRPCRequest.self, from: line)
            guard request.method == ControlMethod.terminalEvents.rawValue,
                  let params = request.params
            else {
                continue
            }

            try onEvent(params)
        }
    }
}

public final class LocalControlServer: @unchecked Sendable {
    public typealias Handler = @Sendable (JSONRPCRequest) -> JSONRPCResponse?
    public typealias StreamHandler = @Sendable (Int32, JSONRPCRequest) throws -> Bool

    private let socketPath: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let queue = DispatchQueue(label: "dev.fingergun.omux.control-plane")
    private var listeningDescriptor: Int32 = -1
    private var isRunning = false

    public init(socketPath: String = ControlPlaneSocket.defaultPath()) {
        self.socketPath = socketPath
    }

    public func start(
        handler: @escaping Handler,
        streamHandler: StreamHandler? = nil
    ) throws {
        try ensureSocketDirectoryExists()
        _ = unlink(socketPath)

        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw UnixSocketError.socketCreationFailed(errno)
        }

        do {
            try UnixSocketAddress.withAddress(path: socketPath) { address, length in
                if Darwin.bind(descriptor, address, length) != 0 {
                    throw UnixSocketError.bindFailed(errno)
                }
            }

            if Darwin.listen(descriptor, SOMAXCONN) != 0 {
                throw UnixSocketError.listenFailed(errno)
            }
        } catch {
            Darwin.close(descriptor)
            throw error
        }

        listeningDescriptor = descriptor
        isRunning = true

        queue.async { [weak self] in
            self?.acceptLoop(handler: handler, streamHandler: streamHandler)
        }
    }

    public func stop() {
        isRunning = false

        if listeningDescriptor >= 0 {
            Darwin.close(listeningDescriptor)
            listeningDescriptor = -1
        }

        _ = unlink(socketPath)
    }

    deinit {
        stop()
    }

    private func ensureSocketDirectoryExists() throws {
        let socketURL = URL(fileURLWithPath: socketPath)
        let directoryURL = socketURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func acceptLoop(handler: @escaping Handler, streamHandler: StreamHandler?) {
        while isRunning {
            let clientDescriptor = Darwin.accept(listeningDescriptor, nil, nil)
            if clientDescriptor < 0 {
                if isRunning {
                    continue
                }
                break
            }

            handleConnection(clientDescriptor, handler: handler, streamHandler: streamHandler)
        }
    }

    private func handleConnection(
        _ descriptor: Int32,
        handler: Handler,
        streamHandler: StreamHandler?
    ) {
        defer { Darwin.close(descriptor) }

        do {
            let requestData = try UnixSocketIO.readToEnd(from: descriptor)
            let request = try decoder.decode(JSONRPCRequest.self, from: requestData)
            if try streamHandler?(descriptor, request) == true {
                return
            }
            if let response = handler(request) {
                let responseData = try encoder.encode(response)
                try UnixSocketIO.writeAll(responseData, to: descriptor)
            }
        } catch {
            let response = JSONRPCResponse(
                id: nil,
                error: JSONRPCError(code: -32000, message: String(describing: error))
            )

            if let responseData = try? encoder.encode(response) {
                _ = try? UnixSocketIO.writeAll(responseData, to: descriptor)
            }
        }
    }
}
