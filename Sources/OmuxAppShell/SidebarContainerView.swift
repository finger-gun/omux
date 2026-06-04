import AppKit

/// Shared base class for sidebar container views.
///
/// Owns:
/// - Standard view configuration (`wantsLayer`, `translatesAutoresizingMaskIntoConstraints`,
///   flipped coordinate system, accessibility group role)
/// - Background color application via `apply(theme:)`
/// - A border sublayer rendered by `applyBorderLayer(theme:)`, which subclasses override
///   to position the border on the correct edge
///
/// Subclasses retain full control of content layout, widget composition, and
/// subclass-specific theme properties.
@MainActor
class SidebarContainerView: NSView {

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        setAccessibilityRole(.group)
        setAccessibilityElement(true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // Keep the accessibility element flag in sync with visibility so that
    // XCUITest's `exists` predicate returns `false` when the sidebar is hidden.
    override var isHidden: Bool {
        didSet { setAccessibilityElement(!isHidden) }
    }

    /// Apply shared sidebar theme properties (background color and border).
    /// Subclasses should call `super.apply(theme:)` first, then apply their own theming.
    func apply(theme: WorkspaceShellTheme) {
        layer?.backgroundColor = theme.shell.sidebarBackground.cgColor
        applyBorderLayer(theme: theme)
    }

    /// Draw the 1px edge separator appropriate for this sidebar's position.
    /// Subclasses MUST override this to render the border on the correct edge.
    func applyBorderLayer(theme: WorkspaceShellTheme) {
        assertionFailure("\(type(of: self)) must override applyBorderLayer(theme:)")
    }

    /// Returns the named `CALayer` sublayer used for the edge border, creating and
    /// attaching it to `layer` the first time. Subclasses use this in `applyBorderLayer`
    /// to avoid duplicating the find-or-create pattern.
    func sidebarBorderLayer(named name: String) -> CALayer {
        if let existing = layer?.sublayers?.first(where: { $0.name == name }) {
            return existing
        }
        let border = CALayer()
        border.name = name
        layer?.addSublayer(border)
        return border
    }
}
