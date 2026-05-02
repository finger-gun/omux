import Foundation

public let OmuxConfigSchemaVersion = 1

public enum OmuxConfigDiagnosticSeverity: String, Sendable {
    case warning
    case error

    public var isError: Bool {
        self == .error
    }
}

public struct OmuxConfigDiagnostic: Error, Equatable, Sendable {
    public let severity: OmuxConfigDiagnosticSeverity
    public let message: String
    public let filePath: String?
    public let line: Int?

    public init(
        severity: OmuxConfigDiagnosticSeverity,
        message: String,
        filePath: String? = nil,
        line: Int? = nil
    ) {
        self.severity = severity
        self.message = message
        self.filePath = filePath
        self.line = line
    }
}

public enum OmuxTOMLValue: Equatable, Sendable {
    case string(String)
    case integer(Int)
    case double(Double)
    case bool(Bool)
    case array([OmuxTOMLValue])

    public var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    public var intValue: Int? {
        guard case .integer(let value) = self else { return nil }
        return value
    }

    public var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    public var doubleValue: Double? {
        switch self {
        case .double(let value):
            return value
        case .integer(let value):
            return Double(value)
        default:
            return nil
        }
    }

    public func serialized() -> String {
        switch self {
        case .string(let value):
            return "\"\(Self.escape(value))\""
        case .integer(let value):
            return String(value)
        case .double(let value):
            return String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .array(let values):
            return "[\(values.map { $0.serialized() }.joined(separator: ", "))]"
        }
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}

public struct OmuxTOMLEntry: Equatable, Sendable {
    public let key: String
    public let value: OmuxTOMLValue
    public let line: Int

    public init(key: String, value: OmuxTOMLValue, line: Int) {
        self.key = key
        self.value = value
        self.line = line
    }
}

public struct OmuxTOMLDocument: Equatable, Sendable {
    private let rootEntries: [OmuxTOMLEntry]
    private let tableEntries: [String: [OmuxTOMLEntry]]

    public init(
        rootEntries: [OmuxTOMLEntry] = [],
        tableEntries: [String: [OmuxTOMLEntry]] = [:]
    ) {
        self.rootEntries = rootEntries
        self.tableEntries = tableEntries
    }

    public var tableNames: [String] {
        tableEntries.keys.sorted()
    }

    public func entries(in tableName: String? = nil) -> [OmuxTOMLEntry] {
        if let tableName {
            return tableEntries[tableName] ?? []
        }

        return rootEntries
    }

    public func value(in tableName: String? = nil, for key: String) -> OmuxTOMLValue? {
        entries(in: tableName).last(where: { $0.key == key })?.value
    }

    public func value(for key: String) -> OmuxTOMLValue? {
        value(in: nil, for: key)
    }

    public func line(in tableName: String? = nil, for key: String) -> Int? {
        entries(in: tableName).last(where: { $0.key == key })?.line
    }

    public func line(for key: String) -> Int? {
        line(in: nil, for: key)
    }
}

public struct OmuxConfigTheme: Equatable, Sendable {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

public struct OmuxConfigTerminal: Equatable, Sendable {
    public enum OptionAsAlt: Equatable, Sendable {
        case disabled
        case both
        case left
        case right

        public var ghosttyValue: String {
            switch self {
            case .disabled:
                return "false"
            case .both:
                return "true"
            case .left:
                return "left"
            case .right:
                return "right"
            }
        }
    }

    public let fontFamily: String?
    public let fontSize: Int?
    public let scrollbackLines: Int?
    public let optionAsAlt: OptionAsAlt?

    public init(
        fontFamily: String? = nil,
        fontSize: Int? = nil,
        scrollbackLines: Int? = nil,
        optionAsAlt: OptionAsAlt? = nil
    ) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.scrollbackLines = scrollbackLines
        self.optionAsAlt = optionAsAlt
    }
}

public struct OmuxGhosttyConfigEntry: Equatable, Sendable {
    public let key: String
    public let value: OmuxTOMLValue
    public let line: Int?

    public init(key: String, value: OmuxTOMLValue, line: Int? = nil) {
        self.key = key
        self.value = value
        self.line = line
    }
}

public struct OmuxConfig: Equatable, Sendable {
    public let schema: Int
    public let theme: OmuxConfigTheme
    public let terminal: OmuxConfigTerminal
    public let ghostty: [OmuxGhosttyConfigEntry]
    public let sourceURL: URL?

    public init(
        schema: Int,
        theme: OmuxConfigTheme,
        terminal: OmuxConfigTerminal,
        ghostty: [OmuxGhosttyConfigEntry],
        sourceURL: URL? = nil
    ) {
        self.schema = schema
        self.theme = theme
        self.terminal = terminal
        self.ghostty = ghostty
        self.sourceURL = sourceURL
    }

    public static let defaults = OmuxConfig(
        schema: OmuxConfigSchemaVersion,
        theme: OmuxConfigTheme(name: "monokai-soda"),
        terminal: OmuxConfigTerminal(),
        ghostty: []
    )
}

public struct OmuxConfigLoadResult: Equatable, Sendable {
    public let config: OmuxConfig
    public let diagnostics: [OmuxConfigDiagnostic]

    public init(config: OmuxConfig, diagnostics: [OmuxConfigDiagnostic]) {
        self.config = config
        self.diagnostics = diagnostics
    }

    public var hasErrors: Bool {
        diagnostics.contains(where: { $0.severity.isError })
    }
}

public enum OmuxConfigPaths {
    public static var homeDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    public static var baseDirectoryURL: URL {
        if let override = ProcessInfo.processInfo.environment["OMUX_HOME"], override.isEmpty == false {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return homeDirectoryURL.appendingPathComponent(".omux", isDirectory: true)
    }

    public static var configFileURL: URL {
        baseDirectoryURL.appendingPathComponent("config.toml")
    }

    public static var themesDirectoryURL: URL {
        baseDirectoryURL.appendingPathComponent("themes", isDirectory: true)
    }

    public static var hooksDirectoryURL: URL {
        baseDirectoryURL.appendingPathComponent("hooks", isDirectory: true)
    }

    public static var generatedDirectoryURL: URL {
        baseDirectoryURL.appendingPathComponent("generated", isDirectory: true)
    }

    public static var generatedGhosttyDirectoryURL: URL {
        generatedDirectoryURL.appendingPathComponent("ghostty", isDirectory: true)
    }
}

public enum OmuxConfigTemplate {
    public static func starter(themeName: String = OmuxConfig.defaults.theme.name) -> String {
        """
        schema = \(OmuxConfigSchemaVersion)

        [theme]
        name = "\(themeName)"

        [terminal]
        # font_family = "Berkeley Mono"
        # font_size = 13
        # scrollback_lines = 100000
        # option_as_alt = "right"

        [ghostty]
        # "copy-on-select" = false
        """
    }
}

public enum OmuxTOMLParser {
    public static func parse(fileAt url: URL) -> (document: OmuxTOMLDocument?, diagnostics: [OmuxConfigDiagnostic]) {
        do {
            let contents = try String(contentsOf: url, encoding: .utf8)
            return parse(contents: contents, sourceURL: url)
        } catch {
            return (
                nil,
                [
                    OmuxConfigDiagnostic(
                        severity: .error,
                        message: "Unable to read TOML file: \(error.localizedDescription)",
                        filePath: url.path
                    ),
                ]
            )
        }
    }

    public static func parse(
        contents: String,
        sourceURL: URL? = nil
    ) -> (document: OmuxTOMLDocument?, diagnostics: [OmuxConfigDiagnostic]) {
        var diagnostics: [OmuxConfigDiagnostic] = []
        var rootEntries: [OmuxTOMLEntry] = []
        var tableEntries: [String: [OmuxTOMLEntry]] = [:]
        var currentTable: String?

        for (index, rawLine) in contents.components(separatedBy: .newlines).enumerated() {
            let lineNumber = index + 1
            let trimmed = stripComment(from: rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else {
                continue
            }

            if trimmed.hasPrefix("[") {
                guard trimmed.hasSuffix("]") else {
                    diagnostics.append(
                        diagnostic(
                            message: "Unterminated table declaration.",
                            sourceURL: sourceURL,
                            line: lineNumber
                        )
                    )
                    continue
                }

                let tableName = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                guard tableName.isEmpty == false else {
                    diagnostics.append(
                        diagnostic(
                            message: "Empty table declaration is not allowed.",
                            sourceURL: sourceURL,
                            line: lineNumber
                        )
                    )
                    continue
                }

                currentTable = tableName
                if tableEntries[tableName] == nil {
                    tableEntries[tableName] = []
                }
                continue
            }

            guard let separatorIndex = separatorIndex(in: trimmed) else {
                diagnostics.append(
                    diagnostic(
                        message: "Expected key/value assignment.",
                        sourceURL: sourceURL,
                        line: lineNumber
                    )
                )
                continue
            }

            let rawKey = String(trimmed[..<separatorIndex]).trimmingCharacters(in: .whitespaces)
            let rawValue = String(trimmed[trimmed.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespaces)

            guard let key = parseKey(rawKey) else {
                diagnostics.append(
                    diagnostic(
                        message: "Invalid TOML key '\(rawKey)'.",
                        sourceURL: sourceURL,
                        line: lineNumber
                    )
                )
                continue
            }

            guard let value = parseValue(rawValue) else {
                diagnostics.append(
                    diagnostic(
                        message: "Unsupported TOML value for key '\(key)'.",
                        sourceURL: sourceURL,
                        line: lineNumber
                    )
                )
                continue
            }

            let entry = OmuxTOMLEntry(key: key, value: value, line: lineNumber)
            if let currentTable {
                tableEntries[currentTable, default: []].append(entry)
            } else {
                rootEntries.append(entry)
            }
        }

        guard diagnostics.isEmpty else {
            return (nil, diagnostics)
        }

        return (OmuxTOMLDocument(rootEntries: rootEntries, tableEntries: tableEntries), [])
    }

    private static func diagnostic(message: String, sourceURL: URL?, line: Int) -> OmuxConfigDiagnostic {
        OmuxConfigDiagnostic(
            severity: .error,
            message: message,
            filePath: sourceURL?.path,
            line: line
        )
    }

    private static func stripComment(from line: String) -> String {
        var isInsideString = false
        var bracketDepth = 0
        var previous: Character?

        for (offset, character) in line.enumerated() {
            if character == "\"" && previous != "\\" {
                isInsideString.toggle()
            } else if isInsideString == false {
                if character == "[" {
                    bracketDepth += 1
                } else if character == "]" {
                    bracketDepth = max(0, bracketDepth - 1)
                } else if character == "#" && bracketDepth == 0 {
                    return String(line.prefix(offset))
                }
            }
            previous = character
        }

        return line
    }

    private static func separatorIndex(in line: String) -> String.Index? {
        var isInsideString = false
        var bracketDepth = 0
        var previous: Character?

        for index in line.indices {
            let character = line[index]
            if character == "\"" && previous != "\\" {
                isInsideString.toggle()
            } else if isInsideString == false {
                if character == "[" {
                    bracketDepth += 1
                } else if character == "]" {
                    bracketDepth = max(0, bracketDepth - 1)
                } else if character == "=" && bracketDepth == 0 {
                    return index
                }
            }
            previous = character
        }

        return nil
    }

    private static func parseKey(_ rawKey: String) -> String? {
        if rawKey.hasPrefix("\""), rawKey.hasSuffix("\"") {
            return parseQuotedString(rawKey)
        }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        guard rawKey.unicodeScalars.allSatisfy(allowed.contains) else {
            return nil
        }

        return rawKey
    }

    private static func parseValue(_ rawValue: String) -> OmuxTOMLValue? {
        if rawValue.hasPrefix("\""), rawValue.hasSuffix("\"") {
            return parseQuotedString(rawValue).map(OmuxTOMLValue.string)
        }

        if rawValue == "true" {
            return .bool(true)
        }

        if rawValue == "false" {
            return .bool(false)
        }

        if rawValue.hasPrefix("["), rawValue.hasSuffix("]") {
            let inner = String(rawValue.dropFirst().dropLast())
            if inner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .array([])
            }

            let parts = splitArray(inner)
            var values: [OmuxTOMLValue] = []
            values.reserveCapacity(parts.count)
            for part in parts {
                guard let value = parseValue(part.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    return nil
                }
                values.append(value)
            }
            return .array(values)
        }

        if rawValue.contains("."), let value = Double(rawValue) {
            return .double(value)
        }

        if let value = Int(rawValue) {
            return .integer(value)
        }

        return nil
    }

    private static func splitArray(_ value: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var isInsideString = false
        var bracketDepth = 0
        var previous: Character?

        for character in value {
            if character == "\"" && previous != "\\" {
                isInsideString.toggle()
            } else if isInsideString == false {
                if character == "[" {
                    bracketDepth += 1
                } else if character == "]" {
                    bracketDepth = max(0, bracketDepth - 1)
                } else if character == "," && bracketDepth == 0 {
                    parts.append(current)
                    current = ""
                    previous = character
                    continue
                }
            }

            current.append(character)
            previous = character
        }

        if current.isEmpty == false {
            parts.append(current)
        }

        return parts
    }

    private static func parseQuotedString(_ rawValue: String) -> String? {
        guard rawValue.count >= 2 else {
            return nil
        }

        let inner = rawValue.dropFirst().dropLast()
        var result = ""
        var escaping = false

        for character in inner {
            if escaping {
                switch character {
                case "\"":
                    result.append("\"")
                case "\\":
                    result.append("\\")
                case "n":
                    result.append("\n")
                case "t":
                    result.append("\t")
                case "r":
                    result.append("\r")
                default:
                    result.append(character)
                }
                escaping = false
                continue
            }

            if character == "\\" {
                escaping = true
            } else {
                result.append(character)
            }
        }

        guard escaping == false else {
            return nil
        }

        return result
    }
}

public struct OmuxConfigLoader {
    private let fileManager: FileManager
    private let configURL: URL

    public init(
        fileManager: FileManager = .default,
        configURL: URL = OmuxConfigPaths.configFileURL
    ) {
        self.fileManager = fileManager
        self.configURL = configURL
    }

    public func load(url: URL? = nil) -> OmuxConfigLoadResult {
        let url = url ?? configURL
        guard fileManager.fileExists(atPath: url.path) else {
            return OmuxConfigLoadResult(config: OmuxConfig.defaults, diagnostics: [])
        }

        let parseResult = OmuxTOMLParser.parse(fileAt: url)
        guard let document = parseResult.document else {
            return OmuxConfigLoadResult(config: OmuxConfig.defaults, diagnostics: parseResult.diagnostics)
        }

        let decodeResult = decode(document: document, sourceURL: url)
        return OmuxConfigLoadResult(config: decodeResult.config, diagnostics: parseResult.diagnostics + decodeResult.diagnostics)
    }

    private func decode(document: OmuxTOMLDocument, sourceURL: URL) -> OmuxConfigLoadResult {
        var diagnostics: [OmuxConfigDiagnostic] = []

        let allowedRootKeys: Set<String> = ["schema"]
        for entry in document.entries() where allowedRootKeys.contains(entry.key) == false {
            diagnostics.append(
                OmuxConfigDiagnostic(
                    severity: .error,
                    message: "Unknown top-level config key '\(entry.key)'.",
                    filePath: sourceURL.path,
                    line: entry.line
                )
            )
        }

        let allowedTables: Set<String> = ["theme", "terminal", "ghostty"]
        for tableName in document.tableNames where allowedTables.contains(tableName) == false {
            diagnostics.append(
                OmuxConfigDiagnostic(
                    severity: .error,
                    message: "Unknown config table [\(tableName)].",
                    filePath: sourceURL.path
                )
            )
        }

        guard let schemaValue = document.value(for: "schema") else {
            diagnostics.append(
                OmuxConfigDiagnostic(
                    severity: .error,
                    message: "Missing required schema field. Add 'schema = \(OmuxConfigSchemaVersion)'.",
                    filePath: sourceURL.path
                )
            )
            return OmuxConfigLoadResult(config: OmuxConfig.defaults, diagnostics: diagnostics)
        }

        guard let schema = schemaValue.intValue else {
            diagnostics.append(
                OmuxConfigDiagnostic(
                    severity: .error,
                    message: "Schema must be an integer.",
                    filePath: sourceURL.path,
                    line: document.line(for: "schema")
                )
            )
            return OmuxConfigLoadResult(config: OmuxConfig.defaults, diagnostics: diagnostics)
        }

        guard schema == OmuxConfigSchemaVersion else {
            diagnostics.append(
                OmuxConfigDiagnostic(
                    severity: .error,
                    message: "Unsupported config schema \(schema). This build supports schema \(OmuxConfigSchemaVersion).",
                    filePath: sourceURL.path,
                    line: document.line(for: "schema")
                )
            )
            return OmuxConfigLoadResult(config: OmuxConfig.defaults, diagnostics: diagnostics)
        }

        var config = OmuxConfig.defaults

        if let themeNameValue = document.value(in: "theme", for: "name") {
            guard let themeName = themeNameValue.stringValue else {
                diagnostics.append(
                    OmuxConfigDiagnostic(
                        severity: .error,
                        message: "theme.name must be a string.",
                        filePath: sourceURL.path,
                        line: document.line(in: "theme", for: "name")
                    )
                )
                return OmuxConfigLoadResult(config: OmuxConfig.defaults, diagnostics: diagnostics)
            }
            config = OmuxConfig(
                schema: config.schema,
                theme: OmuxConfigTheme(name: themeName),
                terminal: config.terminal,
                ghostty: config.ghostty,
                sourceURL: sourceURL
            )
        } else {
            config = OmuxConfig(
                schema: config.schema,
                theme: config.theme,
                terminal: config.terminal,
                ghostty: config.ghostty,
                sourceURL: sourceURL
            )
        }

        let themeAllowedKeys: Set<String> = ["name"]
        for entry in document.entries(in: "theme") where themeAllowedKeys.contains(entry.key) == false {
            diagnostics.append(
                OmuxConfigDiagnostic(
                    severity: .error,
                    message: "Unknown [theme] key '\(entry.key)'.",
                    filePath: sourceURL.path,
                    line: entry.line
                )
            )
        }

        let terminalAllowedKeys: Set<String> = ["font_family", "font_size", "scrollback_lines", "option_as_alt"]
        var fontFamily = config.terminal.fontFamily
        var fontSize = config.terminal.fontSize
        var scrollbackLines = config.terminal.scrollbackLines
        var optionAsAlt = config.terminal.optionAsAlt

        for entry in document.entries(in: "terminal") {
            guard terminalAllowedKeys.contains(entry.key) else {
                diagnostics.append(
                    OmuxConfigDiagnostic(
                        severity: .error,
                        message: "Unknown [terminal] key '\(entry.key)'.",
                        filePath: sourceURL.path,
                        line: entry.line
                    )
                )
                continue
            }

            switch entry.key {
            case "font_family":
                guard let value = entry.value.stringValue else {
                    diagnostics.append(
                        OmuxConfigDiagnostic(
                            severity: .error,
                            message: "terminal.font_family must be a string.",
                            filePath: sourceURL.path,
                            line: entry.line
                        )
                    )
                    continue
                }
                fontFamily = value
            case "font_size":
                guard let value = entry.value.intValue else {
                    diagnostics.append(
                        OmuxConfigDiagnostic(
                            severity: .error,
                            message: "terminal.font_size must be an integer.",
                            filePath: sourceURL.path,
                            line: entry.line
                        )
                    )
                    continue
                }
                fontSize = value
            case "scrollback_lines":
                guard let value = entry.value.intValue else {
                    diagnostics.append(
                        OmuxConfigDiagnostic(
                            severity: .error,
                            message: "terminal.scrollback_lines must be an integer.",
                            filePath: sourceURL.path,
                            line: entry.line
                        )
                    )
                    continue
                }
                scrollbackLines = value
            case "option_as_alt":
                switch entry.value {
                case .bool(false):
                    optionAsAlt = .disabled
                case .bool(true):
                    optionAsAlt = .both
                case .string("left"):
                    optionAsAlt = .left
                case .string("right"):
                    optionAsAlt = .right
                default:
                    diagnostics.append(
                        OmuxConfigDiagnostic(
                            severity: .error,
                            message: "terminal.option_as_alt must be true, false, \"left\", or \"right\".",
                            filePath: sourceURL.path,
                            line: entry.line
                        )
                    )
                    continue
                }
            default:
                break
            }
        }

        let ghosttyEntries = document.entries(in: "ghostty").map {
            OmuxGhosttyConfigEntry(key: $0.key, value: $0.value, line: $0.line)
        }

        config = OmuxConfig(
            schema: schema,
            theme: config.theme,
            terminal: OmuxConfigTerminal(
                fontFamily: fontFamily,
                fontSize: fontSize,
                scrollbackLines: scrollbackLines,
                optionAsAlt: optionAsAlt
            ),
            ghostty: ghosttyEntries,
            sourceURL: sourceURL
        )

        return OmuxConfigLoadResult(config: config, diagnostics: diagnostics)
    }
}
