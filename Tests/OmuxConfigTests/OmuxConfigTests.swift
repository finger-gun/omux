import Foundation
import Testing
@testable import OmuxConfig

struct OmuxConfigTests {
    @Test
    func rejectsMissingSchema() throws {
        let home = try temporaryHome()
        defer { cleanup(home) }
        try write(
            """
            [theme]
            name = "dracula"
            """,
            to: home.appendingPathComponent("config.toml")
        )

        let result = OmuxConfigLoader(configURL: home.appendingPathComponent("config.toml")).load()
        #expect(result.hasErrors)
        #expect(result.config == .defaults)
        #expect(result.diagnostics.contains(where: { $0.message.contains("schema") }))
    }

    @Test
    func loadsPartialConfigOverDefaults() throws {
        let home = try temporaryHome()
        defer { cleanup(home) }
        try write(
            """
            schema = 1

            [theme]
            name = "nord"
            """,
            to: home.appendingPathComponent("config.toml")
        )

        let result = OmuxConfigLoader(configURL: home.appendingPathComponent("config.toml")).load()
        #expect(result.hasErrors == false)
        #expect(result.config.theme.name == "nord")
        #expect(result.config.terminal == OmuxConfig.defaults.terminal)
        #expect(result.config.workspace == OmuxConfig.defaults.workspace)
    }

    @Test
    func extractsGhosttyPassThroughInFileOrder() throws {
        let home = try temporaryHome()
        defer { cleanup(home) }
        try write(
            """
            schema = 1

            [ghostty]
            "copy-on-select" = false
            "font-feature" = ["-calt", "-liga"]
            """,
            to: home.appendingPathComponent("config.toml")
        )

        let result = OmuxConfigLoader(configURL: home.appendingPathComponent("config.toml")).load()
        #expect(result.hasErrors == false)
        #expect(result.config.ghostty.map(\.key) == ["copy-on-select", "font-feature"])
        #expect(result.config.ghostty[0].value == .bool(false))
        #expect(result.config.ghostty[1].value == .array([.string("-calt"), .string("-liga")]))
    }

    @Test
    func rejectsUnknownTerminalKey() throws {
        let home = try temporaryHome()
        defer { cleanup(home) }
        try write(
            """
            schema = 1

            [terminal]
            nope = "x"
            """,
            to: home.appendingPathComponent("config.toml")
        )

        let result = OmuxConfigLoader(configURL: home.appendingPathComponent("config.toml")).load()
        #expect(result.hasErrors)
        #expect(result.diagnostics.contains(where: { $0.message.contains("Unknown [terminal] key") }))
    }

    @Test
    func ignoresDeprecatedKeyboardSelectionTerminalKey() throws {
        let home = try temporaryHome()
        defer { cleanup(home) }
        try write(
            """
            schema = 1

            [terminal]
            keyboard_selection = true
            option_as_alt = "right"
            """,
            to: home.appendingPathComponent("config.toml")
        )

        let result = OmuxConfigLoader(configURL: home.appendingPathComponent("config.toml")).load()
        #expect(result.hasErrors == false)
        #expect(result.config.terminal.optionAsAlt == .right)
        #expect(result.diagnostics.contains(where: {
            $0.severity == .warning && $0.message.contains("keyboard_selection")
        }))
    }

    @Test
    func loadsOptionAsAltTerminalSetting() throws {
        let cases: [(String, OmuxConfigTerminal.OptionAsAlt)] = [
            ("false", .disabled),
            ("true", .both),
            ("\"left\"", .left),
            ("\"right\"", .right),
        ]

        for (literal, expected) in cases {
            let home = try temporaryHome()
            defer { cleanup(home) }
            try write(
                """
                schema = 1

                [terminal]
                option_as_alt = \(literal)
                """,
                to: home.appendingPathComponent("config.toml")
            )

            let result = OmuxConfigLoader(configURL: home.appendingPathComponent("config.toml")).load()
            #expect(result.hasErrors == false)
            #expect(result.config.terminal.optionAsAlt == expected)
        }
    }

    @Test
    func rejectsInvalidOptionAsAltTerminalSetting() throws {
        let home = try temporaryHome()
        defer { cleanup(home) }
        try write(
            """
            schema = 1

            [terminal]
            option_as_alt = "upside-down"
            """,
            to: home.appendingPathComponent("config.toml")
        )

        let result = OmuxConfigLoader(configURL: home.appendingPathComponent("config.toml")).load()
        #expect(result.hasErrors)
        #expect(result.diagnostics.contains(where: { $0.message.contains("terminal.option_as_alt") }))
    }

    @Test
    func loadsWorkspaceDefaultRootSetting() throws {
        let home = try temporaryHome()
        defer { cleanup(home) }
        let projectRoot = home.appendingPathComponent("projects", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try write(
            """
            schema = 1

            [workspace]
            default_root_path = "\(projectRoot.path)"
            """,
            to: home.appendingPathComponent("config.toml")
        )

        let result = OmuxConfigLoader(configURL: home.appendingPathComponent("config.toml")).load()
        #expect(result.hasErrors == false)
        #expect(result.config.workspace.defaultRootPath == projectRoot.standardizedFileURL.path)
    }

    @Test
    func expandsHomeWorkspaceDefaultRootSetting() throws {
        let home = try temporaryHome()
        defer { cleanup(home) }
        try write(
            """
            schema = 1

            [workspace]
            default_root_path = "~"
            """,
            to: home.appendingPathComponent("config.toml")
        )

        let result = OmuxConfigLoader(configURL: home.appendingPathComponent("config.toml")).load()
        #expect(result.hasErrors == false)
        #expect(result.config.workspace.defaultRootPath == OmuxWorkspacePathResolver.defaultRootPath)
    }

    @Test
    func rejectsInvalidWorkspaceDefaultRootSettings() throws {
        let cases = [
            ("123", "workspace.default_root_path must be a string"),
            ("\"relative/path\"", "workspace.default_root_path must be an absolute path"),
            ("\"/definitely/not/a/real/omux/path\"", "workspace.default_root_path must point to an existing directory"),
        ]

        for (literal, expectedMessage) in cases {
            let home = try temporaryHome()
            defer { cleanup(home) }
            try write(
                """
                schema = 1

                [workspace]
                default_root_path = \(literal)
                """,
                to: home.appendingPathComponent("config.toml")
            )

            let result = OmuxConfigLoader(configURL: home.appendingPathComponent("config.toml")).load()
            #expect(result.hasErrors)
            #expect(result.diagnostics.contains(where: { $0.message.contains(expectedMessage) }))
            #expect(result.config.workspace == OmuxConfig.defaults.workspace)
        }
    }

    @Test
    func rejectsUnknownWorkspaceKey() throws {
        let home = try temporaryHome()
        defer { cleanup(home) }
        try write(
            """
            schema = 1

            [workspace]
            nope = "x"
            """,
            to: home.appendingPathComponent("config.toml")
        )

        let result = OmuxConfigLoader(configURL: home.appendingPathComponent("config.toml")).load()
        #expect(result.hasErrors)
        #expect(result.diagnostics.contains(where: { $0.message.contains("Unknown [workspace] key") }))
    }
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
