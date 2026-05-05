import AppKit
import CoreText
import Foundation
import OmuxConfig
import OmuxCore
import OmuxTheme

struct OmuxSemanticIcon: Equatable {
    enum Kind: String, Equatable {
        case ai
        case docker
        case folder
        case git
        case go
        case node
        case package
        case python
        case rust
        case swift
        case terminal
        case workspace
    }

    let kind: Kind
    let nerdFontGlyph: String
    let fallbackText: String
    let sfSymbolName: String?
    let colorToken: ThemeToken
    let accessibilityLabel: String
    let priority: Int

    static let ai = OmuxSemanticIcon(
        kind: .ai,
        nerdFontGlyph: "\u{f1d8}",
        fallbackText: "AI",
        sfSymbolName: "sparkles",
        colorToken: .ansiBrightMagenta,
        accessibilityLabel: "AI session",
        priority: 100
    )
    static let docker = OmuxSemanticIcon(
        kind: .docker,
        nerdFontGlyph: "\u{f308}",
        fallbackText: "D",
        sfSymbolName: "shippingbox",
        colorToken: .ansiCyan,
        accessibilityLabel: "Docker project",
        priority: 80
    )
    static let folder = OmuxSemanticIcon(
        kind: .folder,
        nerdFontGlyph: "\u{f07b}",
        fallbackText: "F",
        sfSymbolName: "folder",
        colorToken: .ansiBrightBlue,
        accessibilityLabel: "Folder",
        priority: 10
    )
    static let git = OmuxSemanticIcon(
        kind: .git,
        nerdFontGlyph: "\u{f1d3}",
        fallbackText: "G",
        sfSymbolName: "point.3.connected.trianglepath.dotted",
        colorToken: .ansiRed,
        accessibilityLabel: "Git project",
        priority: 40
    )
    static let go = OmuxSemanticIcon(
        kind: .go,
        nerdFontGlyph: "\u{e626}",
        fallbackText: "Go",
        sfSymbolName: "curlybraces",
        colorToken: .ansiCyan,
        accessibilityLabel: "Go project",
        priority: 90
    )
    static let node = OmuxSemanticIcon(
        kind: .node,
        nerdFontGlyph: "\u{e718}",
        fallbackText: "JS",
        sfSymbolName: "hexagon",
        colorToken: .ansiGreen,
        accessibilityLabel: "Node project",
        priority: 90
    )
    static let package = OmuxSemanticIcon(
        kind: .package,
        nerdFontGlyph: "\u{f487}",
        fallbackText: "P",
        sfSymbolName: "shippingbox",
        colorToken: .ansiYellow,
        accessibilityLabel: "Package project",
        priority: 60
    )
    static let python = OmuxSemanticIcon(
        kind: .python,
        nerdFontGlyph: "\u{e73c}",
        fallbackText: "Py",
        sfSymbolName: "curlybraces",
        colorToken: .ansiBrightYellow,
        accessibilityLabel: "Python project",
        priority: 90
    )
    static let rust = OmuxSemanticIcon(
        kind: .rust,
        nerdFontGlyph: "\u{e7a8}",
        fallbackText: "Rs",
        sfSymbolName: "gearshape",
        colorToken: .ansiBrightRed,
        accessibilityLabel: "Rust project",
        priority: 90
    )
    static let swift = OmuxSemanticIcon(
        kind: .swift,
        nerdFontGlyph: "\u{e755}",
        fallbackText: "S",
        sfSymbolName: "swift",
        colorToken: .ansiBrightRed,
        accessibilityLabel: "Swift project",
        priority: 90
    )
    static let terminal = OmuxSemanticIcon(
        kind: .terminal,
        nerdFontGlyph: "\u{f489}",
        fallbackText: ">",
        sfSymbolName: "terminal",
        colorToken: .ansiBrightBlack,
        accessibilityLabel: "Terminal",
        priority: 20
    )
    static let workspace = OmuxSemanticIcon(
        kind: .workspace,
        nerdFontGlyph: "\u{f07c}",
        fallbackText: "W",
        sfSymbolName: "rectangle.3.group",
        colorToken: .ansiBlue,
        accessibilityLabel: "Workspace",
        priority: 10
    )
}

struct OmuxRenderedIcon: Equatable {
    let text: String
    let font: NSFont
    let accessibilityLabel: String
    let symbolName: String?
    let prefersSymbol: Bool
    let colorToken: ThemeToken
    let colorsEnabled: Bool
}

@MainActor
struct OmuxIconRenderer {
    let configuration: OmuxConfigUI.Icons
    private let pointSize: CGFloat
    private let weight: NSFont.Weight

    init(
        configuration: OmuxConfigUI.Icons,
        pointSize: CGFloat,
        weight: NSFont.Weight
    ) {
        self.configuration = configuration
        self.pointSize = pointSize
        self.weight = weight
    }

    func render(_ icon: OmuxSemanticIcon?) -> OmuxRenderedIcon? {
        guard configuration.enabled, let icon else {
            return nil
        }

        switch configuration.provider {
        case .nerdFont:
            if let font = nerdFont(for: icon.nerdFontGlyph) {
                return OmuxRenderedIcon(
                    text: icon.nerdFontGlyph,
                    font: font,
                    accessibilityLabel: icon.accessibilityLabel,
                    symbolName: nil,
                    prefersSymbol: false,
                    colorToken: icon.colorToken,
                    colorsEnabled: configuration.colorsEnabled
                )
            }
            return OmuxRenderedIcon(
                text: icon.fallbackText,
                font: .systemFont(ofSize: pointSize, weight: weight),
                accessibilityLabel: icon.accessibilityLabel,
                symbolName: icon.sfSymbolName,
                prefersSymbol: false,
                colorToken: icon.colorToken,
                colorsEnabled: configuration.colorsEnabled
            )
        case .sfSymbols:
            return OmuxRenderedIcon(
                text: icon.fallbackText,
                font: .systemFont(ofSize: pointSize, weight: weight),
                accessibilityLabel: icon.accessibilityLabel,
                symbolName: icon.sfSymbolName,
                prefersSymbol: true,
                colorToken: icon.colorToken,
                colorsEnabled: configuration.colorsEnabled
            )
        case .text:
            return OmuxRenderedIcon(
                text: icon.fallbackText,
                font: .systemFont(ofSize: pointSize, weight: weight),
                accessibilityLabel: icon.accessibilityLabel,
                symbolName: nil,
                prefersSymbol: false,
                colorToken: icon.colorToken,
                colorsEnabled: configuration.colorsEnabled
            )
        }
    }

    private func nerdFont(for glyph: String) -> NSFont? {
        BundledIconFont.registerIfNeeded()

        let candidates = ([configuration.fontFamily].compactMap { $0 })
            + [BundledIconFont.familyName]
            + [
                "Symbols Nerd Font",
                "JetBrainsMono Nerd Font",
                "MesloLGS NF",
                "Hack Nerd Font",
            ]

        for family in candidates {
            guard let font = NSFont(name: family, size: pointSize),
                  font.canRender(glyph)
            else {
                continue
            }
            return font
        }

        return nil
    }
}

@MainActor
private enum BundledIconFont {
    static let familyName = "Symbols Nerd Font Mono"
    private static let resourceName = "SymbolsNerdFontMono-Regular"
    private static let resourceSubdirectory = "Fonts"
    private static var didAttemptRegistration = false

    static func registerIfNeeded() {
        guard didAttemptRegistration == false else {
            return
        }
        didAttemptRegistration = true

        if fontIsAvailable() {
            return
        }

        guard let fontURL = Bundle.module.url(
            forResource: resourceName,
            withExtension: "ttf",
            subdirectory: resourceSubdirectory
        ) ?? Bundle.module.url(forResource: resourceName, withExtension: "ttf") else {
            fputs("warning: bundled OpenMUX icon font resource is missing\n", stderr)
            return
        }

        var registrationError: Unmanaged<CFError>?
        let didRegister = CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &registrationError)
        if didRegister == false, fontIsAvailable() == false {
            let message = registrationError?.takeRetainedValue().localizedDescription
                ?? "unknown CoreText registration error"
            fputs("warning: failed to register bundled OpenMUX icon font: \(message)\n", stderr)
        } else {
            registrationError?.release()
        }
    }

    private static func fontIsAvailable() -> Bool {
        NSFont(name: familyName, size: 11) != nil
    }
}

final class WorkspaceIconResolver {
    private enum CachedIcon {
        case icon(OmuxSemanticIcon)
        case miss
    }

    private struct MarkerRule {
        let markerNames: [String]
        let icon: OmuxSemanticIcon
    }

    private let fileManager: FileManager
    private var iconByPath: [String: CachedIcon] = [:]

    private let markerRules: [MarkerRule] = [
        MarkerRule(markerNames: ["package.json", "pnpm-lock.yaml", "yarn.lock", "node_modules"], icon: .node),
        MarkerRule(markerNames: ["Package.swift"], icon: .swift),
        MarkerRule(markerNames: ["Cargo.toml"], icon: .rust),
        MarkerRule(markerNames: ["go.mod"], icon: .go),
        MarkerRule(markerNames: ["pyproject.toml", "requirements.txt", ".python-version"], icon: .python),
        MarkerRule(markerNames: ["Dockerfile", "docker-compose.yml", "compose.yml"], icon: .docker),
        MarkerRule(markerNames: [".git"], icon: .git),
    ]

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func icon(for pane: Pane) -> OmuxSemanticIcon {
        specificIcon(for: pane) ?? .terminal
    }

    func icon(for workspace: Workspace) -> OmuxSemanticIcon {
        if let focusedPane = workspace.focusedPane,
           let focusedIcon = specificIcon(for: focusedPane) {
            return focusedIcon
        }

        return workspace.tabs
            .flatMap(\.panes)
            .compactMap(specificIcon(for:))
            .max { $0.priority < $1.priority }
            ?? .workspace
    }

    func invalidate(path: String) {
        iconByPath.removeValue(forKey: normalizedPath(path))
    }

    private func specificIcon(for pane: Pane) -> OmuxSemanticIcon? {
        let title = pane.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let icon = titleIcon(for: title) {
            return icon
        }

        let workingDirectory = pane.terminalState.reportedWorkingDirectory ?? pane.session.workingDirectory
        if let icon = projectIcon(forPath: workingDirectory) {
            return icon
        }

        return nil
    }

    private func titleIcon(for title: String) -> OmuxSemanticIcon? {
        let lowercased = title.localizedLowercase
        let aiTerms = ["copilot", "github copilot", "claude", "chatgpt", "openai", "codex"]
        if aiTerms.contains(where: lowercased.contains) {
            return .ai
        }
        return nil
    }

    private func projectIcon(forPath path: String) -> OmuxSemanticIcon? {
        let path = normalizedPath(path)
        if let cached = iconByPath[path] {
            switch cached {
            case .icon(let icon):
                return icon
            case .miss:
                return nil
            }
        }

        let icon = ancestorURLs(startingAt: URL(fileURLWithPath: path, isDirectory: true))
            .lazy
            .compactMap(iconForDirectory)
            .first
        iconByPath[path] = icon.map(CachedIcon.icon) ?? .miss
        return icon
    }

    private func iconForDirectory(_ directoryURL: URL) -> OmuxSemanticIcon? {
        for rule in markerRules {
            if rule.markerNames.contains(where: { markerExists(named: $0, in: directoryURL) }) {
                return rule.icon
            }
        }
        return nil
    }

    private func markerExists(named markerName: String, in directoryURL: URL) -> Bool {
        fileManager.fileExists(atPath: directoryURL.appendingPathComponent(markerName).path)
    }

    private func ancestorURLs(startingAt startURL: URL) -> [URL] {
        var urls: [URL] = []
        var current = startURL.standardizedFileURL
        let root = URL(fileURLWithPath: "/", isDirectory: true).standardizedFileURL.path
        let home = fileManager.homeDirectoryForCurrentUser.standardizedFileURL.path

        while true {
            urls.append(current)
            let path = current.path
            guard path != root, path != home else {
                break
            }

            let parent = current.deletingLastPathComponent().standardizedFileURL
            guard parent.path != path else {
                break
            }
            current = parent
        }

        return urls
    }

    private func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
    }
}

private extension NSFont {
    func canRender(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { scalar in
            coveredCharacterSet.contains(scalar)
        }
    }
}

extension OmuxRenderedIcon {
    func symbolImage() -> NSImage? {
        guard prefersSymbol, let symbolName else {
            return nil
        }
        return NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityLabel)
    }
}
