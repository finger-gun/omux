import Foundation
import OmuxControlPlane
import OmuxCore

public struct OmuxAIStatusPlugin {
    public static let pluginID = "dev.fingergun.ai-status"
    public static let commandName = "ai-status"
    public static let commandDisplayPath = "bundled:\(pluginID)"

    private let environment: [String: String]
    private let standardInputData: () -> Data

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        standardInputData: @escaping () -> Data = { FileHandle.standardInput.readDataToEndOfFile() }
    ) {
        self.environment = environment
        self.standardInputData = standardInputData
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
            return try runVendorCommand(vendor: .codex, arguments: rest, client: client, writeLine: writeLine)
        case "hook":
            return try runHook(arguments: rest, client: client, writeLine: writeLine)
        case "hooks":
            return runHooks(arguments: rest, writeLine: writeLine)
        case "clear-stale":
            writeLine("clear-stale is not implemented for bundled ai-status.")
            return 1
        default:
            writeLine(Self.usage)
            return 1
        }
    }

    private func runHooks(
        arguments: [String],
        writeLine: (String) -> Void
    ) -> Int32 {
        guard let action = arguments.first,
              action == "setup" || action == "uninstall"
        else {
            writeLine(Self.hooksUsage)
            return 1
        }

        let requestedVendors = Array(arguments.dropFirst())
        let vendors: [OmuxAIStatusHookInstaller.Vendor]
        if requestedVendors.isEmpty {
            vendors = OmuxAIStatusHookInstaller.Vendor.allCases
        } else {
            var parsed = [OmuxAIStatusHookInstaller.Vendor]()
            for vendorName in requestedVendors {
                guard let vendor = OmuxAIStatusHookInstaller.Vendor(rawValue: vendorName.lowercased()) else {
                    writeLine("Unsupported ai-status hook vendor: \(vendorName)")
                    writeLine(Self.hooksUsage)
                    return 1
                }
                parsed.append(vendor)
            }
            vendors = parsed
        }

        let installer = OmuxAIStatusHookInstaller(environment: environment)
        var didFail = false
        for vendor in vendors {
            do {
                switch action {
                case "setup":
                    let result = try installer.setup(vendor: vendor)
                    writeLine(result)
                case "uninstall":
                    let result = try installer.uninstall(vendor: vendor)
                    writeLine(result)
                default:
                    break
                }
            } catch {
                didFail = true
                writeLine("Failed to \(action) \(vendor.rawValue) hooks: \(error.localizedDescription)")
            }
        }
        return didFail ? 1 : 0
    }

    private func runHook(
        arguments: [String],
        client: OmuxControlClient,
        writeLine: (String) -> Void
    ) throws -> Int32 {
        guard let request = parseHookRequest(arguments) else {
            writeLine(Self.hookUsage)
            return 1
        }
        guard let target = request.target ?? inferredTarget() else {
            writeLine("{}")
            return 0
        }
        guard let observation = OmuxAIStatusHookAdapter.observe(
            source: request.source,
            event: request.event,
            payload: standardInputData()
        ) else {
            writeLine("{}")
            return 0
        }

        try sendStatus(
            state: observation.state,
            target: target,
            label: observation.label,
            message: observation.message,
            source: observation.source,
            client: client,
            writeLine: writeLine
        )
        return 0
    }

    private func runVendorCommand(
        vendor: OmuxAIStatusCommandVendor,
        arguments: [String],
        client: OmuxControlClient,
        writeLine: (String) -> Void
    ) throws -> Int32 {
        guard let subcommand = arguments.first else {
            writeLine(vendor.usage)
            return 1
        }

        let rest = Array(arguments.dropFirst())
        switch subcommand {
        case "title":
            guard let parsed = parseTitleCommand(rest) else {
                writeLine(vendor.titleUsage)
                return 1
            }
            let state = state(forTitle: parsed.title, vendor: vendor)
            try sendStatus(
                state: state,
                target: parsed.target,
                label: vendor.label,
                message: message(forTitle: parsed.title),
                source: vendor.source,
                client: client,
                writeLine: writeLine
            )
            return 0
        case "clear":
            guard let target = parseTarget(rest) ?? inferredTarget() else {
                writeLine(vendor.clearUsage)
                return 1
            }
            try sendStatus(
                state: .clear,
                target: target,
                label: nil,
                message: nil,
                source: vendor.source,
                client: client,
                writeLine: writeLine
            )
            return 0
        case "wrap":
            return try runVendorWrapper(vendor: vendor, arguments: rest, client: client, writeLine: writeLine)
        default:
            writeLine(vendor.usage)
            return 1
        }
    }

    private func runVendorWrapper(
        vendor: OmuxAIStatusCommandVendor,
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
            writeLine(vendor.wrapUsage)
            return 1
        }

        try sendStatus(
            state: .working,
            target: target,
            label: vendor.label,
            message: redactedCommandSummary(commandArguments),
            source: vendor.source,
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
                label: vendor.label,
                message: error.localizedDescription,
                source: vendor.source,
                client: client,
                writeLine: { _ in }
            )
            return 1
        }

        try sendStatus(
            state: process.terminationStatus == 0 ? .idle : .error,
            target: target,
            label: vendor.label,
            message: nil,
            source: vendor.source,
            client: client,
            writeLine: { _ in }
        )
        return process.terminationStatus
    }

    private func redactedCommandSummary(_ commandArguments: [String]) -> String {
        guard let executable = commandArguments.first,
              executable.isEmpty == false
        else {
            return "<redacted command>"
        }
        return "\(executable) [arguments redacted]"
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

    private func parseTitleCommand(_ arguments: [String]) -> (target: ControlPlaneTerminalTarget, title: String)? {
        guard let titleIndex = arguments.firstIndex(of: "--title"),
              arguments.indices.contains(titleIndex + 1),
              let target = parseTarget(arguments) ?? inferredTarget()
        else {
            return nil
        }
        return (target, arguments[titleIndex + 1])
    }

    private func parseHookRequest(_ arguments: [String]) -> (
        source: String,
        event: String,
        target: ControlPlaneTerminalTarget?
    )? {
        guard let sourceIndex = arguments.firstIndex(of: "--source"),
              arguments.indices.contains(sourceIndex + 1),
              let eventIndex = arguments.firstIndex(of: "--event"),
              arguments.indices.contains(eventIndex + 1)
        else {
            return nil
        }

        let source = arguments[sourceIndex + 1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let event = arguments[eventIndex + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard source.isEmpty == false, event.isEmpty == false else {
            return nil
        }
        return (source, event, parseTarget(arguments))
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

    private func state(forTitle title: String, vendor: OmuxAIStatusCommandVendor) -> ControlPlanePaneStatusState {
        OmuxAIStatusTitleObserver.observe(title: title, previousAdapterID: vendor.adapterID)?.state ?? .working
    }

    private func message(forTitle title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public static let usage = "usage: omux ai-status codex|hook|hooks|clear-stale ..."
    public static let codexUsage = "usage: omux ai-status codex title|clear|wrap ..."
    public static let codexTitleUsage = "usage: omux ai-status codex title --pane <id>|--session <id>|--focused --title <raw title>"
    public static let codexClearUsage = "usage: omux ai-status codex clear --pane <id>|--session <id>|--focused"
    public static let codexWrapUsage = "usage: omux ai-status codex wrap --pane <id>|--session <id>|--focused -- <command> [args...]"
    public static let hookUsage = "usage: omux ai-status hook --source codex|gemini|claude --event <event> [--pane <id>|--session <id>|--focused]"
    public static let hooksUsage = "usage: omux ai-status hooks setup|uninstall [codex|gemini|claude]"
}

private enum OmuxAIStatusCommandVendor {
    case codex

    var adapterID: String {
        switch self {
        case .codex:
            return "codex"
        }
    }

    var label: String {
        switch self {
        case .codex:
            return "Codex"
        }
    }

    var source: String {
        "plugin.ai-status.\(adapterID)"
    }

    var usage: String {
        switch self {
        case .codex:
            return OmuxAIStatusPlugin.codexUsage
        }
    }

    var titleUsage: String {
        switch self {
        case .codex:
            return OmuxAIStatusPlugin.codexTitleUsage
        }
    }

    var clearUsage: String {
        switch self {
        case .codex:
            return OmuxAIStatusPlugin.codexClearUsage
        }
    }

    var wrapUsage: String {
        switch self {
        case .codex:
            return OmuxAIStatusPlugin.codexWrapUsage
        }
    }
}

public struct OmuxAIStatusHookInstaller {
    public enum Vendor: String, CaseIterable, Sendable {
        case codex
        case gemini
        case claude
    }

    private let environment: [String: String]
    private let fileManager: FileManager

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) {
        self.environment = environment
        self.fileManager = fileManager
    }

    public func setup(vendor: Vendor) throws -> String {
        switch vendor {
        case .codex:
            try mergeJSONHooks(
                configURL: codexHooksURL(),
                vendor: vendor,
                events: ["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "Stop"]
            )
            try ensureCodexHooksEnabled()
            return "Installed OpenMUX ai-status Codex hooks."
        case .gemini:
            try mergeJSONHooks(
                configURL: geminiSettingsURL(),
                vendor: vendor,
                events: ["SessionStart", "PreToolUse", "BeforeAgent", "AfterAgent", "Notification", "SessionEnd"]
            )
            return "Installed OpenMUX ai-status Gemini hooks."
        case .claude:
            return "Claude ai-status hooks use guided or wrapper-injected setup; no Claude settings were edited."
        }
    }

    public func uninstall(vendor: Vendor) throws -> String {
        switch vendor {
        case .codex:
            try removeJSONHooks(configURL: codexHooksURL(), vendor: vendor)
            try removeCodexHooksEnabledBlock()
            return "Uninstalled OpenMUX ai-status Codex hooks."
        case .gemini:
            try removeJSONHooks(configURL: geminiSettingsURL(), vendor: vendor)
            return "Uninstalled OpenMUX ai-status Gemini hooks."
        case .claude:
            return "Claude ai-status hooks use guided or wrapper-injected setup; no Claude settings were edited."
        }
    }

    private func mergeJSONHooks(
        configURL: URL,
        vendor: Vendor,
        events: [String]
    ) throws {
        var root = try loadJSONObject(at: configURL)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in events {
            var entries = hooks[event] as? [[String: Any]] ?? []
            entries.removeAll { isOpenMUXHookEntry($0, vendor: vendor) }
            entries.append(hookEntry(vendor: vendor, event: event))
            hooks[event] = entries
        }
        root["hooks"] = hooks
        try writeJSONObject(root, to: configURL)
    }

    private func removeJSONHooks(
        configURL: URL,
        vendor: Vendor
    ) throws {
        guard fileManager.fileExists(atPath: configURL.path(percentEncoded: false)) else {
            return
        }
        var root = try loadJSONObject(at: configURL)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for key in hooks.keys {
            guard var entries = hooks[key] as? [[String: Any]] else {
                continue
            }
            entries.removeAll { isOpenMUXHookEntry($0, vendor: vendor) }
            if entries.isEmpty {
                hooks.removeValue(forKey: key)
            } else {
                hooks[key] = entries
            }
        }
        root["hooks"] = hooks
        try writeJSONObject(root, to: configURL)
    }

    private func hookEntry(vendor: Vendor, event: String) -> [String: Any] {
        [
            "type": "command",
            "command": "omux ai-status hook --source \(vendor.rawValue) --event \(event)",
            "timeout_ms": vendor == .gemini ? 10_000 : 5_000,
            "openmux_ai_status": true,
            "openmux_ai_status_vendor": vendor.rawValue,
        ]
    }

    private func isOpenMUXHookEntry(_ entry: [String: Any], vendor: Vendor) -> Bool {
        if let marker = entry["openmux_ai_status"] as? Bool,
           marker,
           let markerVendor = entry["openmux_ai_status_vendor"] as? String {
            return markerVendor == vendor.rawValue
        }
        if let command = entry["command"] as? String {
            return command.contains("omux ai-status hook --source \(vendor.rawValue)")
        }
        return false
    }

    private func loadJSONObject(at url: URL) throws -> [String: Any] {
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
            return [:]
        }
        let data = try Data(contentsOf: url)
        guard data.isEmpty == false else {
            return [:]
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "OmuxAIStatusHookInstaller", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "\(url.path(percentEncoded: false)) must contain a JSON object.",
            ])
        }
        return object
    }

    private func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }

    private func ensureCodexHooksEnabled() throws {
        let url = codexConfigURL()
        let block = """
        # OpenMUX ai-status managed start
        codex_hooks = true
        # OpenMUX ai-status managed end
        """
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        guard existing.contains("# OpenMUX ai-status managed start") == false else {
            return
        }
        let existingWithoutManagedBlock = existing.replacingOccurrences(
            of: #"(?ms)^# OpenMUX ai-status managed start\n.*?\n# OpenMUX ai-status managed end\n?"#,
            with: "",
            options: .regularExpression
        )
        if existingWithoutManagedBlock.range(of: #"(?m)^\s*codex_hooks\s*="#, options: .regularExpression) != nil {
            throw NSError(
                domain: "OmuxAIStatusHookInstaller",
                code: 3,
                userInfo: [
                    NSLocalizedDescriptionKey: "\(url.path(percentEncoded: false)) already defines codex_hooks; remove it before running ai-status hooks setup.",
                ]
            )
        }
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let separator = existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n"
        try (existing + separator + block + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func removeCodexHooksEnabledBlock() throws {
        let url = codexConfigURL()
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
            return
        }
        let existing = try String(contentsOf: url, encoding: .utf8)
        let pattern = #"(?ms)^# OpenMUX ai-status managed start\n.*?\n# OpenMUX ai-status managed end\n?"#
        let updated = existing.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        try updated.write(to: url, atomically: true, encoding: .utf8)
    }

    private func codexHooksURL() -> URL {
        codexHomeURL().appendingPathComponent("hooks.json", isDirectory: false)
    }

    private func codexConfigURL() -> URL {
        codexHomeURL().appendingPathComponent("config.toml", isDirectory: false)
    }

    private func codexHomeURL() -> URL {
        if let path = environment["CODEX_HOME"], path.isEmpty == false {
            return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath, isDirectory: true)
        }
        return homeURL().appendingPathComponent(".codex", isDirectory: true)
    }

    private func geminiSettingsURL() -> URL {
        homeURL()
            .appendingPathComponent(".gemini", isDirectory: true)
            .appendingPathComponent("settings.json", isDirectory: false)
    }

    private func homeURL() -> URL {
        if let path = environment["HOME"], path.isEmpty == false {
            return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath, isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }
}

public struct OmuxAIStatusHookObservation: Equatable, Sendable {
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

public enum OmuxAIStatusHookAdapter {
    public static func observe(
        source: String,
        event: String,
        payload: Data
    ) -> OmuxAIStatusHookObservation? {
        let normalizedSource = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let vendor = Vendor(rawValue: normalizedSource),
              let state = state(for: vendor, event: event, payload: payload)
        else {
            return nil
        }

        return OmuxAIStatusHookObservation(
            adapterID: vendor.rawValue,
            label: vendor.label,
            state: state,
            message: message(from: payload),
            source: "plugin.ai-status.\(vendor.rawValue).hook",
            confidence: 0.95
        )
    }

    private enum Vendor: String {
        case codex
        case gemini
        case claude

        var label: String {
            switch self {
            case .codex:
                return "Codex"
            case .gemini:
                return "Gemini"
            case .claude:
                return "Claude"
            }
        }
    }

    private static func state(
        for vendor: Vendor,
        event: String,
        payload: Data
    ) -> ControlPlanePaneStatusState? {
        let normalizedEvent = event
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")

        switch vendor {
        case .codex:
            switch normalizedEvent {
            case "permissionrequest":
                return .needsInput
            case "pretooluse", "userpromptsubmit", "sessionstart":
                return .working
            case "turnfailed", "stopfailure", "error":
                return .error
            case "stop", "turncompleted":
                return .idle
            default:
                return nil
            }
        case .gemini:
            switch normalizedEvent {
            case "pretooluse", "beforeagent", "tooluse", "sessionstart":
                return .working
            case "notification":
                return notificationNeedsInput(payload) ? .needsInput : .idle
            case "error", "stopfailure":
                return .error
            case "afteragent", "sessionend", "result":
                return .idle
            default:
                return nil
            }
        case .claude:
            switch normalizedEvent {
            case "permissionrequest", "permissiondenied":
                return .needsInput
            case "notification":
                return notificationNeedsInput(payload) ? .needsInput : .idle
            case "pretooluse", "userpromptsubmit", "sessionstart":
                return .working
            case "stopfailure", "posttoolusefailure", "error":
                return .error
            case "stop":
                return .idle
            default:
                return nil
            }
        }
    }

    private static func notificationNeedsInput(_ payload: Data) -> Bool {
        let text = String(decoding: payload, as: UTF8.self).lowercased()
        return text.contains("permission")
            || text.contains("approval")
            || text.contains("approve")
            || text.contains("action required")
            || text.contains("needs input")
    }

    private static func message(from payload: Data) -> String? {
        guard payload.isEmpty == false,
              let object = try? JSONSerialization.jsonObject(with: payload),
              let text = firstString(in: object)
        else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(240))
    }

    private static func firstString(in value: Any) -> String? {
        let preferredKeys = [
            "message",
            "last_assistant_message",
            "last-assistant-message",
            "errorMessage",
            "error_message",
            "error",
            "title",
            "body",
        ]
        if let dictionary = value as? [String: Any] {
            for key in preferredKeys {
                if let string = dictionary[key] as? String, string.isEmpty == false {
                    return string
                }
            }
            for nested in dictionary.values {
                if let string = firstString(in: nested) {
                    return string
                }
            }
        }
        if let array = value as? [Any] {
            for nested in array {
                if let string = firstString(in: nested) {
                    return string
                }
            }
        }
        return nil
    }
}

public enum OmuxAIStatusJSONLAdapter {
    public static func observe(
        source: String,
        line: String
    ) -> OmuxAIStatusHookObservation? {
        let normalizedSource = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let vendor = Vendor(rawValue: normalizedSource),
              let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let state = state(for: vendor, object: object)
        else {
            return nil
        }

        return OmuxAIStatusHookObservation(
            adapterID: vendor.rawValue,
            label: vendor.label,
            state: state,
            message: message(from: object),
            source: "plugin.ai-status.\(vendor.rawValue).jsonl",
            confidence: 0.98
        )
    }

    private enum Vendor: String {
        case codex
        case gemini
        case claude

        var label: String {
            switch self {
            case .codex:
                return "Codex"
            case .gemini:
                return "Gemini"
            case .claude:
                return "Claude"
            }
        }
    }

    private static func state(
        for vendor: Vendor,
        object: [String: Any]
    ) -> ControlPlanePaneStatusState? {
        let type = normalizedType(from: object)
        switch vendor {
        case .codex:
            if type == "turnstarted" || type == "itemstarted" {
                return .working
            }
            if type == "turncompleted" {
                return .idle
            }
            if type == "turnfailed" || type == "error" {
                return .error
            }
            if normalizedString(object["status"]) == "inprogress" {
                return .working
            }
            return nil
        case .gemini:
            switch type {
            case "tooluse", "message":
                return .working
            case "toolresult":
                return .indeterminate
            case "result":
                return .idle
            case "error":
                return .error
            default:
                return nil
            }
        case .claude:
            switch type {
            case "assistant", "streamevent", "contentblockdelta":
                return .working
            case "result":
                let subtype = normalizedString(object["subtype"])
                if subtype.isEmpty == false,
                   subtype != "success" {
                    return .error
                }
                return .idle
            case "error", "systemapiretry":
                return .error
            default:
                return nil
            }
        }
    }

    private static func normalizedType(from object: [String: Any]) -> String {
        let value = (object["type"] as? String)
            ?? (object["event"] as? String)
            ?? (object["name"] as? String)
            ?? ""
        return normalizedString(value)
    }

    private static func normalizedString(_ value: Any?) -> String {
        guard let string = value as? String else {
            return ""
        }
        return string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
    }

    private static func message(from object: [String: Any]) -> String? {
        for key in ["message", "error", "text", "content", "summary"] {
            if let value = object[key] as? String,
               value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                return String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
            }
        }
        return nil
    }
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
        for adapter in OmuxAIStatusTitleAdapter.allAdapters {
            if let observation = adapter.observe(title: title, previousAdapterID: previousAdapterID) {
                return observation
            }
        }
        return nil
    }
}

private struct OmuxAIStatusTitleAdapter: Sendable {
    struct Rule: Sendable {
        let state: ControlPlanePaneStatusState
        let keywords: [String]
        let icons: [String]
        let allowsColdStart: Bool
        let requiresIdentityOrPrevious: Bool

        init(
            state: ControlPlanePaneStatusState,
            keywords: [String] = [],
            icons: [String] = [],
            allowsColdStart: Bool = false,
            requiresIdentityOrPrevious: Bool = true
        ) {
            self.state = state
            self.keywords = keywords
            self.icons = icons
            self.allowsColdStart = allowsColdStart
            self.requiresIdentityOrPrevious = requiresIdentityOrPrevious
        }
    }

    let adapterID: String
    let label: String
    let identityKeywords: [String]
    let rules: [Rule]
    let identityImpliesWorking: Bool
    let customRule: (@Sendable (_ title: String, _ normalized: String) -> ControlPlanePaneStatusState?)?

    func observe(title: String, previousAdapterID: String?) -> OmuxAIStatusTitleObservation? {
        let normalized = title.localizedLowercase
        let hasIdentity = identityKeywords.contains { normalized.contains($0) }
        let hasPreviousIdentity = previousAdapterID == adapterID

        if let state = customRule?(title, normalized) {
            return observation(title: title, state: state, confidence: hasIdentity ? 0.75 : 0.6)
        }

        for rule in rules {
            let didMatchKeyword = rule.keywords.contains { normalized.contains($0) }
            let didMatchIcon = rule.icons.contains { title.contains($0) }
            guard didMatchKeyword || didMatchIcon else {
                continue
            }
            if rule.requiresIdentityOrPrevious,
               hasIdentity == false,
               hasPreviousIdentity == false,
               rule.allowsColdStart == false {
                continue
            }
            return observation(title: title, state: rule.state, confidence: confidence(hasIdentity: hasIdentity, coldStart: rule.allowsColdStart))
        }

        guard hasIdentity, identityImpliesWorking else {
            return nil
        }
        return observation(title: title, state: .working, confidence: 0.65)
    }

    private func observation(
        title: String,
        state: ControlPlanePaneStatusState,
        confidence: Double
    ) -> OmuxAIStatusTitleObservation {
        OmuxAIStatusTitleObservation(
            adapterID: adapterID,
            label: label,
            state: state,
            message: title.trimmingCharacters(in: .whitespacesAndNewlines).emptyAsNil,
            source: "plugin.ai-status.\(adapterID).title",
            confidence: confidence
        )
    }

    private func confidence(hasIdentity: Bool, coldStart: Bool) -> Double {
        if hasIdentity { return 0.75 }
        if coldStart { return 0.6 }
        return 0.55
    }
}

private extension OmuxAIStatusTitleAdapter {
    static let allAdapters: [OmuxAIStatusTitleAdapter] = [
        .gemini,
        .codex,
        .claude,
        .copilot,
    ]

    static let codex = OmuxAIStatusTitleAdapter(
        adapterID: "codex",
        label: "Codex",
        identityKeywords: ["codex"],
        rules: [
            Rule(state: .needsInput, keywords: ["approval", "permission", "confirm", "waiting", "needs input"]),
            Rule(state: .error, keywords: ["error", "failed"]),
            Rule(state: .idle, keywords: ["idle", "done", "finished"]),
            Rule(state: .working, keywords: ["working", "thinking", "reading", "editing", "writing", "running", "searching", "reviewing"]),
        ],
        identityImpliesWorking: true,
        customRule: { _, normalized in
            if isCodexActionRequiredTitle(normalized) {
                return .needsInput
            }
            if hasSpinnerPrefix(normalized) || normalized.contains("esc to interrupt") {
                return .working
            }
            return nil
        }
    )

    static let gemini = OmuxAIStatusTitleAdapter(
        adapterID: "gemini",
        label: "Gemini",
        identityKeywords: ["gemini"],
        rules: [
            Rule(state: .needsInput, keywords: ["action required", "approval", "permission", "needs input"], icons: ["\u{270B}"], allowsColdStart: true, requiresIdentityOrPrevious: false),
            Rule(state: .working, keywords: ["working", "thinking", "running"], icons: ["\u{2726}"], allowsColdStart: true, requiresIdentityOrPrevious: false),
            Rule(state: .idle, keywords: ["idle", "done", "finished", "ready"], icons: ["\u{25C7}"], allowsColdStart: true, requiresIdentityOrPrevious: false),
            Rule(state: .error, keywords: ["error", "failed"]),
        ],
        identityImpliesWorking: false,
        customRule: nil
    )

    static let claude = OmuxAIStatusTitleAdapter(
        adapterID: "claude",
        label: "Claude",
        identityKeywords: ["claude"],
        rules: [
            Rule(state: .needsInput, keywords: ["action required", "approval", "permission", "confirm", "waiting", "needs input"]),
            Rule(state: .working, keywords: ["working", "thinking", "reading", "editing", "writing", "running"]),
            Rule(state: .idle, keywords: ["idle", "done", "finished", "ready"]),
            Rule(state: .error, keywords: ["error", "failed"]),
        ],
        identityImpliesWorking: false,
        customRule: nil
    )

    static let copilot = OmuxAIStatusTitleAdapter(
        adapterID: "copilot",
        label: "Copilot",
        identityKeywords: ["copilot", "github copilot"],
        rules: [
            Rule(state: .needsInput, keywords: ["action required", "approval", "permission", "confirm", "waiting", "needs input"]),
            Rule(state: .working, keywords: ["working", "thinking", "running", "generating"]),
            Rule(state: .idle, keywords: ["idle", "done", "finished", "ready"]),
            Rule(state: .error, keywords: ["error", "failed"]),
        ],
        identityImpliesWorking: false,
        customRule: nil
    )

    private static func isCodexActionRequiredTitle(_ normalized: String) -> Bool {
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "action required" {
            return true
        }

        let strippedPrefix = trimmed.replacingOccurrences(
            of: #"^\[\s*[.!]\s*\]\s*"#,
            with: "",
            options: .regularExpression
        )
        return strippedPrefix == "action required" || strippedPrefix.hasPrefix("action required |")
    }

    private static func hasSpinnerPrefix(_ normalized: String) -> Bool {
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else {
            return false
        }
        return first.isAIStatusSpinnerGlyph
    }
}

private extension Character {
    var isAIStatusSpinnerGlyph: Bool {
        guard unicodeScalars.count == 1,
              let scalar = unicodeScalars.first
        else {
            return false
        }

        if (0x2800...0x28FF).contains(Int(scalar.value)) {
            return true
        }

        switch scalar {
        case "•", "●", "◦", "○",
             "◐", "◓", "◑", "◒",
             "◜", "◠", "◝", "◞", "◡", "◟":
            return true
        default:
            return false
        }
    }
}

private extension String {
    var emptyAsNil: String? {
        isEmpty ? nil : self
    }
}
