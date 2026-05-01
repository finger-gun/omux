import AppKit
import OmuxCore
import OmuxTerminalBridge

private enum ShellLayoutMetrics {
    static let sidebarWidth: CGFloat = 224
    static let outerPadding: CGFloat = 0
    static let interRegionSpacing: CGFloat = 0
    static let canvasPadding: CGFloat = 0
    static let splitSpacing: CGFloat = 8
    static let paneHeaderHeight: CGFloat = 28
}

@MainActor
final class WorkspaceWindowController: NSWindowController {
    private let rootViewController: WorkspaceShellViewController

    init(
        workspace: Workspace,
        controller: WorkspaceController,
        initialTheme: WorkspaceShellTheme = .defaultTheme,
        sidebarVisibilityStore: any WorkspaceSidebarVisibilityStoring = WorkspaceSidebarVisibilityStore.shared
    ) {
        self.rootViewController = WorkspaceShellViewController(
            controller: controller,
            initialTheme: initialTheme,
            sidebarVisibilityStore: sidebarVisibilityStore
        )
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 1220, height: 780),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
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

    func toggleSidebarVisibility() {
        rootViewController.toggleSidebarVisibility()
    }

    func presentRenameWorkspacePrompt(workspaceID: WorkspaceID? = nil) {
        rootViewController.presentRenameWorkspacePrompt(workspaceID: workspaceID)
    }
}

@MainActor
final class WorkspaceShellViewController: NSViewController {
    private let controller: WorkspaceController
    private let metadataResolver = TerminalSidebarMetadataResolver()
    private let sidebarView = WorkspaceSidebarView()
    private let canvasView = WorkspaceCanvasView()
    private let sidebarVisibilityStore: any WorkspaceSidebarVisibilityStoring
    private var sidebarWidthConstraint: NSLayoutConstraint?
    private var mainColumnLeadingConstraint: NSLayoutConstraint?
    private var currentWorkspace: Workspace?
    private var currentTheme: WorkspaceShellTheme
    private var isSidebarVisible: Bool

    init(
        controller: WorkspaceController,
        initialTheme: WorkspaceShellTheme,
        sidebarVisibilityStore: any WorkspaceSidebarVisibilityStoring
    ) {
        self.controller = controller
        self.currentTheme = initialTheme
        self.sidebarVisibilityStore = sidebarVisibilityStore
        self.isSidebarVisible = sidebarVisibilityStore.isSidebarVisible
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
        mainColumn.alignment = .width
        mainColumn.distribution = .fill
        mainColumn.spacing = 0
        mainColumn.translatesAutoresizingMaskIntoConstraints = false

        mainColumn.addArrangedSubview(canvasView)

        view.addSubview(sidebarView)
        view.addSubview(mainColumn)

        let sidebarWidthConstraint = sidebarView.widthAnchor.constraint(equalToConstant: ShellLayoutMetrics.sidebarWidth)
        let mainColumnLeadingConstraint = mainColumn.leadingAnchor.constraint(
            equalTo: sidebarView.trailingAnchor,
            constant: ShellLayoutMetrics.interRegionSpacing
        )
        self.sidebarWidthConstraint = sidebarWidthConstraint
        self.mainColumnLeadingConstraint = mainColumnLeadingConstraint

        NSLayoutConstraint.activate([
            sidebarView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            sidebarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sidebarView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebarWidthConstraint,

            mainColumn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: ShellLayoutMetrics.outerPadding),
            mainColumnLeadingConstraint,
            mainColumn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -ShellLayoutMetrics.outerPadding),
            mainColumn.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -ShellLayoutMetrics.outerPadding),
            canvasView.widthAnchor.constraint(equalTo: mainColumn.widthAnchor),
        ])

        applySidebarVisibility()
    }

    func update(workspace: Workspace) {
        currentWorkspace = workspace
        apply(theme: currentTheme)

        let workspaceItems = makeWorkspaceSidebarItems(
            workspaces: controller.allWorkspaces(),
            activeWorkspace: workspace
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
            onDeleteWorkspace: { [weak self] in
                _ = try? self?.controller.deleteActiveWorkspace()
            },
            canDeleteWorkspace: controller.canDeleteActiveWorkspace(),
            onSelectPane: { [weak self] paneID in
                _ = self?.controller.focus(paneID: paneID)
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
        canvasView.apply(theme: theme)
    }

    func toggleSidebarVisibility() {
        isSidebarVisible.toggle()
        sidebarVisibilityStore.isSidebarVisible = isSidebarVisible
        applySidebarVisibility()
    }

    private func applySidebarVisibility() {
        sidebarView.isHidden = !isSidebarVisible
        sidebarWidthConstraint?.constant = isSidebarVisible ? ShellLayoutMetrics.sidebarWidth : 0
        mainColumnLeadingConstraint?.constant = isSidebarVisible ? ShellLayoutMetrics.interRegionSpacing : 0
        view.layoutSubtreeIfNeeded()
    }

    private func makeWorkspaceSidebarItems(
        workspaces: [Workspace],
        activeWorkspace: Workspace
    ) -> [SidebarItem] {
        workspaces.flatMap { workspace in
            let workspaceItem = SidebarItem(
                kind: .workspace,
                identifier: workspace.id.rawValue,
                title: workspace.name,
                subtitle: nil,
                isActive: workspace.id == activeWorkspace.id,
                action: .workspace(workspace.id),
                contextMenuProvider: { [weak self] in
                    guard let self else { return NSMenu() }
                    return makeWorkspaceContextMenu(for: workspace)
                }
            )

            let terminalItems = workspace.tabs
                .flatMap { tab in
                    tab.panes.map { pane -> SidebarItem in
                        let metadata = metadataResolver.metadata(for: pane)
                        let paneStack = tab.rootLayout.paneStack(containingPaneID: pane.id)
                        return SidebarItem(
                            kind: .terminal,
                            identifier: pane.id.rawValue,
                            title: metadata.title,
                            subtitle: metadata.subtitle,
                            isActive: workspace.id == activeWorkspace.id && pane.id == activeWorkspace.focusedPane?.id,
                            action: .pane(pane.id),
                            contextMenuProvider: { [weak self] in
                                guard let self, let paneStack else { return NSMenu() }
                                return makePaneTabContextMenu(pane: pane, paneStack: paneStack)
                            }
                        )
                    }
                }

            return [workspaceItem] + terminalItems
        }
    }

    func presentRenameWorkspacePrompt(workspaceID: WorkspaceID? = nil) {
        guard let workspace = workspaceID.flatMap({ id in
            controller.allWorkspaces().first(where: { $0.id == id })
        }) ?? controller.activeWorkspace() else {
            return
        }

        let alert = NSAlert()
        alert.messageText = "Rename Workspace"
        alert.informativeText = "Choose a new name for this workspace."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let nameField = NSTextField(string: workspace.customName ?? workspace.name)
        nameField.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = nameField

        let rename = { [weak self] in
            guard let self else { return }
            do {
                _ = try controller.renameWorkspace(workspace.id, to: nameField.stringValue)
            } catch {
                assertionFailure("Failed to rename workspace: \(error)")
            }
        }

        if let window = view.window {
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn {
                    rename()
                }
            }
        } else if alert.runModal() == .alertFirstButtonReturn {
            rename()
        }
    }

    private func presentRenamePanePrompt(paneID: PaneID, currentTitle: String) {
        let alert = NSAlert()
        alert.messageText = "Rename Tab"
        alert.informativeText = "Choose a new name for this terminal tab."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let nameField = NSTextField(string: currentTitle)
        nameField.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = nameField

        let rename = { [weak self] in
            guard let self else { return }
            _ = controller.renamePaneTab(paneID, to: nameField.stringValue)
        }

        if let window = view.window {
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn {
                    rename()
                }
            }
        } else if alert.runModal() == .alertFirstButtonReturn {
            rename()
        }
    }

    private func makeWorkspaceContextMenu(for workspace: Workspace) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Rename…", action: nil, keyEquivalent: "").onSelect { [weak self] in
            self?.presentRenameWorkspacePrompt(workspaceID: workspace.id)
        }
        if workspace.hasCustomName {
            menu.addItem(withTitle: "Remove Custom Name", action: nil, keyEquivalent: "").onSelect { [weak self] in
                _ = self?.controller.removeCustomWorkspaceName(workspace.id)
            }
        }
        menu.addItem(.separator())

        let closeItem = menu.addItem(withTitle: "Close", action: nil, keyEquivalent: "")
        closeItem.isEnabled = controller.allWorkspaces().count > 1
        closeItem.onSelect { [weak self] in
            _ = try? self?.controller.closeWorkspace(workspace.id)
        }

        let index = controller.allWorkspaces().firstIndex(where: { $0.id == workspace.id }) ?? 0
        let totalCount = controller.allWorkspaces().count

        let closeOthersItem = menu.addItem(withTitle: "Close Others", action: nil, keyEquivalent: "")
        closeOthersItem.isEnabled = totalCount > 1
        closeOthersItem.onSelect { [weak self] in
            _ = try? self?.controller.closeOtherWorkspaces(keeping: workspace.id)
        }

        let closeAboveItem = menu.addItem(withTitle: "Close Above", action: nil, keyEquivalent: "")
        closeAboveItem.isEnabled = index > 0
        closeAboveItem.onSelect { [weak self] in
            _ = try? self?.controller.closeWorkspacesAbove(workspace.id)
        }

        let closeBelowItem = menu.addItem(withTitle: "Close Below", action: nil, keyEquivalent: "")
        closeBelowItem.isEnabled = index < totalCount - 1
        closeBelowItem.onSelect { [weak self] in
            _ = try? self?.controller.closeWorkspacesBelow(workspace.id)
        }
        return menu
    }

    private func makePaneTabContextMenu(
        pane: Pane,
        paneStack: PaneStack
    ) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Rename…", action: nil, keyEquivalent: "").onSelect { [weak self] in
            self?.presentRenamePanePrompt(paneID: pane.id, currentTitle: pane.title)
        }

        let closeItem = menu.addItem(withTitle: "Close", action: nil, keyEquivalent: "")
        closeItem.isEnabled = paneStack.panes.count > 1
        closeItem.onSelect { [weak self] in
            _ = try? self?.controller.closePaneTab(paneID: pane.id)
        }

        let targetIndex = paneStack.panes.firstIndex(where: { $0.id == pane.id }) ?? 0

        let closeOthersItem = menu.addItem(withTitle: "Close Others", action: nil, keyEquivalent: "")
        closeOthersItem.isEnabled = paneStack.panes.count > 1
        closeOthersItem.onSelect { [weak self] in
            _ = try? self?.controller.closeOtherPaneTabs(paneID: pane.id)
        }

        let closeAboveItem = menu.addItem(withTitle: "Close Above", action: nil, keyEquivalent: "")
        closeAboveItem.isEnabled = targetIndex > 0
        closeAboveItem.onSelect { [weak self] in
            _ = try? self?.controller.closePaneTabsAbove(paneID: pane.id)
        }

        let closeBelowItem = menu.addItem(withTitle: "Close Below", action: nil, keyEquivalent: "")
        closeBelowItem.isEnabled = targetIndex < paneStack.panes.count - 1
        closeBelowItem.onSelect { [weak self] in
            _ = try? self?.controller.closePaneTabsBelow(paneID: pane.id)
        }
        return menu
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
                contextMenuProvider: { [weak self] pane in
                    guard let self else { return NSMenu() }
                    return makePaneTabContextMenu(pane: pane, paneStack: paneStack)
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
        case terminal
    }

    enum Action {
        case workspace(WorkspaceID)
        case pane(PaneID)
    }

    let kind: Kind
    let identifier: String
    let title: String
    let subtitle: String?
    let isActive: Bool
    let action: Action
    let contextMenuProvider: (() -> NSMenu)?

    var rowHeight: CGFloat {
        switch kind {
        case .workspace:
            return 28
        case .terminal:
            return subtitle == nil ? 26 : 34
        }
    }
}

private struct SidebarSectionAccessory {
    enum Content {
        case text(String)
        case symbol(name: String, accessibilityLabel: String)
    }

    let content: Content
    let isEnabled: Bool
    let action: () -> Void
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
        layer?.borderWidth = 0
        workspacesSection.apply(theme: theme)
    }

    func render(
        workspaceItems: [SidebarItem],
        theme: WorkspaceShellTheme,
        onSelectWorkspace: @escaping @MainActor (WorkspaceID) -> Void,
        onCreateWorkspace: @escaping @MainActor () -> Void,
        onDeleteWorkspace: @escaping @MainActor () -> Void,
        canDeleteWorkspace: Bool,
        onSelectPane: @escaping @MainActor (PaneID) -> Void
    ) {
        apply(theme: theme)

        workspacesSection.renderButtons(
            items: workspaceItems,
            title: "WORKSPACES",
            count: workspaceItems.filter { $0.kind == .workspace }.count,
            emptyState: "No workspaces open",
            theme: theme,
            accessories: [
                SidebarSectionAccessory(
                    content: .symbol(name: "plus", accessibilityLabel: "Create workspace"),
                    isEnabled: true,
                    action: onCreateWorkspace
                ),
                SidebarSectionAccessory(
                    content: .symbol(name: "xmark", accessibilityLabel: "Close active workspace"),
                    isEnabled: canDeleteWorkspace,
                    action: onDeleteWorkspace
                ),
            ],
            buttonHandler: { item in
                switch item.action {
                case .workspace(let workspaceID):
                    onSelectWorkspace(workspaceID)
                case .pane(let paneID):
                    onSelectPane(paneID)
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
    private var accessoryButtons: [ChromePillButton] = []
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
        accessoryButtons.forEach { $0.applyTheme(theme) }
    }

    func renderButtons(
        items: [SidebarItem],
        title: String,
        count: Int,
        emptyState: String,
        theme: WorkspaceShellTheme,
        accessories: [SidebarSectionAccessory],
        buttonHandler: @escaping (SidebarItem) -> Void
    ) {
        titleLabel.stringValue = "\(title) · \(count)"
        emptyLabel.stringValue = emptyState

        for button in itemButtons {
            itemStack.removeArrangedSubview(button)
            button.removeFromSuperview()
        }
        itemButtons.removeAll()

        for accessoryButton in accessoryButtons {
            headerStack.removeArrangedSubview(accessoryButton)
            accessoryButton.removeFromSuperview()
        }
        accessoryButtons.removeAll()
        for accessory in accessories {
            let button = ChromePillButton()
            switch accessory.content {
            case .text(let title):
                button.configure(title: title, active: false, theme: theme, compact: true)
            case .symbol(let name, let accessibilityLabel):
                button.configure(symbolName: name, accessibilityLabel: accessibilityLabel, active: false, theme: theme, compact: true)
            }
            button.isEnabled = accessory.isEnabled
            button.onPress = accessory.action
            accessoryButtons.append(button)
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
            button.contextMenuProvider = item.contextMenuProvider
            itemStack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: itemStack.widthAnchor).isActive = true
            button.heightAnchor.constraint(equalToConstant: item.rowHeight).isActive = true
            itemButtons.append(button)
        }
    }
}

@MainActor
final class WorkspaceCanvasView: NSView {
    private var currentContentView: NSView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func apply(theme: WorkspaceShellTheme) {
        layer?.backgroundColor = theme.shell.canvasBackground.cgColor
        layer?.borderWidth = 0
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
        contextMenuProvider: @escaping @MainActor (Pane) -> NSMenu,
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
            onClosePaneTab: onClosePaneTab,
            contextMenuProvider: contextMenuProvider
        )
        paneCardView.configure(
            headerView: headerView,
            statusText: activePane.terminalState.statusSummary,
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
    private let statusLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        container.orientation = .vertical
        container.alignment = .width
        container.distribution = .fill
        container.spacing = 0
        container.translatesAutoresizingMaskIntoConstraints = false
        addSubview(container)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 11, weight: .regular)
        statusLabel.lineBreakMode = .byTruncatingMiddle

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
        statusText: String?,
        terminalPaneView: HostedTerminalPaneView,
        theme: WorkspaceShellTheme,
        focused: Bool
    ) {
        container.arrangedSubviews.forEach { view in
            container.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        terminalPaneView.apply(themePalette: theme.terminalPalette)
        terminalPaneView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        terminalPaneView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        headerView.heightAnchor.constraint(equalToConstant: ShellLayoutMetrics.paneHeaderHeight).isActive = true
        statusLabel.stringValue = statusText ?? ""
        statusLabel.textColor = theme.shell.textMuted
        statusLabel.isHidden = statusText == nil

        container.addArrangedSubview(headerView)
        headerView.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
        if statusText != nil {
            container.addArrangedSubview(statusLabel)
            statusLabel.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
        }
        container.addArrangedSubview(terminalPaneView)
        terminalPaneView.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true

        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderWidth = 0
        layer?.borderColor = nil
    }
}

@MainActor
final class PaneHeaderView: NSView {
    private let tabStrip = NSStackView()
    private let controls = NSStackView()

    init(
        paneStack: PaneStack,
        theme: WorkspaceShellTheme,
        onSelectPaneTab: @escaping @MainActor (PaneID) -> Void,
        onCreatePaneTab: @escaping @MainActor () throws -> Void,
        onClosePaneTab: @escaping @MainActor (PaneID) throws -> Void,
        contextMenuProvider: @escaping @MainActor (Pane) -> NSMenu
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
            button.contextMenuProvider = { contextMenuProvider(pane) }
            tabStrip.addArrangedSubview(button)
        }

        let addButton = ChromePillButton()
        addButton.configure(symbolName: "plus", accessibilityLabel: "Add pane tab", active: false, theme: theme, compact: true)
        addButton.onPress = {
            try? onCreatePaneTab()
        }
        controls.addArrangedSubview(addButton)

        let closeButton = ChromePillButton()
        closeButton.configure(symbolName: "xmark", accessibilityLabel: "Close pane tab", active: false, theme: theme, compact: true)
        closeButton.isEnabled = paneStack.panes.count > 1
        closeButton.onPress = {
            try? onClosePaneTab(paneStack.focusedPaneID)
        }
        controls.addArrangedSubview(closeButton)

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
    private var currentTheme = WorkspaceShellTheme.defaultTheme

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
        let foreground = isActive ? currentTheme.shell.textPrimary : currentTheme.shell.textSecondary
        titleLabel.textColor = foreground
        imageView.contentTintColor = foreground
        layer?.backgroundColor = (isActive ? currentTheme.shell.selection : NSColor.clear).cgColor
        layer?.borderWidth = 0
        layer?.borderColor = nil
        alphaValue = isEnabled ? 1 : 0.4
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

    override var acceptsFirstResponder: Bool { false }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else {
            return
        }

        onPress?()
        super.mouseDown(with: event)
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
final class SidebarItemButton: NSView {
    var onPress: (() -> Void)?
    var contextMenuProvider: (() -> NSMenu?)? {
        didSet {
            menu = contextMenuProvider?()
        }
    }
    private let titleField = NSTextField(labelWithString: "")
    private let subtitleField = NSTextField(labelWithString: "")
    private var leadingInset: CGFloat = 12

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        titleField.maximumNumberOfLines = 1
        titleField.lineBreakMode = .byTruncatingTail
        titleField.isBezeled = false
        titleField.drawsBackground = false
        titleField.isEditable = false
        titleField.isSelectable = false
        addSubview(titleField)

        subtitleField.maximumNumberOfLines = 1
        subtitleField.lineBreakMode = .byTruncatingMiddle
        subtitleField.isBezeled = false
        subtitleField.drawsBackground = false
        subtitleField.isEditable = false
        subtitleField.isSelectable = false
        addSubview(subtitleField)
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
            subtitleField.font = .systemFont(ofSize: 11, weight: .regular)
        case .terminal:
            titleField.font = .systemFont(ofSize: 10, weight: .regular)
            subtitleField.font = .systemFont(ofSize: 10, weight: .regular)
            leadingInset = 22
        }

        titleField.stringValue = item.title
        titleField.textColor = item.kind == .terminal
            ? theme.shell.textMuted
            : (item.isActive ? theme.shell.textPrimary : theme.shell.textSecondary)
        subtitleField.stringValue = item.subtitle ?? ""
        subtitleField.textColor = theme.shell.textMuted
        subtitleField.isHidden = item.subtitle == nil
        switch item.kind {
        case .workspace:
            layer?.backgroundColor = item.isActive
                ? theme.shell.selection.cgColor
                : NSColor.clear.cgColor
        case .terminal:
            layer?.backgroundColor = item.isActive
                ? theme.shell.selection.withAlphaComponent(0.28).cgColor
                : NSColor.clear.cgColor
        }
        layer?.borderWidth = 0
        layer?.borderColor = nil
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let trailingInset: CGFloat = 12
        let labelWidth = bounds.width - leadingInset - trailingInset
        let titleHeight = titleField.intrinsicContentSize.height
        if subtitleField.isHidden {
            titleField.frame = NSRect(
                x: leadingInset,
                y: (bounds.height - titleHeight) / 2,
                width: max(labelWidth, 0),
                height: titleHeight
            )
            subtitleField.frame = .zero
        } else {
            let subtitleHeight = subtitleField.intrinsicContentSize.height
            let totalHeight = titleHeight + subtitleHeight + 2
            let startY = (bounds.height - totalHeight) / 2
            titleField.frame = NSRect(
                x: leadingInset,
                y: startY + subtitleHeight + 2,
                width: max(labelWidth, 0),
                height: titleHeight
            )
            subtitleField.frame = NSRect(
                x: leadingInset,
                y: startY,
                width: max(labelWidth, 0),
                height: subtitleHeight
            )
        }
    }

    override var acceptsFirstResponder: Bool { false }

    override func mouseDown(with event: NSEvent) {
        onPress?()
    }

    override func rightMouseDown(with event: NSEvent) {
        if let menu = menu ?? contextMenuProvider?() {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        } else {
            super.rightMouseDown(with: event)
        }
    }
}

@MainActor
private final class MenuActionTrampoline: NSObject {
    let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func performAction(_ sender: Any?) {
        _ = sender
        handler()
    }
}

private extension NSMenuItem {
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
