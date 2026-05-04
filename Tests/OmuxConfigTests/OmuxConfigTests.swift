import Foundation
import Testing
@testable import OmuxConfig
@testable import OmuxCore

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
        #expect(result.config.autoCheckUpdate)
        #expect(result.config.terminal == OmuxConfig.defaults.terminal)
        #expect(result.config.workspace == OmuxConfig.defaults.workspace)
    }

    @Test
    func loadsAutoCheckUpdateSetting() throws {
        let cases = [
            ("true", true),
            ("false", false),
        ]

        for (literal, expected) in cases {
            let home = try temporaryHome()
            defer { cleanup(home) }
            try write(
                """
                schema = 1
                auto_check_update = \(literal)
                """,
                to: home.appendingPathComponent("config.toml")
            )

            let result = OmuxConfigLoader(configURL: home.appendingPathComponent("config.toml")).load()
            #expect(result.hasErrors == false)
            #expect(result.config.autoCheckUpdate == expected)
        }
    }

    @Test
    func rejectsInvalidAutoCheckUpdateSetting() throws {
        let home = try temporaryHome()
        defer { cleanup(home) }
        try write(
            """
            schema = 1
            auto_check_update = "nope"
            """,
            to: home.appendingPathComponent("config.toml")
        )

        let result = OmuxConfigLoader(configURL: home.appendingPathComponent("config.toml")).load()
        #expect(result.hasErrors)
        #expect(result.config.autoCheckUpdate)
        #expect(result.diagnostics.contains(where: { $0.message.contains("auto_check_update must be a boolean") }))
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

    @Test
    func loadsKeyBindingsAndUnbinds() throws {
        let home = try temporaryHome()
        defer { cleanup(home) }
        try write(
            """
            schema = 1

            [keys]
            "cmd+shift+w" = "none"
            "cmd+shift+p" = "pane.remove"
            """,
            to: home.appendingPathComponent("config.toml")
        )

        let result = OmuxConfigLoader(configURL: home.appendingPathComponent("config.toml")).load()
        #expect(result.hasErrors == false)
        #expect(result.config.keyBindings.count == 2)
        #expect(result.config.keyBindings[0].chord.description == "cmd+shift+w")
        #expect(result.config.keyBindings[0].action == nil)
        #expect(result.config.keyBindings[1].chord.description == "cmd+shift+p")
        #expect(result.config.keyBindings[1].action == .paneRemove)
    }

    @Test
    func rejectsInvalidKeyBindings() throws {
        let cases = [
            ("\"cmd+option+w\" = \"pane.remove\"", "Option/Alt bindings are not supported"),
            ("\"cmd+shift+w\" = \"pane.explode\"", "Unsupported [keys] action"),
            ("\"cmd+shift+w\" = 123", "must be an action string"),
            ("\"cmd+shift+w\" = \"pane.remove\"\n\"cmd+shift+w\" = \"workspace.close\"", "Duplicate [keys] chord"),
        ]

        for (entry, expectedMessage) in cases {
            let home = try temporaryHome()
            defer { cleanup(home) }
            try write(
                """
                schema = 1

                [keys]
                \(entry)
                """,
                to: home.appendingPathComponent("config.toml")
            )

            let result = OmuxConfigLoader(configURL: home.appendingPathComponent("config.toml")).load()
            #expect(result.hasErrors)
            #expect(result.diagnostics.contains(where: { $0.message.contains(expectedMessage) }))
        }
    }

    @Test
    func starterConfigIncludesDefaultKeyBindingsAndLoads() throws {
        let home = try temporaryHome()
        defer { cleanup(home) }
        let configURL = home.appendingPathComponent("config.toml")
        try write(OmuxConfigTemplate.starter(), to: configURL)

        let contents = try String(contentsOf: configURL, encoding: .utf8)
        #expect(contents.contains("# auto_check_update = true"))
        #expect(contents.contains("default_root_path = \"~\""))
        #expect(contents.contains("[keys]"))
        for (chord, action) in OpenMUXKeyBindingRegistry.defaultBindingPairs {
            #expect(contents.contains("\"\(chord.description)\" = \"\(action.rawValue)\""))
        }

        let result = OmuxConfigLoader(configURL: configURL).load()
        #expect(result.hasErrors == false)
        #expect(OpenMUXKeyBindingRegistry.effective(overrides: result.config.keyBindings).chord(for: .paneRemove)?.description == "cmd+shift+w")
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
