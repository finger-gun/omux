import Foundation
import OmuxCore

public enum TerminalOpenURLKind: String, Codable, Sendable {
    case unknown
    case text
    case html
}

public enum TerminalProgressState: String, Codable, Sendable {
    case removed
    case active
    case error
    case indeterminate
    case paused
}

public enum TerminalAction: Equatable, Codable, Sendable {
    case workingDirectoryChanged(String)
    case titleChanged(String)
    case tabTitleChanged(String)
    case openURL(url: String, kind: TerminalOpenURLKind)
    case desktopNotification(title: String, body: String?)
    case bell
    case inputSent(text: String?, key: String?, keyCode: UInt16?, modifiers: KeyModifiers, route: NormalizedInputRoute?, source: String)
    case commandFinished(exitCode: Int?, durationNanoseconds: UInt64)
    case progressReported(state: TerminalProgressState, progress: Int?)
    case childExited(exitCode: Int, elapsedMilliseconds: UInt64)
    case rendererHealthChanged(isHealthy: Bool)

    public var payload: OmuxValue {
        switch self {
        case .workingDirectoryChanged(let path):
            return .object(["path": .string(path)])
        case .titleChanged(let title):
            return .object(["title": .string(title)])
        case .tabTitleChanged(let title):
            return .object(["title": .string(title)])
        case .openURL(let url, let kind):
            return .object([
                "url": .string(url),
                "kind": .string(kind.rawValue),
            ])
        case .desktopNotification(let title, let body):
            return .object([
                "title": .string(title),
                "body": body.map(OmuxValue.string) ?? .null,
            ])
        case .bell:
            return .object([:])
        case .inputSent(let text, let key, let keyCode, let modifiers, let route, let source):
            return .object([
                "text": text.map(OmuxValue.string) ?? .null,
                "key": key.map(OmuxValue.string) ?? .null,
                "keyCode": keyCode.map { .integer(Int($0)) } ?? .null,
                "modifiers": .integer(Int(modifiers.rawValue)),
                "route": route.map { .string($0.rawValue) } ?? .null,
                "source": .string(source),
            ])
        case .commandFinished(let exitCode, let durationNanoseconds):
            return .object([
                "exitCode": exitCode.map(OmuxValue.integer) ?? .null,
                "durationNanoseconds": Int(exactly: durationNanoseconds).map(OmuxValue.integer) ?? .double(Double(durationNanoseconds)),
            ])
        case .progressReported(let state, let progress):
            return .object([
                "state": .string(state.rawValue),
                "progress": progress.map(OmuxValue.integer) ?? .null,
            ])
        case .childExited(let exitCode, let elapsedMilliseconds):
            return .object([
                "exitCode": .integer(exitCode),
                "elapsedMilliseconds": Int(exactly: elapsedMilliseconds).map(OmuxValue.integer) ?? .double(Double(elapsedMilliseconds)),
            ])
        case .rendererHealthChanged(let isHealthy):
            return .object(["isHealthy": .bool(isHealthy)])
        }
    }

    public var hookName: String {
        switch self {
        case .workingDirectoryChanged:
            return "terminal-cwd-changed"
        case .titleChanged:
            return "terminal-title-changed"
        case .tabTitleChanged:
            return "terminal-tab-title-changed"
        case .openURL:
            return "terminal-open-url"
        case .desktopNotification:
            return "terminal-desktop-notification"
        case .bell:
            return "terminal-bell"
        case .inputSent:
            return "terminal-input-sent"
        case .commandFinished:
            return "terminal-command-finished"
        case .progressReported:
            return "terminal-progress-reported"
        case .childExited:
            return "terminal-child-exited"
        case .rendererHealthChanged:
            return "terminal-renderer-health-changed"
        }
    }
}

public struct RuntimeTerminalActionRecord: Equatable, Sendable {
    public let runtimeSurfaceID: String
    public let action: TerminalAction

    public init(runtimeSurfaceID: String, action: TerminalAction) {
        self.runtimeSurfaceID = runtimeSurfaceID
        self.action = action
    }
}

public struct TerminalActionEvent: Equatable, Sendable {
    public let paneID: PaneID
    public let sessionID: SessionID
    public let runtimeSurfaceID: String
    public let action: TerminalAction

    public init(
        paneID: PaneID,
        sessionID: SessionID,
        runtimeSurfaceID: String,
        action: TerminalAction
    ) {
        self.paneID = paneID
        self.sessionID = sessionID
        self.runtimeSurfaceID = runtimeSurfaceID
        self.action = action
    }

    public var payload: OmuxValue {
        action.payload
    }
}

enum TerminalActionTranslation: Equatable {
    case supported(TerminalAction)
    case rejected
    case deferred
}
