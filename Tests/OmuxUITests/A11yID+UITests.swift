/// Mirrors `A11yID` from `OmuxAppShell`.
///
/// XCUITest targets run in a separate process and cannot import the app's modules.
/// The raw string values here must stay in sync with `Sources/OmuxAppShell/A11yID.swift`.
enum A11yID: String {
    case mainWindow = "omux.mainWindow"
    case workspaceList = "omux.workspaceList"
    case paneContainer = "omux.paneContainer"
    case commandPalette = "omux.commandPalette"
}

// MARK: - Dynamic element identifier prefixes

extension A11yID {
    /// Prefix for pane tab buttons. Full ID: "omux.paneTab.<uuid>"
    static let paneTabPrefix = "omux.paneTab."
    /// Prefix for command palette result rows. Full ID: "omux.commandPaletteRow.<index>"
    static let commandPaletteRowPrefix = "omux.commandPaletteRow."
    /// Prefix for workspace sidebar item buttons. Full ID: "omux.workspaceItem.<uuid>"
    static let workspaceItemPrefix = "omux.workspaceItem."
}
