import AppKit
import OmuxCore

// MARK: - Data model

struct PaneFindMatch {
    let lineText: String
    let matchRanges: [NSRange]
}

struct PaneFindPaneResult {
    let paneID: PaneID
    let workspaceName: String
    let paneTitle: String
    let matches: [PaneFindMatch]
}

// MARK: - Find bar

@MainActor
final class PaneFindBarView: NSView {
    enum Mode {
        case currentPane
        case allPanes
    }

    var onDismiss: (() -> Void)?
    var onFocusPane: ((PaneID) -> Void)?

    private let searchField = NSSearchField()
    private let matchCountLabel = NSTextField(labelWithString: "")
    private let prevButton = NSButton()
    private let nextButton = NSButton()
    private let allPanesButton = NSButton()
    private let resultsScrollView = NSScrollView()
    private let resultsTextView = NSTextView()

    private(set) var mode: Mode = .currentPane
    private var paneResults: [PaneFindPaneResult] = []
    private var flatMatches: [(paneResultIndex: Int, matchIndex: Int)] = []
    private var currentFlatIndex: Int = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: - Public interface

    func present(
        mode: Mode,
        paneResults: [PaneFindPaneResult],
        existingQuery: String = ""
    ) {
        self.mode = mode
        self.paneResults = paneResults
        updateFlatMatches()
        currentFlatIndex = 0
        updateMatchUI()
        renderResults()
        allPanesButton.state = mode == .allPanes ? .on : .off
        allPanesButton.toolTip = mode == .allPanes ? "Searching all panes" : "Search all panes"
        if !existingQuery.isEmpty {
            searchField.stringValue = existingQuery
        }
        window?.makeFirstResponder(searchField)
    }

    var currentQuery: String {
        searchField.stringValue
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

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        searchField.placeholderString = "Find in pane…"
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

        nextButton.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Next match")
        nextButton.bezelStyle = .regularSquare
        nextButton.isBordered = false
        nextButton.target = self
        nextButton.action = #selector(nextMatch(_:))
        nextButton.translatesAutoresizingMaskIntoConstraints = false
        nextButton.contentTintColor = .secondaryLabelColor

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

        resultsScrollView.translatesAutoresizingMaskIntoConstraints = false
        resultsScrollView.hasVerticalScroller = true
        resultsScrollView.borderType = .noBorder
        resultsScrollView.backgroundColor = .clear
        resultsScrollView.drawsBackground = false

        resultsTextView.isEditable = false
        resultsTextView.isSelectable = true
        resultsTextView.backgroundColor = .clear
        resultsTextView.drawsBackground = false
        resultsTextView.textContainerInset = NSSize(width: 8, height: 6)
        resultsTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        resultsTextView.isVerticallyResizable = true
        resultsTextView.autoresizingMask = [.width]
        resultsTextView.textContainer?.widthTracksTextView = true
        resultsScrollView.documentView = resultsTextView

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
        addSubview(separator)
        addSubview(resultsScrollView)

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            controlsRow.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            controlsRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            controlsRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            controlsRow.heightAnchor.constraint(equalToConstant: 28),

            separator.topAnchor.constraint(equalTo: controlsRow.bottomAnchor, constant: 6),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),

            resultsScrollView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            resultsScrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            resultsScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            resultsScrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            prevButton.widthAnchor.constraint(equalToConstant: 20),
            prevButton.heightAnchor.constraint(equalToConstant: 20),
            nextButton.widthAnchor.constraint(equalToConstant: 20),
            nextButton.heightAnchor.constraint(equalToConstant: 20),
            allPanesButton.widthAnchor.constraint(equalToConstant: 20),
            allPanesButton.heightAnchor.constraint(equalToConstant: 20),
            closeButton.widthAnchor.constraint(equalToConstant: 20),
            closeButton.heightAnchor.constraint(equalToConstant: 20),
            matchCountLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 52),
        ])
    }

    // MARK: - Search

    private func updateFlatMatches() {
        flatMatches = paneResults.enumerated().flatMap { paneIdx, paneResult in
            paneResult.matches.indices.map { matchIdx in (paneResultIndex: paneIdx, matchIndex: matchIdx) }
        }
    }

    private func updateMatchUI() {
        let total = flatMatches.count
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            matchCountLabel.stringValue = ""
        } else if total == 0 {
            matchCountLabel.stringValue = "No results"
            matchCountLabel.textColor = .systemRed
        } else {
            matchCountLabel.stringValue = "\(currentFlatIndex + 1) of \(total)"
            matchCountLabel.textColor = .secondaryLabelColor
        }
        prevButton.isEnabled = total > 1
        nextButton.isEnabled = total > 1
    }

    private func renderResults() {
        let storage = resultsTextView.textStorage
        let attributed = NSMutableAttributedString()
        let baseFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let sectionFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let highlightColor = NSColor.systemYellow.withAlphaComponent(0.45)
        let activeHighlightColor = NSColor.systemOrange.withAlphaComponent(0.55)

        var globalMatchIdx = 0
        for (paneIdx, paneResult) in paneResults.enumerated() {
            if mode == .allPanes {
                let header = "\(paneResult.workspaceName)  ›  \(paneResult.paneTitle)\n"
                let headerAttr = NSMutableAttributedString(
                    string: header,
                    attributes: [
                        .font: sectionFont,
                        .foregroundColor: NSColor.tertiaryLabelColor,
                    ]
                )
                if paneIdx > 0 {
                    attributed.append(NSAttributedString(string: "\n"))
                }
                attributed.append(headerAttr)
            }

            for (matchIdx, match) in paneResult.matches.enumerated() {
                let isActive = globalMatchIdx == currentFlatIndex
                let lineStr = NSMutableAttributedString(
                    string: match.lineText + "\n",
                    attributes: [
                        .font: baseFont,
                        .foregroundColor: NSColor.labelColor,
                    ]
                )
                if isActive {
                    lineStr.addAttribute(
                        .backgroundColor,
                        value: NSColor.controlAccentColor.withAlphaComponent(0.15),
                        range: NSRange(location: 0, length: lineStr.length - 1)
                    )
                }
                for range in match.matchRanges {
                    let color = isActive ? activeHighlightColor : highlightColor
                    lineStr.addAttribute(.backgroundColor, value: color, range: range)
                }
                _ = matchIdx
                attributed.append(lineStr)
                globalMatchIdx += 1
            }
        }

        storage?.setAttributedString(attributed)
        scrollToCurrentMatch()
    }

    private func scrollToCurrentMatch() {
        guard !flatMatches.isEmpty else { return }
        var lineOffset = 0
        for (idx, _) in flatMatches.enumerated() {
            if idx == currentFlatIndex { break }
            let prevFlat = flatMatches[idx]
            if mode == .allPanes, idx == 0 || prevFlat.paneResultIndex != flatMatches[max(0, idx - 1)].paneResultIndex {
                lineOffset += 1
            }
            lineOffset += 1
        }
        if mode == .allPanes {
            let paneIdx = flatMatches[currentFlatIndex].paneResultIndex
            lineOffset += paneIdx
        }
        let estimatedLineHeight: CGFloat = 17
        let yPos = CGFloat(lineOffset) * estimatedLineHeight
        resultsTextView.scroll(NSPoint(x: 0, y: yPos))
    }

    // MARK: - Actions

    @objc private func searchFieldAction(_ sender: Any?) {
        nextMatch(sender)
    }

    @objc func nextMatch(_ sender: Any?) {
        guard !flatMatches.isEmpty else { return }
        currentFlatIndex = (currentFlatIndex + 1) % flatMatches.count
        updateMatchUI()
        renderResults()
    }

    @objc func previousMatch(_ sender: Any?) {
        guard !flatMatches.isEmpty else { return }
        currentFlatIndex = (currentFlatIndex - 1 + flatMatches.count) % flatMatches.count
        updateMatchUI()
        renderResults()
    }

    @objc private func toggleAllPanes(_ sender: Any?) {
        let newMode: Mode = allPanesButton.state == .on ? .allPanes : .currentPane
        onModeToggle?(newMode, searchField.stringValue)
    }

    @objc private func closeFind(_ sender: Any?) {
        onDismiss?()
    }

    var onModeToggle: ((Mode, String) -> Void)?
    var onQueryChange: ((String) -> Void)?

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
        currentFlatIndex = 0
        onQueryChange?(searchField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(cancelOperation(_:)) {
            closeFind(nil)
            return true
        }
        return false
    }
}

// MARK: - Search logic

enum PaneFindSearch {
    static func search(query: String, in text: String) -> [PaneFindMatch] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let lowercasedQuery = query.lowercased()
        return text
            .components(separatedBy: "\n")
            .compactMap { line -> PaneFindMatch? in
                let lowercasedLine = line.lowercased()
                var ranges: [NSRange] = []
                var searchFrom = lowercasedLine.startIndex
                while let range = lowercasedLine.range(of: lowercasedQuery, range: searchFrom..<lowercasedLine.endIndex) {
                    ranges.append(NSRange(range, in: line))
                    searchFrom = range.upperBound
                }
                guard !ranges.isEmpty else { return nil }
                return PaneFindMatch(lineText: line, matchRanges: ranges)
            }
    }
}
