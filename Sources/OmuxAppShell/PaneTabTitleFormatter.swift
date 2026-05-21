/// Formats pane tab titles for display, truncating long titles with middle ellipsis.
enum PaneTabTitleFormatter {
    static let defaultMaximumLength = 32

    /// Returns a display-safe version of `title`, truncating with middle ellipsis if it exceeds `maximumLength`.
    static func displayTitle(_ title: String, maximumLength: Int = defaultMaximumLength) -> String {
        guard title.count > maximumLength else { return title }

        let available = maximumLength - 3  // subtract "..."
        let suffixLength = (available + 1) / 2  // ceil
        let prefixLength = available - suffixLength

        let prefix = title.prefix(prefixLength)
        let suffix = title.suffix(suffixLength)
        return "\(prefix)...\(suffix)"
    }
}
