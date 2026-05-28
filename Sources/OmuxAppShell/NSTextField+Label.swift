import AppKit

extension NSTextField {
    /// Returns a non-editable, non-selectable label with `translatesAutoresizingMaskIntoConstraints`
    /// set to `false`, an optional initial string, font size, and weight.
    ///
    /// - Parameters:
    ///   - text: Initial string value. Defaults to empty string.
    ///   - fontSize: Point size for the system font. Defaults to `12`.
    ///   - weight: Font weight. Defaults to `.regular`.
    ///   - maxLines: Maximum number of lines (`0` = unlimited). Defaults to `1`.
    static func label(
        _ text: String = "",
        fontSize: CGFloat = 12,
        weight: NSFont.Weight = .regular,
        maxLines: Int = 1
    ) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.font = .systemFont(ofSize: fontSize, weight: weight)
        if maxLines != 1 {
            field.maximumNumberOfLines = maxLines
        }
        return field
    }
}
