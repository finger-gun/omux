import AppKit
import OmuxCore
import OmuxTerminalBridge

@MainActor
final class WorkspaceWindowController: NSWindowController {
    private let rootViewController: WorkspaceViewController

    init(workspace: Workspace, controller: WorkspaceController) {
        self.rootViewController = WorkspaceViewController(controller: controller)
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 1100, height: 720),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = workspace.name
        window.contentViewController = rootViewController
        super.init(window: window)
        rootViewController.update(workspace: workspace)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func update(workspace: Workspace) {
        window?.title = workspace.name
        rootViewController.update(workspace: workspace)
    }
}

@MainActor
final class WorkspaceViewController: NSViewController {
    private let controller: WorkspaceController
    private let inputNormalizer = AppKitKeyEventNormalizer()
    private let titleLabel = NSTextField(labelWithString: "OpenMUX")
    private let detailLabel = NSTextField(labelWithString: "")
    private let tabSelector = NSSegmentedControl(labels: [], trackingMode: .selectOne, target: nil, action: nil)
    private let splitView = NSSplitView()
    private let newTabButton = NSButton(title: "New Tab", target: nil, action: nil)
    private let splitButton = NSButton(title: "Split Pane", target: nil, action: nil)
    private let runButton = NSButton(title: "Run Command", target: nil, action: nil)
    private var currentWorkspace: Workspace?

    init(controller: WorkspaceController) {
        self.controller = controller
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false

        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 16
        container.translatesAutoresizingMaskIntoConstraints = false

        let header = NSStackView()
        header.orientation = .horizontal
        header.spacing = 12
        header.alignment = .centerY
        header.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        detailLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor

        tabSelector.target = self
        tabSelector.action = #selector(selectTab(_:))

        newTabButton.target = self
        newTabButton.action = #selector(createTab(_:))

        splitButton.target = self
        splitButton.action = #selector(splitPane(_:))

        runButton.target = self
        runButton.action = #selector(runCommand(_:))

        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false

        container.addArrangedSubview(titleLabel)
        container.addArrangedSubview(detailLabel)
        header.addArrangedSubview(tabSelector)
        header.addArrangedSubview(newTabButton)
        header.addArrangedSubview(splitButton)
        header.addArrangedSubview(runButton)
        container.addArrangedSubview(header)
        container.addArrangedSubview(splitView)
        view.addSubview(container)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -24),
            splitView.heightAnchor.constraint(greaterThanOrEqualToConstant: 480),
        ])
    }

    func update(workspace: Workspace) {
        currentWorkspace = workspace
        titleLabel.stringValue = workspace.name
        detailLabel.stringValue = "Root: \(workspace.rootPath)"

        tabSelector.segmentCount = workspace.tabs.count
        for (index, tab) in workspace.tabs.enumerated() {
            tabSelector.setLabel(tab.title, forSegment: index)
            if tab.id == workspace.focusedTabID {
                tabSelector.selectedSegment = index
            }
        }

        splitView.arrangedSubviews.forEach { subview in
            splitView.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        if let tab = workspace.focusedTab {
            for pane in tab.panes {
                let paneView = TerminalPaneView(
                    pane: pane,
                    isFocused: pane.id == tab.focusedPaneID,
                    bridge: controller.terminalBridge,
                    normalizer: inputNormalizer,
                    onFocus: { [weak self] paneID in
                        _ = self?.controller.focus(paneID: paneID)
                    },
                    onInput: { [weak self] paneID, event in
                        try self?.controller.handleInput(event, in: paneID)
                    }
                )
                splitView.addArrangedSubview(paneView)
            }
        }
    }

    @objc private func selectTab(_ sender: NSSegmentedControl) {
        guard let workspace = currentWorkspace,
              sender.selectedSegment >= 0,
              sender.selectedSegment < workspace.tabs.count
        else {
            return
        }

        _ = controller.focus(tabID: workspace.tabs[sender.selectedSegment].id)
    }

    @objc private func createTab(_ sender: NSButton) {
        _ = sender
        _ = try? controller.createTab()
    }

    @objc private func splitPane(_ sender: NSButton) {
        _ = sender
        _ = try? controller.splitFocusedPane()
    }

    @objc private func runCommand(_ sender: NSButton) {
        _ = sender
        guard let workspace = currentWorkspace,
              let focusedPane = workspace.focusedPane
        else {
            return
        }

        let alert = NSAlert()
        alert.messageText = "Run command in pane"
        alert.informativeText = "The command will run in the focused session."
        let field = NSTextField(string: "")
        field.placeholderString = "ls -la"
        alert.accessoryView = field
        alert.addButton(withTitle: "Run")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            _ = try? controller.runCommand(in: focusedPane.session.id, command: field.stringValue)
        }
    }
}

@MainActor
final class TerminalPaneView: NSView {
    private let textView = TerminalTextView()
    private let scrollView = NSScrollView()
    private let paneID: PaneID
    private var observerToken: UUID?
    private let bridge: GhosttyTerminalBridge

    init(
        pane: Pane,
        isFocused: Bool,
        bridge: GhosttyTerminalBridge,
        normalizer: AppKitKeyEventNormalizer,
        onFocus: @escaping @MainActor (PaneID) -> Void,
        onInput: @escaping @MainActor (PaneID, NormalizedKeyEvent) throws -> Void
    ) {
        self.paneID = pane.id
        self.bridge = bridge
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = isFocused ? 2 : 1
        layer?.borderColor = (isFocused ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor

        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false

        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.backgroundColor = .clear
        textView.normalizer = normalizer
        textView.paneID = pane.id
        textView.onFocus = onFocus
        textView.onInput = onInput
        scrollView.documentView = textView

        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 360),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 280),
        ])

        observerToken = bridge.addObserver(for: pane.id) { [weak textView] snapshot in
            DispatchQueue.main.async {
                textView?.string = snapshot.renderedText
                textView?.scrollToEndOfDocument(nil)
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        if let observerToken {
            bridge.removeObserver(for: paneID, token: observerToken)
        }
    }
}

@MainActor
final class TerminalTextView: NSTextView {
    var normalizer = AppKitKeyEventNormalizer()
    var paneID = PaneID(rawValue: "unbound")
    var onFocus: (@MainActor (PaneID) -> Void)?
    var onInput: (@MainActor (PaneID, NormalizedKeyEvent) throws -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        onFocus?(paneID)
        return super.becomeFirstResponder()
    }

    override func mouseDown(with event: NSEvent) {
        onFocus?(paneID)
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let normalizedEvent = normalizer.normalize(event)
        do {
            try onInput?(paneID, normalizedEvent)
        } catch {
            NSSound.beep()
        }
    }
}
