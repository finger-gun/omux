import Foundation
import Testing
@testable import OmuxTheme

struct OmuxThemeTests {
    @Test
    func builtInThemesLoadWithoutErrors() {
        let registry = OmuxThemeRegistry()
        let (themes, diagnostics) = registry.loadBuiltInThemes()

        #expect(diagnostics.contains(where: { $0.severity.isError }) == false)
        #expect(Set(themes.map(\.name)) == Set([
            "atom-one-dark",
            "atom-one-light",
            "ayu",
            "ayu-light",
            "ayu-mirage",
            "carbonfox",
            "catppuccin",
            "catppuccin-frappe",
            "catppuccin-macchiato",
            "catppuccin-mocha",
            "cobalt2",
            "doom-one",
            "dracula",
            "duskfox",
            "everforest-dark",
            "fairyfloss",
            "firewatch",
            "flexoki-dark",
            "github-dark",
            "github-dark-dimmed",
            "github-dark-high-contrast",
            "github-light",
            "gruvbox",
            "gruvbox-dark-hard",
            "gruvbox-light-hard",
            "gruvbox-material-dark",
            "horizon",
            "kanagawa-wave",
            "material-darker",
            "material-ocean",
            "monokai-pro",
            "monokai-soda",
            "nightfox",
            "nord",
            "one-dark",
            "one-half-dark",
            "one-half-light",
            "onenord",
            "rose-pine",
            "snazzy",
            "solarized-dark",
            "solarized-light",
            "synthwave",
            "tokyo-night-storm",
            "tokyonight-moon",
            "tomorrow-night-eighties",
            "vesper",
            "wez",
        ]))
        #expect(themes.allSatisfy { $0.tokens[.backgroundSurface] == $0.tokens[.backgroundCanvas] })
    }

    @Test
    func importedBuiltInThemeLoadsWithExpectedTokens() {
        let result = OmuxThemeRegistry().loadTheme(named: "tokyo-night-storm")

        #expect(result.hasErrors == false)
        #expect(result.theme?.displayName == "Tokyo Night Storm")
        #expect(result.theme?.tokens[.backgroundCanvas]?.hexString == "#24283b")
        #expect(result.theme?.tokens[.foregroundPrimary]?.hexString == "#c0caf5")
        #expect(result.theme?.tokens[.ansiBlue]?.hexString == "#7aa2f7")
        #expect(result.theme?.tokens[.accent]?.hexString == "#7aa2f7")
    }

    @Test
    func packagedAppResourceBundleLoadsFromContentsResources() throws {
        let root = try temporaryHome()
        defer { cleanup(root) }

        let appURL = root.appendingPathComponent("OpenMUX.app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        let executableURL = contentsURL.appendingPathComponent("MacOS/OpenMUXApp", isDirectory: false)
        let themeBundleURL = resourcesURL.appendingPathComponent("OpenMUX_OmuxTheme.bundle", isDirectory: true)

        try FileManager.default.createDirectory(at: themeBundleURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: executableURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: executableURL)

        let bundle = OmuxThemeRegistry.packagedResourceBundle(
            mainBundleURL: appURL,
            mainResourceURL: resourcesURL,
            mainExecutableURL: executableURL
        )

        #expect(bundle?.bundleURL == themeBundleURL)
    }

    @Test
    func symlinkedCLIResourceBundleLoadsFromAppContentsResources() throws {
        let root = try temporaryHome()
        defer { cleanup(root) }

        let appURL = root.appendingPathComponent("OpenMUX.app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        let executableURL = contentsURL.appendingPathComponent("MacOS/omux", isDirectory: false)
        let symlinkURL = root
            .appendingPathComponent(".local/bin", isDirectory: true)
            .appendingPathComponent("omux", isDirectory: false)
        let themeBundleURL = resourcesURL.appendingPathComponent("OpenMUX_OmuxTheme.bundle", isDirectory: true)

        try FileManager.default.createDirectory(at: themeBundleURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: executableURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: symlinkURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: executableURL)
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: executableURL)

        let bundle = OmuxThemeRegistry.packagedResourceBundle(
            mainBundleURL: symlinkURL.deletingLastPathComponent(),
            mainResourceURL: symlinkURL.deletingLastPathComponent(),
            mainExecutableURL: symlinkURL
        )

        #expect(bundle?.bundleURL == themeBundleURL)
    }

    @Test
    func rejectsThemeInheritance() throws {
        let home = try temporaryHome()
        defer { cleanup(home) }
        try write(
            """
            schema = 1
            name = "bad"
            displayName = "Bad"
            extends = "catppuccin"

            [tokens]
            "bg.canvas" = "#111111"
            """,
            to: home.appendingPathComponent("themes/bad.toml")
        )

        let result = OmuxThemeRegistry(userThemesDirectoryURL: home.appendingPathComponent("themes")).loadTheme(named: "bad")
        #expect(result.hasErrors)
        #expect(result.diagnostics.contains(where: { $0.message.contains("inheritance") }))
    }

    @Test
    func rejectsMissingTokens() throws {
        let home = try temporaryHome()
        defer { cleanup(home) }
        try write(
            """
            schema = 1
            name = "partial"
            displayName = "Partial"

            [tokens]
            "bg.canvas" = "#111111"
            "bg.surface" = "#222222"
            """,
            to: home.appendingPathComponent("themes/partial.toml")
        )

        let result = OmuxThemeRegistry(userThemesDirectoryURL: home.appendingPathComponent("themes")).loadTheme(named: "partial")
        #expect(result.hasErrors)
        #expect(result.diagnostics.contains(where: { $0.message.contains("missing required tokens") }))
    }

    @Test
    func userThemeOverridesBundledTheme() throws {
        let home = try temporaryHome()
        defer { cleanup(home) }
        try write(fullTheme(named: "catppuccin", displayName: "My Cat"), to: home.appendingPathComponent("themes/catppuccin.toml"))

        let result = OmuxThemeRegistry(userThemesDirectoryURL: home.appendingPathComponent("themes")).loadTheme(named: "catppuccin")
        #expect(result.hasErrors == false)
        #expect(result.theme?.displayName == "My Cat")
        #expect(result.diagnostics.contains(where: { $0.severity == .warning && $0.message.contains("overrides a bundled theme") }))
    }
}

private func fullTheme(named name: String, displayName: String) -> String {
    let tokens = ThemeToken.allCases.map { "\"\($0.rawValue)\" = \"#112233\"" }.joined(separator: "\n")
    return """
    schema = 1
    name = "\(name)"
    displayName = "\(displayName)"

    [tokens]
    \(tokens)
    """
}

private func temporaryHome() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func cleanup(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

private func write(_ contents: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try contents.write(to: url, atomically: true, encoding: .utf8)
}
