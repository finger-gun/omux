import AppKit
import OmuxCore

// MARK: - Find bar

@MainActor
final class PaneFindBarView: NSView {
    enum Mode {
        case currentPane
        case allPanes
    }

    // Callbacks wired by WorkspaceWindowController
    var onDismiss: (() -> Void)?
    var onSearch: ((String) -> Void)?
    var onNavigate: ((Bool) -> Void)?   // true = forward
    var onModeToggle: ((Mode, String) -> Void)?
    var onFocusPaneForSearch: ((PaneID, String) -> Void)?

    private let searchField = NSSearchField()
    private let matchCountLabel = NSTextField(labelWithString: "")
    private let prevButton = NSButton()
    private let nextButton = NSButton()
    private let allPanesButton = NSButton()

    // Per-pane summary shown in all-panes mode
    private var paneSummaryStack: NSStackView?
    private var paneSummaryItems: [(paneID: PaneID, label: NSButton)] = []
    private var heightConstraint: NSLayoutConstraint?

    private(set) var mode: Mode = .currentPane

    private var searchTotal: Int = 0
    private var searchSelected: Int = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: - Public interface

    func present(mode: Mode, existingQuery: String = "") {
        self.mode = mode
        allPanesButton.state = mode == .allPanes ? .on : .off
        allPanesButton.toolTip = mode == .allPanes ? "Searching all panes" : "Search all panes"
        searchTotal = 0
        searchSelected = 0
        updateMatchUI()
        if !existingQuery.isEmpty {
            searchField.stringValue = existingQuery
        }
        window?.makeFirstResponder(searchField)
    }

    var currentQuery: String { searchField.stringValue }

    /// Called by the controller when Ghostty fires SEARCH_TOTAL / SEARCH_SELECTED callbacks.
    /// Pass -1 for a field to keep its current value.
    func updateMatchCount(total: Int, selected: Int) {
        if total >= 0 { searchTotal = total }
        if selected >= 0 { searchSelected = selected }
        updateMatchUI()
    }

    /// Called by the controller to populate the per-pane summary in all-panes mode.
    func setPaneSummary(_ items: [(paneID: PaneID, title: String, count: Int)]) {
        paneSummaryStack?.removeFromSuperview()
        paneSummaryStack = nil
        paneSummaryItems = []
        guard mode == .allPanes, !items.isEmpty else {
            updateHeight(showSummary: false)
            return
        }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.alignment = .leading

        for item in items {
            let btn = NSButton(title: "\(item.title): \(item.count) match\(item.count == 1 ? "" : "es")",
                               target: self, action: #selector(paneSummaryTapped(_:)))
            btn.bezelStyle = .inline
            btn.isBordered = false
            btn.alignment = .left
            btn.font = .systemFont(ofSize: 11)
            btn.contentTintColor = .secondaryLabelColor
            btn.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(btn)
            paneSummaryItems.append((paneID: item.paneID, label: btn))
        }

        let separatorBox = NSBox()
        separatorBox.boxType = .separator
        separatorBox.translatesAutoresizingMaskIntoConstraints = false

        addSubview(separatorBox)
        addSubview(stack)
        paneSummaryStack = stack

        NSLayoutConstraint.activate([
            separatorBox.topAnchor.constraint(equalTo: topAnchor, constant: 44),
            separatorBox.leadingAnchor.constraint(equalTo: leadingAnchor),
            separatorBox.trailingAnchor.constraint(equalTo: trailingAnchor),

            stack.topAnchor.constraint(equalTo: separatorBox.bottomAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
        ])

        updateHeight(showSummary: true, rowCount: items.count)
    }

    // MARK: - View setup

    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true

        let blurView = NSVisualEffectView()
        blurView.blendingMode = .withinWindow
        blurView.material = .popover
        blurView.state = .active
        blurView.translatesAutoresizingMaskIntoConstraints = false

        searchField.placeholderString = "Find…"
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(searchFieldAction(_:))
        (searchField.cell as? NSSearchFieldCell)?.cancelButtonCell = nil
        searchField.delegate = self

        matchCountLabel.translatesAutoresizingMaskIntoConstraints = false
        matchCountLabel.textColor = .secondaryLabelColor
        matchCountLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        matchCountLabel.alignment = .right

        prevButton.image = NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "Previous match")
        prevButton.bezelStyle = .regularSquare
        prevButton.isBordered = false
        prevButton.target = self
        prevButton.action = #selector(previousMatch(_:))
        prevButton.translatesAutoresizingMaskIntoConstraints = false
        prevButton.contentTintColor = .secondaryLabelColor
        prevButton.isEnabled = false

        nextButton.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Next match")
        nextButton.bezelStyle = .regularSquare
        nextButton.isBordered = false
        nextButton.target = self
        nextButton.action = #selector(nextMatch(_:))
        nextButton.translatesAutoresizingMaskIntoConstraints = false
        nextButton.contentTintColor = .secondaryLabelColor
        nextButton.isEnabled = false

        allPanesButton.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Search all panes")
        allPanesButton.bezelStyle = .regularSquare
        allPanesButton.isBordered = false
        allPanesButton.setButtonType(.toggle)
        allPanesButton.target = self
        allPanesButton.action = #selector(toggleAllPanes(_:))
        allPanesButton.translatesAutoresizingMaskIntoConstraints = false
        allPanesButton.toolTip = "Search all panes"
        allPanesButton.contentTintColor = .secondaryLabelColor

        let closeButton = NSButton()
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close find bar")
        closeButton.bezelStyle = .regularSquare
        closeButton.isBordered = false
        closeButton.target = self
        closeButton.action = #selector(closeFind(_:))
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.contentTintColor = .secondaryLabelColor

        let controlsRow = NSStackView(views: [
            searchField, matchCountLabel, prevButton, nextButton, allPanesButton, closeButton
        ])
        controlsRow.orientation = .horizontal
        controlsRow.spacing = 4
        controlsRow.alignment = .centerY
        controlsRow.translatesAutoresizingMaskIntoConstraints = false
        controlsRow.setHuggingPriority(.defaultLow, for: .horizontal)
        controlsRow.setCustomSpacing(8, after: matchCountLabel)
        controlsRow.setCustomSpacing(12, after: nextButton)
        controlsRow.setCustomSpacing(8, after: allPanesButton)

        addSubview(blurView)
        addSubview(controlsRow)

        let hc = heightAnchor.constraint(equalToConstant: 44)
        heightConstraint = hc

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            controlsRow.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            controlsRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            controlsRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            controlsRow.heightAnchor.constraint(equalToConstant: 28),

            prevButton.widthAnchor.constraint(equalToConstant: 20),
            prevButton.heightAnchor.constraint(equalToConstant: 20),
            nextButton.widthAnchor.constraint(equalToConstant: 20),
            nextButton.heightAnchor.constraint(equalToConstant: 20),
            allPanesButton.widthAnchor.constraint(equalToConstant: 20),
            allPanesButton.heightAnchor.constraint(equalToConstant: 20),
            closeButton.widthAnchor.constraint(equalToConstant: 20),
            closeButton.heightAnchor.constraint(equalToConstant: 20),
            matchCountLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 52),

            hc,
        ])
    }

    private func updateHeight(showSummary: Bool, rowCount: Int = 0) {
        let base: CGFloat = 44
        let extraPerRow: CGFloat = 22
        let separatorHeight: CGFloat = 10
        let newHeight = showSummary ? base + separatorHeight + extraPerRow * CGFloat(rowCount) : base
        heightConstraint?.constant = newHeight
    }

    // MARK: - Match count UI

    private func updateMatchUI() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            matchCountLabel.stringValue = ""
            prevButton.isEnabled = false
            nextButton.isEnabled = false
        } else if searchTotal == 0 {
            matchCountLabel.stringValue = "No results"
            matchCountLabel.textColor = .systemRed
            prevButton.isEnabled = false
            nextButton.isEnabled = false
        } else {
            let idx = searchSelected >= 0 ? searchSelected + 1 : 1
            matchCountLabel.stringValue = "\(idx) of \(searchTotal)"
            matchCountLabel.textColor = .secondaryLabelColor
            prevButton.isEnabled = searchTotal > 1
            nextButton.isEnabled = searchTotal > 1
        }
    }

    // MARK: - Actions

    @objc private func searchFieldAction(_ sender: Any?) {
        onNavigate?(true)
    }

    @objc func nextMatch(_ sender: Any?) {
        onNavigate?(true)
    }

    @objc func previousMatch(_ sender: Any?) {
        onNavigate?(false)
    }

    @objc private func toggleAllPanes(_ sender: Any?) {
        let newMode: Mode = allPanesButton.state == .on ? .allPanes : .currentPane
        onModeToggle?(newMode, searchField.stringValue)
    }

    @objc private func closeFind(_ sender: Any?) {
        onDismiss?()
    }

    @objc private func paneSummaryTapped(_ sender: NSButton) {
        guard let item = paneSummaryItems.first(where: { $0.label === sender }) else { return }
        onFocusPaneForSearch?(item.paneID, searchField.stringValue)
    }

    // MARK: - Key handling

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Escape
            closeFind(nil)
        case 36: // Return
            if event.modifierFlags.contains(.shift) {
                previousMatch(nil)
            } else {
                nextMatch(nil)
            }
        default:
            super.keyDown(with: event)
        }
    }
}

extension PaneFindBarView: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        searchTotal = 0
        searchSelected = 0
        updateMatchUI()
        onSearch?(searchField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(cancelOperation(_:)) {
            closeFind(nil)
            return true
        }
        return false
    }
}

// MARK: - Text search helper (used for all-panes match counting)

enum PaneFindSearch {
    static func matchCount(query: String, in text: String) -> Int {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return 0 }
        let lower = text.lowercased()
        var count = 0
        var start = lower.startIndex
        while let range = lower.range(of: q, range: start..<lower.endIndex) {
            count += 1
            start = range.upperBound
        }
        return count
    }
}
