import Foundation
import OmuxControlPlane
import OmuxCore

public struct OmuxAIStatusPlugin {
    public static let pluginID = "dev.fingergun.ai-status"
    public static let commandName = "ai-status"
    public static let commandDisplayPath = "bundled:\(pluginID)"

    private let environment: [String: String]

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    public func run(
        arguments: [String],
        client: OmuxControlClient,
        writeLine: (String) -> Void
    ) throws -> Int32 {
        guard let subcommand = arguments.first else {
            writeLine(Self.usage)
            return 1
        }

        let rest = Array(arguments.dropFirst())
        switch subcommand {
        case "codex":
            return try runCodex(arguments: rest, client: client, writeLine: writeLine)
        case "clear-stale":
            writeLine("No stale bundled AI status entries.")
            return 0
        default:
            writeLine(Self.usage)
            return 1
        }
    }

    private func runCodex(
        arguments: [String],
        client: OmuxControlClient,
        writeLine: (String) -> Void
    ) throws -> Int32 {
        guard let subcommand = arguments.first else {
            writeLine(Self.codexUsage)
            return 1
        }

        let rest = Array(arguments.dropFirst())
        switch subcommand {
        case "title":
            guard let parsed = parseCodexTitle(rest) else {
                writeLine(Self.codexTitleUsage)
                return 1
            }
            let state = codexState(forTitle: parsed.title)
            try sendStatus(
                state: state,
                target: parsed.target,
                label: "Codex",
                message: codexMessage(forTitle: parsed.title),
                source: "plugin.ai-status.codex",
                client: client,
                writeLine: writeLine
            )
            return 0
        case "clear":
            guard let target = parseTarget(rest) ?? inferredTarget() else {
                writeLine(Self.codexClearUsage)
                return 1
            }
            try sendStatus(
                state: .clear,
                target: target,
                label: nil,
                message: nil,
                source: "plugin.ai-status.codex",
                client: client,
                writeLine: writeLine
            )
            return 0
        case "wrap":
            return try runCodexWrapper(arguments: rest, client: client, writeLine: writeLine)
        default:
            writeLine(Self.codexUsage)
            return 1
        }
    }

    private func runCodexWrapper(
        arguments: [String],
        client: OmuxControlClient,
        writeLine: (String) -> Void
    ) throws -> Int32 {
        let separatorIndex = arguments.firstIndex(of: "--")
        let targetArguments = separatorIndex.map { Array(arguments[..<$0]) } ?? arguments
        let commandArguments = separatorIndex.map { Array(arguments[arguments.index(after: $0)...]) } ?? arguments
        guard commandArguments.isEmpty == false,
              let target = parseTarget(targetArguments) ?? inferredTarget()
        else {
            writeLine(Self.codexWrapUsage)
            return 1
        }

        try sendStatus(
            state: .working,
            target: target,
            label: "Codex",
            message: commandArguments.joined(separator: " "),
            source: "plugin.ai-status.codex",
            client: client,
            writeLine: { _ in }
        )

        let process = Process()
        do {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = commandArguments
            process.environment = environment
            try process.run()
            process.waitUntilExit()
        } catch {
            try sendStatus(
                state: .error,
                target: target,
                label: "Codex",
                message: error.localizedDescription,
                source: "plugin.ai-status.codex",
                client: client,
                writeLine: { _ in }
            )
            return 1
        }

        try sendStatus(
            state: process.terminationStatus == 0 ? .idle : .error,
            target: target,
            label: "Codex",
            message: nil,
            source: "plugin.ai-status.codex",
            client: client,
            writeLine: { _ in }
        )
        return process.terminationStatus
    }

    private func sendStatus(
        state: ControlPlanePaneStatusState,
        target: ControlPlaneTerminalTarget,
        label: String?,
        message: String?,
        source: String,
        client: OmuxControlClient,
        writeLine: (String) -> Void
    ) throws {
        let request = ControlPlanePaneStatusRequest(
            target: target,
            state: state,
            label: label,
            message: message,
            source: source
        )
        let response = try client.request(method: .paneStatus, params: request.rpcValue)
        writeLine(response.result?.prettyPrinted ?? "")
    }

    private func parseCodexTitle(_ arguments: [String]) -> (target: ControlPlaneTerminalTarget, title: String)? {
        guard let titleIndex = arguments.firstIndex(of: "--title"),
              arguments.indices.contains(titleIndex + 1),
              let target = parseTarget(arguments) ?? inferredTarget()
        else {
            return nil
        }
        return (target, arguments[titleIndex + 1])
    }

    private func parseTarget(_ arguments: [String]) -> ControlPlaneTerminalTarget? {
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--session":
                guard arguments.indices.contains(index + 1) else { return nil }
                return .session(SessionID(rawValue: arguments[index + 1]))
            case "--pane", "--pane-tab":
                guard arguments.indices.contains(index + 1) else { return nil }
                return .pane(PaneID(rawValue: arguments[index + 1]))
            case "--tab":
                guard arguments.indices.contains(index + 1) else { return nil }
                return .tab(TabID(rawValue: arguments[index + 1]))
            case "--workspace":
                guard arguments.indices.contains(index + 1) else { return nil }
                return .workspace(WorkspaceID(rawValue: arguments[index + 1]))
            case "--focused":
                return .focused
            default:
                index += 1
            }
        }
        return nil
    }

    private func inferredTarget() -> ControlPlaneTerminalTarget? {
        if let paneID = environment["OMUX_PANE_ID"], paneID.isEmpty == false {
            return .pane(PaneID(rawValue: paneID))
        }
        if let sessionID = environment["OMUX_SESSION_ID"], sessionID.isEmpty == false {
            return .session(SessionID(rawValue: sessionID))
        }
        return nil
    }

    private func codexState(forTitle title: String) -> ControlPlanePaneStatusState {
        OmuxCodexTitleAdapter.observe(title: title, allowsStateOnlyMatch: true)?.state ?? .working
    }

    private func codexMessage(forTitle title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public static let usage = "usage: omux ai-status codex|clear-stale ..."
    public static let codexUsage = "usage: omux ai-status codex title|clear|wrap ..."
    public static let codexTitleUsage = "usage: omux ai-status codex title --pane <id>|--session <id>|--focused --title <raw title>"
    public static let codexClearUsage = "usage: omux ai-status codex clear --pane <id>|--session <id>|--focused"
    public static let codexWrapUsage = "usage: omux ai-status codex wrap --pane <id>|--session <id>|--focused -- <command> [args...]"
}

public struct OmuxAIStatusTitleObservation: Equatable, Sendable {
    public let adapterID: String
    public let label: String
    public let state: ControlPlanePaneStatusState
    public let message: String?
    public let source: String
    public let confidence: Double

    public init(
        adapterID: String,
        label: String,
        state: ControlPlanePaneStatusState,
        message: String?,
        source: String,
        confidence: Double
    ) {
        self.adapterID = adapterID
        self.label = label
        self.state = state
        self.message = message
        self.source = source
        self.confidence = confidence
    }
}

public enum OmuxAIStatusTitleObserver {
    public static func observe(
        title: String,
        previousAdapterID: String? = nil
    ) -> OmuxAIStatusTitleObservation? {
        if let gemini = OmuxGeminiTitleAdapter.observe(title: title) {
            return gemini
        }
        return OmuxCodexTitleAdapter.observe(
            title: title,
            allowsStateOnlyMatch: previousAdapterID == OmuxCodexTitleAdapter.adapterID
        )
    }
}

enum OmuxCodexTitleAdapter {
    static let adapterID = "codex"

    static func observe(
        title: String,
        allowsStateOnlyMatch: Bool
    ) -> OmuxAIStatusTitleObservation? {
        let normalized = title.lowercased()
        let hasCodexIdentity = isCodexTitle(normalized)
        if normalized.contains("approval")
            || normalized.contains("permission")
            || normalized.contains("confirm")
            || normalized.contains("waiting")
            || normalized.contains("needs input")
            || normalized.contains("action required") {
            guard hasCodexIdentity || allowsStateOnlyMatch else {
                return nil
            }
            return observation(title: title, state: .needsInput, confidence: hasCodexIdentity ? 0.75 : 0.55)
        }
        if normalized.contains("error") || normalized.contains("failed") {
            guard hasCodexIdentity || allowsStateOnlyMatch else {
                return nil
            }
            return observation(title: title, state: .error, confidence: hasCodexIdentity ? 0.75 : 0.55)
        }
        if normalized.contains("idle") || normalized.contains("done") || normalized.contains("finished") {
            guard hasCodexIdentity || allowsStateOnlyMatch else {
                return nil
            }
            return observation(title: title, state: .idle, confidence: hasCodexIdentity ? 0.75 : 0.55)
        }
        guard hasCodexIdentity else {
            return nil
        }
        return observation(title: title, state: .working, confidence: 0.65)
    }

    private static func isCodexTitle(_ normalized: String) -> Bool {
        normalized.contains("codex")
    }

    private static func observation(
        title: String,
        state: ControlPlanePaneStatusState,
        confidence: Double
    ) -> OmuxAIStatusTitleObservation {
        OmuxAIStatusTitleObservation(
            adapterID: adapterID,
            label: "Codex",
            state: state,
            message: message(forTitle: title),
            source: "plugin.ai-status.codex.title",
            confidence: confidence
        )
    }

    private static func message(forTitle title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum OmuxGeminiTitleAdapter {
    private static let readyIcon = "\u{25C7}"
    private static let actionRequiredIcon = "\u{270B}"
    private static let workingIcon = "\u{2726}"

    static func observe(title: String) -> OmuxAIStatusTitleObservation? {
        if title.contains(actionRequiredIcon) {
            return observation(title: title, state: .needsInput)
        }
        if title.contains(workingIcon) {
            return observation(title: title, state: .working)
        }
        if title.contains(readyIcon) {
            return observation(title: title, state: .idle)
        }
        return nil
    }

    private static func observation(
        title: String,
        state: ControlPlanePaneStatusState
    ) -> OmuxAIStatusTitleObservation {
        OmuxAIStatusTitleObservation(
            adapterID: "gemini",
            label: "Gemini",
            state: state,
            message: message(forTitle: title),
            source: "plugin.ai-status.gemini.title",
            confidence: 0.9
        )
    }

    private static func message(forTitle title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
