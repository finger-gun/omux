import AppKit
import OmuxConfig
import OmuxControlPlane
import OmuxCore
import OmuxVault
import QuartzCore

final class PaneTabButton: NSControl, NSTextFieldDelegate {
    var onPress: (() -> Void)?
    var onDragStarted: ((PaneTabButton, NSEvent) -> Void)?
    var onDragMoved: ((PaneTabButton, NSEvent) -> Void)?
    var onDragEnded: ((PaneTabButton, NSEvent) -> Void)?
    var onDragCancelled: ((PaneTabButton) -> Void)?
    var canStartDrag: (() -> Bool)?
    var contextMenuProvider: (() -> NSMenu)? {
        didSet {
            menu = contextMenuProvider?()
        }
    }
    /// Called when the user commits a non-empty inline rename.
    var onRename: ((String) -> Void)?
    /// Called when the user commits an empty inline rename (clears alias).
    var onClearAlias: (() -> Void)?

    private var isRenaming = false
    private var originalTitle: String = ""
    private weak var previousFirstResponder: NSResponder?
    private let titleLabel = NSTextField(labelWithString: "")
    private let iconLabel = NSTextField(labelWithString: "")
    private let iconImageView = NSImageView()
    private let progressOrb = PaneProgressOrbView()
    private let closeButton = ChromePillButton()
    private let contentInsets = NSEdgeInsets(top: 0, left: 5, bottom: 0, right: 3)
    private let interItemSpacing = CGFloat(4)
    private let iconSpacing = CGFloat(4)
    private let symbolSide = CGFloat(12)
    private let showsClose: Bool
    private let currentTheme: WorkspaceShellTheme
    private var isActiveTab: Bool
    private let topBorderLayer = CALayer()
    private let renderedIcon: OmuxRenderedIcon?
    private let iconSymbolImage: NSImage?
    private let progress: PaneProgress?
    private let fullDisplayTitle: String
    var isActivePaneTab: Bool { isActiveTab }

    init(
        pane: Pane,
        active: Bool,
        theme: WorkspaceShellTheme,
        icon: OmuxRenderedIcon?,
        progress: PaneProgress?,
        showsClose: Bool,
        onClose: @escaping () -> Void
    ) {
        self.showsClose = showsClose
        self.currentTheme = theme
        self.isActiveTab = active
        self.renderedIcon = icon
        self.iconSymbolImage = icon?.symbolImage()
        self.progress = progress
        self.fullDisplayTitle = pane.displayTitle
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        topBorderLayer.zPosition = 1
        layer?.addSublayer(topBorderLayer)
        identifier = NSUserInterfaceItemIdentifier("pane-tab-\(pane.id.rawValue)")
        setAccessibilityIdentifier("\(A11yID.paneTabPrefix)\(pane.id.rawValue)")
        setAccessibilityRole(.button)
        setAccessibilityElement(true)
        setAccessibilityLabel(icon.map { "\($0.accessibilityLabel), \(fullDisplayTitle)" } ?? fullDisplayTitle)
        toolTip = fullDisplayTitle
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        progressOrb.identifier = NSUserInterfaceItemIdentifier("pane-tab-progress-\(pane.id.rawValue)")
        progressOrb.configure(progress: progress, theme: theme)
        addSubview(progressOrb)

        iconLabel.translatesAutoresizingMaskIntoConstraints = false
        iconLabel.font = icon?.font ?? .systemFont(ofSize: 11, weight: active ? .semibold : .medium)
        iconLabel.lineBreakMode = .byClipping
        iconLabel.alignment = .center
        iconLabel.stringValue = icon?.text ?? ""
        iconLabel.toolTip = icon?.accessibilityLabel
         iconLabel.textColor = icon.flatMap { theme.iconColor(for: $0, selected: active) }
            ?? (active ? theme.shell.textPrimary : theme.shell.textSecondary)
        iconLabel.isHidden = icon == nil || iconSymbolImage != nil
        addSubview(iconLabel)

        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.symbolConfiguration = .init(pointSize: 11, weight: active ? .semibold : .medium)
        iconImageView.image = iconSymbolImage
         iconImageView.contentTintColor = icon.flatMap { theme.iconColor(for: $0, selected: active) }
            ?? (active ? theme.shell.textPrimary : theme.shell.textSecondary)
        iconImageView.toolTip = icon?.accessibilityLabel
        iconImageView.isHidden = iconSymbolImage == nil
        addSubview(iconImageView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 11, weight: active ? .semibold : .medium)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.stringValue = pane.displayTitle
        titleLabel.toolTip = pane.displayTitle
         titleLabel.textColor = active ? theme.shell.textPrimary : theme.shell.textSecondary
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(titleLabel)

        if showsClose {
            closeButton.configure(
                symbolName: "xmark",
                accessibilityLabel: "Close \(fullDisplayTitle)",
                active: false,
                theme: theme,
                compact: true
            )
            closeButton.identifier = NSUserInterfaceItemIdentifier("pane-tab-close-\(pane.id.rawValue)")
            closeButton.onPress = onClose
            addSubview(closeButton)
        }

        updateVisualState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    // XCUITest determines isHittable for custom NSControl subclasses by checking
    // whether accessibilityPerformPress() is implemented. Without this override,
    // the button exists in the a11y tree but is not considered hittable by the
    // test framework — especially on headless CI runners where there is no key
    // window guarantee. Implementing this makes the element interactable for both
    // XCUITest and assistive technologies without changing first-responder behaviour.
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        onPress?()
        return true
    }

    override var isEnabled: Bool {
        didSet {
            updateVisualState()
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: ShellLayoutMetrics.paneHeaderHeight)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        topBorderLayer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 1)
        CATransaction.commit()
        let contentLeft = contentInsets.left
        let contentRight = contentInsets.right

        var titleMinX = contentLeft
        if progress != nil {
            progressOrb.frame = NSRect(
                x: contentLeft,
                y: round((bounds.height - PaneProgressOrbView.side) / 2),
                width: PaneProgressOrbView.side,
                height: PaneProgressOrbView.side
            )
            titleMinX = progressOrb.frame.maxX + iconSpacing
        } else {
            progressOrb.frame = .zero
        }

        if let renderedIcon {
            if iconSymbolImage == nil {
                let iconSize = iconLabel.intrinsicContentSize
                iconLabel.frame = NSRect(
                    x: titleMinX,
                    y: round((bounds.height - iconSize.height) / 2),
                    width: iconSize.width,
                    height: iconSize.height
                )
                iconLabel.setAccessibilityLabel(renderedIcon.accessibilityLabel)
                iconImageView.frame = .zero
                titleMinX = iconLabel.frame.maxX + iconSpacing
            } else {
                iconImageView.frame = NSRect(
                    x: titleMinX,
                    y: round((bounds.height - symbolSide) / 2),
                    width: symbolSide,
                    height: symbolSide
                )
                iconImageView.setAccessibilityLabel(renderedIcon.accessibilityLabel)
                iconLabel.frame = .zero
                titleMinX = iconImageView.frame.maxX + iconSpacing
            }
        } else {
            iconLabel.frame = .zero
            iconImageView.frame = .zero
        }

        let titleH = titleLabel.intrinsicContentSize.height
        let titleY = round((bounds.height - titleH) / 2)
        if showsClose {
            let closeSize = closeButton.intrinsicContentSize
            closeButton.frame = NSRect(
                x: bounds.width - contentRight - closeSize.width,
                y: round((bounds.height - closeSize.height) / 2),
                width: closeSize.width,
                height: closeSize.height
            )
            titleLabel.frame = NSRect(
                x: titleMinX,
                y: titleY,
                width: max(0, closeButton.frame.minX - interItemSpacing - titleMinX),
                height: titleH
            )
        } else {
            titleLabel.frame = NSRect(
                x: titleMinX,
                y: titleY,
                width: max(0, bounds.width - contentRight - titleMinX),
                height: titleH
            )
            closeButton.frame = .zero
        }
        titleLabel.lineBreakMode = .byTruncatingMiddle
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }

        // Double-click triggers rename regardless of drag capability.
        if event.clickCount == 2 {
            beginInlineRename()
            return
        }

        guard onDragStarted != nil || onDragMoved != nil || onDragEnded != nil else {
            onPress?()
            return
        }

        let initialLocation = convert(event.locationInWindow, from: nil)
        var didStartDragging = false

        // Once a drag starts, tracking must continue until mouse-up so drag cleanup always runs.
        while let nextEvent = window?.nextEvent(
            matching: [.leftMouseDragged, .leftMouseUp, .keyDown],
            until: .distantFuture,
            inMode: .eventTracking,
            dequeue: true
        ) {
            switch nextEvent.type {
            case .keyDown where nextEvent.keyCode == 53: // Escape
                if didStartDragging {
                    onDragCancelled?(self)
                }
                return

            case .leftMouseDragged:
                let location = convert(nextEvent.locationInWindow, from: nil)
                let delta = hypot(location.x - initialLocation.x, location.y - initialLocation.y)
                guard delta >= 4 else { continue }
                if !didStartDragging {
                    guard canStartDrag?() ?? true else { continue }
                    didStartDragging = true
                    onDragStarted?(self, nextEvent)
                }
                onDragMoved?(self, nextEvent)

            case .leftMouseUp:
                if didStartDragging {
                    onDragEnded?(self, nextEvent)
                } else {
                    onPress?()
                }
                return

            default:
                NSApp.postEvent(nextEvent, atStart: false)
                return
            }
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard isEnabled else {
            return
        }

        if let menu = menu ?? contextMenuProvider?() {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        } else {
            super.rightMouseDown(with: event)
        }
    }

    func beginInlineRename() {
        guard !isRenaming else { return }
        isRenaming = true
        originalTitle = fullDisplayTitle
        previousFirstResponder = window?.firstResponder
        titleLabel.isEditable = true
        titleLabel.isSelectable = true
        titleLabel.isBezeled = false
        titleLabel.focusRingType = .none
        titleLabel.drawsBackground = false
        titleLabel.delegate = self
        window?.makeFirstResponder(titleLabel)
        titleLabel.currentEditor()?.selectAll(nil)
    }

    private func commitInlineRename() {
        guard isRenaming else { return }
        let newName = titleLabel.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        endInlineRename()
        if newName.isEmpty {
            onClearAlias?()
        } else {
            onRename?(newName)
        }
    }

    private func cancelInlineRename() {
        guard isRenaming else { return }
        titleLabel.stringValue = originalTitle
        endInlineRename()
    }

    private func endInlineRename() {
        guard isRenaming else { return }
        isRenaming = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.delegate = nil
        window?.makeFirstResponder(previousFirstResponder)
        previousFirstResponder = nil
    }

    nonisolated func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        MainActor.assumeIsolated {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                commitInlineRename()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                cancelInlineRename()
                return true
            }
            return false
        }
    }

    nonisolated func controlTextDidEndEditing(_ obj: Notification) {
        MainActor.assumeIsolated {
            if isRenaming {
                commitInlineRename()
            }
        }
    }

    func setActive(_ active: Bool) {
        guard active != isActiveTab else { return }
        isActiveTab = active
        titleLabel.font = .systemFont(ofSize: 11, weight: active ? .semibold : .medium)
        updateVisualState()
    }

    private func updateVisualState() {
        titleLabel.textColor = isActiveTab ? currentTheme.shell.textPrimary : currentTheme.shell.textSecondary
        let iconColor = renderedIcon.flatMap { currentTheme.iconColor(for: $0, selected: isActiveTab) }
            ?? titleLabel.textColor
        iconLabel.textColor = iconColor
        iconImageView.contentTintColor = iconColor
        if isActiveTab {
            layer?.backgroundColor = currentTheme.shell.paneCardBackground.cgColor
            topBorderLayer.backgroundColor = currentTheme.shell.border.cgColor
            topBorderLayer.isHidden = false
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            topBorderLayer.isHidden = true
        }
        alphaValue = isEnabled ? 1.0 : 0.4
    }
}

@MainActor
class ChromePillButton: NSControl {
    var onPress: (() -> Void)?
    var contextMenuProvider: (() -> NSMenu)? {
        didSet {
            menu = contextMenuProvider?()
        }
    }
    private let titleLabel = NSTextField(labelWithString: "")
    private let imageView = NSImageView()
    private var compact = false
    private var contentInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
    private var title: String?
    private var symbolName: String?
    private var accessibilityLabel: String?
    private var isActive = false
    private var isHovered = false
    private var currentTheme = WorkspaceShellTheme.defaultTheme
    private var hoverTrackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.masksToBounds = true

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.symbolConfiguration = .init(pointSize: 11, weight: .medium)
        imageView.isHidden = true
        addSubview(imageView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.alignment = .center
        addSubview(titleLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func configure(title: String, active: Bool, theme: WorkspaceShellTheme, compact: Bool = false) {
        self.title = title
        symbolName = nil
        accessibilityLabel = title
        setAccessibilityLabel(title)
        imageView.isHidden = true
        titleLabel.isHidden = false
        titleLabel.stringValue = title
        applyConfiguration(active: active, theme: theme, compact: compact)
    }

    func configure(
        symbolName: String,
        accessibilityLabel: String,
        active: Bool,
        theme: WorkspaceShellTheme,
        compact: Bool = false
    ) {
        title = nil
        self.symbolName = symbolName
        self.accessibilityLabel = accessibilityLabel
        setAccessibilityLabel(accessibilityLabel)
        titleLabel.isHidden = true
        imageView.isHidden = false
        imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityLabel)
        applyConfiguration(active: active, theme: theme, compact: compact)
    }

    func applyTheme(_ theme: WorkspaceShellTheme) {
        applyConfiguration(active: isActive, theme: theme, compact: compact)
    }

    override var isEnabled: Bool {
        didSet {
            updateVisualState()
        }
    }

    private func applyConfiguration(active: Bool, theme: WorkspaceShellTheme, compact: Bool) {
        self.compact = compact
        isActive = active
        currentTheme = theme
        self.compact = compact
        contentInsets = NSEdgeInsets(top: compact ? 2 : 4, left: compact ? 6 : 8, bottom: compact ? 2 : 4, right: compact ? 6 : 8)
        titleLabel.font = .systemFont(ofSize: compact ? 11 : 12, weight: active ? .semibold : .medium)
        layer?.cornerRadius = compact ? 3 : 4
        imageView.symbolConfiguration = .init(pointSize: compact ? 11 : 12, weight: active ? .semibold : .medium)
        updateVisualState()
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    private func updateVisualState() {
        let foreground = isActive ? currentTheme.shell.selectedText : currentTheme.shell.textSecondary
        titleLabel.textColor = foreground
        imageView.contentTintColor = foreground
        let background: NSColor
        if isActive {
            background = currentTheme.shell.selection
        } else if isHovered {
            background = NSColor.labelColor.withAlphaComponent(0.15)
        } else {
            background = .clear
        }
        layer?.backgroundColor = background.cgColor
        layer?.borderWidth = 0
        layer?.borderColor = nil
        alphaValue = isEnabled ? 1 : 0.4
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        replaceTrackingArea(&hoverTrackingArea, options: [.mouseEnteredAndExited, .activeAlways])
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if newSize == .zero {
            isHovered = false
            updateVisualState()
        }
        updateTrackingAreas()
        window?.invalidateCursorRects(for: self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateVisualState()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateVisualState()
    }

    override var intrinsicContentSize: NSSize {
        let contentSize: NSSize
        if let title {
            titleLabel.stringValue = title
            contentSize = titleLabel.intrinsicContentSize
        } else {
            let symbolSide = compact ? CGFloat(11) : CGFloat(12)
            contentSize = NSSize(width: symbolSide, height: symbolSide)
        }
        return NSSize(
            width: contentSize.width + contentInsets.left + contentInsets.right,
            height: max(contentSize.height + contentInsets.top + contentInsets.bottom, compact ? 18 : 24)
        )
    }

    override func layout() {
        super.layout()
        updateTrackingAreas()
        let contentBounds = bounds.insetBy(dx: contentInsets.left, dy: contentInsets.top)
        if title == nil {
            let symbolSide = compact ? CGFloat(11) : CGFloat(12)
            imageView.frame = NSRect(
                x: round((bounds.width - symbolSide) / 2),
                y: round((bounds.height - symbolSide) / 2),
                width: symbolSide,
                height: symbolSide
            )
            titleLabel.frame = .zero
        } else {
            titleLabel.frame = contentBounds
            imageView.frame = .zero
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else {
            return
        }

        onPress?()
    }

    override func rightMouseDown(with event: NSEvent) {
        guard isEnabled else {
            return
        }

        if let menu = menu ?? contextMenuProvider?() {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        } else {
            super.rightMouseDown(with: event)
        }
    }

}

@MainActor
final class SidebarItemButton: NSView, NSTextFieldDelegate {
    var onPress: (() -> Void)?
    var onToggleExpansion: (() -> Void)?
    var onRename: ((String) -> Void)?
    var onBeginRename: (() -> Void)?
    var workspaceID: WorkspaceID?
    var onDragStarted: ((SidebarItemButton, NSEvent) -> Void)?
    var onDragMoved: ((SidebarItemButton, NSEvent) -> Void)?
    var onDragEnded: ((SidebarItemButton, NSEvent) -> Void)?
    var contextMenuProvider: (() -> NSMenu?)? {
        didSet {
            menu = contextMenuProvider?()
        }
    }
    private let titleField = NSTextField(labelWithString: "")
    private let subtitleField = NSTextField(labelWithString: "")
    private let detailField = NSTextField(labelWithString: "")
    private let disclosureImageView = NSImageView()
    private let iconField = NSTextField(labelWithString: "")
    private let iconImageView = NSImageView()
    private let progressOrb = PaneProgressOrbView()
    private var leadingInset: CGFloat = 12
    private var textLeadingInset: CGFloat = 12
    private var renderedIcon: OmuxRenderedIcon?
    private var iconSymbolImage: NSImage?
    private var iconSide = CGFloat(13)
    private var progress: PaneProgress?
    private var showsDisclosure = false
    private var isActive = false
    private var isRenaming = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        progressOrb.identifier = NSUserInterfaceItemIdentifier("sidebar-pane-progress")
        addSubview(progressOrb)

        disclosureImageView.isHidden = true
        addSubview(disclosureImageView)

        titleField.maximumNumberOfLines = 1
        titleField.lineBreakMode = .byTruncatingTail
        titleField.isBezeled = false
        titleField.drawsBackground = false
        titleField.isEditable = false
        titleField.isSelectable = false
        addSubview(titleField)

        iconField.maximumNumberOfLines = 1
        iconField.lineBreakMode = .byClipping
        iconField.alignment = .center
        iconField.isBezeled = false
        iconField.drawsBackground = false
        iconField.isEditable = false
        iconField.isSelectable = false
        addSubview(iconField)

        iconImageView.isHidden = true
        addSubview(iconImageView)

        subtitleField.maximumNumberOfLines = 1
        subtitleField.lineBreakMode = .byTruncatingMiddle
        subtitleField.isBezeled = false
        subtitleField.drawsBackground = false
        subtitleField.isEditable = false
        subtitleField.isSelectable = false
        addSubview(subtitleField)

        detailField.maximumNumberOfLines = 1
        detailField.lineBreakMode = .byTruncatingMiddle
        detailField.isBezeled = false
        detailField.drawsBackground = false
        detailField.isEditable = false
        detailField.isSelectable = false
        addSubview(detailField)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func configure(item: SidebarItem, theme: WorkspaceShellTheme) {
        switch item.kind {
        case .workspace:
            titleField.font = .systemFont(ofSize: 13, weight: .semibold)
            leadingInset = 6
            subtitleField.font = .systemFont(ofSize: 11, weight: .regular)
            subtitleField.maximumNumberOfLines = 1
            subtitleField.lineBreakMode = .byTruncatingMiddle
            detailField.font = .systemFont(ofSize: 10, weight: .regular)
            titleField.lineBreakMode = .byTruncatingTail
        case .terminal:
            titleField.font = .systemFont(ofSize: 10, weight: .regular)
            titleField.lineBreakMode = .byTruncatingMiddle
            subtitleField.font = .systemFont(ofSize: 10, weight: .regular)
            subtitleField.maximumNumberOfLines = 1
            subtitleField.lineBreakMode = .byTruncatingMiddle
            detailField.font = .systemFont(ofSize: 10, weight: .regular)
            leadingInset = 22
        }

        titleField.stringValue = item.title
        isActive = item.isActive
        progress = item.progress
        progressOrb.configure(progress: item.progress, theme: theme)
        renderedIcon = item.icon
        iconSymbolImage = item.icon?.symbolImage()
        iconSide = item.kind == .workspace ? 13 : 11
        showsDisclosure = item.kind == .workspace && item.isExpanded != nil
        let disclosureSymbol = item.isExpanded == false ? "chevron.right" : "chevron.down"
        disclosureImageView.symbolConfiguration = .init(pointSize: 9, weight: .semibold)
        disclosureImageView.image = NSImage(systemSymbolName: disclosureSymbol, accessibilityDescription: nil)
        disclosureImageView.isHidden = !showsDisclosure
        disclosureImageView.setAccessibilityLabel(item.isExpanded == false ? "Expand workspace panes" : "Collapse workspace panes")
        iconField.stringValue = item.icon?.text ?? ""
        iconField.font = item.icon?.font ?? .systemFont(ofSize: item.kind == .workspace ? 13 : 11, weight: .medium)
        iconField.isHidden = item.icon == nil || iconSymbolImage != nil
        iconField.toolTip = item.icon?.accessibilityLabel
        iconImageView.symbolConfiguration = .init(pointSize: iconSide, weight: item.kind == .workspace ? .semibold : .medium)
        iconImageView.image = iconSymbolImage
        iconImageView.isHidden = iconSymbolImage == nil
        iconImageView.toolTip = item.icon?.accessibilityLabel
        setAccessibilityLabel(item.icon.map { "\($0.accessibilityLabel), \(item.title)" } ?? item.title)
        if item.kind == .workspace {
            setAccessibilityIdentifier("\(A11yID.workspaceItemPrefix)\(item.identifier)")
            setAccessibilityRole(.button)
            setAccessibilityElement(true)
        }
        titleField.textColor = item.kind == .terminal
            ? theme.shell.textMuted
            : (item.isActive ? theme.shell.selectedText : theme.shell.textSecondary)
        let iconColor = item.icon.map {
            theme.iconColor(
                for: $0,
                selected: item.isActive,
                fallback: titleField.textColor ?? theme.shell.textSecondary
            )
        } ?? titleField.textColor
        iconField.textColor = iconColor
        iconImageView.contentTintColor = iconColor
        disclosureImageView.contentTintColor = item.isActive ? theme.shell.selectedText : theme.shell.textMuted
        subtitleField.stringValue = item.subtitle ?? ""
        subtitleField.textColor = theme.shell.textMuted
        if let subtitle = item.subtitle {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = subtitleField.lineBreakMode
            let attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: theme.shell.textMuted,
                .font: subtitleField.font as Any,
                .paragraphStyle: paragraphStyle,
            ]
            let attributed = NSMutableAttributedString(string: subtitle, attributes: attributes)
            if let accentLength = item.subtitleAccentPrefixLength,
               accentLength > 0,
               accentLength <= subtitle.utf16.count {
                attributed.addAttribute(
                    .foregroundColor,
                    value: theme.shell.accent,
                    range: NSRange(location: 0, length: accentLength)
                )
            }
            subtitleField.attributedStringValue = attributed
        } else {
            subtitleField.attributedStringValue = NSAttributedString(string: "")
        }
        subtitleField.toolTip = item.subtitle
        subtitleField.isHidden = item.subtitle == nil
        detailField.stringValue = item.detail ?? ""
        detailField.textColor = theme.shell.textMuted.withAlphaComponent(0.85)
        detailField.isHidden = item.detail == nil
        switch item.kind {
        case .workspace:
            layer?.backgroundColor = item.isActive
                ? theme.shell.selection.cgColor
                : NSColor.clear.cgColor
            layer?.cornerRadius = 3
        case .terminal:
            layer?.backgroundColor = item.isActive
                ? theme.shell.selection.withAlphaComponent(0.28).cgColor
                : NSColor.clear.cgColor
            layer?.cornerRadius = 3
        }
        layer?.borderWidth = 0
        layer?.borderColor = nil
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let trailingInset: CGFloat = 12
        let iconSpacing: CGFloat = renderedIcon == nil ? 0 : 6
        var textX = leadingInset
        if progress != nil {
            let progressX = max(0, leadingInset - PaneProgressOrbView.side - 5)
            progressOrb.frame = NSRect(
                x: progressX,
                y: round((bounds.height - PaneProgressOrbView.side) / 2),
                width: PaneProgressOrbView.side,
                height: PaneProgressOrbView.side
            )
        } else {
            progressOrb.frame = .zero
        }
        if showsDisclosure {
            let disclosureSide: CGFloat = 11
            disclosureImageView.frame = NSRect(
                x: textX,
                y: round((bounds.height - disclosureSide) / 2),
                width: disclosureSide,
                height: disclosureSide
            )
            textX = disclosureImageView.frame.maxX + 4
        } else {
            disclosureImageView.frame = .zero
        }
        if let renderedIcon {
            if iconSymbolImage == nil {
                let iconSize = iconField.intrinsicContentSize
                iconField.frame = NSRect(
                    x: textX,
                    y: round((bounds.height - iconSize.height) / 2),
                    width: iconSize.width,
                    height: iconSize.height
                )
                iconField.setAccessibilityLabel(renderedIcon.accessibilityLabel)
                iconImageView.frame = .zero
                textX = iconField.frame.maxX + iconSpacing
            } else {
                iconImageView.frame = NSRect(
                    x: textX,
                    y: round((bounds.height - iconSide) / 2),
                    width: iconSide,
                    height: iconSide
                )
                iconImageView.setAccessibilityLabel(renderedIcon.accessibilityLabel)
                iconField.frame = .zero
                textX = iconImageView.frame.maxX + iconSpacing
            }
        } else {
            iconField.frame = .zero
            iconImageView.frame = .zero
        }
        textLeadingInset = textX
        let labelWidth = bounds.width - textLeadingInset - trailingInset
        let titleHeight = titleField.intrinsicContentSize.height
        if subtitleField.isHidden {
            titleField.frame = NSRect(
                x: textLeadingInset,
                y: (bounds.height - titleHeight) / 2,
                width: max(labelWidth, 0),
                height: titleHeight
            )
            subtitleField.frame = .zero
            detailField.frame = .zero
        } else if detailField.isHidden == false {
            let subtitleHeight = subtitleField.intrinsicContentSize.height
            let detailHeight = detailField.intrinsicContentSize.height
            let totalHeight = titleHeight + subtitleHeight + detailHeight + 2
            let startY = (bounds.height - totalHeight) / 2
            titleField.frame = NSRect(
                x: textLeadingInset,
                y: startY + subtitleHeight + detailHeight + 2,
                width: max(labelWidth, 0),
                height: titleHeight
            )
            subtitleField.frame = NSRect(
                x: textLeadingInset,
                y: startY + detailHeight,
                width: max(labelWidth, 0),
                height: subtitleHeight
            )
            detailField.frame = NSRect(
                x: textLeadingInset,
                y: startY,
                width: max(labelWidth, 0),
                height: detailHeight
            )
        } else {
            let subtitleHeight = subtitleField.intrinsicContentSize.height
            let totalHeight = titleHeight + subtitleHeight + 2
            let startY = (bounds.height - totalHeight) / 2
            titleField.frame = NSRect(
                x: textLeadingInset,
                y: startY + subtitleHeight + 2,
                width: max(labelWidth, 0),
                height: titleHeight
            )
            subtitleField.frame = NSRect(
                x: textLeadingInset,
                y: startY,
                width: max(labelWidth, 0),
                height: subtitleHeight
            )
            detailField.frame = .zero
        }
    }

    override var acceptsFirstResponder: Bool { isRenaming }
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        if showsDisclosure,
           disclosureImageView.frame.insetBy(dx: -5, dy: -5).contains(convert(event.locationInWindow, from: nil)) {
            onToggleExpansion?()
            return
        }

        guard onDragStarted != nil || onDragMoved != nil || onDragEnded != nil else {
            if event.clickCount == 2, onRename != nil {
                onBeginRename?()
            } else {
                onPress?()
            }
            return
        }

        let initialLocation = convert(event.locationInWindow, from: nil)
        var didStartDragging = false

        while let nextEvent = window?.nextEvent(
            matching: [.leftMouseDragged, .leftMouseUp, .leftMouseDown],
            until: .distantFuture,
            inMode: .eventTracking,
            dequeue: true
        ) {
            switch nextEvent.type {
            case .leftMouseDown:
                if nextEvent.clickCount == 2, onRename != nil {
                    onBeginRename?()
                }
                return

            case .leftMouseDragged:
                let location = convert(nextEvent.locationInWindow, from: nil)
                let delta = hypot(location.x - initialLocation.x, location.y - initialLocation.y)
                guard delta >= 4 else {
                    continue
                }

                if didStartDragging == false {
                    didStartDragging = true
                    onDragStarted?(self, nextEvent)
                }
                onDragMoved?(self, nextEvent)

            case .leftMouseUp:
                if didStartDragging {
                    onDragEnded?(self, nextEvent)
                    return
                }
                // Only wait for a possible double-click if this workspace is already active.
                // If it's inactive, fire onPress immediately — no delay on workspace switching.
                if onRename != nil, isActive {
                    let doubleClickInterval = NSEvent.doubleClickInterval
                    if let secondClick = window?.nextEvent(
                        matching: [.leftMouseDown],
                        until: Date(timeIntervalSinceNow: doubleClickInterval),
                        inMode: .eventTracking,
                        dequeue: true
                    ) {
                        if secondClick.clickCount == 2 {
                            onBeginRename?()
                        } else {
                            onPress?()
                            NSApp.postEvent(secondClick, atStart: true)
                        }
                    } else {
                        onPress?()
                    }
                    return
                }
                onPress?()
                return

            default:
                return
            }
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        if let menu = menu ?? contextMenuProvider?() {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        } else {
            super.rightMouseDown(with: event)
        }
    }

    func beginInlineRename() {
        guard !isRenaming else { return }
        isRenaming = true

        titleField.isEditable = true
        titleField.isSelectable = true
        titleField.isBezeled = false
        titleField.focusRingType = .none
        titleField.drawsBackground = false
        titleField.delegate = self
        window?.makeFirstResponder(titleField)
        titleField.currentEditor()?.selectAll(nil)
    }

    private func commitInlineRename() {
        guard isRenaming else { return }
        let newName = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        endInlineRename()
        if !newName.isEmpty {
            onRename?(newName)
        }
    }

    private func cancelInlineRename() {
        endInlineRename()
    }

    private func endInlineRename() {
        guard isRenaming else { return }
        isRenaming = false
        titleField.isEditable = false
        titleField.isSelectable = false
        titleField.delegate = nil
        window?.makeFirstResponder(nil)
    }

    func setDropTarget(_ isDropTarget: Bool, theme: WorkspaceShellTheme?) {
        guard let theme else {
            return
        }
        layer?.borderWidth = isDropTarget ? 1 : 0
        layer?.borderColor = isDropTarget ? theme.shell.selection.cgColor : nil
    }

    nonisolated func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        MainActor.assumeIsolated {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                commitInlineRename()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                cancelInlineRename()
                return true
            }
            return false
        }
    }

    nonisolated func controlTextDidEndEditing(_ obj: Notification) {
        MainActor.assumeIsolated {
            // only commit if we initiated this — avoids acting on unrelated end-editing events
            if isRenaming {
                commitInlineRename()
            }
        }
    }

    func setDraggingPreview(_ isDragging: Bool, theme: WorkspaceShellTheme?) {
        layer?.shadowOpacity = isDragging ? 0.18 : 0
        layer?.shadowRadius = isDragging ? 8 : 0
        layer?.shadowOffset = isDragging ? CGSize(width: 0, height: -2) : .zero
        layer?.shadowColor = theme?.shell.selection.cgColor
    }
}

@MainActor
final class MenuActionTrampoline: NSObject {
    let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func performAction(_ sender: Any?) {
        _ = sender
        handler()
    }
}

extension NSMenuItem {
    @discardableResult
    @MainActor
    func onSelect(_ handler: @escaping () -> Void) -> NSMenuItem {
        let trampoline = MenuActionTrampoline(handler: handler)
        target = trampoline
        action = #selector(MenuActionTrampoline.performAction(_:))
        representedObject = trampoline
        return self
    }
}
