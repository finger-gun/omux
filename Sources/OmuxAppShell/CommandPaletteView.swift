import AppKit
import OmuxCore

@MainActor
final class CommandPaletteView: NSView, NSTextFieldDelegate {
    var resultProvider: ((String) -> [CommandPaletteResult])?
    var invokeResult: ((CommandPaletteResult) -> CommandPaletteInvocationResult)?
    var dismissHandler: (() -> Void)?

    private let panel = NSVisualEffectView()
    private let searchField = CommandPaletteSearchField()
    private let statusLabel = NSTextField(labelWithString: "")
    private let resultStack = NSStackView()
    private var results: [CommandPaletteResult] = []
    private var selectedIndex: Int = 0
    private var focusRestoreResponder: NSResponder?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.20).cgColor

        panel.material = .hudWindow
        panel.blendingMode = .withinWindow
        panel.state = .active
        panel.wantsLayer = true
        panel.layer?.cornerRadius = 14
        panel.translatesAutoresizingMaskIntoConstraints = false

        searchField.font = .systemFont(ofSize: 20, weight: .regular)
        searchField.isBordered = false
        searchField.focusRingType = .none
        searchField.backgroundColor = .clear
        searchField.delegate = self
        searchField.commandHandler = { [weak self] command in self?.handle(command) }
        searchField.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        resultStack.orientation = .vertical
        resultStack.alignment = .leading
        resultStack.spacing = 2
        resultStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(panel)
        panel.addSubview(searchField)
        panel.addSubview(statusLabel)
        panel.addSubview(resultStack)

        NSLayoutConstraint.activate([
            panel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 72),
            panel.centerXAnchor.constraint(equalTo: centerXAnchor),
            panel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -48),
            panel.widthAnchor.constraint(equalToConstant: 680),

            searchField.topAnchor.constraint(equalTo: panel.topAnchor, constant: 18),
            searchField.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 18),
            searchField.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -18),
            searchField.heightAnchor.constraint(equalToConstant: 32),

            statusLabel.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: searchField.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: searchField.trailingAnchor),

            resultStack.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 10),
            resultStack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 10),
            resultStack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -10),
            resultStack.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -10),
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

    func controlTextDidChange(_ notification: Notification) {
        _ = notification
        refreshResults()
    }

    private func refreshResults() {
        results = resultProvider?(searchField.stringValue) ?? []
        selectedIndex = min(selectedIndex, max(results.count - 1, 0))
        renderResults()
    }

    private func renderResults() {
        resultStack.arrangedSubviews.forEach { view in
            resultStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let parsedQuery = CommandPaletteParsedQuery(rawText: searchField.stringValue)
        statusLabel.stringValue = parsedQuery.mode == .command ? "Command search" : "Workspace search"

        guard results.isEmpty == false else {
            let label = NSTextField(labelWithString: "No results")
            label.textColor = .secondaryLabelColor
            label.font = .systemFont(ofSize: 13)
            label.translatesAutoresizingMaskIntoConstraints = false
            resultStack.addArrangedSubview(label)
            label.widthAnchor.constraint(equalTo: resultStack.widthAnchor).isActive = true
            return
        }

        for (index, result) in results.enumerated() {
            let row = CommandPaletteResultRow(result: result, isSelected: index == selectedIndex)
            row.target = self
            row.action = #selector(resultRowClicked(_:))
            row.tag = index
            resultStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: resultStack.widthAnchor).isActive = true
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
            selectedIndex = max(selectedIndex - 1, 0)
            renderResults()
        case .moveDown:
            guard results.isEmpty == false else { return }
            selectedIndex = min(selectedIndex + 1, results.count - 1)
            renderResults()
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
            statusLabel.stringValue = reason ?? "Command is disabled"
        case .failed(let message):
            statusLabel.stringValue = message
        }
    }
}

@MainActor
final class CommandPaletteSearchField: NSTextField {
    enum Command {
        case moveUp
        case moveDown
        case submit
        case dismiss
    }

    var commandHandler: ((Command) -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126:
            commandHandler?(.moveUp)
        case 125:
            commandHandler?(.moveDown)
        case 36:
            commandHandler?(.submit)
        case 53:
            if let editor = currentEditor() as? NSTextView, editor.hasMarkedText() {
                super.keyDown(with: event)
            } else {
                commandHandler?(.dismiss)
            }
        default:
            super.keyDown(with: event)
        }
    }
}

@MainActor
final class CommandPaletteResultRow: NSButton {
    private let result: CommandPaletteResult
    private let selected: Bool

    init(result: CommandPaletteResult, isSelected: Bool) {
        self.result = result
        self.selected = isSelected
        super.init(frame: .zero)
        isBordered = false
        setButtonType(.momentaryChange)
        alignment = .left
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 46).isActive = true
        applyPresentation()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var allowsVibrancy: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    private func applyPresentation() {
        layer?.cornerRadius = 8
        layer?.backgroundColor = selected ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.35).cgColor : NSColor.clear.cgColor

        let title = NSMutableAttributedString(
            string: result.title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: result.isEnabled ? NSColor.labelColor : NSColor.disabledControlTextColor,
            ]
        )
        let details = [result.category.rawValue, result.shortcutLabel, result.disabledReason ?? result.subtitle]
            .compactMap { $0 }
            .filter { $0.isEmpty == false }
            .joined(separator: "  ")
        if details.isEmpty == false {
            title.append(NSAttributedString(
                string: "\n\(details)",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
            ))
        }
        attributedTitle = title
        setAccessibilityLabel("\(result.title), \(result.category.rawValue)")
    }
}
