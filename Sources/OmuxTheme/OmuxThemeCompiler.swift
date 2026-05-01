import CryptoKit
import Foundation
import OmuxConfig

public struct OmuxThemeCompilerOutput: Equatable, Sendable {
    public let theme: OmuxTheme
    public let hash: String
    public let contents: String
    public let fileURL: URL
    public let diagnostics: [OmuxConfigDiagnostic]

    public init(
        theme: OmuxTheme,
        hash: String,
        contents: String,
        fileURL: URL,
        diagnostics: [OmuxConfigDiagnostic]
    ) {
        self.theme = theme
        self.hash = hash
        self.contents = contents
        self.fileURL = fileURL
        self.diagnostics = diagnostics
    }
}

public enum OmuxManagedGhosttyKey {
    public static let all: Set<String> = [
        "background",
        "foreground",
        "cursor-color",
        "cursor-text",
        "selection-background",
        "selection-foreground",
        "palette",
        "font-family",
        "font-size",
        "scrollback-limit",
        "window-padding-x",
        "window-padding-y",
    ]
}

public struct OmuxThemeCompiler {
    private let fileManager: FileManager
    private let buildVersion: String
    private let retentionInterval: TimeInterval
    private let maxDirectoryBytes: Int
    private let generatedGhosttyDirectoryURL: URL

    public init(
        fileManager: FileManager = .default,
        buildVersion: String = OmuxBuildVersion.current,
        retentionInterval: TimeInterval = 60 * 60 * 24 * 14,
        maxDirectoryBytes: Int = 1_048_576,
        generatedGhosttyDirectoryURL: URL = OmuxConfigPaths.generatedGhosttyDirectoryURL
    ) {
        self.fileManager = fileManager
        self.buildVersion = buildVersion
        self.retentionInterval = retentionInterval
        self.maxDirectoryBytes = maxDirectoryBytes
        self.generatedGhosttyDirectoryURL = generatedGhosttyDirectoryURL
    }

    public func compile(theme: OmuxTheme, config: OmuxConfig) -> OmuxThemeCompilerOutput {
        let resolved = ResolvedThemeTokens(theme: theme)
        let passThroughEntries = config.ghostty.sorted(by: {
            if $0.key == $1.key {
                return ($0.line ?? 0) < ($1.line ?? 0)
            }
            return $0.key < $1.key
        })

        let managedEntries = ghosttyEntries(resolvedTokens: resolved, config: config)
        let diagnostics = passThroughEntries.compactMap { entry -> OmuxConfigDiagnostic? in
            guard OmuxManagedGhosttyKey.all.contains(entry.key) else {
                return nil
            }

            return OmuxConfigDiagnostic(
                severity: .warning,
                message: "Ghostty key '\(entry.key)' is managed by OpenMUX and will be overridden.",
                filePath: config.sourceURL?.path,
                line: entry.line
            )
        }

        let hash = compiledHash(
            schema: config.schema,
            tokens: ThemeToken.allCases.compactMap { token in
                theme.tokens[token].map { "\(token.rawValue)=\($0.hexString)" }
            },
            passThrough: passThroughEntries.map { "\($0.key)=\($0.value.serialized())" },
            managed: managedEntries.map { "\($0.0)=\($0.1)" }
        )

        let fileURL = generatedGhosttyDirectoryURL.appendingPathComponent("config-\(hash)")
        let contents = render(
            hash: hash,
            theme: theme,
            config: config,
            passThroughEntries: passThroughEntries,
            managedEntries: managedEntries
        )

        return OmuxThemeCompilerOutput(
            theme: theme,
            hash: hash,
            contents: contents,
            fileURL: fileURL,
            diagnostics: diagnostics
        )
    }

    @discardableResult
    public func write(output: OmuxThemeCompilerOutput) throws -> URL {
        try fileManager.createDirectory(at: generatedGhosttyDirectoryURL, withIntermediateDirectories: true)
        let temporaryURL = output.fileURL.appendingPathExtension("tmp")
        try output.contents.write(to: temporaryURL, atomically: true, encoding: .utf8)
        if fileManager.fileExists(atPath: output.fileURL.path) {
            try fileManager.removeItem(at: output.fileURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: output.fileURL)
        return output.fileURL
    }

    public func garbageCollect(activeFileURL: URL?) {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: generatedGhosttyDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let now = Date()
        var survivingURLs: [URL] = []
        for url in urls {
            if url.standardizedFileURL.path == activeFileURL?.standardizedFileURL.path {
                survivingURLs.append(url)
                continue
            }

            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            let age = values?.contentModificationDate.map { now.timeIntervalSince($0) } ?? .infinity
            if age >= retentionInterval || belongsToDifferentBuild(url: url) {
                try? fileManager.removeItem(at: url)
            } else {
                survivingURLs.append(url)
            }
        }

        trimToMaximumDirectorySize(urls: survivingURLs, activeFileURL: activeFileURL)
    }

    private func ghosttyEntries(
        resolvedTokens: ResolvedThemeTokens,
        config: OmuxConfig
    ) -> [(String, String)] {
        var entries: [(String, String)] = [
            ("background", resolvedTokens[.backgroundCanvas].hexString),
            ("foreground", resolvedTokens[.foregroundPrimary].hexString),
            ("cursor-color", resolvedTokens[.cursor].hexString),
            ("cursor-text", resolvedTokens[.cursorText].hexString),
            ("selection-background", resolvedTokens[.selectionBackground].hexString),
            ("selection-foreground", resolvedTokens[.selectionForeground].hexString),
            ("window-padding-x", "6"),
            ("window-padding-y", "6"),
        ]

        let paletteTokens: [ThemeToken] = [
            .ansiBlack, .ansiRed, .ansiGreen, .ansiYellow,
            .ansiBlue, .ansiMagenta, .ansiCyan, .ansiWhite,
            .ansiBrightBlack, .ansiBrightRed, .ansiBrightGreen, .ansiBrightYellow,
            .ansiBrightBlue, .ansiBrightMagenta, .ansiBrightCyan, .ansiBrightWhite,
        ]

        for (index, token) in paletteTokens.enumerated() {
            entries.append(("palette", "\(index)=\(resolvedTokens[token].hexString)"))
        }

        if let fontFamily = config.terminal.fontFamily {
            entries.append(("font-family", "\"\(fontFamily)\""))
        }

        if let fontSize = config.terminal.fontSize {
            entries.append(("font-size", String(fontSize)))
        }

        if let scrollbackLines = config.terminal.scrollbackLines {
            entries.append(("scrollback-limit", String(scrollbackLines)))
        }

        if let optionAsAlt = config.terminal.optionAsAlt {
            entries.append(("macos-option-as-alt", optionAsAlt.ghosttyValue))
        }

        return entries
    }

    private func render(
        hash: String,
        theme: OmuxTheme,
        config: OmuxConfig,
        passThroughEntries: [OmuxGhosttyConfigEntry],
        managedEntries: [(String, String)]
    ) -> String {
        var lines: [String] = [
            "# OpenMUX managed file. Do not edit directly.",
            "# source-config: \(config.sourceURL?.path ?? OmuxConfigPaths.configFileURL.path)",
            "# theme: \(theme.name)",
            "# openmux-version: \(buildVersion)",
            "# hash: \(hash)",
            "#",
            "# === [ghostty] pass-through ===",
        ]

        if passThroughEntries.isEmpty {
            lines.append("# (none)")
        } else {
            lines.append(contentsOf: passThroughEntries.map { "\($0.key) = \($0.value.serialized())" })
        }

        lines.append("")
        lines.append("# === OpenMUX-managed ===")
        lines.append(contentsOf: managedEntries.map { "\($0.0) = \($0.1)" })
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private func compiledHash(
        schema: Int,
        tokens: [String],
        passThrough: [String],
        managed: [String]
    ) -> String {
        let canonical = ([String(schema), buildVersion] + tokens + passThrough + managed)
            .joined(separator: "\n")
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined().prefix(16).description
    }

    private func belongsToDifferentBuild(url: URL) -> Bool {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return false
        }

        guard let versionLine = contents.split(separator: "\n").first(where: { $0.hasPrefix("# openmux-version: ") }) else {
            return false
        }

        let version = versionLine.replacingOccurrences(of: "# openmux-version: ", with: "")
        return version != buildVersion
    }

    private func trimToMaximumDirectorySize(urls: [URL], activeFileURL: URL?) {
        guard maxDirectoryBytes > 0 else {
            return
        }

        let activePath = activeFileURL?.standardizedFileURL.path
        let keyedValues = urls.compactMap { url -> (url: URL, size: Int, modified: Date)? in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = values?.fileSize ?? 0
            let modified = values?.contentModificationDate ?? .distantPast
            return (url, size, modified)
        }

        var totalBytes = keyedValues.reduce(0) { $0 + $1.size }
        guard totalBytes > maxDirectoryBytes else {
            return
        }

        let removable = keyedValues
            .filter { $0.url.standardizedFileURL.path != activePath }
            .sorted(by: { $0.modified < $1.modified })

        for entry in removable where totalBytes > maxDirectoryBytes {
            try? fileManager.removeItem(at: entry.url)
            totalBytes -= entry.size
        }
    }
}

public enum OmuxBuildVersion {
    public static var current: String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String, version.isEmpty == false {
            return version
        }

        return "dev"
    }
}
