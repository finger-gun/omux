import AppKit

// MARK: - Find bar

@MainActor
final class PaneFindBarView: NSView {
    // Callbacks wired by WorkspaceWindowController
    var onDismiss: (() -> Void)?
    var onSearch: ((String) -> Void)?
    var onNavigate: ((Bool) -> Void)?   // true = forward

    private let searchField = NSSearchField()
    private let matchCountLabel = NSTextField(labelWithString: "")
    private let prevButton = NSButton()
    private let nextButton = NSButton()

    private var searchTotal: Int = 0
    private var searchSelected: Int = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: - Public interface

    func present(existingQuery: String = "") {
        searchField.stringValue = existingQuery
        searchTotal = 0
        searchSelected = 0
        updateMatchUI()
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

        let closeButton = NSButton()
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close find bar")
        closeButton.bezelStyle = .regularSquare
        closeButton.isBordered = false
        closeButton.target = self
        closeButton.action = #selector(closeFind(_:))
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.contentTintColor = .secondaryLabelColor

        let controlsRow = NSStackView(views: [
            searchField, matchCountLabel, prevButton, nextButton, closeButton
        ])
        controlsRow.orientation = .horizontal
        controlsRow.spacing = 4
        controlsRow.alignment = .centerY
        controlsRow.translatesAutoresizingMaskIntoConstraints = false
        controlsRow.setHuggingPriority(.defaultLow, for: .horizontal)
        controlsRow.setCustomSpacing(8, after: matchCountLabel)
        controlsRow.setCustomSpacing(12, after: nextButton)

        addSubview(blurView)
        addSubview(controlsRow)

        let hc = heightAnchor.constraint(equalToConstant: 44)

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
            closeButton.widthAnchor.constraint(equalToConstant: 20),
            closeButton.heightAnchor.constraint(equalToConstant: 20),
            matchCountLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 52),

            hc,
        ])
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

    @objc private func closeFind(_ sender: Any?) {
        onDismiss?()
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

// MARK: - Text search helper

enum PaneFindSearch {
    static func matchCount(query: String, in text: String) -> Int {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return 0 }

        let text = text.lowercased()
        var count = 0
        var start = text.startIndex
        while let range = text.range(of: query, range: start..<text.endIndex) {
            count += 1
            start = range.upperBound
        }
        return count
    }
}
