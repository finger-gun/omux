import AppKit

final class SidebarScroller: NSScroller {
    var sidebarBackgroundColor: NSColor = .clear
    var knobColor: NSColor = .tertiaryLabelColor

    override var floatValue: Float {
        didSet {
            needsDisplay = true
        }
    }

    override var knobProportion: CGFloat {
        didSet {
            needsDisplay = true
        }
    }

    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat {
        let defaultWidth = super.scrollerWidth(for: controlSize, scrollerStyle: scrollerStyle)
        switch scrollerStyle {
        case .legacy:
            return max(7, defaultWidth - 8)
        case .overlay:
            return defaultWidth
        @unknown default:
            return defaultWidth
        }
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        sidebarBackgroundColor.setFill()
        bounds.fill()
    }

    override func drawKnob() {
        let knobRect = rect(for: .knob)
        guard knobRect.isEmpty == false else { return }

        let desiredWidth = max(5, bounds.width - 7)
        let indicatorRect = NSRect(
            x: bounds.midX - (desiredWidth / 2),
            y: knobRect.minY + 2,
            width: desiredWidth,
            height: max(0, knobRect.height - 4)
        )
        guard indicatorRect.isEmpty == false else { return }

        knobColor.setFill()
        NSBezierPath(
            roundedRect: indicatorRect,
            xRadius: indicatorRect.width / 2,
            yRadius: indicatorRect.width / 2
        ).fill()
    }
}

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
        if verticalScroller is SidebarScroller == false {
            verticalScroller = SidebarScroller()
        }
        self.documentView = documentView
    }

    func applySidebarScrollerTheme(_ theme: WorkspaceShellTheme) {
        let isDarkSidebar = theme.shell.sidebarBackground.omuxIsDark
        let appearanceName: NSAppearance.Name = isDarkSidebar ? .darkAqua : .aqua
        appearance = NSAppearance(named: appearanceName)
        scrollerKnobStyle = isDarkSidebar ? .light : .dark
        verticalScroller?.knobStyle = isDarkSidebar ? .light : .dark
        if let scroller = verticalScroller as? SidebarScroller {
            scroller.sidebarBackgroundColor = theme.shell.sidebarBackground
            scroller.knobColor = theme.shell.textMuted.withAlphaComponent(isDarkSidebar ? 0.55 : 0.4)
            scroller.needsDisplay = true
        }
    }
}

private extension NSColor {
    var omuxIsDark: Bool {
        let color = usingColorSpace(.sRGB) ?? usingColorSpace(.deviceRGB) ?? self
        let luminance = 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
        return luminance < 0.5
    }
}
