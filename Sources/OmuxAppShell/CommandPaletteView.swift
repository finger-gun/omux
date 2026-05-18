import AppKit
import OmuxCore

@MainActor
final class CommandPaletteView: NSView, NSTextFieldDelegate {
    // MARK: - Sub-palette mode

    enum SubPaletteMode {
        case none
        case theme(originalTheme: WorkspaceShellTheme)
        case vaultSessions

        var isActive: Bool {
            if case .none = self { return false }
            return true
        }

        var sectionTitle: String? {
            switch self {
            case .none:
                return nil
            case .theme:
                return "Themes"
            case .vaultSessions:
                return "Agent Sessions"
            }
        }
    }

    var resultProvider: ((String) -> [CommandPaletteResult])?
    var invokeResult: ((CommandPaletteResult) -> CommandPaletteInvocationResult)?
    var dismissHandler: (() -> Void)?
    var iconProvider: ((String) -> NSImage?)?

    var subPalettePreviewHandler: ((String) -> Void)?
    var subPaletteCommitHandler: ((String) -> Void)?
    var subPaletteRevertHandler: (() -> Void)?
    var subPaletteQueryChangeHandler: ((String) -> Void)?

    private var subPaletteMode: SubPaletteMode = .none
    private var topLevelResultProvider: ((String) -> [CommandPaletteResult])?

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
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard panel.frame.contains(point) else {
            dismissAndRestoreFocus()
            return
        }

        window?.makeFirstResponder(searchField)
        super.mouseDown(with: event)
    }

    func present(initialQuery: String, restoring responder: NSResponder?) {
        resetSubPaletteStateForPresentation()
        focusRestoreResponder = responder
        searchField.stringValue = initialQuery
        selectedIndex = 0
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

    // MARK: - Sub-palette

    func enterThemeSubPalette(originalTheme: WorkspaceShellTheme) {
        subPaletteMode = .theme(originalTheme: originalTheme)
        topLevelResultProvider = resultProvider
        resultProvider = { [weak self] query in
            guard let self else { return [] }
            return CommandPaletteSearch.themeResults(query: query, activeIdentifier: self.currentTheme.identifier)
        }
        searchField.stringValue = ""
        selectedIndex = 0
        sectionLabel.stringValue = subPaletteMode.sectionTitle ?? ""
        refreshResults()
    }

    func enterVaultSessionsSubPalette(resultProvider: @escaping (String) -> [CommandPaletteResult]) {
        subPaletteMode = .vaultSessions
        topLevelResultProvider = self.resultProvider
        self.resultProvider = resultProvider
        searchField.stringValue = ""
        selectedIndex = 0
        sectionLabel.stringValue = subPaletteMode.sectionTitle ?? ""
        refreshResults()
    }

    func exitSubPalette() {
        resultProvider = topLevelResultProvider
        topLevelResultProvider = nil
        subPaletteMode = .none
        searchField.stringValue = ""
        selectedIndex = 0
        subPaletteQueryChangeHandler = nil
        refreshResults()
    }

    func refreshPresentedResults() {
        refreshResults()
    }

    private func resetSubPaletteStateForPresentation() {
        if let topLevelResultProvider {
            resultProvider = topLevelResultProvider
        }
        topLevelResultProvider = nil
        subPaletteMode = .none
        subPaletteQueryChangeHandler = nil
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ notification: Notification) {
        _ = notification
        if subPaletteMode.isActive {
            subPaletteQueryChangeHandler?(searchField.stringValue)
        }
        refreshResults()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.cancelOperation(_:)):
            if textView.hasMarkedText() { return false }
            if subPaletteMode.isActive {
                exitSubPalette()
                subPaletteRevertHandler?()
            } else {
                dismissAndRestoreFocus()
            }
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

        if subPaletteMode.isActive {
            sectionLabel.stringValue = subPaletteMode.sectionTitle ?? ""
        } else {
            let parsed = CommandPaletteParsedQuery(rawText: searchField.stringValue)
            switch parsed.mode {
            case .command:
                sectionLabel.stringValue = "Commands"
            case .workspace:
                sectionLabel.stringValue = searchField.stringValue.isEmpty ? "Workspaces" : "Results"
            }
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
            let row = CommandPaletteResultRow(result: result, isSelected: index == selectedIndex, theme: currentTheme, iconProvider: iconProvider)
            row.clickHandler = { [weak self] clickedRow in
                self?.resultRowClicked(clickedRow)
            }
            row.hoverHandler = { [weak self] hoveredRow in
                self?.updateSelection(to: hoveredRow.rowIndex)
            }
            row.rowIndex = index
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
        if case .theme = subPaletteMode, let result = results[safe: newIndex] {
            subPalettePreviewHandler?(result.id)
        }
    }

    private func resultRowClicked(_ sender: CommandPaletteResultRow) {
        selectedIndex = sender.rowIndex
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

        if subPaletteMode.isActive {
            subPaletteCommitHandler?(result.id)
            resetSubPaletteStateForPresentation()
            dismissAndRestoreFocus()
            return
        }

        let invocation = invokeResult?(result) ?? .failed("No palette invocation handler")
        switch invocation {
        case .invoked:
            dismissAndRestoreFocus()
        case .inert:
            break
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
    private let iconProvider: ((String) -> NSImage?)?

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let reasonLabel = NSTextField(labelWithString: "")
    private let rightStack = NSStackView()
    private let appIconView = NSImageView()
    private let shortcutLabel = NSTextField(labelWithString: "")
    private let checkmarkView = NSImageView()

    private static let rowHeightNormal: CGFloat = 38
    private static let rowHeightWithReason: CGFloat = 52
    private static let iconSize: CGFloat = 14
    private static let hPad: CGFloat = 12
    private static let cornerRadius: CGFloat = 6

    var clickHandler: ((CommandPaletteResultRow) -> Void)?
    var hoverHandler: ((CommandPaletteResultRow) -> Void)?
    var rowIndex: Int = 0

    init(result: CommandPaletteResult, isSelected: Bool, theme: WorkspaceShellTheme, iconProvider: ((String) -> NSImage?)?) {
        self.result = result
        self.selected = isSelected
        self.theme = theme
        self.iconProvider = iconProvider
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = Self.cornerRadius
        translatesAutoresizingMaskIntoConstraints = false
        let rowHeight = result.disabledReason != nil ? Self.rowHeightWithReason : Self.rowHeightNormal
        heightAnchor.constraint(equalToConstant: rowHeight).isActive = true

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

        appIconView.imageScaling = .scaleProportionallyDown
        appIconView.setContentHuggingPriority(.required, for: .horizontal)
        appIconView.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            appIconView.widthAnchor.constraint(equalToConstant: 16),
            appIconView.heightAnchor.constraint(equalToConstant: 16),
        ])

        rightStack.orientation = .horizontal
        rightStack.spacing = 5
        rightStack.alignment = .centerY
        rightStack.setViews([appIconView, shortcutLabel], in: .leading)
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rightStack)

        let checkmarkCfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        checkmarkView.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(checkmarkCfg)
        checkmarkView.imageScaling = .scaleProportionallyDown
        checkmarkView.translatesAutoresizingMaskIntoConstraints = false
        checkmarkView.setContentHuggingPriority(.required, for: .horizontal)
        checkmarkView.setContentCompressionResistancePriority(.required, for: .horizontal)
        checkmarkView.isHidden = !result.isActive
        addSubview(checkmarkView)

        if result.disabledReason != nil {
            // Two-line layout: title + reason stacked, icon centered on title
            NSLayoutConstraint.activate([
                iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.hPad),
                iconView.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: Self.iconSize),
                iconView.heightAnchor.constraint(equalToConstant: Self.iconSize),

                titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
                titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 9),
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: rightStack.leadingAnchor, constant: -12),

                reasonLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
                reasonLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
                reasonLabel.trailingAnchor.constraint(lessThanOrEqualTo: rightStack.leadingAnchor, constant: -12),

                rightStack.trailingAnchor.constraint(equalTo: checkmarkView.leadingAnchor, constant: -8),
                rightStack.centerYAnchor.constraint(equalTo: centerYAnchor),

                checkmarkView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.hPad),
                checkmarkView.centerYAnchor.constraint(equalTo: centerYAnchor),
                checkmarkView.widthAnchor.constraint(equalToConstant: 14),
                checkmarkView.heightAnchor.constraint(equalToConstant: 14),
            ])
        } else {
            // Single-line layout: everything centered
            NSLayoutConstraint.activate([
                iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.hPad),
                iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: Self.iconSize),
                iconView.heightAnchor.constraint(equalToConstant: Self.iconSize),

                titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
                titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: rightStack.leadingAnchor, constant: -12),

                rightStack.trailingAnchor.constraint(equalTo: checkmarkView.leadingAnchor, constant: -8),
                rightStack.centerYAnchor.constraint(equalTo: centerYAnchor),

                checkmarkView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.hPad),
                checkmarkView.centerYAnchor.constraint(equalTo: centerYAnchor),
                checkmarkView.widthAnchor.constraint(equalToConstant: 14),
                checkmarkView.heightAnchor.constraint(equalToConstant: 14),
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

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        hoverHandler?(self)
    }

    override var acceptsFirstResponder: Bool { false }

    override func mouseDown(with event: NSEvent) {
        // Absorb mouseDown so the window doesn't start a drag
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        clickHandler?(self)
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

        // Secondary line: disabled reason only
        reasonLabel.stringValue = result.disabledReason ?? ""
        reasonLabel.textColor = colors.textMuted
        reasonLabel.isHidden = result.disabledReason == nil

        // Shortcut label, or subtitle (e.g. "Opens in Xcode") when no shortcut is bound
        let rightLabel = result.shortcutLabel ?? result.subtitle
        shortcutLabel.stringValue = rightLabel ?? ""
        shortcutLabel.textColor = colors.textMuted
        shortcutLabel.isHidden = rightLabel == nil

        // App icon — shown next to the label when an icon is provided and no keybinding occupies the slot
        let appIcon = result.shortcutLabel == nil ? iconProvider?(result.id) : nil
        appIconView.image = appIcon
        appIconView.isHidden = appIcon == nil

        checkmarkView.contentTintColor = colors.accent
        checkmarkView.isHidden = !result.isActive

        setAccessibilityLabel("\(result.title), \(result.category.rawValue)")
    }
}

// MARK: - Helpers

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
