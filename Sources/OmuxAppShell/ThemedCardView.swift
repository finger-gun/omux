import AppKit

/// A base `NSView` subclass that applies a standard card appearance:
/// rounded corners, a border, and theme-driven background and border colours.
///
/// Subclasses call `applyCardTheme(_:)` from their own `apply(theme:)` method
/// to update the layer colours without duplicating the property assignments.
class ThemedCardView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        setAccessibilityRole(.group)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// Apply the card background and border colour from `theme`.
    /// Call this from subclass `apply(theme:)` implementations.
    func applyCardTheme(_ theme: WorkspaceShellTheme) {
        layer?.backgroundColor = theme.shell.paneCardBackground.cgColor
        layer?.borderColor = theme.shell.subduedBorder.cgColor
    }
}
