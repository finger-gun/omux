import AppKit

/// Stable accessibility identifiers for key UI elements used by XCUITest.
///
/// Set via `.accessibilityIdentifier` (AppKit) or `.accessibilityIdentifier(_:)` (SwiftUI)
/// at the view definition site.
public enum A11yID: String {
    case mainWindow = "omux.mainWindow"
    case workspaceList = "omux.workspaceList"
    case paneContainer = "omux.paneContainer"
    case commandPalette = "omux.commandPalette"
    case vaultSidebar = "omux.vaultSidebar"
    case vaultSidebarToggle = "omux.vaultSidebarToggle"

    // MARK: - Dynamic element prefixes (not used as raw values directly)
    //
    // Pane tabs use "omux.paneTab.<uuid>" — query with app.buttons.matching(NSPredicate(format: ...))
    // Command palette rows use "omux.commandPaletteRow.<index>"
    // Workspace sidebar items use "omux.workspaceItem.<uuid>"

    /// Prefix for pane tab buttons. Full ID: "omux.paneTab.<uuid>"
    static let paneTabPrefix = "omux.paneTab."
    /// Prefix for command palette result rows. Full ID: "omux.commandPaletteRow.<index>"
    static let commandPaletteRowPrefix = "omux.commandPaletteRow."
    /// Prefix for workspace sidebar item buttons. Full ID: "omux.workspaceItem.<uuid>"
    static let workspaceItemPrefix = "omux.workspaceItem."
}

public extension NSView {
    /// Convenience setter that accepts an `A11yID` value.
    func setAccessibilityIdentifier(_ id: A11yID) {
        setAccessibilityIdentifier(id.rawValue)
    }
}

public extension NSWindow {
    /// Convenience setter that accepts an `A11yID` value.
    ///
    /// Sets the identifier on the window itself (for XCUITest `app.windows.matching(identifier:)`)
    /// and also on the content view (for view-level queries within the window).
    func setAccessibilityIdentifier(_ id: A11yID) {
        setAccessibilityIdentifier(id.rawValue)
        contentView?.setAccessibilityIdentifier(id.rawValue)
    }
}
