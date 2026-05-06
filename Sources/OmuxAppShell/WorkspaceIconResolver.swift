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
        case helix
        case emacs
        case nano
        case node
        case neovim
        case package
        case python
        case rust
        case ssh
        case swift
        case terminal
        case tmux
        case vim
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
    static let helix = OmuxSemanticIcon(
        kind: .helix,
        nerdFontGlyph: "\u{ed7d}",
        fallbackText: "Hx",
        sfSymbolName: "pencil.and.scribble",
        colorToken: .ansiBrightGreen,
        accessibilityLabel: "Helix editor",
        priority: 110
    )
    static let emacs = OmuxSemanticIcon(
        kind: .emacs,
        nerdFontGlyph: "\u{e632}",
        fallbackText: "Em",
        sfSymbolName: "pencil",
        colorToken: .ansiMagenta,
        accessibilityLabel: "Emacs editor",
        priority: 110
    )
    static let nano = OmuxSemanticIcon(
        kind: .nano,
        nerdFontGlyph: "\u{f040}",
        fallbackText: "Na",
        sfSymbolName: "pencil",
        colorToken: .ansiCyan,
        accessibilityLabel: "nano editor",
        priority: 110
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
    static let neovim = OmuxSemanticIcon(
        kind: .neovim,
        nerdFontGlyph: "\u{e7c5}",
        fallbackText: "Nv",
        sfSymbolName: "pencil",
        colorToken: .ansiGreen,
        accessibilityLabel: "Neovim editor",
        priority: 110
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
    static let ssh = OmuxSemanticIcon(
        kind: .ssh,
        nerdFontGlyph: "\u{f817}",
        fallbackText: "SSH",
        sfSymbolName: "network",
        colorToken: .ansiBrightCyan,
        accessibilityLabel: "SSH session",
        priority: 105
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
    static let tmux = OmuxSemanticIcon(
        kind: .tmux,
        nerdFontGlyph: "\u{f120}",
        fallbackText: "Tx",
        sfSymbolName: "rectangle.split.3x1",
        colorToken: .ansiBrightBlue,
        accessibilityLabel: "tmux session",
        priority: 105
    )
    static let vim = OmuxSemanticIcon(
        kind: .vim,
        nerdFontGlyph: "\u{e7c5}",
        fallbackText: "Vi",
        sfSymbolName: "pencil",
        colorToken: .ansiGreen,
        accessibilityLabel: "Vim editor",
        priority: 110
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
enum BundledIconFont {
    static let familyName = "Symbols Nerd Font Mono"
    private static let resourceName = "SymbolsNerdFontMono-Regular"
    private static let resourceSubdirectory = "Fonts"
    private static let appShellResourceBundleName = "OpenMUX_OmuxAppShell.bundle"
    private static var didAttemptRegistration = false

    static func registerIfNeeded() {
        guard didAttemptRegistration == false else {
            return
        }
        didAttemptRegistration = true

        if fontIsAvailable() {
            return
        }

        guard let fontURL = fontURL() else {
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

    static func fontURL(
        fileManager: FileManager = .default,
        mainBundleURL: URL = Bundle.main.bundleURL,
        mainResourceURL: URL? = Bundle.main.resourceURL,
        mainExecutableURL: URL? = Bundle.main.executableURL
    ) -> URL? {
        packagedFontURL(
            fileManager: fileManager,
            mainBundleURL: mainBundleURL,
            mainResourceURL: mainResourceURL,
            mainExecutableURL: mainExecutableURL
        ) ?? swiftPMModuleFontURL(mainBundleURL: mainBundleURL)
    }

    private static func packagedFontURL(
        fileManager: FileManager,
        mainBundleURL: URL,
        mainResourceURL: URL?,
        mainExecutableURL: URL?
    ) -> URL? {
        let executableURLs = executableResourceLookupURLs(from: mainExecutableURL)
        let executableCandidates = executableURLs.flatMap { executableURL in
            [
                executableURL
                    .deletingLastPathComponent()
                    .appendingPathComponent(appShellResourceBundleName, isDirectory: true),
                executableURL
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .appendingPathComponent("Resources", isDirectory: true)
                    .appendingPathComponent(appShellResourceBundleName, isDirectory: true),
            ]
        }

        let candidates = [
            mainResourceURL?.appendingPathComponent(appShellResourceBundleName, isDirectory: true),
            mainBundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent(appShellResourceBundleName, isDirectory: true),
        ].compactMap { $0 } + executableCandidates

        for bundleURL in candidates {
            guard fileManager.fileExists(atPath: bundleURL.path) else {
                continue
            }
            if let fontURL = fontURL(inResourceBundleAt: bundleURL, fileManager: fileManager) {
                return fontURL
            }
        }

        return nil
    }

    private static func swiftPMModuleFontURL(mainBundleURL: URL) -> URL? {
        guard mainBundleURL.pathExtension != "app" else {
            return nil
        }
        return Bundle.module.url(
            forResource: resourceName,
            withExtension: "ttf",
            subdirectory: resourceSubdirectory
        ) ?? Bundle.module.url(forResource: resourceName, withExtension: "ttf")
    }

    private static func fontURL(inResourceBundleAt bundleURL: URL, fileManager: FileManager) -> URL? {
        let candidates = [
            bundleURL
                .appendingPathComponent(resourceSubdirectory, isDirectory: true)
                .appendingPathComponent("\(resourceName).ttf", isDirectory: false),
            bundleURL.appendingPathComponent("\(resourceName).ttf", isDirectory: false),
        ]
        return candidates.first { fileManager.fileExists(atPath: $0.path) }
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

    func icon(for pane: Pane, terminalText: String? = nil) -> OmuxSemanticIcon {
        specificIcon(for: pane, terminalText: terminalText) ?? .terminal
    }

    func icon(for workspace: Workspace) -> OmuxSemanticIcon {
        if let focusedPane = workspace.focusedPane,
           let focusedIcon = specificIcon(for: focusedPane) {
            return focusedIcon
        }

        return workspace.tabs
            .flatMap(\.panes)
            .compactMap { specificIcon(for: $0) }
            .max { $0.priority < $1.priority }
            ?? .workspace
    }

    func icon(for panes: [Pane], focusedPaneID: PaneID?, terminalText: (Pane) -> String?) -> OmuxSemanticIcon {
        if let focusedPane = panes.first(where: { $0.id == focusedPaneID }),
           let focusedIcon = specificIcon(for: focusedPane, terminalText: terminalText(focusedPane)) {
            return focusedIcon
        }

        return panes
            .compactMap { pane in specificIcon(for: pane, terminalText: terminalText(pane)) }
            .max { $0.priority < $1.priority }
            ?? .workspace
    }

    func invalidate(path: String) {
        iconByPath.removeValue(forKey: normalizedPath(path))
    }

    private func specificIcon(for pane: Pane, terminalText: String? = nil) -> OmuxSemanticIcon? {
        let titleCandidates = [
            pane.terminalState.reportedTitle,
            pane.title,
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }

        for title in titleCandidates where title.isEmpty == false {
            if let icon = Self.terminalApplicationIcon(forTitle: title) ?? titleIcon(for: title) {
                return icon
            }
        }

        if let icon = terminalText.flatMap(Self.terminalApplicationIcon(forScreenText:)) {
            return icon
        }

        if let workingDirectory = pane.terminalState.reportedWorkingDirectory ?? pane.terminalSession?.workingDirectory,
           let icon = projectIcon(forPath: workingDirectory) {
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

    static func terminalApplicationIcon(forTitle title: String) -> OmuxSemanticIcon? {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedTitle.isEmpty == false else {
            return nil
        }

        let commandCandidates = commandCandidates(from: normalizedTitle)
        if commandCandidates.contains("lazydocker") {
            return .docker
        }
        if commandCandidates.contains("lazygit") {
            return .git
        }
        if commandCandidates.contains("nvim") || commandCandidates.contains("neovim") {
            return .neovim
        }
        if commandCandidates.contains("vim") {
            return .vim
        }
        if commandCandidates.contains("hx") || commandCandidates.contains("helix") {
            return .helix
        }
        if commandCandidates.contains("emacs") {
            return .emacs
        }
        if commandCandidates.contains("nano") {
            return .nano
        }
        if commandCandidates.contains("tmux") {
            return .tmux
        }
        if commandCandidates.contains("ssh") {
            return .ssh
        }
        return nil
    }

    static func terminalApplicationIcon(forScreenText text: String) -> OmuxSemanticIcon? {
        let lowercased = text.localizedLowercase
        guard lowercased.isEmpty == false else {
            return nil
        }

        if lowercased.contains("vim - vi improved")
            || lowercased.contains("vi improved")
            || lowercased.contains("type  :q<enter>") {
            return .vim
        }

        if lowercased.contains("gnu nano")
            || lowercased.contains("uw pico")
            || (lowercased.contains("writeout") && lowercased.contains("where is")) {
            return .nano
        }

        if lowercased.contains("[scratch]")
            && (lowercased.contains(" nor ") || lowercased.contains(" ins ") || lowercased.contains("1 sel")) {
            return .helix
        }

        return nil
    }

    private static func commandCandidates(from title: String) -> Set<String> {
        let lowercased = title.localizedLowercase
        let separators = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "-_./"))
            .inverted
        let tokens = lowercased
            .components(separatedBy: separators)
            .filter { $0.isEmpty == false }

        var candidates = Set(tokens)
        for token in tokens {
            let executableName = URL(fileURLWithPath: token).lastPathComponent
            if executableName.isEmpty == false {
                candidates.insert(executableName)
            }
        }
        return candidates
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
