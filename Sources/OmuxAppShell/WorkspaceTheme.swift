import AppKit
import Darwin
import OmuxTerminalBridge
import OmuxTheme

struct WorkspaceShellTheme {
    let identifier: String
    let displayName: String
    let shell: WorkspaceShellColors
    let terminalPalette: TerminalThemePalette
    let resolvedTokens: ResolvedThemeTokens

    init(theme: OmuxTheme) {
        let resolvedTokens = ResolvedThemeTokens(theme: theme)
        self.identifier = theme.name
        self.displayName = theme.displayName
        self.resolvedTokens = resolvedTokens

        let canvas = NSColor(themeColor: resolvedTokens[.backgroundCanvas])
        let surface = NSColor(themeColor: resolvedTokens[.backgroundSurface])
        let accent = NSColor(themeColor: resolvedTokens[.accent])
        let selection = NSColor(themeColor: resolvedTokens[.selectionBackground])
        let sidebarSelection = selection.blended(withFraction: 0.2, of: accent) ?? selection
        let chromeActive = sidebarSelection.blended(withFraction: 0.2, of: accent) ?? accent
        let foregroundPrimary = NSColor(themeColor: resolvedTokens[.foregroundPrimary])
        let foregroundSecondary = NSColor(themeColor: resolvedTokens[.foregroundSecondary])
        let foregroundMuted = NSColor(themeColor: resolvedTokens[.foregroundMuted])
        let selectionForeground = NSColor(themeColor: resolvedTokens[.selectionForeground])
        let selectedText = Self.bestContrastingColor(
            against: sidebarSelection,
            candidates: [
                selectionForeground,
                foregroundPrimary,
                foregroundSecondary,
                foregroundMuted,
                canvas,
                surface,
                .black,
                .white,
            ]
        )

        self.shell = WorkspaceShellColors(
            windowBackground: canvas,
            sidebarBackground: surface,
            topBarBackground: surface,
            canvasBackground: canvas,
            paneCardBackground: canvas,
            paneHeaderBackground: surface,
            chromeButtonBackground: surface,
            chromeButtonActiveBackground: chromeActive,
            border: NSColor(themeColor: resolvedTokens[.borderStrong]),
            subduedBorder: NSColor(themeColor: resolvedTokens[.borderSubtle]),
            accent: accent,
            selection: sidebarSelection,
            textPrimary: foregroundPrimary,
            textSecondary: foregroundSecondary,
            textMuted: foregroundMuted,
            selectedText: selectedText
        )
        self.terminalPalette = TerminalThemePalette(
            backgroundColor: canvas,
            foregroundColor: foregroundPrimary,
            cursorColor: NSColor(themeColor: resolvedTokens[.cursor]),
            selectionColor: NSColor(themeColor: resolvedTokens[.selectionBackground])
        )
    }

    static let builtInPresets: [WorkspaceShellTheme] = {
        let registry = OmuxThemeRegistry()
        let (themes, _) = registry.loadBuiltInThemes()
        let presets = themes.map(WorkspaceShellTheme.init(theme:))
        if presets.isEmpty == false {
            return presets
        }

        return [WorkspaceShellTheme.fallback]
    }()

    static let defaultTheme: WorkspaceShellTheme = {
        builtInPresets.first(where: { $0.identifier == "monokai-soda" }) ?? builtInPresets[0]
    }()

    static var availableThemes: [WorkspaceShellTheme] {
        let registry = OmuxThemeRegistry()
        let (themes, _) = registry.loadThemes()
        let presets = themes.map(WorkspaceShellTheme.init(theme:))
        return presets.isEmpty ? builtInPresets : presets
    }

    static func named(_ identifier: String) -> WorkspaceShellTheme? {
        OmuxThemeRegistry().loadTheme(named: identifier).theme.map(WorkspaceShellTheme.init(theme:))
    }

    private static let fallback = WorkspaceShellTheme(
        theme: OmuxTheme(
            schema: 1,
            name: "monokai-soda",
            displayName: "Monokai Soda",
            tokens: [
                .backgroundCanvas: ThemeColor(red: 0x1A, green: 0x1A, blue: 0x1A),
                .backgroundSurface: ThemeColor(red: 0x1A, green: 0x1A, blue: 0x1A),
                .backgroundElevated: ThemeColor(red: 0x2D, green: 0x2F, blue: 0x30),
                .foregroundPrimary: ThemeColor(red: 0xC4, green: 0xC5, blue: 0xB5),
                .foregroundSecondary: ThemeColor(red: 0xA0, green: 0xA0, blue: 0x8B),
                .foregroundMuted: ThemeColor(red: 0x75, green: 0x71, blue: 0x5E),
                .borderSubtle: ThemeColor(red: 0x3B, green: 0x3D, blue: 0x3E),
                .borderStrong: ThemeColor(red: 0x5A, green: 0x5D, blue: 0x5E),
                .accent: ThemeColor(red: 0x66, green: 0xD9, blue: 0xEF),
                .cursor: ThemeColor(red: 0xF6, green: 0xF6, blue: 0xEF),
                .cursorText: ThemeColor(red: 0x1A, green: 0x1A, blue: 0x1A),
                .selectionBackground: ThemeColor(red: 0x49, green: 0x48, blue: 0x3E),
                .selectionForeground: ThemeColor(red: 0xF8, green: 0xF8, blue: 0xF2),
                .ansiBlack: ThemeColor(red: 0x1A, green: 0x1A, blue: 0x1A),
                .ansiRed: ThemeColor(red: 0xF4, green: 0x00, blue: 0x5F),
                .ansiGreen: ThemeColor(red: 0x98, green: 0xE0, blue: 0x24),
                .ansiYellow: ThemeColor(red: 0xFA, green: 0x84, blue: 0x19),
                .ansiBlue: ThemeColor(red: 0x9D, green: 0x65, blue: 0xFF),
                .ansiMagenta: ThemeColor(red: 0xF4, green: 0x00, blue: 0x5F),
                .ansiCyan: ThemeColor(red: 0x58, green: 0xD1, blue: 0xEB),
                .ansiWhite: ThemeColor(red: 0xC4, green: 0xC5, blue: 0xB5),
                .ansiBrightBlack: ThemeColor(red: 0x62, green: 0x5E, blue: 0x4C),
                .ansiBrightRed: ThemeColor(red: 0xFF, green: 0x1F, blue: 0x79),
                .ansiBrightGreen: ThemeColor(red: 0xB1, green: 0xEF, blue: 0x43),
                .ansiBrightYellow: ThemeColor(red: 0xFB, green: 0xC7, blue: 0x4D),
                .ansiBrightBlue: ThemeColor(red: 0xB4, green: 0x8A, blue: 0xFF),
                .ansiBrightMagenta: ThemeColor(red: 0xFF, green: 0x4F, blue: 0x98),
                .ansiBrightCyan: ThemeColor(red: 0x88, green: 0xE8, blue: 0xF7),
                .ansiBrightWhite: ThemeColor(red: 0xF6, green: 0xF6, blue: 0xEF),
            ]
        )
    )

    static func contrastRatio(_ first: NSColor, _ second: NSColor) -> CGFloat {
        let firstLuminance = relativeLuminance(first)
        let secondLuminance = relativeLuminance(second)
        let lighter = max(firstLuminance, secondLuminance)
        let darker = min(firstLuminance, secondLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    func color(for token: ThemeToken) -> NSColor {
        NSColor(themeColor: resolvedTokens[token])
    }

    private static func bestContrastingColor(against background: NSColor, candidates: [NSColor]) -> NSColor {
        candidates.max(by: {
            contrastRatio($0, background) < contrastRatio($1, background)
        }) ?? candidates.first ?? .labelColor
    }

    private static func relativeLuminance(_ color: NSColor) -> CGFloat {
        let rgb = color.usingColorSpace(.sRGB) ?? color.usingColorSpace(.deviceRGB) ?? color
        let red = linearizedComponent(rgb.redComponent)
        let green = linearizedComponent(rgb.greenComponent)
        let blue = linearizedComponent(rgb.blueComponent)
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    private static func linearizedComponent(_ value: CGFloat) -> CGFloat {
        let clamped = min(max(value, 0), 1)
        if clamped <= 0.03928 {
            return clamped / 12.92
        }
        return CGFloat(pow(Double((clamped + 0.055) / 1.055), 2.4))
    }
}

struct WorkspaceShellColors {
    let windowBackground: NSColor
    let sidebarBackground: NSColor
    let topBarBackground: NSColor
    let canvasBackground: NSColor
    let paneCardBackground: NSColor
    let paneHeaderBackground: NSColor
    let chromeButtonBackground: NSColor
    let chromeButtonActiveBackground: NSColor
    let border: NSColor
    let subduedBorder: NSColor
    let accent: NSColor
    let selection: NSColor
    let textPrimary: NSColor
    let textSecondary: NSColor
    let textMuted: NSColor
    let selectedText: NSColor
}

private extension NSColor {
    convenience init(themeColor: ThemeColor) {
        self.init(
            calibratedRed: CGFloat(themeColor.red) / 255.0,
            green: CGFloat(themeColor.green) / 255.0,
            blue: CGFloat(themeColor.blue) / 255.0,
            alpha: CGFloat(themeColor.alpha) / 255.0
        )
    }
}
