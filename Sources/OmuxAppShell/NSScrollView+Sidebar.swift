import AppKit

extension NSScrollView {
    /// Returns a pre-configured sidebar scroll view with standard settings:
    /// no background, no border, vertical scroller with overlay style, no horizontal scroller.
    ///
    /// - Parameter documentView: The view to set as `documentView`.
    static func makeSidebarScrollView(documentView: NSView) -> NSScrollView {
        let sv = NSScrollView()
        sv.configureSidebarScrollView(documentView: documentView)
        return sv
    }

    /// Applies standard sidebar scroll view configuration in-place.
    /// Use this when the scroll view is already declared as a stored property.
    func configureSidebarScrollView(documentView: NSView) {
        translatesAutoresizingMaskIntoConstraints = false
        drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        scrollerStyle = .overlay
        self.documentView = documentView
    }
}
