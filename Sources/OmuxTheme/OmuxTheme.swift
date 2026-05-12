import Foundation
import OmuxConfig

public enum ThemeToken: String, CaseIterable, Sendable {
    case backgroundCanvas = "bg.canvas"
    case backgroundSurface = "bg.surface"
    case backgroundElevated = "bg.elevated"
    case foregroundPrimary = "fg.primary"
    case foregroundSecondary = "fg.secondary"
    case foregroundMuted = "fg.muted"
    case borderSubtle = "border.subtle"
    case borderStrong = "border.strong"
    case accent = "accent"
    case cursor = "cursor"
    case cursorText = "cursor.text"
    case selectionBackground = "selection.bg"
    case selectionForeground = "selection.fg"
    case ansiBlack = "ansi.black"
    case ansiRed = "ansi.red"
    case ansiGreen = "ansi.green"
    case ansiYellow = "ansi.yellow"
    case ansiBlue = "ansi.blue"
    case ansiMagenta = "ansi.magenta"
    case ansiCyan = "ansi.cyan"
    case ansiWhite = "ansi.white"
    case ansiBrightBlack = "ansi.brightBlack"
    case ansiBrightRed = "ansi.brightRed"
    case ansiBrightGreen = "ansi.brightGreen"
    case ansiBrightYellow = "ansi.brightYellow"
    case ansiBrightBlue = "ansi.brightBlue"
    case ansiBrightMagenta = "ansi.brightMagenta"
    case ansiBrightCyan = "ansi.brightCyan"
    case ansiBrightWhite = "ansi.brightWhite"
}

public struct ThemeColor: Hashable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8
    public let alpha: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.hasPrefix("#") else {
            return nil
        }

        let digits = String(cleaned.dropFirst())
        let scanner = Scanner(string: digits)
        var value: UInt64 = 0
        guard scanner.scanHexInt64(&value) else {
            return nil
        }

        switch digits.count {
        case 6:
            self.init(
                red: UInt8((value >> 16) & 0xFF),
                green: UInt8((value >> 8) & 0xFF),
                blue: UInt8(value & 0xFF)
            )
        case 8:
            self.init(
                red: UInt8((value >> 24) & 0xFF),
                green: UInt8((value >> 16) & 0xFF),
                blue: UInt8((value >> 8) & 0xFF),
                alpha: UInt8(value & 0xFF)
            )
        default:
            return nil
        }
    }

    public var hexString: String {
        if alpha == 255 {
            return String(format: "#%02x%02x%02x", red, green, blue)
        }

        return String(format: "#%02x%02x%02x%02x", red, green, blue, alpha)
    }
}

public struct OmuxTheme: Equatable, Sendable {
    public let schema: Int
    public let name: String
    public let displayName: String
    public let tokens: [ThemeToken: ThemeColor]
    public let sourceURL: URL?

    public init(
        schema: Int,
        name: String,
        displayName: String,
        tokens: [ThemeToken: ThemeColor],
        sourceURL: URL? = nil
    ) {
        self.schema = schema
        self.name = name
        self.displayName = displayName
        self.tokens = tokens
        self.sourceURL = sourceURL
    }
}

public struct ResolvedThemeTokens: Equatable, Sendable {
    public let theme: OmuxTheme

    public init(theme: OmuxTheme) {
        self.theme = theme
    }

    public subscript(_ token: ThemeToken) -> ThemeColor {
        guard let color = theme.tokens[token] else {
            preconditionFailure("Missing required token: \(token.rawValue)")
        }
        return color
    }
}

public struct OmuxThemeLoadResult: Equatable, Sendable {
    public let theme: OmuxTheme?
    public let diagnostics: [OmuxConfigDiagnostic]

    public init(theme: OmuxTheme?, diagnostics: [OmuxConfigDiagnostic]) {
        self.theme = theme
        self.diagnostics = diagnostics
    }

    public var hasErrors: Bool {
        diagnostics.contains(where: { $0.severity.isError })
    }
}

public struct OmuxThemeRegistry {
    private static let bundledThemesBundleName = "OpenMUX_OmuxTheme.bundle"

    private let bundle: Bundle
    private let fileManager: FileManager
    private let userThemesDirectoryURL: URL

    public init(
        bundle: Bundle? = nil,
        fileManager: FileManager = .default,
        userThemesDirectoryURL: URL = OmuxConfigPaths.themesDirectoryURL
    ) {
        self.bundle = bundle ?? Self.packagedResourceBundle(fileManager: fileManager) ?? .module
        self.fileManager = fileManager
        self.userThemesDirectoryURL = userThemesDirectoryURL
    }

    static func packagedResourceBundle(
        fileManager: FileManager = .default,
        mainBundleURL: URL = Bundle.main.bundleURL,
        mainResourceURL: URL? = Bundle.main.resourceURL,
        mainExecutableURL: URL? = Bundle.main.executableURL
    ) -> Bundle? {
        let executableURLs = Self.executableResourceLookupURLs(from: mainExecutableURL)
        let executableCandidates = executableURLs.flatMap { executableURL in
            [
                executableURL
                    .deletingLastPathComponent()
                    .appendingPathComponent(Self.bundledThemesBundleName, isDirectory: true),
                executableURL
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .appendingPathComponent("Resources", isDirectory: true)
                    .appendingPathComponent(Self.bundledThemesBundleName, isDirectory: true),
            ]
        }

        let candidates = [
            mainResourceURL?.appendingPathComponent(Self.bundledThemesBundleName, isDirectory: true),
            mainBundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent(Self.bundledThemesBundleName, isDirectory: true),
            mainBundleURL.appendingPathComponent(Self.bundledThemesBundleName, isDirectory: true),
        ].compactMap { $0 } + executableCandidates

        for url in candidates where fileManager.fileExists(atPath: url.path) {
            if let bundle = Bundle(path: url.path) {
                return bundle
            }
        }

        return nil
    }

    private static func executableResourceLookupURLs(from executableURL: URL?) -> [URL] {
        guard let executableURL else {
            return []
        }

        let resolvedURL = executableURL.resolvingSymlinksInPath().standardizedFileURL
        let standardizedURL = executableURL.standardizedFileURL
        if resolvedURL == standardizedURL {
            return [standardizedURL]
        }
        return [standardizedURL, resolvedURL]
    }

    public func loadBuiltInThemes() -> ([OmuxTheme], [OmuxConfigDiagnostic]) {
        guard let urls = bundle.urls(forResourcesWithExtension: "toml", subdirectory: nil) else {
            return (
                [],
                [OmuxConfigDiagnostic(severity: .error, message: "Missing bundled theme resources.")]
            )
        }

        var themes: [OmuxTheme] = []
        var diagnostics: [OmuxConfigDiagnostic] = []
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where url.pathExtension == "toml" {
            let result = loadTheme(from: url)
            diagnostics.append(contentsOf: result.diagnostics)
            if let theme = result.theme {
                themes.append(theme)
            }
        }

        return (themes, diagnostics)
    }

    public func loadThemes() -> ([OmuxTheme], [OmuxConfigDiagnostic]) {
        let (builtIns, builtInDiagnostics) = loadBuiltInThemes()
        let (userThemes, userDiagnostics) = loadUserThemes()

        var byName = Dictionary(uniqueKeysWithValues: builtIns.map { ($0.name, $0) })
        var diagnostics = builtInDiagnostics + userDiagnostics

        for userTheme in userThemes {
            if byName[userTheme.name] != nil {
                diagnostics.append(
                    OmuxConfigDiagnostic(
                        severity: .warning,
                        message: "User theme '\(userTheme.name)' overrides a bundled theme.",
                        filePath: userTheme.sourceURL?.path
                    )
                )
            }
            byName[userTheme.name] = userTheme
        }

        return (byName.values.sorted(by: { $0.name < $1.name }), diagnostics)
    }

    public func loadTheme(named name: String) -> OmuxThemeLoadResult {
        let (themes, diagnostics) = loadThemes()
        let theme = themes.first(where: { $0.name == name })
        if let theme {
            return OmuxThemeLoadResult(theme: theme, diagnostics: diagnostics)
        }

        return OmuxThemeLoadResult(
            theme: nil,
            diagnostics: diagnostics + [
                OmuxConfigDiagnostic(
                    severity: .error,
                    message: "Unknown theme '\(name)'."
                ),
            ]
        )
    }

    private func loadUserThemes() -> ([OmuxTheme], [OmuxConfigDiagnostic]) {
        guard fileManager.fileExists(atPath: userThemesDirectoryURL.path) else {
            return ([], [])
        }

        guard let urls = try? fileManager.contentsOfDirectory(
            at: userThemesDirectoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return (
                [],
                [
                    OmuxConfigDiagnostic(
                        severity: .error,
                        message: "Unable to enumerate user themes directory.",
                        filePath: userThemesDirectoryURL.path
                    ),
                ]
            )
        }

        var themes: [OmuxTheme] = []
        var diagnostics: [OmuxConfigDiagnostic] = []
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where url.pathExtension == "toml" {
            let result = loadTheme(from: url)
            diagnostics.append(contentsOf: result.diagnostics)
            if let theme = result.theme {
                themes.append(theme)
            }
        }

        return (themes, diagnostics)
    }

    private func loadTheme(from url: URL) -> OmuxThemeLoadResult {
        let parseResult = OmuxTOMLParser.parse(fileAt: url)
        guard let document = parseResult.document else {
            return OmuxThemeLoadResult(theme: nil, diagnostics: parseResult.diagnostics)
        }

        let decodeResult = decode(document: document, sourceURL: url)
        return OmuxThemeLoadResult(theme: decodeResult.theme, diagnostics: parseResult.diagnostics + decodeResult.diagnostics)
    }

    private func decode(document: OmuxTOMLDocument, sourceURL: URL) -> OmuxThemeLoadResult {
        var diagnostics: [OmuxConfigDiagnostic] = []

        let allowedRootKeys: Set<String> = ["schema", "name", "displayName"]
        for entry in document.entries() where allowedRootKeys.contains(entry.key) == false {
            diagnostics.append(
                OmuxConfigDiagnostic(
                    severity: .warning,
                    message: "Unknown top-level theme key '\(entry.key)' will be ignored.",
                    filePath: sourceURL.path,
                    line: entry.line
                )
            )
        }

        let tables = Set(document.tableNames)
        if tables.contains("tokens") == false {
            diagnostics.append(
                OmuxConfigDiagnostic(
                    severity: .error,
                    message: "Theme file must contain a [tokens] table.",
                    filePath: sourceURL.path
                )
            )
        }

        for tableName in tables where tableName != "tokens" {
            diagnostics.append(
                OmuxConfigDiagnostic(
                    severity: .error,
                    message: "Unknown theme table [\(tableName)].",
                    filePath: sourceURL.path
                )
            )
        }

        if document.value(for: "extends") != nil {
            diagnostics.append(
                OmuxConfigDiagnostic(
                    severity: .error,
                    message: "Theme inheritance is not supported. Remove 'extends'.",
                    filePath: sourceURL.path,
                    line: document.line(for: "extends")
                )
            )
        }

        guard let schemaValue = document.value(for: "schema"), let schema = schemaValue.intValue else {
            diagnostics.append(
                OmuxConfigDiagnostic(
                    severity: .error,
                    message: "Theme file must declare integer 'schema = \(OmuxConfigSchemaVersion)'.",
                    filePath: sourceURL.path,
                    line: document.line(for: "schema")
                )
            )
            return OmuxThemeLoadResult(theme: nil, diagnostics: diagnostics)
        }

        guard schema == OmuxConfigSchemaVersion else {
            diagnostics.append(
                OmuxConfigDiagnostic(
                    severity: .error,
                    message: "Unsupported theme schema \(schema). This build supports schema \(OmuxConfigSchemaVersion).",
                    filePath: sourceURL.path,
                    line: document.line(for: "schema")
                )
            )
            return OmuxThemeLoadResult(theme: nil, diagnostics: diagnostics)
        }

        guard let name = document.value(for: "name")?.stringValue else {
            diagnostics.append(
                OmuxConfigDiagnostic(
                    severity: .error,
                    message: "Theme file must declare string 'name'.",
                    filePath: sourceURL.path,
                    line: document.line(for: "name")
                )
            )
            return OmuxThemeLoadResult(theme: nil, diagnostics: diagnostics)
        }

        guard let displayName = document.value(for: "displayName")?.stringValue else {
            diagnostics.append(
                OmuxConfigDiagnostic(
                    severity: .error,
                    message: "Theme file must declare string 'displayName'.",
                    filePath: sourceURL.path,
                    line: document.line(for: "displayName")
                )
            )
            return OmuxThemeLoadResult(theme: nil, diagnostics: diagnostics)
        }

        var tokens: [ThemeToken: ThemeColor] = [:]
        for entry in document.entries(in: "tokens") {
            guard let token = ThemeToken(rawValue: entry.key) else {
                diagnostics.append(
                    OmuxConfigDiagnostic(
                        severity: .error,
                        message: "Unknown theme token '\(entry.key)'.",
                        filePath: sourceURL.path,
                        line: entry.line
                    )
                )
                continue
            }

            guard let rawValue = entry.value.stringValue, let color = ThemeColor(hex: rawValue) else {
                diagnostics.append(
                    OmuxConfigDiagnostic(
                        severity: .error,
                        message: "Theme token '\(entry.key)' must be a hex color string.",
                        filePath: sourceURL.path,
                        line: entry.line
                    )
                )
                continue
            }

            tokens[token] = color
        }

        let missing = ThemeToken.allCases.filter { tokens[$0] == nil }
        if missing.isEmpty == false {
            diagnostics.append(
                OmuxConfigDiagnostic(
                    severity: .error,
                    message: "Theme is missing required tokens: \(missing.map(\.rawValue).joined(separator: ", ")).",
                    filePath: sourceURL.path
                )
            )
        }

        guard diagnostics.contains(where: { $0.severity.isError }) == false else {
            return OmuxThemeLoadResult(theme: nil, diagnostics: diagnostics)
        }

        return OmuxThemeLoadResult(
            theme: OmuxTheme(
                schema: schema,
                name: name,
                displayName: displayName,
                tokens: tokens,
                sourceURL: sourceURL
            ),
            diagnostics: diagnostics
        )
    }
}
