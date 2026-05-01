import Foundation
import Testing
@testable import OmuxConfig
@testable import OmuxTheme

struct OmuxThemeCompilerTests {
    @Test
    func compilerIsDeterministic() {
        let theme = makeTheme(name: "test")
        let config = OmuxConfig(
            schema: 1,
            theme: OmuxConfigTheme(name: "test"),
            terminal: OmuxConfigTerminal(fontFamily: "Berkeley Mono", fontSize: 13, scrollbackLines: 1000),
            ghostty: [OmuxGhosttyConfigEntry(key: "copy-on-select", value: .bool(false))]
        )
        let compiler = OmuxThemeCompiler(buildVersion: "test-build")

        let first = compiler.compile(theme: theme, config: config)
        let second = compiler.compile(theme: theme, config: config)

        #expect(first.hash == second.hash)
        #expect(first.fileURL == second.fileURL)
        #expect(first.contents == second.contents)
    }

    @Test
    func compilerWarnsAndWritesManagedKeysLast() {
        let theme = makeTheme(name: "test")
        let config = OmuxConfig(
            schema: 1,
            theme: OmuxConfigTheme(name: "test"),
            terminal: OmuxConfigTerminal(),
            ghostty: [
                OmuxGhosttyConfigEntry(key: "background", value: .string("#000000")),
                OmuxGhosttyConfigEntry(key: "copy-on-select", value: .bool(false)),
            ]
        )
        let output = OmuxThemeCompiler(buildVersion: "test-build").compile(theme: theme, config: config)

        #expect(output.diagnostics.contains(where: { $0.severity == .warning && $0.message.contains("background") }))
        let passThroughIndex = output.contents.range(of: "background = \"#000000\"")?.lowerBound
        let expectedBackground = theme.tokens[.backgroundCanvas]!.hexString
        let managedIndex = output.contents.range(of: "background = \(expectedBackground)")?.lowerBound
        #expect(passThroughIndex != nil)
        #expect(managedIndex != nil)
        #expect(passThroughIndex! < managedIndex!)
        #expect(output.contents.contains("copy-on-select = false"))
    }

    @Test
    func compilerEmitsOwnedOptionAsAltSetting() {
        let theme = makeTheme(name: "test")
        let cases: [(OmuxConfigTerminal.OptionAsAlt?, String?)] = [
            (nil, nil),
            (.disabled, "false"),
            (.both, "true"),
            (.left, "left"),
            (.right, "right"),
        ]

        for (value, expectedLiteral) in cases {
            let config = OmuxConfig(
                schema: 1,
                theme: OmuxConfigTheme(name: "test"),
                terminal: OmuxConfigTerminal(optionAsAlt: value),
                ghostty: []
            )

            let output = OmuxThemeCompiler(buildVersion: "test-build").compile(theme: theme, config: config)

            if let expectedLiteral {
                #expect(output.contents.contains("macos-option-as-alt = \(expectedLiteral)"))
            } else {
                #expect(output.contents.contains("macos-option-as-alt") == false)
            }
        }
    }

    @Test
    func compilerEmitsManagedWindowPadding() {
        let output = OmuxThemeCompiler(buildVersion: "test-build").compile(
            theme: makeTheme(name: "test"),
            config: OmuxConfig.defaults
        )

        #expect(output.contents.contains("window-padding-x = 6"))
        #expect(output.contents.contains("window-padding-y = 6"))
    }

    @Test
    func writeCreatesGeneratedFileWithHeader() throws {
        let directory = try temporaryDirectory()
        defer { cleanup(directory) }

        let compiler = OmuxThemeCompiler(
            buildVersion: "test-build",
            generatedGhosttyDirectoryURL: directory
        )
        let output = compiler.compile(theme: makeTheme(name: "test"), config: OmuxConfig.defaults)
        let fileURL = try compiler.write(output: output)
        let contents = try String(contentsOf: fileURL, encoding: .utf8)

        #expect(fileURL.path.contains("config-"))
        #expect(contents.contains("# OpenMUX managed file. Do not edit directly."))
        #expect(contents.contains("# theme: test"))
        #expect(contents.contains("# openmux-version: test-build"))
    }

    @Test
    func garbageCollectorPreservesActiveFile() throws {
        let directory = try temporaryDirectory()
        defer { cleanup(directory) }

        let compiler = OmuxThemeCompiler(
            buildVersion: "test-build",
            retentionInterval: 0,
            generatedGhosttyDirectoryURL: directory
        )
        let active = try compiler.write(output: compiler.compile(theme: makeTheme(name: "active"), config: OmuxConfig.defaults))
        let stale = try compiler.write(output: compiler.compile(theme: makeTheme(name: "stale"), config: OmuxConfig.defaults))

        compiler.garbageCollect(activeFileURL: active)

        #expect(FileManager.default.fileExists(atPath: active.path))
        #expect(FileManager.default.fileExists(atPath: stale.path) == false)
    }

    @Test
    func garbageCollectorTrimsDirectoryToSizeLimit() throws {
        let directory = try temporaryDirectory()
        defer { cleanup(directory) }

        let compiler = OmuxThemeCompiler(
            buildVersion: "test-build",
            retentionInterval: 60 * 60 * 24,
            maxDirectoryBytes: 750,
            generatedGhosttyDirectoryURL: directory
        )

        let newest = try compiler.write(output: compiler.compile(theme: makeTheme(name: "newest"), config: OmuxConfig.defaults))
        sleep(1)
        _ = try compiler.write(output: compiler.compile(theme: makeTheme(name: "middle"), config: OmuxConfig.defaults))
        sleep(1)
        let active = try compiler.write(output: compiler.compile(theme: makeTheme(name: "active"), config: OmuxConfig.defaults))

        compiler.garbageCollect(activeFileURL: active)

        #expect(FileManager.default.fileExists(atPath: active.path))
        #expect(FileManager.default.fileExists(atPath: newest.path) == false)
    }
}

private func makeTheme(name: String) -> OmuxTheme {
    let seed = UInt8(abs(name.hashValue) % 200 + 20)
    let tokens = Dictionary(
        uniqueKeysWithValues: ThemeToken.allCases.map { token in
            let offset = UInt8(ThemeToken.allCases.firstIndex(of: token) ?? 0)
            return (
                token,
                ThemeColor(
                    red: seed &+ offset,
                    green: seed &+ 1 &+ offset,
                    blue: seed &+ 2 &+ offset
                )
            )
        }
    )
    return OmuxTheme(schema: 1, name: name, displayName: name.capitalized, tokens: tokens)
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func cleanup(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}
