import Darwin
import Foundation
import OmuxCore

public struct TerminalSize: Equatable, Sendable {
    public var columns: Int
    public var rows: Int

    static let `default` = TerminalSize(columns: 80, rows: 24)

    public init(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
    }
}

enum InteractiveTerminalRuntimeError: Error {
    case openPTFailed
    case grantPTFailed(Int32)
    case unlockPTFailed(Int32)
    case missingSlavePath
    case openSlaveFailed
    case resizeFailed(Int32)
    case writeFailed(Int32)
}

final class InteractiveTerminalRuntimeSession: @unchecked Sendable {
    private var masterFD: Int32
    private var slaveFD: Int32
    private let process: Process
    private let outputQueue = DispatchQueue(label: "dev.fingergun.omux.terminal-output", qos: .userInitiated)
    private var readSource: DispatchSourceRead?
    private let onOutput: @Sendable (Data) -> Void
    private var isStopped = false

    init(
        descriptor: SessionDescriptor,
        initialSize: TerminalSize = .default,
        onOutput: @escaping @Sendable (Data) -> Void
    ) throws {
        self.onOutput = onOutput

        let masterFD = posix_openpt(O_RDWR | O_NOCTTY)
        guard masterFD >= 0 else {
            throw InteractiveTerminalRuntimeError.openPTFailed
        }
        self.masterFD = masterFD

        guard grantpt(masterFD) == 0 else {
            let error = errno
            close(masterFD)
            throw InteractiveTerminalRuntimeError.grantPTFailed(error)
        }

        guard unlockpt(masterFD) == 0 else {
            let error = errno
            close(masterFD)
            throw InteractiveTerminalRuntimeError.unlockPTFailed(error)
        }

        guard let slaveName = ptsname(masterFD) else {
            close(masterFD)
            throw InteractiveTerminalRuntimeError.missingSlavePath
        }

        let slaveFD = open(slaveName, O_RDWR | O_NOCTTY)
        guard slaveFD >= 0 else {
            close(masterFD)
            throw InteractiveTerminalRuntimeError.openSlaveFailed
        }
        self.slaveFD = slaveFD
        self.process = Process()

        try resize(to: initialSize)
        try startProcess(descriptor: descriptor)
        startReading()
    }

    deinit {
        stop()
    }

    func write(_ data: Data) throws {
        let result = data.withUnsafeBytes { bytes in
            Darwin.write(masterFD, bytes.baseAddress, bytes.count)
        }

        guard result >= 0 else {
            throw InteractiveTerminalRuntimeError.writeFailed(errno)
        }
    }

    func resize(to size: TerminalSize) throws {
        var winsize = winsize(
            ws_row: UInt16(max(1, size.rows)),
            ws_col: UInt16(max(1, size.columns)),
            ws_xpixel: 0,
            ws_ypixel: 0
        )

        guard ioctl(masterFD, TIOCSWINSZ, &winsize) == 0 else {
            throw InteractiveTerminalRuntimeError.resizeFailed(errno)
        }
    }

    func stop() {
        guard isStopped == false else {
            return
        }
        isStopped = true

        readSource?.cancel()
        readSource = nil

        if process.isRunning {
            process.terminate()
            usleep(100_000)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }

        if slaveFD >= 0 {
            close(slaveFD)
            slaveFD = -1
        }

        if masterFD >= 0 {
            close(masterFD)
            masterFD = -1
        }
    }

    private func startProcess(descriptor: SessionDescriptor) throws {
        let slaveHandle = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: false)

        process.executableURL = URL(fileURLWithPath: descriptor.shell)
        process.arguments = interactiveArguments(for: descriptor.shell)
        process.currentDirectoryURL = URL(fileURLWithPath: descriptor.workingDirectory)
        process.standardInput = slaveHandle
        process.standardOutput = slaveHandle
        process.standardError = slaveHandle

        var environment = ProcessInfo.processInfo.environment
        descriptor.environment.forEach { environment[$0.key] = $0.value }
        environment["TERM"] = environment["TERM"] ?? "xterm-256color"
        environment["COLUMNS"] = environment["COLUMNS"] ?? "80"
        environment["LINES"] = environment["LINES"] ?? "24"
        process.environment = environment

        try process.run()
        close(slaveFD)
        slaveFD = -1
    }

    private func startReading() {
        let readSource = DispatchSource.makeReadSource(fileDescriptor: masterFD, queue: outputQueue)
        readSource.setEventHandler { [weak self] in
            self?.drainOutput()
        }
        readSource.setCancelHandler {}
        readSource.resume()
        self.readSource = readSource
    }

    private func drainOutput() {
        guard masterFD >= 0 else {
            return
        }

        var buffer = [UInt8](repeating: 0, count: 4096)

        while true {
            let count = Darwin.read(masterFD, &buffer, buffer.count)
            if count > 0 {
                onOutput(Data(buffer.prefix(Int(count))))
                continue
            }

            if count == 0 || errno != EAGAIN {
                break
            }

            break
        }
    }

    private func interactiveArguments(for shellPath: String) -> [String] {
        let shellName = URL(fileURLWithPath: shellPath).lastPathComponent
        switch shellName {
        case "bash", "zsh", "sh":
            return ["-i"]
        default:
            return ["-i"]
        }
    }
}
