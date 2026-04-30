import AppKit
import OmuxTerminalBridge

struct WorkspaceShellTheme {
    let identifier: String
    let displayName: String
    let shell: WorkspaceShellColors
    let terminalPalette: TerminalThemePalette

    static let openMUXDark = WorkspaceShellTheme(
        identifier: "openmux-dark",
        displayName: "OpenMUX Dark",
        shell: WorkspaceShellColors(
            windowBackground: NSColor(hex: 0x10141B),
            sidebarBackground: NSColor(hex: 0x141A23),
            topBarBackground: NSColor(hex: 0x121821),
            canvasBackground: NSColor(hex: 0x0D1218),
            paneCardBackground: NSColor(hex: 0x121923),
            paneHeaderBackground: NSColor(hex: 0x192230),
            chromeButtonBackground: NSColor(hex: 0x202B3A),
            chromeButtonActiveBackground: NSColor(hex: 0x2A3950),
            border: NSColor(hex: 0x2A3648),
            subduedBorder: NSColor(hex: 0x212C3B),
            accent: NSColor(hex: 0x71B7FF),
            selection: NSColor(hex: 0x20314A),
            textPrimary: NSColor(hex: 0xE8EDF5),
            textSecondary: NSColor(hex: 0x98A7BD),
            textMuted: NSColor(hex: 0x72829A)
        ),
        terminalPalette: TerminalThemePalette(
            backgroundColor: NSColor(hex: 0x0D1218),
            foregroundColor: NSColor(hex: 0xE8EDF5),
            cursorColor: NSColor(hex: 0x71B7FF),
            selectionColor: NSColor(hex: 0x20314A)
        )
    )

    static let catppuccin = WorkspaceShellTheme(
        identifier: "catppuccin",
        displayName: "Catppuccin",
        shell: WorkspaceShellColors(
            windowBackground: NSColor(hex: 0x1E1E2E),
            sidebarBackground: NSColor(hex: 0x181825),
            topBarBackground: NSColor(hex: 0x181825),
            canvasBackground: NSColor(hex: 0x11111B),
            paneCardBackground: NSColor(hex: 0x1E1E2E),
            paneHeaderBackground: NSColor(hex: 0x313244),
            chromeButtonBackground: NSColor(hex: 0x313244),
            chromeButtonActiveBackground: NSColor(hex: 0x45475A),
            border: NSColor(hex: 0x45475A),
            subduedBorder: NSColor(hex: 0x313244),
            accent: NSColor(hex: 0x89B4FA),
            selection: NSColor(hex: 0x45475A),
            textPrimary: NSColor(hex: 0xCDD6F4),
            textSecondary: NSColor(hex: 0xA6ADC8),
            textMuted: NSColor(hex: 0x7F849C)
        ),
        terminalPalette: TerminalThemePalette(
            backgroundColor: NSColor(hex: 0x11111B),
            foregroundColor: NSColor(hex: 0xCDD6F4),
            cursorColor: NSColor(hex: 0xF5E0DC),
            selectionColor: NSColor(hex: 0x45475A)
        )
    )

    static let gruvbox = WorkspaceShellTheme(
        identifier: "gruvbox",
        displayName: "Gruvbox",
        shell: WorkspaceShellColors(
            windowBackground: NSColor(hex: 0x282828),
            sidebarBackground: NSColor(hex: 0x1D2021),
            topBarBackground: NSColor(hex: 0x1D2021),
            canvasBackground: NSColor(hex: 0x202020),
            paneCardBackground: NSColor(hex: 0x282828),
            paneHeaderBackground: NSColor(hex: 0x32302F),
            chromeButtonBackground: NSColor(hex: 0x3C3836),
            chromeButtonActiveBackground: NSColor(hex: 0x504945),
            border: NSColor(hex: 0x504945),
            subduedBorder: NSColor(hex: 0x3C3836),
            accent: NSColor(hex: 0x83A598),
            selection: NSColor(hex: 0x504945),
            textPrimary: NSColor(hex: 0xEBDBB2),
            textSecondary: NSColor(hex: 0xD5C4A1),
            textMuted: NSColor(hex: 0xA89984)
        ),
        terminalPalette: TerminalThemePalette(
            backgroundColor: NSColor(hex: 0x1D2021),
            foregroundColor: NSColor(hex: 0xEBDBB2),
            cursorColor: NSColor(hex: 0xFABD2F),
            selectionColor: NSColor(hex: 0x504945)
        )
    )

    static let sonokai = WorkspaceShellTheme(
        identifier: "sonokai",
        displayName: "Sonokai",
        shell: WorkspaceShellColors(
            windowBackground: NSColor(hex: 0x2C2E34),
            sidebarBackground: NSColor(hex: 0x25272D),
            topBarBackground: NSColor(hex: 0x25272D),
            canvasBackground: NSColor(hex: 0x1F2126),
            paneCardBackground: NSColor(hex: 0x2C2E34),
            paneHeaderBackground: NSColor(hex: 0x3B3E48),
            chromeButtonBackground: NSColor(hex: 0x3B3E48),
            chromeButtonActiveBackground: NSColor(hex: 0x4C505C),
            border: NSColor(hex: 0x4C505C),
            subduedBorder: NSColor(hex: 0x3B3E48),
            accent: NSColor(hex: 0x9ED072),
            selection: NSColor(hex: 0x4C505C),
            textPrimary: NSColor(hex: 0xE2E2E3),
            textSecondary: NSColor(hex: 0xB6B7B9),
            textMuted: NSColor(hex: 0x7F8490)
        ),
        terminalPalette: TerminalThemePalette(
            backgroundColor: NSColor(hex: 0x2A2C32),
            foregroundColor: NSColor(hex: 0xE2E2E3),
            cursorColor: NSColor(hex: 0xFC5D7C),
            selectionColor: NSColor(hex: 0x4C505C)
        )
    )

    static let builtInPresets: [WorkspaceShellTheme] = [
        .openMUXDark,
        .catppuccin,
        .gruvbox,
        .sonokai,
    ]
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
}

private extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}
