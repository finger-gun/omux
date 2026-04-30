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
    private let titleLabel = NSTextField(labelWithString: "OpenMUX")
    private let detailLabel = NSTextField(labelWithString: "")
    private let tabSelector = NSSegmentedControl(labels: [], trackingMode: .selectOne, target: nil, action: nil)
    private let paneContainerView = NSView()
    private let newTabButton = NSButton(title: "New Tab", target: nil, action: nil)
    private let splitRightButton = NSButton(title: "Split Right", target: nil, action: nil)
    private let splitDownButton = NSButton(title: "Split Down", target: nil, action: nil)
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

        splitRightButton.target = self
        splitRightButton.action = #selector(splitRight(_:))

        splitDownButton.target = self
        splitDownButton.action = #selector(splitDown(_:))

        paneContainerView.translatesAutoresizingMaskIntoConstraints = false

        container.addArrangedSubview(titleLabel)
        container.addArrangedSubview(detailLabel)
        header.addArrangedSubview(tabSelector)
        header.addArrangedSubview(newTabButton)
        header.addArrangedSubview(splitRightButton)
        header.addArrangedSubview(splitDownButton)
        container.addArrangedSubview(header)
        container.addArrangedSubview(paneContainerView)
        view.addSubview(container)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -24),
            paneContainerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 480),
        ])
    }

    func update(workspace: Workspace) {
        currentWorkspace = workspace
        titleLabel.stringValue = workspace.name
        detailLabel.stringValue = "Root: \(workspace.rootPath)"
        var focusedPaneView: HostedTerminalPaneView?

        tabSelector.segmentCount = workspace.tabs.count
        for (index, tab) in workspace.tabs.enumerated() {
            tabSelector.setLabel(tab.title, forSegment: index)
            if tab.id == workspace.focusedTabID {
                tabSelector.selectedSegment = index
            }
        }

        paneContainerView.subviews.forEach { subview in
            subview.removeFromSuperview()
        }

        if let tab = workspace.focusedTab {
            let layout = makeLayoutView(for: tab.rootLayout, focusedPaneID: tab.focusedPaneID)
            let layoutView = layout.view
            focusedPaneView = layout.focusedPaneView
            paneContainerView.addSubview(layoutView)
            NSLayoutConstraint.activate([
                layoutView.topAnchor.constraint(equalTo: paneContainerView.topAnchor),
                layoutView.leadingAnchor.constraint(equalTo: paneContainerView.leadingAnchor),
                layoutView.trailingAnchor.constraint(equalTo: paneContainerView.trailingAnchor),
                layoutView.bottomAnchor.constraint(equalTo: paneContainerView.bottomAnchor),
            ])
            if let singlePaneView = layoutView as? HostedTerminalPaneView {
                focusedPaneView = singlePaneView
            }
        }

        if let focusedPaneView {
            DispatchQueue.main.async { [weak self, weak focusedPaneView] in
                guard let self, let focusedPaneView else {
                    return
                }

                self.view.window?.makeFirstResponder(focusedPaneView.focusTarget)
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

    @objc private func splitRight(_ sender: NSButton) {
        _ = sender
        _ = try? controller.splitFocusedPane(axis: .columns)
    }

    @objc private func splitDown(_ sender: NSButton) {
        _ = sender
        _ = try? controller.splitFocusedPane(axis: .rows)
    }

    private func makeLayoutView(
        for node: TabLayoutNode,
        focusedPaneID: PaneID
    ) -> (view: NSView, focusedPaneView: HostedTerminalPaneView?) {
        switch node {
        case .paneStack(let paneStack):
            let stackView = PaneStackView(
                paneStack: paneStack,
                focusedPaneID: focusedPaneID,
                bridge: controller.terminalBridge,
                onSelectPaneTab: { [weak self] paneID in
                    _ = self?.controller.focusPaneTab(paneID: paneID)
                },
                onCreatePaneTab: { [weak self] in
                    _ = try self?.controller.createPaneTab()
                },
                onClosePaneTab: { [weak self] paneID in
                    _ = try self?.controller.closePaneTab(paneID: paneID)
                },
                onFocus: { [weak self] paneID in
                    _ = self?.controller.focus(paneID: paneID)
                }
            )
            return (stackView, paneStack.focusedPaneID == focusedPaneID ? stackView.focusedPaneView : nil)

        case .split(let axis, let children):
            let splitView = NSSplitView()
            splitView.isVertical = axis == .columns
            splitView.dividerStyle = .thin
            splitView.translatesAutoresizingMaskIntoConstraints = false

            var focusedPaneView: HostedTerminalPaneView?
            for child in children {
                let childLayout = makeLayoutView(for: child, focusedPaneID: focusedPaneID)
                if focusedPaneView == nil {
                    focusedPaneView = childLayout.focusedPaneView
                }
                splitView.addArrangedSubview(childLayout.view)
            }

            return (splitView, focusedPaneView)
        }
    }
}

@MainActor
final class PaneStackView: NSView {
    private let tabSelector = NSSegmentedControl(labels: [], trackingMode: .selectOne, target: nil, action: nil)
    private let newPaneTabButton = NSButton(title: "+", target: nil, action: nil)
    private let closePaneTabButton = NSButton(title: "Close", target: nil, action: nil)
    private let terminalPaneView: HostedTerminalPaneView
    private let paneStack: PaneStack
    private let onSelectPaneTab: (PaneID) -> Void
    private let onCreatePaneTab: () throws -> Void
    private let onClosePaneTab: (PaneID) throws -> Void

    init(
        paneStack: PaneStack,
        focusedPaneID: PaneID,
        bridge: GhosttyTerminalBridge,
        onSelectPaneTab: @escaping @MainActor (PaneID) -> Void,
        onCreatePaneTab: @escaping @MainActor () throws -> Void,
        onClosePaneTab: @escaping @MainActor (PaneID) throws -> Void,
        onFocus: @escaping @MainActor (PaneID) -> Void
    ) {
        self.paneStack = paneStack
        self.onSelectPaneTab = onSelectPaneTab
        self.onCreatePaneTab = onCreatePaneTab
        self.onClosePaneTab = onClosePaneTab
        let activePane = paneStack.focusedPane ?? paneStack.panes[0]
        self.terminalPaneView = bridge.makeHostedPaneView(
            for: activePane,
            isFocused: activePane.id == focusedPaneID,
            onFocus: onFocus
        )
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 8
        container.translatesAutoresizingMaskIntoConstraints = false

        let header = NSStackView()
        header.orientation = .horizontal
        header.spacing = 8
        header.alignment = .centerY
        header.translatesAutoresizingMaskIntoConstraints = false

        tabSelector.target = self
        tabSelector.action = #selector(selectPaneTab(_:))
        tabSelector.segmentStyle = .rounded
        tabSelector.segmentCount = paneStack.panes.count
        for (index, pane) in paneStack.panes.enumerated() {
            tabSelector.setLabel(pane.title, forSegment: index)
            if pane.id == paneStack.focusedPaneID {
                tabSelector.selectedSegment = index
            }
        }

        newPaneTabButton.target = self
        newPaneTabButton.action = #selector(createPaneTab(_:))
        closePaneTabButton.target = self
        closePaneTabButton.action = #selector(closePaneTab(_:))
        closePaneTabButton.isEnabled = paneStack.panes.count > 1

        header.addArrangedSubview(tabSelector)
        header.addArrangedSubview(newPaneTabButton)
        header.addArrangedSubview(closePaneTabButton)
        container.addArrangedSubview(header)
        container.addArrangedSubview(terminalPaneView)
        addSubview(container)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor),
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    @objc private func selectPaneTab(_ sender: NSSegmentedControl) {
        guard sender.selectedSegment >= 0,
              sender.selectedSegment < paneStack.panes.count
        else {
            return
        }

        onSelectPaneTab(paneStack.panes[sender.selectedSegment].id)
    }

    @objc private func createPaneTab(_ sender: NSButton) {
        _ = sender
        try? onCreatePaneTab()
    }

    @objc private func closePaneTab(_ sender: NSButton) {
        _ = sender
        try? onClosePaneTab(paneStack.focusedPaneID)
    }

    var focusedPaneView: HostedTerminalPaneView {
        terminalPaneView
    }
}
