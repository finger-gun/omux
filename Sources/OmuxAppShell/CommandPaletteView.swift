import AppKit
import OmuxCore

@MainActor
final class CommandPaletteView: NSView, NSTextFieldDelegate {
    var resultProvider: ((String) -> [CommandPaletteResult])?
    var invokeResult: ((CommandPaletteResult) -> CommandPaletteInvocationResult)?
    var dismissHandler: (() -> Void)?

    private var currentTheme: WorkspaceShellTheme = .defaultTheme

    private let panel = NSView()
    private let searchRow = NSView()
    private let searchIcon = NSImageView()
    private let searchField = CommandPaletteSearchField()
    private let searchSeparator = NSView()
    private let sectionHeader = NSView()
    private let sectionLabel = NSTextField(labelWithString: "")
    private let sectionHeaderBorder = NSView()
    private let resultStack = NSStackView()
    private let scrollView = NSScrollView()
    private var results: [CommandPaletteResult] = []
    private var selectedIndex: Int = 0
    private var focusRestoreResponder: NSResponder?

    // MARK: - Layout constants
    private enum Layout {
        static let panelWidth: CGFloat = 540
        static let cornerRadius: CGFloat = 14
        static let searchRowHeight: CGFloat = 52
        static let searchIconSize: CGFloat = 16
        static let sectionLabelHeight: CGFloat = 28
        static let horizontalPadding: CGFloat = 16
        static let verticalOffsetFromCenter: CGFloat = -60
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        panel.wantsLayer = true
        panel.layer?.cornerRadius = Layout.cornerRadius
        panel.layer?.masksToBounds = true
        panel.translatesAutoresizingMaskIntoConstraints = false

        // Shadow
        panel.shadow = NSShadow()
        panel.layer?.shadowColor = NSColor.black.withAlphaComponent(0.5).cgColor
        panel.layer?.shadowOpacity = 1
        panel.layer?.shadowRadius = 24
        panel.layer?.shadowOffset = CGSize(width: 0, height: -8)

        searchRow.translatesAutoresizingMaskIntoConstraints = false

        let cfg = NSImage.SymbolConfiguration(pointSize: Layout.searchIconSize, weight: .regular)
        searchIcon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)
        searchIcon.contentTintColor = .secondaryLabelColor
        searchIcon.translatesAutoresizingMaskIntoConstraints = false
        searchIcon.setContentHuggingPriority(.required, for: .horizontal)

        searchField.font = .systemFont(ofSize: 15, weight: .regular)
        searchField.isBordered = false
        searchField.focusRingType = .none
        searchField.backgroundColor = .clear
        searchField.delegate = self
        searchField.commandHandler = { [weak self] cmd in self?.handle(cmd) }
        searchField.translatesAutoresizingMaskIntoConstraints = false

        searchSeparator.wantsLayer = true
        searchSeparator.translatesAutoresizingMaskIntoConstraints = false

        sectionHeader.wantsLayer = true
        sectionHeader.translatesAutoresizingMaskIntoConstraints = false

        sectionLabel.font = .systemFont(ofSize: 11, weight: .medium)
        sectionLabel.translatesAutoresizingMaskIntoConstraints = false

        sectionHeaderBorder.wantsLayer = true
        sectionHeaderBorder.translatesAutoresizingMaskIntoConstraints = false

        resultStack.orientation = .vertical
        resultStack.alignment = .leading
        resultStack.spacing = 2
        resultStack.translatesAutoresizingMaskIntoConstraints = false
        resultStack.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 8, right: 0)

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = resultStack

        // Assemble search row
        searchRow.addSubview(searchIcon)
        searchRow.addSubview(searchField)

        addSubview(panel)
        panel.addSubview(searchRow)
        panel.addSubview(searchSeparator)
        panel.addSubview(sectionHeader)
        sectionHeader.addSubview(sectionLabel)
        sectionHeader.addSubview(sectionHeaderBorder)
        panel.addSubview(scrollView)

        let bottomCap = panel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -80)
        bottomCap.priority = .required

        NSLayoutConstraint.activate([
            // Panel: top-anchored, centered horizontally
            panel.topAnchor.constraint(equalTo: topAnchor, constant: 80),
            panel.centerXAnchor.constraint(equalTo: centerXAnchor),
            panel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -48),
            panel.widthAnchor.constraint(equalToConstant: Layout.panelWidth),
            bottomCap,

            // Search row
            searchRow.topAnchor.constraint(equalTo: panel.topAnchor),
            searchRow.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            searchRow.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            searchRow.heightAnchor.constraint(equalToConstant: Layout.searchRowHeight),

            searchIcon.leadingAnchor.constraint(equalTo: searchRow.leadingAnchor, constant: Layout.horizontalPadding),
            searchIcon.centerYAnchor.constraint(equalTo: searchRow.centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: Layout.searchIconSize),
            searchIcon.heightAnchor.constraint(equalToConstant: Layout.searchIconSize),

            searchField.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: searchRow.trailingAnchor, constant: -Layout.horizontalPadding),
            searchField.centerYAnchor.constraint(equalTo: searchRow.centerYAnchor),

            // Separator
            searchSeparator.topAnchor.constraint(equalTo: searchRow.bottomAnchor),
            searchSeparator.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            searchSeparator.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            searchSeparator.heightAnchor.constraint(equalToConstant: 1),

            // Section header
            sectionHeader.topAnchor.constraint(equalTo: searchSeparator.bottomAnchor),
            sectionHeader.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            sectionHeader.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            sectionHeader.heightAnchor.constraint(equalToConstant: Layout.sectionLabelHeight),

            sectionLabel.leadingAnchor.constraint(equalTo: sectionHeader.leadingAnchor, constant: Layout.horizontalPadding),
            sectionLabel.trailingAnchor.constraint(equalTo: sectionHeader.trailingAnchor, constant: -Layout.horizontalPadding),
            sectionLabel.centerYAnchor.constraint(equalTo: sectionHeader.centerYAnchor),

            sectionHeaderBorder.leadingAnchor.constraint(equalTo: sectionHeader.leadingAnchor),
            sectionHeaderBorder.trailingAnchor.constraint(equalTo: sectionHeader.trailingAnchor),
            sectionHeaderBorder.bottomAnchor.constraint(equalTo: sectionHeader.bottomAnchor),
            sectionHeaderBorder.heightAnchor.constraint(equalToConstant: 1),

            // Scroll view
            scrollView.topAnchor.constraint(equalTo: sectionHeader.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: panel.bottomAnchor),

            resultStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            scrollView.heightAnchor.constraint(lessThanOrEqualTo: resultStack.heightAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    func present(initialQuery: String, restoring responder: NSResponder?) {
        focusRestoreResponder = responder
        searchField.stringValue = initialQuery
        isHidden = false
        refreshResults()
        window?.makeFirstResponder(searchField)
        searchField.currentEditor()?.selectedRange = NSRange(location: initialQuery.count, length: 0)
    }

    func dismissAndRestoreFocus() {
        removeFromSuperview()
        if let focusRestoreResponder {
            window?.makeFirstResponder(focusRestoreResponder)
        }
        dismissHandler?()
    }

    func apply(theme: WorkspaceShellTheme) {
        currentTheme = theme
        let colors = theme.shell
        layer?.backgroundColor = NSColor.clear.cgColor
        panel.layer?.backgroundColor = colors.paneCardBackground.cgColor
        searchSeparator.layer?.backgroundColor = colors.border.cgColor
        sectionHeader.layer?.backgroundColor = colors.windowBackground.cgColor
        sectionHeaderBorder.layer?.backgroundColor = colors.border.cgColor
        searchIcon.contentTintColor = colors.textMuted
        searchField.textColor = colors.textPrimary
        searchField.placeholderAttributedString = NSAttributedString(
            string: "Search commands or workspaces…",
            attributes: [
                .foregroundColor: colors.textMuted,
                .font: NSFont.systemFont(ofSize: 15, weight: .regular),
            ]
        )
        sectionLabel.textColor = colors.textMuted
        for row in resultStack.arrangedSubviews.compactMap({ $0 as? CommandPaletteResultRow }) {
            row.apply(theme: theme)
        }
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ notification: Notification) {
        _ = notification
        refreshResults()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.cancelOperation(_:)):
            if textView.hasMarkedText() { return false }
            dismissAndRestoreFocus()
            return true
        case #selector(NSResponder.moveUp(_:)):
            handle(.moveUp)
            return true
        case #selector(NSResponder.moveDown(_:)):
            handle(.moveDown)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            handle(.submit)
            return true
        default:
            return false
        }
    }

    // MARK: - Results

    private func refreshResults() {
        results = resultProvider?(searchField.stringValue) ?? []
        selectedIndex = min(selectedIndex, max(results.count - 1, 0))
        renderResults()
    }

    private func renderResults() {
        resultStack.arrangedSubviews.forEach { v in
            resultStack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }

        let parsed = CommandPaletteParsedQuery(rawText: searchField.stringValue)
        switch parsed.mode {
        case .command:
            sectionLabel.stringValue = "Commands"
        case .workspace:
            sectionLabel.stringValue = searchField.stringValue.isEmpty ? "Workspaces" : "Results"
        }

        guard results.isEmpty == false else {
            let label = NSTextField(labelWithString: "No results")
            label.textColor = currentTheme.shell.textMuted
            label.font = .systemFont(ofSize: 13)
            label.translatesAutoresizingMaskIntoConstraints = false
            let wrapper = NSView()
            wrapper.translatesAutoresizingMaskIntoConstraints = false
            wrapper.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: Layout.horizontalPadding),
                label.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
                wrapper.heightAnchor.constraint(equalToConstant: 36),
            ])
            resultStack.addArrangedSubview(wrapper)
            wrapper.widthAnchor.constraint(equalTo: resultStack.widthAnchor).isActive = true
            return
        }

        for (index, result) in results.enumerated() {
            let row = CommandPaletteResultRow(result: result, isSelected: index == selectedIndex, theme: currentTheme)
            row.target = self
            row.action = #selector(resultRowClicked(_:))
            row.tag = index
            resultStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: resultStack.widthAnchor).isActive = true
        }

        if results.indices.contains(selectedIndex) {
            let row = resultStack.arrangedSubviews[selectedIndex]
            DispatchQueue.main.async { row.scrollToVisible(row.bounds) }
        }
    }

    private func updateSelection(to newIndex: Int) {
        guard newIndex != selectedIndex else { return }
        let oldIndex = selectedIndex
        selectedIndex = newIndex
        if let old = resultStack.arrangedSubviews[safe: oldIndex] as? CommandPaletteResultRow {
            old.setSelected(false, theme: currentTheme)
        }
        if let new = resultStack.arrangedSubviews[safe: newIndex] as? CommandPaletteResultRow {
            new.setSelected(true, theme: currentTheme)
            DispatchQueue.main.async { new.scrollToVisible(new.bounds) }
        }
    }

    @objc private func resultRowClicked(_ sender: CommandPaletteResultRow) {
        selectedIndex = sender.tag
        invokeSelectedResult()
    }

    private func handle(_ command: CommandPaletteSearchField.Command) {
        switch command {
        case .moveUp:
            guard results.isEmpty == false else { return }
            updateSelection(to: max(selectedIndex - 1, 0))
        case .moveDown:
            guard results.isEmpty == false else { return }
            updateSelection(to: min(selectedIndex + 1, results.count - 1))
        case .submit:
            invokeSelectedResult()
        case .dismiss:
            dismissAndRestoreFocus()
        }
    }

    private func invokeSelectedResult() {
        guard results.indices.contains(selectedIndex) else { return }
        let result = results[selectedIndex]
        let invocation = invokeResult?(result) ?? .failed("No palette invocation handler")
        switch invocation {
        case .invoked, .inert:
            dismissAndRestoreFocus()
        case .disabled(let reason):
            searchField.placeholderAttributedString = NSAttributedString(
                string: reason ?? "Command is disabled",
                attributes: [
                    .foregroundColor: currentTheme.shell.accent,
                    .font: NSFont.systemFont(ofSize: 15, weight: .regular),
                ]
            )
        case .failed(let message):
            searchField.placeholderAttributedString = NSAttributedString(
                string: message,
                attributes: [
                    .foregroundColor: currentTheme.shell.accent,
                    .font: NSFont.systemFont(ofSize: 15, weight: .regular),
                ]
            )
        }
    }
}

// MARK: - Search field

@MainActor
final class CommandPaletteSearchField: NSTextField {
    enum Command {
        case moveUp, moveDown, submit, dismiss
    }
    var commandHandler: ((Command) -> Void)?

    override func awakeFromNib() {
        super.awakeFromNib()
        MainActor.assumeIsolated {
            (cell as? NSTextFieldCell)?.usesSingleLineMode = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let centeredCell = VerticallyCenteredTextFieldCell()
        centeredCell.isEditable = true
        centeredCell.isSelectable = true
        centeredCell.isBordered = false
        centeredCell.backgroundColor = .clear
        centeredCell.focusRingType = .none
        centeredCell.usesSingleLineMode = true
        centeredCell.lineBreakMode = .byClipping
        cell = centeredCell
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}

private final class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    private func centeredRect(for rect: NSRect) -> NSRect {
        let size = cellSize(forBounds: rect)
        let y = rect.minY + (rect.height - size.height) / 2
        return NSRect(x: rect.minX, y: y, width: rect.width, height: size.height)
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        centeredRect(for: rect)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: centeredRect(for: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: centeredRect(for: rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.drawInterior(withFrame: centeredRect(for: cellFrame), in: controlView)
    }
}

// MARK: - Result row

@MainActor
final class CommandPaletteResultRow: NSView {
    private let result: CommandPaletteResult
    private var selected: Bool
    private var theme: WorkspaceShellTheme

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let reasonLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")
    private let clickTarget = NSButton(frame: .zero)

    private static let rowHeightNormal: CGFloat = 38
    private static let rowHeightWithReason: CGFloat = 52
    private static let iconSize: CGFloat = 14
    private static let hPad: CGFloat = 12
    private static let cornerRadius: CGFloat = 6

    var target: AnyObject? {
        get { clickTarget.target }
        set { clickTarget.target = newValue }
    }
    var action: Selector? {
        get { clickTarget.action }
        set { clickTarget.action = newValue }
    }
    override var tag: Int {
        get { clickTarget.tag }
        set { clickTarget.tag = newValue }
    }

    init(result: CommandPaletteResult, isSelected: Bool, theme: WorkspaceShellTheme) {
        self.result = result
        self.selected = isSelected
        self.theme = theme
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = Self.cornerRadius
        translatesAutoresizingMaskIntoConstraints = false
        let rowHeight = result.disabledReason != nil ? Self.rowHeightWithReason : Self.rowHeightNormal
        heightAnchor.constraint(equalToConstant: rowHeight).isActive = true

        // Transparent full-size button for click handling
        clickTarget.isBordered = false
        clickTarget.setButtonType(.momentaryChange)
        clickTarget.title = ""
        clickTarget.translatesAutoresizingMaskIntoConstraints = false
        addSubview(clickTarget)

        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(iconView)

        titleLabel.isBordered = false
        titleLabel.isEditable = false
        titleLabel.backgroundColor = .clear
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        reasonLabel.isBordered = false
        reasonLabel.isEditable = false
        reasonLabel.backgroundColor = .clear
        reasonLabel.font = .systemFont(ofSize: 11)
        reasonLabel.lineBreakMode = .byTruncatingTail
        reasonLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        reasonLabel.translatesAutoresizingMaskIntoConstraints = false
        reasonLabel.isHidden = result.disabledReason == nil
        addSubview(reasonLabel)

        shortcutLabel.isBordered = false
        shortcutLabel.isEditable = false
        shortcutLabel.backgroundColor = .clear
        shortcutLabel.font = .systemFont(ofSize: 12, weight: .regular)
        shortcutLabel.lineBreakMode = .byTruncatingTail
        shortcutLabel.setContentHuggingPriority(.required, for: .horizontal)
        shortcutLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(shortcutLabel)

        if result.disabledReason != nil {
            // Two-line layout: title + reason stacked, icon centered on title
            NSLayoutConstraint.activate([
                clickTarget.topAnchor.constraint(equalTo: topAnchor),
                clickTarget.leadingAnchor.constraint(equalTo: leadingAnchor),
                clickTarget.trailingAnchor.constraint(equalTo: trailingAnchor),
                clickTarget.bottomAnchor.constraint(equalTo: bottomAnchor),

                iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.hPad),
                iconView.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: Self.iconSize),
                iconView.heightAnchor.constraint(equalToConstant: Self.iconSize),

                titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
                titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 9),
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: shortcutLabel.leadingAnchor, constant: -12),

                reasonLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
                reasonLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
                reasonLabel.trailingAnchor.constraint(lessThanOrEqualTo: shortcutLabel.leadingAnchor, constant: -12),

                shortcutLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.hPad),
                shortcutLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        } else {
            // Single-line layout: everything centered
            NSLayoutConstraint.activate([
                clickTarget.topAnchor.constraint(equalTo: topAnchor),
                clickTarget.leadingAnchor.constraint(equalTo: leadingAnchor),
                clickTarget.trailingAnchor.constraint(equalTo: trailingAnchor),
                clickTarget.bottomAnchor.constraint(equalTo: bottomAnchor),

                iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.hPad),
                iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: Self.iconSize),
                iconView.heightAnchor.constraint(equalToConstant: Self.iconSize),

                titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
                titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: shortcutLabel.leadingAnchor, constant: -12),

                shortcutLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.hPad),
                shortcutLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }

        applyPresentation()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func setSelected(_ isSelected: Bool, theme: WorkspaceShellTheme) {
        guard isSelected != selected else { return }
        selected = isSelected
        layer?.backgroundColor = selected
            ? theme.shell.selection.withAlphaComponent(0.25).cgColor
            : NSColor.clear.cgColor
    }

    func apply(theme: WorkspaceShellTheme) {
        self.theme = theme
        applyPresentation()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    private func applyPresentation() {
        let colors = theme.shell
        layer?.backgroundColor = selected
            ? colors.selection.withAlphaComponent(0.25).cgColor
            : NSColor.clear.cgColor

        // Icon
        let iconName: String
        switch result.category {
        case .workspace: iconName = "square.split.2x1"
        case .action:    iconName = "terminal"
        case .cli:       iconName = "chevron.right"
        }
        let cfg = NSImage.SymbolConfiguration(pointSize: Self.iconSize, weight: .regular)
        iconView.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)
        iconView.contentTintColor = colors.textMuted

        // Title
        titleLabel.stringValue = result.title
        titleLabel.textColor = result.isEnabled ? colors.textPrimary : colors.textMuted

        // Disabled reason
        reasonLabel.stringValue = result.disabledReason ?? ""
        reasonLabel.textColor = colors.textMuted
        reasonLabel.isHidden = result.disabledReason == nil

        // Shortcut
        shortcutLabel.stringValue = result.shortcutLabel ?? ""
        shortcutLabel.textColor = colors.textMuted
        shortcutLabel.isHidden = result.shortcutLabel == nil

        setAccessibilityLabel("\(result.title), \(result.category.rawValue)")
    }
}

// MARK: - Helpers

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
