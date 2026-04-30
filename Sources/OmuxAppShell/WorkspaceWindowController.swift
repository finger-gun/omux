import AppKit
import OmuxCore
import OmuxTerminalBridge

private enum ShellLayoutMetrics {
    static let sidebarWidth: CGFloat = 224
    static let outerPadding: CGFloat = 12
    static let interRegionSpacing: CGFloat = 12
    static let topBarHeight: CGFloat = 58
    static let canvasPadding: CGFloat = 10
    static let splitSpacing: CGFloat = 12
    static let paneHeaderHeight: CGFloat = 34
}

@MainActor
final class WorkspaceWindowController: NSWindowController {
    private let rootViewController: WorkspaceShellViewController

    init(
        workspace: Workspace,
        controller: WorkspaceController,
        initialTheme: WorkspaceShellTheme = .defaultTheme
    ) {
        self.rootViewController = WorkspaceShellViewController(
            controller: controller,
            initialTheme: initialTheme
        )
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 1220, height: 780),
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

    func updateTheme(_ theme: WorkspaceShellTheme) {
        rootViewController.updateTheme(theme)
    }
}

@MainActor
final class WorkspaceShellViewController: NSViewController {
    private let controller: WorkspaceController
    private let sidebarView = WorkspaceSidebarView()
    private let topBarView = WorkspaceTopBarView()
    private let canvasView = WorkspaceCanvasView()
    private var currentWorkspace: Workspace?
    private var currentTheme: WorkspaceShellTheme

    init(controller: WorkspaceController, initialTheme: WorkspaceShellTheme) {
        self.controller = controller
        self.currentTheme = initialTheme
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true

        let mainColumn = NSStackView()
        mainColumn.orientation = .vertical
        mainColumn.spacing = ShellLayoutMetrics.interRegionSpacing
        mainColumn.translatesAutoresizingMaskIntoConstraints = false

        mainColumn.addArrangedSubview(topBarView)
        mainColumn.addArrangedSubview(canvasView)
        topBarView.heightAnchor.constraint(equalToConstant: ShellLayoutMetrics.topBarHeight).isActive = true

        view.addSubview(sidebarView)
        view.addSubview(mainColumn)

        NSLayoutConstraint.activate([
            sidebarView.topAnchor.constraint(equalTo: view.topAnchor),
            sidebarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sidebarView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebarView.widthAnchor.constraint(equalToConstant: ShellLayoutMetrics.sidebarWidth),

            mainColumn.topAnchor.constraint(equalTo: view.topAnchor, constant: ShellLayoutMetrics.outerPadding),
            mainColumn.leadingAnchor.constraint(equalTo: sidebarView.trailingAnchor, constant: ShellLayoutMetrics.interRegionSpacing),
            mainColumn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -ShellLayoutMetrics.outerPadding),
            mainColumn.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -ShellLayoutMetrics.outerPadding),
        ])
    }

    func update(workspace: Workspace) {
        currentWorkspace = workspace
        apply(theme: currentTheme)

        topBarView.render(
            workspace: workspace,
            theme: currentTheme,
            availableThemes: WorkspaceShellTheme.availableThemes,
            onSelectTheme: { [weak self] themeIdentifier in
                guard let self,
                      let theme = WorkspaceShellTheme.availableThemes.first(where: { $0.identifier == themeIdentifier })
                else {
                    return
                }

                currentTheme = theme
                if let workspace = currentWorkspace {
                    update(workspace: workspace)
                }
            }
        )

        let workspaceItems = makeWorkspaceSidebarItems(
            summaries: controller.listWorkspaces(),
            workspace: workspace
        )
        sidebarView.render(
            workspaceItems: workspaceItems,
            theme: currentTheme,
            onSelectWorkspace: { [weak self] workspaceID in
                _ = self?.controller.restore(workspaceID: workspaceID)
            },
            onCreateWorkspace: { [weak self] in
                _ = try? self?.controller.createWorkspace()
            },
            onSelectTab: { [weak self] tabID in
                _ = self?.controller.focus(tabID: tabID)
            }
        )

        let layout = workspace.focusedTab.map {
            makeLayoutView(for: $0.rootLayout, focusedPaneID: $0.focusedPaneID)
        }
        canvasView.render(layoutView: layout?.view, theme: currentTheme)

        if let focusedPaneView = layout?.focusedPaneView {
            DispatchQueue.main.async { [weak self, weak focusedPaneView] in
                guard let self, let focusedPaneView else {
                    return
                }

                view.window?.makeFirstResponder(focusedPaneView.focusTarget)
            }
        }
    }

    func updateTheme(_ theme: WorkspaceShellTheme) {
        currentTheme = theme
        apply(theme: theme)
        if let currentWorkspace {
            update(workspace: currentWorkspace)
        }
    }

    private func apply(theme: WorkspaceShellTheme) {
        view.layer?.backgroundColor = theme.shell.windowBackground.cgColor
        view.window?.backgroundColor = theme.shell.windowBackground
        sidebarView.apply(theme: theme)
        topBarView.apply(theme: theme)
        canvasView.apply(theme: theme)
    }

    private func makeWorkspaceSidebarItems(
        summaries: [WorkspaceSummary],
        workspace: Workspace
    ) -> [SidebarItem] {
        summaries.map { summary in
            SidebarItem(
                kind: .workspace,
                identifier: summary.id.rawValue,
                title: summary.name,
                subtitle: "\(summary.tabCount) tabs · \(summary.paneCount) panes",
                isActive: summary.id == workspace.id,
                action: .workspace(summary.id)
            )
        }
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
                theme: currentTheme,
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
            let splitView = SplitLayoutView(axis: axis)
            var focusedPaneView: HostedTerminalPaneView?

            for child in children {
                let childLayout = makeLayoutView(for: child, focusedPaneID: focusedPaneID)
                if focusedPaneView == nil {
                    focusedPaneView = childLayout.focusedPaneView
                }
                splitView.addArrangedSubview(childLayout.view)
                if axis == .columns {
                    childLayout.view.heightAnchor.constraint(equalTo: splitView.heightAnchor).isActive = true
                } else {
                    childLayout.view.widthAnchor.constraint(equalTo: splitView.widthAnchor).isActive = true
                }
            }

            return (splitView, focusedPaneView)
        }
    }
}

struct SidebarItem {
    enum Kind {
        case workspace
        case tab
    }

    enum Action {
        case workspace(WorkspaceID)
        case tab(TabID)
    }

    let kind: Kind
    let identifier: String
    let title: String
    let subtitle: String
    let isActive: Bool
    let action: Action
}

@MainActor
final class WorkspaceSidebarView: NSView {
    private let workspacesSection = WorkspaceSidebarSectionView()
    private let container = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 0
        container.translatesAutoresizingMaskIntoConstraints = false

        addSubview(container)
        container.addArrangedSubview(workspacesSection)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            container.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            workspacesSection.widthAnchor.constraint(equalTo: container.widthAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }

    func apply(theme: WorkspaceShellTheme) {
        layer?.backgroundColor = theme.shell.sidebarBackground.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = theme.shell.subduedBorder.cgColor
        workspacesSection.apply(theme: theme)
    }

    func render(
        workspaceItems: [SidebarItem],
        theme: WorkspaceShellTheme,
        onSelectWorkspace: @escaping @MainActor (WorkspaceID) -> Void,
        onCreateWorkspace: @escaping @MainActor () -> Void,
        onSelectTab: @escaping @MainActor (TabID) -> Void
    ) {
        apply(theme: theme)

        workspacesSection.renderButtons(
            items: workspaceItems,
            title: "WORKSPACES",
            count: workspaceItems.filter { $0.kind == .workspace }.count,
            emptyState: "No workspaces open",
            theme: theme,
            accessoryTitle: "+",
            accessoryAction: onCreateWorkspace,
            buttonHandler: { item in
                switch item.action {
                case .workspace(let workspaceID):
                    onSelectWorkspace(workspaceID)
                case .tab(let tabID):
                    onSelectTab(tabID)
                }
            }
        )
    }
}

@MainActor
private final class WorkspaceSidebarSectionView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let headerStack = NSStackView()
    private let itemStack = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private var accessoryButton: ChromePillButton?
    private var itemButtons: [NSView] = []

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        itemStack.orientation = .vertical
        itemStack.alignment = .leading
        itemStack.spacing = 2
        itemStack.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        emptyLabel.font = .systemFont(ofSize: 11, weight: .regular)
        emptyLabel.maximumNumberOfLines = 2
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        headerStack.addArrangedSubview(titleLabel)
        headerStack.addArrangedSubview(NSView())

        addSubview(headerStack)
        addSubview(itemStack)
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: topAnchor),
            headerStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerStack.trailingAnchor.constraint(equalTo: trailingAnchor),

            itemStack.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 8),
            itemStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            itemStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            itemStack.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyLabel.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 8),
            emptyLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func apply(theme: WorkspaceShellTheme) {
        titleLabel.textColor = theme.shell.textMuted
        emptyLabel.textColor = theme.shell.textMuted
        accessoryButton?.configure(title: accessoryButton?.displayTitleLabel.stringValue ?? "+", active: false, theme: theme, compact: true)
    }

    func renderButtons(
        items: [SidebarItem],
        title: String,
        count: Int,
        emptyState: String,
        theme: WorkspaceShellTheme,
        accessoryTitle: String?,
        accessoryAction: (() -> Void)?,
        buttonHandler: @escaping (SidebarItem) -> Void
    ) {
        titleLabel.stringValue = "\(title) · \(count)"
        emptyLabel.stringValue = emptyState

        for button in itemButtons {
            itemStack.removeArrangedSubview(button)
            button.removeFromSuperview()
        }
        itemButtons.removeAll()

        if let accessoryButton {
            headerStack.removeArrangedSubview(accessoryButton)
            accessoryButton.removeFromSuperview()
        }
        accessoryButton = nil
        if let accessoryTitle, let accessoryAction {
            let button = ChromePillButton()
            button.configure(title: accessoryTitle, active: false, theme: theme, compact: true)
            button.onPress = accessoryAction
            accessoryButton = button
            headerStack.addArrangedSubview(button)
        }

        emptyLabel.isHidden = !items.isEmpty
        itemStack.isHidden = items.isEmpty

        for item in items {
            let button = SidebarItemButton()
            button.configure(item: item, theme: theme)
            button.onPress = {
                buttonHandler(item)
            }
            itemStack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: itemStack.widthAnchor).isActive = true
            button.heightAnchor.constraint(equalToConstant: 28).isActive = true
            itemButtons.append(button)
        }
    }
}

@MainActor
final class WorkspaceTopBarView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let themePicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let themeActionProxy = ThemePickerProxy()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 12

        let titleColumn = NSStackView()
        titleColumn.orientation = .vertical
        titleColumn.spacing = 2
        titleColumn.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        pathLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)

        titleColumn.addArrangedSubview(titleLabel)
        titleColumn.addArrangedSubview(pathLabel)

        themePicker.translatesAutoresizingMaskIntoConstraints = false
        themePicker.setContentHuggingPriority(.required, for: .horizontal)
        themePicker.font = .systemFont(ofSize: 12, weight: .medium)
        themePicker.controlSize = .small

        let content = NSStackView()
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 12
        content.translatesAutoresizingMaskIntoConstraints = false
        content.addArrangedSubview(titleColumn)
        content.addArrangedSubview(NSView())
        content.addArrangedSubview(themePicker)

        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func apply(theme: WorkspaceShellTheme) {
        layer?.backgroundColor = theme.shell.topBarBackground.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = theme.shell.subduedBorder.cgColor
        titleLabel.textColor = theme.shell.textPrimary
        pathLabel.textColor = theme.shell.textSecondary
        themePicker.contentTintColor = theme.shell.textPrimary
    }

    func render(
        workspace: Workspace,
        theme: WorkspaceShellTheme,
        availableThemes: [WorkspaceShellTheme],
        onSelectTheme: @escaping @MainActor (String) -> Void
    ) {
        apply(theme: theme)
        titleLabel.stringValue = workspace.name
        pathLabel.stringValue = workspace.rootPath

        themePicker.removeAllItems()
        themePicker.addItems(withTitles: availableThemes.map(\.displayName))
        if let selectedIndex = availableThemes.firstIndex(where: { $0.identifier == theme.identifier }) {
            themePicker.selectItem(at: selectedIndex)
        }

        themePicker.action = #selector(ThemePickerProxy.selectTheme(_:))
        themePicker.target = themeActionProxy
        themeActionProxy.onSelectTheme = { [weak themePicker] in
            guard let themePicker else {
                return
            }

            let selectedIndex = themePicker.indexOfSelectedItem
            guard availableThemes.indices.contains(selectedIndex) else {
                return
            }

            onSelectTheme(availableThemes[selectedIndex].identifier)
        }
    }
}

@MainActor
private final class ThemePickerProxy: NSObject {
    var onSelectTheme: (() -> Void)?

    @objc func selectTheme(_ sender: NSPopUpButton) {
        _ = sender
        onSelectTheme?()
    }
}

@MainActor
final class WorkspaceCanvasView: NSView {
    private var currentContentView: NSView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 14
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func apply(theme: WorkspaceShellTheme) {
        layer?.backgroundColor = theme.shell.canvasBackground.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = theme.shell.subduedBorder.cgColor
    }

    func render(layoutView: NSView?, theme: WorkspaceShellTheme) {
        apply(theme: theme)
        currentContentView?.removeFromSuperview()
        currentContentView = nil

        guard let layoutView else {
            return
        }

        layoutView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(layoutView)
        currentContentView = layoutView
        NSLayoutConstraint.activate([
            layoutView.topAnchor.constraint(equalTo: topAnchor, constant: ShellLayoutMetrics.canvasPadding),
            layoutView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ShellLayoutMetrics.canvasPadding),
            layoutView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -ShellLayoutMetrics.canvasPadding),
            layoutView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -ShellLayoutMetrics.canvasPadding),
        ])
    }
}

@MainActor
private final class SplitLayoutView: NSStackView {
    init(axis: PaneSplitAxis) {
        super.init(frame: .zero)
        orientation = axis == .columns ? .horizontal : .vertical
        distribution = .fillEqually
        spacing = ShellLayoutMetrics.splitSpacing
        alignment = axis == .columns ? .height : .width
        translatesAutoresizingMaskIntoConstraints = false
        setHuggingPriority(.defaultLow, for: .horizontal)
        setHuggingPriority(.defaultLow, for: .vertical)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

@MainActor
final class PaneStackView: NSView {
    private let terminalPaneView: HostedTerminalPaneView
    private let paneCardView = PaneCardView()

    init(
        paneStack: PaneStack,
        focusedPaneID: PaneID,
        bridge: GhosttyTerminalBridge,
        theme: WorkspaceShellTheme,
        onSelectPaneTab: @escaping @MainActor (PaneID) -> Void,
        onCreatePaneTab: @escaping @MainActor () throws -> Void,
        onClosePaneTab: @escaping @MainActor (PaneID) throws -> Void,
        onFocus: @escaping @MainActor (PaneID) -> Void
    ) {
        let activePane = paneStack.focusedPane ?? paneStack.panes[0]
        self.terminalPaneView = bridge.makeHostedPaneView(
            for: activePane,
            isFocused: activePane.id == focusedPaneID,
            themePalette: theme.terminalPalette,
            onFocus: onFocus
        )
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let headerView = PaneHeaderView(
            paneStack: paneStack,
            theme: theme,
            onSelectPaneTab: onSelectPaneTab,
            onCreatePaneTab: onCreatePaneTab,
            onClosePaneTab: onClosePaneTab
        )
        paneCardView.configure(
            headerView: headerView,
            terminalPaneView: terminalPaneView,
            theme: theme,
            focused: activePane.id == focusedPaneID
        )
        addSubview(paneCardView)

        NSLayoutConstraint.activate([
            paneCardView.topAnchor.constraint(equalTo: topAnchor),
            paneCardView.leadingAnchor.constraint(equalTo: leadingAnchor),
            paneCardView.trailingAnchor.constraint(equalTo: trailingAnchor),
            paneCardView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    var focusedPaneView: HostedTerminalPaneView {
        terminalPaneView
    }
}

@MainActor
final class PaneCardView: NSView {
    private let container = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 12

        container.orientation = .vertical
        container.spacing = 0
        container.translatesAutoresizingMaskIntoConstraints = false
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

    func configure(
        headerView: PaneHeaderView,
        terminalPaneView: HostedTerminalPaneView,
        theme: WorkspaceShellTheme,
        focused: Bool
    ) {
        container.arrangedSubviews.forEach { view in
            container.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        terminalPaneView.apply(themePalette: theme.terminalPalette)
        headerView.heightAnchor.constraint(equalToConstant: ShellLayoutMetrics.paneHeaderHeight).isActive = true

        container.addArrangedSubview(headerView)
        container.addArrangedSubview(terminalPaneView)

        layer?.backgroundColor = theme.shell.paneCardBackground.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = (focused ? theme.shell.accent : theme.shell.border).cgColor
    }
}

@MainActor
final class PaneHeaderView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let tabStrip = NSStackView()
    private let controls = NSStackView()

    init(
        paneStack: PaneStack,
        theme: WorkspaceShellTheme,
        onSelectPaneTab: @escaping @MainActor (PaneID) -> Void,
        onCreatePaneTab: @escaping @MainActor () throws -> Void,
        onClosePaneTab: @escaping @MainActor (PaneID) throws -> Void
    ) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = theme.shell.paneHeaderBackground.cgColor

        let content = NSStackView()
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 6
        content.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = theme.shell.textSecondary
        titleLabel.stringValue = paneStack.focusedPane?.title ?? "Pane"

        tabStrip.orientation = .horizontal
        tabStrip.alignment = .centerY
        tabStrip.spacing = 6

        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 6

        for pane in paneStack.panes {
            let button = ChromePillButton()
            button.configure(
                title: pane.title,
                active: pane.id == paneStack.focusedPaneID,
                theme: theme,
                compact: true
            )
            button.onPress = { onSelectPaneTab(pane.id) }
            tabStrip.addArrangedSubview(button)
        }

        let addButton = ChromePillButton()
        addButton.configure(title: "+", active: false, theme: theme, compact: true)
        addButton.onPress = {
            try? onCreatePaneTab()
        }
        controls.addArrangedSubview(addButton)

        let closeButton = ChromePillButton()
        closeButton.configure(title: "x", active: false, theme: theme, compact: true)
        closeButton.isEnabled = paneStack.panes.count > 1
        closeButton.onPress = {
            try? onClosePaneTab(paneStack.focusedPaneID)
        }
        controls.addArrangedSubview(closeButton)

        content.addArrangedSubview(titleLabel)
        content.addArrangedSubview(tabStrip)
        content.addArrangedSubview(NSView())
        content.addArrangedSubview(controls)
        addSubview(content)

        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

@MainActor
private class ChromePillButton: NSControl {
    var onPress: (() -> Void)?
    private let titleLabel = NSTextField(labelWithString: "")
    private var compact = false
    private var contentInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.masksToBounds = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.alignment = .center
        addSubview(titleLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func configure(title: String, active: Bool, theme: WorkspaceShellTheme, compact: Bool = false) {
        self.compact = compact
        contentInsets = NSEdgeInsets(top: compact ? 3 : 5, left: compact ? 8 : 10, bottom: compact ? 3 : 5, right: compact ? 8 : 10)
        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: compact ? 11 : 12, weight: active ? .semibold : .medium)
        titleLabel.textColor = active ? theme.shell.textPrimary : theme.shell.textSecondary
        layer?.cornerRadius = compact ? 7 : 8
        layer?.backgroundColor = (active ? theme.shell.chromeButtonActiveBackground : theme.shell.chromeButtonBackground).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = (active ? theme.shell.accent.withAlphaComponent(0.45) : theme.shell.subduedBorder).cgColor
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override var intrinsicContentSize: NSSize {
        let labelSize = titleLabel.intrinsicContentSize
        return NSSize(
            width: labelSize.width + contentInsets.left + contentInsets.right,
            height: max(labelSize.height + contentInsets.top + contentInsets.bottom, compact ? 22 : 28)
        )
    }

    override func layout() {
        super.layout()
        titleLabel.frame = bounds.insetBy(dx: contentInsets.left, dy: contentInsets.top)
    }

    override var acceptsFirstResponder: Bool { false }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else {
            return
        }

        onPress?()
        super.mouseDown(with: event)
    }

    fileprivate var displayTitleLabel: NSTextField {
        titleLabel
    }
}

@MainActor
final class SidebarItemButton: NSView {
    var onPress: (() -> Void)?
    private let titleField = NSTextField(labelWithString: "")
    private var leadingInset: CGFloat = 12

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 4

        titleField.maximumNumberOfLines = 1
        titleField.lineBreakMode = .byTruncatingTail
        titleField.isBezeled = false
        titleField.drawsBackground = false
        titleField.isEditable = false
        titleField.isSelectable = false
        addSubview(titleField)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func configure(item: SidebarItem, theme: WorkspaceShellTheme) {
        switch item.kind {
        case .workspace:
            titleField.font = .systemFont(ofSize: 13, weight: .semibold)
            leadingInset = 12
        case .tab:
            titleField.font = .systemFont(ofSize: 12, weight: .regular)
            leadingInset = 12
        }

        titleField.stringValue = item.title
        titleField.textColor = item.isActive ? theme.shell.textPrimary : theme.shell.textSecondary
        layer?.backgroundColor = item.isActive
            ? theme.shell.selection.cgColor
            : NSColor.clear.cgColor
        layer?.borderWidth = item.isActive ? 1 : 0
        layer?.borderColor = theme.shell.accent.withAlphaComponent(0.28).cgColor
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let trailingInset: CGFloat = 12
        let labelWidth = bounds.width - leadingInset - trailingInset
        let labelHeight = titleField.intrinsicContentSize.height
        titleField.frame = NSRect(
            x: leadingInset,
            y: (bounds.height - labelHeight) / 2,
            width: max(labelWidth, 0),
            height: labelHeight
        )
    }

    override var acceptsFirstResponder: Bool { false }

    override func mouseDown(with event: NSEvent) {
        onPress?()
    }
}
