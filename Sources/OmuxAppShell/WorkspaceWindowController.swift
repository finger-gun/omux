import AppKit
import OmuxConfig
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
final class WorkspaceRootView: NSView {
    var titlebarHeightOverrideForTesting: CGFloat?
    var titlebarDoubleClickHandler: ((NSWindow) -> Void)?

    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard isInUnifiedTitlebar(event) else {
            super.mouseDown(with: event)
            return
        }

        guard let window else {
            return
        }

        if event.clickCount >= 2 {
            if let titlebarDoubleClickHandler {
                titlebarDoubleClickHandler(window)
            } else {
                window.zoom(nil)
            }
            return
        }

        window.performDrag(with: event)
    }

    func isInUnifiedTitlebar(_ event: NSEvent) -> Bool {
        let point = convert(event.locationInWindow, from: nil)
        let titlebarHeight = titlebarHeightOverrideForTesting ?? safeAreaInsets.top
        guard titlebarHeight > 0 else {
            return false
        }
        return point.y >= bounds.maxY - titlebarHeight
    }
}

@MainActor
final class WorkspaceWindowController: NSWindowController {
    private let controller: WorkspaceController
    private let rootViewController: WorkspaceShellViewController

    init(
        workspace: Workspace,
        controller: WorkspaceController,
        initialTheme: WorkspaceShellTheme = .defaultTheme,
        initialIcons: OmuxConfigUI.Icons = OmuxConfigUI.Icons(),
        sidebarVisibilityStore: any WorkspaceSidebarVisibilityStoring = WorkspaceSidebarVisibilityStore.shared
    ) {
        self.controller = controller
        self.rootViewController = WorkspaceShellViewController(
            controller: controller,
            initialTheme: initialTheme,
            initialIcons: initialIcons,
            sidebarVisibilityStore: sidebarVisibilityStore
        )
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 1220, height: 780),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 720, height: 480)
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.title = workspace.name
        window.contentViewController = rootViewController
        window.setContentSize(NSSize(width: 1220, height: 780))
        super.init(window: window)
        rootViewController.update(workspace: workspace)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func update(workspace: Workspace) {
        let displayedWorkspace = controller.activeWorkspace() ?? workspace
        window?.title = displayedWorkspace.name
        rootViewController.update(workspace: displayedWorkspace)
    }

    func updateTheme(_ theme: WorkspaceShellTheme) {
        rootViewController.updateTheme(theme)
    }

    func updateIcons(_ icons: OmuxConfigUI.Icons) {
        rootViewController.updateIcons(icons)
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
    private let iconResolver = WorkspaceIconResolver()
    private let sidebarView = WorkspaceSidebarView()
    private let canvasView = WorkspaceCanvasView()
    private let sidebarVisibilityStore: any WorkspaceSidebarVisibilityStoring
    private var sidebarWidthConstraint: NSLayoutConstraint?
    private var mainColumnLeadingConstraint: NSLayoutConstraint?
    private var currentWorkspace: Workspace?
    private var currentTheme: WorkspaceShellTheme
    private var currentIcons: OmuxConfigUI.Icons
    private var isSidebarVisible: Bool
    private var focusRestoreGeneration: UInt = 0
    private var terminalIconRefreshTimer: Timer?
    private var renderedIconKindByPaneID: [PaneID: OmuxSemanticIcon.Kind] = [:]

    init(
        controller: WorkspaceController,
        initialTheme: WorkspaceShellTheme,
        initialIcons: OmuxConfigUI.Icons,
        sidebarVisibilityStore: any WorkspaceSidebarVisibilityStoring
    ) {
        self.controller = controller
        self.currentTheme = initialTheme
        self.currentIcons = initialIcons
        self.sidebarVisibilityStore = sidebarVisibilityStore
        self.isSidebarVisible = sidebarVisibilityStore.isSidebarVisible
        super.init(nibName: nil, bundle: nil)
    }

    deinit {
        MainActor.assumeIsolated {
            terminalIconRefreshTimer?.invalidate()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = WorkspaceRootView()
        view.translatesAutoresizingMaskIntoConstraints = true
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
        startTerminalIconRefreshTimer()
    }

    func update(workspace: Workspace) {
        let previousWorkspaceID = currentWorkspace?.id
        let previousFocusedPaneID = currentWorkspace?.focusedPane?.id
        let shouldRestoreFocus = shouldRestoreFocus(
            previousWorkspaceID: previousWorkspaceID,
            previousFocusedPaneID: previousFocusedPaneID,
            workspace: workspace
        )
        invalidateIconCacheForChangedPaths(from: currentWorkspace, to: workspace)
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
            updateAvailability: controller.currentUpdateAvailability(),
            onMoveWorkspace: { [weak self] workspaceID, targetIndex in
                _ = self?.controller.moveWorkspace(workspaceID, toDisplayIndex: targetIndex)
            },
            onSelectPane: { [weak self] paneID in
                _ = self?.controller.focus(paneID: paneID)
            }
        )

        let layout = workspace.focusedTab.map {
            makeLayoutView(for: $0.rootLayout, focusedPaneID: $0.focusedPaneID)
        }
        canvasView.render(layoutView: layout?.view, theme: currentTheme)
        renderedIconKindByPaneID = iconKindSignature(for: workspace)

        if shouldRestoreFocus, let focusedPaneView = layout?.focusedPaneView {
            focusRestoreGeneration &+= 1
            let generation = focusRestoreGeneration

            if let window = view.window {
                window.makeFirstResponder(focusedPaneView.focusTarget)
            } else {
                DispatchQueue.main.async { [weak self, weak focusedPaneView] in
                    guard let self,
                          let focusedPaneView,
                          self.focusRestoreGeneration == generation
                    else {
                        return
                    }

                    self.view.window?.makeFirstResponder(focusedPaneView.focusTarget)
                }
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

    func updateIcons(_ icons: OmuxConfigUI.Icons) {
        currentIcons = icons
        if let currentWorkspace {
            update(workspace: currentWorkspace)
        }
    }

    private func invalidateIconCacheForChangedPaths(from previousWorkspace: Workspace?, to workspace: Workspace) {
        guard let previousWorkspace else {
            return
        }

        let previousPaths = Dictionary(
            uniqueKeysWithValues: previousWorkspace.tabs
                .flatMap(\.panes)
                .map { ($0.id, iconResolutionPath(for: $0)) }
        )

        for pane in workspace.tabs.flatMap(\.panes) {
            let path = iconResolutionPath(for: pane)
            if let previousPath = previousPaths[pane.id], previousPath != path {
                iconResolver.invalidate(path: previousPath)
                iconResolver.invalidate(path: path)
            } else if previousPaths[pane.id] == nil {
                iconResolver.invalidate(path: path)
            }
        }
    }

    private func iconResolutionPath(for pane: Pane) -> String {
        pane.terminalState.reportedWorkingDirectory ?? pane.session.workingDirectory
    }

    private func apply(theme: WorkspaceShellTheme) {
        view.layer?.backgroundColor = theme.shell.windowBackground.cgColor
        view.window?.backgroundColor = theme.shell.windowBackground
        sidebarView.apply(theme: theme)
        canvasView.apply(theme: theme)
    }

    private func shouldRestoreFocus(
        previousWorkspaceID: WorkspaceID?,
        previousFocusedPaneID: PaneID?,
        workspace: Workspace
    ) -> Bool {
        let focusedPaneID = workspace.focusedPane?.id
        if previousWorkspaceID != workspace.id || previousFocusedPaneID != focusedPaneID {
            return true
        }

        return wasFocusedPaneFirstResponder(paneID: focusedPaneID)
    }

    private func wasFocusedPaneFirstResponder(paneID: PaneID?) -> Bool {
        guard let paneID,
              let firstResponder = view.window?.firstResponder as? NSView,
              let paneView = findHostedTerminalPaneView(in: canvasView, paneID: paneID)
        else {
            return false
        }

        return firstResponder === paneView.focusTarget || firstResponder.isDescendant(of: paneView.focusTarget)
    }

    private func findHostedTerminalPaneView(in rootView: NSView, paneID: PaneID) -> HostedTerminalPaneView? {
        if let paneView = rootView as? HostedTerminalPaneView, paneView.representedPaneID == paneID {
            return paneView
        }

        for subview in rootView.subviews {
            if let paneView = findHostedTerminalPaneView(in: subview, paneID: paneID) {
                return paneView
            }
        }

        return nil
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
        var terminalTextByPaneID: [PaneID: String?] = [:]
        let terminalText: (Pane) -> String? = { [weak self] pane in
            if let cached = terminalTextByPaneID[pane.id] {
                return cached
            }
            let text = self?.terminalScreenText(for: pane)
            terminalTextByPaneID[pane.id] = text
            return text
        }

        return workspaces.flatMap { workspace in
            let panes = workspace.tabs.flatMap(\.panes)
            let workspaceItem = SidebarItem(
                kind: .workspace,
                identifier: workspace.id.rawValue,
                icon: renderedIcon(
                    for: iconResolver.icon(
                        for: panes,
                        focusedPaneID: workspace.focusedPane?.id,
                        terminalText: terminalText
                    ),
                    pointSize: 13,
                    weight: .semibold
                ),
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
                        let paneIcon = iconResolver.icon(for: pane, terminalText: terminalText(pane))
                        let metadata = metadataResolver.metadata(for: pane, icon: paneIcon)
                        let paneStack = tab.rootLayout.paneStack(containingPaneID: pane.id)
                        return SidebarItem(
                            kind: .terminal,
                            identifier: pane.id.rawValue,
                            icon: renderedIcon(for: metadata.icon, pointSize: 11, weight: .medium),
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

    private func terminalScreenText(for pane: Pane) -> String? {
        let snapshot = controller.terminalBridge.terminalTextSnapshot(
            for: pane.id,
            maxBytes: 4_096,
            maxLines: 40
        )
        return snapshot.text.isEmpty ? nil : snapshot.text
    }

    private func iconKindSignature(for workspace: Workspace) -> [PaneID: OmuxSemanticIcon.Kind] {
        Dictionary(
            uniqueKeysWithValues: workspace.tabs
                .flatMap(\.panes)
                .map { pane in
                    (
                        pane.id,
                        iconResolver.icon(for: pane, terminalText: terminalScreenText(for: pane)).kind
                    )
                }
        )
    }

    private func startTerminalIconRefreshTimer() {
        terminalIconRefreshTimer?.invalidate()
        terminalIconRefreshTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshTerminalAppIconsIfNeeded()
            }
        }
    }

    private func refreshTerminalAppIconsIfNeeded() {
        guard let currentWorkspace else {
            return
        }

        let currentSignature = iconKindSignature(for: currentWorkspace)
        guard currentSignature != renderedIconKindByPaneID else {
            return
        }

        update(workspace: currentWorkspace)
    }

    private func renderedIcon(
        for icon: OmuxSemanticIcon,
        pointSize: CGFloat,
        weight: NSFont.Weight
    ) -> OmuxRenderedIcon? {
        OmuxIconRenderer(
            configuration: currentIcons,
            pointSize: pointSize,
            weight: weight
        ).render(icon)
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
    ) -> (view: NSView, focusedPaneView: HostedTerminalPaneView?, representativePaneID: PaneID?) {
        switch node {
        case .paneStack(let paneStack):
            let stackView = PaneStackView(
                paneStack: paneStack,
                focusedPaneID: focusedPaneID,
                bridge: controller.terminalBridge,
                theme: currentTheme,
                iconResolver: iconResolver,
                iconConfiguration: currentIcons,
                onSelectPaneTab: { [weak self] paneID in
                    _ = self?.controller.focusPaneTab(paneID: paneID)
                },
                onCreatePaneTab: { [weak self] in
                    _ = try self?.controller.createPaneTab(in: paneStack.id)
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
            return (
                stackView,
                paneStack.focusedPaneID == focusedPaneID ? stackView.focusedPaneView : nil,
                paneStack.panes.first?.id
            )

        case .split(let axis, let proportions, let children):
            var focusedPaneView: HostedTerminalPaneView?
            var childViews: [NSView] = []
            var childPaneIDs: [PaneID] = []

            for child in children {
                let childLayout = makeLayoutView(for: child, focusedPaneID: focusedPaneID)
                if focusedPaneView == nil {
                    focusedPaneView = childLayout.focusedPaneView
                }
                childViews.append(childLayout.view)
                if let representativePaneID = childLayout.representativePaneID {
                    childPaneIDs.append(representativePaneID)
                }
            }

            let splitView = SplitLayoutView(
                axis: axis,
                proportions: proportions,
                childPaneIDs: childPaneIDs,
                onResize: { [weak self] childPaneIDs, proportions in
                    _ = self?.controller.updateSplitProportions(proportions, forChildPaneIDs: childPaneIDs)
                }
            )
            childViews.forEach { childView in
                childView.translatesAutoresizingMaskIntoConstraints = true
                splitView.addSubview(childView)
            }

            return (splitView, focusedPaneView, children.first?.representativePaneID)
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
    let icon: OmuxRenderedIcon?
    let title: String
    let subtitle: String?
    let isActive: Bool
    let action: Action
    let contextMenuProvider: (() -> NSMenu)?

    var workspaceID: WorkspaceID? {
        guard case .workspace(let workspaceID) = action else {
            return nil
        }
        return workspaceID
    }

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
    private let spacer = NSView()
    private let updateNoticeView = SidebarUpdateNoticeView()
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
        container.addArrangedSubview(spacer)
        container.addArrangedSubview(updateNoticeView)
        updateNoticeView.isHidden = true

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            container.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            container.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            workspacesSection.widthAnchor.constraint(equalTo: container.widthAnchor),
            spacer.widthAnchor.constraint(equalTo: container.widthAnchor),
            updateNoticeView.widthAnchor.constraint(equalTo: container.widthAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    func apply(theme: WorkspaceShellTheme) {
        layer?.backgroundColor = theme.shell.sidebarBackground.cgColor
        layer?.borderWidth = 0
        workspacesSection.apply(theme: theme)
        updateNoticeView.apply(theme: theme)
    }

    func render(
        workspaceItems: [SidebarItem],
        theme: WorkspaceShellTheme,
        onSelectWorkspace: @escaping @MainActor (WorkspaceID) -> Void,
        onCreateWorkspace: @escaping @MainActor () -> Void,
        onDeleteWorkspace: @escaping @MainActor () -> Void,
        canDeleteWorkspace: Bool,
        updateAvailability: OpenMUXUpdateAvailability?,
        onMoveWorkspace: @escaping @MainActor (WorkspaceID, Int) -> Void,
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
            onMoveWorkspace: onMoveWorkspace,
            buttonHandler: { item in
                switch item.action {
                case .workspace(let workspaceID):
                    onSelectWorkspace(workspaceID)
                case .pane(let paneID):
                    onSelectPane(paneID)
                }
            }
        )
        updateNoticeView.render(updateAvailability: updateAvailability)
    }

    var updateNoticeTextForTesting: String? {
        updateNoticeView.noticeTextForTesting
    }
}

@MainActor
private final class SidebarUpdateNoticeView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let commandLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 10

        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        commandLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        titleLabel.maximumNumberOfLines = 2
        commandLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        commandLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(commandLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            commandLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            commandLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            commandLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            commandLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func apply(theme: WorkspaceShellTheme) {
        titleLabel.textColor = theme.shell.textPrimary
        commandLabel.textColor = theme.shell.textMuted
        layer?.backgroundColor = theme.shell.canvasBackground.cgColor
    }

    func render(updateAvailability: OpenMUXUpdateAvailability?) {
        guard let updateAvailability else {
            isHidden = true
            titleLabel.stringValue = ""
            commandLabel.stringValue = ""
            return
        }

        isHidden = false
        titleLabel.stringValue = "New version \(updateAvailability.version)"
        commandLabel.stringValue = "run: omux update"
    }

    var noticeTextForTesting: String? {
        guard isHidden == false else {
            return nil
        }
        return "\(titleLabel.stringValue) \(commandLabel.stringValue)"
    }
}

@MainActor
private final class WorkspaceSidebarSectionView: NSView {
    private struct WorkspaceDragGroup {
        let workspaceID: WorkspaceID
        var buttons: [SidebarItemButton]
    }

    private let titleLabel = NSTextField(labelWithString: "")
    private let headerStack = NSStackView()
    private let itemStack = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private var accessoryButtons: [ChromePillButton] = []
    private var itemButtons: [SidebarItemButton] = []
    private var workspaceButtons: [SidebarItemButton] = []
    private var workspaceDragGroups: [WorkspaceDragGroup] = []
    private var currentTheme: WorkspaceShellTheme?
    private var reorderHandler: ((WorkspaceID, Int) -> Void)?
    private var draggingWorkspaceID: WorkspaceID?

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
        onMoveWorkspace: @escaping (WorkspaceID, Int) -> Void,
        buttonHandler: @escaping (SidebarItem) -> Void
    ) {
        titleLabel.stringValue = "\(title) · \(count)"
        emptyLabel.stringValue = emptyState
        currentTheme = theme
        reorderHandler = onMoveWorkspace
        draggingWorkspaceID = nil

        for button in itemButtons {
            itemStack.removeArrangedSubview(button)
            button.removeFromSuperview()
        }
        itemButtons.removeAll()
        workspaceButtons.removeAll()
        workspaceDragGroups.removeAll()

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
            if let workspaceID = item.workspaceID {
                button.workspaceID = workspaceID
                workspaceButtons.append(button)
                workspaceDragGroups.append(WorkspaceDragGroup(workspaceID: workspaceID, buttons: [button]))
                button.onDragStarted = { [weak self] button, _ in
                    self?.beginWorkspaceDrag(for: button)
                }
                button.onDragMoved = { [weak self] button, event in
                    self?.updateWorkspaceDrag(for: button, with: event)
                }
                button.onDragEnded = { [weak self] button, _ in
                    self?.finishWorkspaceDrag(for: button)
                }
            } else {
                button.workspaceID = nil
                button.onDragStarted = nil
                button.onDragMoved = nil
                button.onDragEnded = nil
                if let lastGroupIndex = workspaceDragGroups.indices.last {
                    workspaceDragGroups[lastGroupIndex].buttons.append(button)
                }
            }
            itemStack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: itemStack.widthAnchor).isActive = true
            button.heightAnchor.constraint(equalToConstant: item.rowHeight).isActive = true
            itemButtons.append(button)
        }
    }

    private func beginWorkspaceDrag(for button: SidebarItemButton) {
        draggingWorkspaceID = button.workspaceID
        updateWorkspaceDragAppearance()
    }

    private func updateWorkspaceDrag(for button: SidebarItemButton, with event: NSEvent) {
        guard draggingWorkspaceID == button.workspaceID else {
            return
        }

        guard let targetIndex = workspaceInsertionIndex(for: event) else {
            return
        }

        previewWorkspaceDrag(toWorkspaceIndex: targetIndex)
        updateWorkspaceDragAppearance()
    }

    private func finishWorkspaceDrag(for button: SidebarItemButton) {
        defer {
            draggingWorkspaceID = nil
            updateWorkspaceDragAppearance()
        }

        guard let workspaceID = button.workspaceID,
              let targetIndex = workspaceDragGroups.firstIndex(where: { $0.workspaceID == workspaceID })
        else {
            return
        }

        reorderHandler?(workspaceID, targetIndex)
    }

    private func workspaceInsertionIndex(for event: NSEvent) -> Int? {
        guard let draggingWorkspaceID else {
            return nil
        }

        let candidateButtons = workspaceButtons.filter { $0.workspaceID != draggingWorkspaceID }
        for (index, button) in candidateButtons.enumerated() {
            let center = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
            if event.locationInWindow.y >= center.y {
                return index
            }
        }
        return candidateButtons.count
    }

    private func updateWorkspaceDragAppearance() {
        for group in workspaceDragGroups {
            let isDraggingGroup = group.workspaceID == draggingWorkspaceID
            for button in group.buttons {
                button.alphaValue = isDraggingGroup ? 0.72 : 1
                button.setDropTarget(false, theme: currentTheme)
            }
            group.buttons.first?.setDraggingPreview(isDraggingGroup, theme: currentTheme)
        }
    }

    private func previewWorkspaceDrag(toWorkspaceIndex targetIndex: Int) {
        guard let draggingWorkspaceID,
              let currentIndex = workspaceDragGroups.firstIndex(where: { $0.workspaceID == draggingWorkspaceID }),
              targetIndex >= workspaceDragGroups.startIndex,
              targetIndex <= workspaceDragGroups.endIndex - 1,
              currentIndex != targetIndex
        else {
            return
        }

        let group = workspaceDragGroups.remove(at: currentIndex)
        workspaceDragGroups.insert(group, at: targetIndex)
        workspaceButtons = workspaceDragGroups.compactMap { group in
            group.buttons.first { $0.workspaceID == group.workspaceID }
        }

        let arrangedButtons = workspaceDragGroups.flatMap(\.buttons)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.allowsImplicitAnimation = true
            for button in arrangedButtons {
                itemStack.removeArrangedSubview(button)
            }
            for (index, button) in arrangedButtons.enumerated() {
                itemStack.insertArrangedSubview(button, at: index)
            }
            itemStack.layoutSubtreeIfNeeded()
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
final class SplitLayoutView: NSView {
    private struct DragState {
        let dividerIndex: Int
        let initialLocation: CGFloat
        let initialLengths: [CGFloat]
    }

    private let axis: PaneSplitAxis
    private let childPaneIDs: [PaneID]
    private let onResize: ([PaneID], [Double]) -> Void
    private var desiredProportions: [Double]
    private var dividerRects: [NSRect] = []
    private var dragState: DragState?

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    init(
        axis: PaneSplitAxis,
        proportions: [Double],
        childPaneIDs: [PaneID],
        onResize: @escaping ([PaneID], [Double]) -> Void
    ) {
        self.axis = axis
        self.childPaneIDs = childPaneIDs
        self.onResize = onResize
        self.desiredProportions = Self.normalizedProportions(proportions, count: childPaneIDs.count)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .vertical)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        applyLayout()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.separatorColor.setFill()
        for rect in dividerRects where dirtyRect.intersects(rect) {
            rect.fill()
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        let cursor: NSCursor = axis == .columns ? .resizeLeftRight : .resizeUpDown
        dividerRects.forEach { addCursorRect($0, cursor: cursor) }
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        guard let dividerIndex = dividerRects.firstIndex(where: { $0.contains(location) }) else {
            return
        }

        dragState = DragState(
            dividerIndex: dividerIndex,
            initialLocation: primaryCoordinate(of: location),
            initialLengths: currentLengths()
        )
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragState else {
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        let delta = primaryCoordinate(of: location) - dragState.initialLocation
        let leadingIndex = dragState.dividerIndex
        let trailingIndex = leadingIndex + 1
        guard dragState.initialLengths.indices.contains(leadingIndex),
              dragState.initialLengths.indices.contains(trailingIndex)
        else {
            return
        }

        let minimumLeading = minimumPrimaryExtent(ofSubviewAt: leadingIndex)
        let minimumTrailing = minimumPrimaryExtent(ofSubviewAt: trailingIndex)
        let minimumDelta = minimumLeading - dragState.initialLengths[leadingIndex]
        let maximumDelta = dragState.initialLengths[trailingIndex] - minimumTrailing
        let clampedDelta = min(max(delta, minimumDelta), maximumDelta)

        var updatedLengths = dragState.initialLengths
        updatedLengths[leadingIndex] += clampedDelta
        updatedLengths[trailingIndex] -= clampedDelta

        desiredProportions = normalizedProportions(for: updatedLengths)
        needsLayout = true
    }

    override func mouseUp(with event: NSEvent) {
        guard dragState != nil else {
            return
        }

        dragState = nil
        guard childPaneIDs.count == subviews.count, subviews.count > 1 else {
            return
        }
        onResize(childPaneIDs, desiredProportions)
    }

    private func applyLayout() {
        guard subviews.isEmpty == false else {
            dividerRects = []
            return
        }

        let spacing = ShellLayoutMetrics.splitSpacing
        let availableLength = max(primaryLength(of: bounds.size) - spacing * CGFloat(max(subviews.count - 1, 0)), 0)
        let lengths = resolvedLengths(totalLength: availableLength)

        var cursor: CGFloat = 0
        dividerRects = []

        for (index, subview) in subviews.enumerated() {
            let length = lengths[index]
            let frame: NSRect
            if axis == .columns {
                frame = NSRect(x: cursor, y: 0, width: length, height: bounds.height)
            } else {
                frame = NSRect(x: 0, y: cursor, width: bounds.width, height: length)
            }
            subview.frame = frame
            cursor += length

            if index < subviews.count - 1 {
                let dividerRect: NSRect
                if axis == .columns {
                    dividerRect = NSRect(x: cursor, y: 0, width: spacing, height: bounds.height)
                } else {
                    dividerRect = NSRect(x: 0, y: cursor, width: bounds.width, height: spacing)
                }
                dividerRects.append(dividerRect)
                cursor += spacing
            }
        }

        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    private func currentLengths() -> [CGFloat] {
        subviews.map { primaryLength(of: $0.frame.size) }
    }

    private func resolvedLengths(totalLength: CGFloat) -> [CGFloat] {
        guard subviews.isEmpty == false else {
            return []
        }

        if totalLength <= 0 {
            return Array(repeating: 0, count: subviews.count)
        }

        let minimums = subviews.indices.map(minimumPrimaryExtent(ofSubviewAt:))
        let minimumTotal = minimums.reduce(0, +)
        guard minimumTotal < totalLength else {
            return Array(repeating: totalLength / CGFloat(subviews.count), count: subviews.count)
        }

        let normalized = Self.normalizedProportions(desiredProportions, count: subviews.count)
        var lengths = normalized.map { CGFloat($0) * totalLength }
        var remainingIndices = Set(lengths.indices)
        var remainingLength = totalLength

        while true {
            let undersized = remainingIndices.filter { lengths[$0] < minimums[$0] }
            guard undersized.isEmpty == false else {
                break
            }

            for index in undersized {
                lengths[index] = minimums[index]
                remainingIndices.remove(index)
                remainingLength -= minimums[index]
            }

            guard remainingIndices.isEmpty == false else {
                break
            }

            let remainingWeight = remainingIndices.reduce(CGFloat(0)) { partialResult, index in
                partialResult + CGFloat(normalized[index])
            }

            for index in remainingIndices {
                let weight = remainingWeight > 0 ? CGFloat(normalized[index]) / remainingWeight : 1 / CGFloat(remainingIndices.count)
                lengths[index] = remainingLength * weight
            }
        }

        let correction = totalLength - lengths.reduce(0, +)
        if let lastIndex = lengths.indices.last {
            lengths[lastIndex] += correction
        }

        return lengths
    }

    private func minimumPrimaryExtent(ofSubviewAt index: Int) -> CGFloat {
        guard subviews.indices.contains(index) else {
            return 0
        }

        let fittingSize = subviews[index].fittingSize
        return max(primaryLength(of: fittingSize), 120)
    }

    private func primaryLength(of size: CGSize) -> CGFloat {
        axis == .columns ? size.width : size.height
    }

    private func primaryCoordinate(of point: CGPoint) -> CGFloat {
        axis == .columns ? point.x : point.y
    }

    private func normalizedProportions(for lengths: [CGFloat]) -> [Double] {
        let total = lengths.reduce(0, +)
        guard total > 0 else {
            return Self.normalizedProportions([], count: lengths.count)
        }
        return lengths.map { Double($0 / total) }
    }

    private static func normalizedProportions(_ proportions: [Double], count: Int) -> [Double] {
        guard count > 0 else {
            return []
        }

        guard proportions.count == count,
              proportions.allSatisfy({ $0.isFinite && $0 > 0 })
        else {
            return Array(repeating: 1.0 / Double(count), count: count)
        }

        let total = proportions.reduce(0, +)
        guard total > 0 else {
            return Array(repeating: 1.0 / Double(count), count: count)
        }
        return proportions.map { $0 / total }
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
        iconResolver: WorkspaceIconResolver,
        iconConfiguration: OmuxConfigUI.Icons,
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
            iconResolver: iconResolver,
            iconConfiguration: iconConfiguration,
            terminalTextProvider: { pane in
                let snapshot = bridge.terminalTextSnapshot(for: pane.id, maxBytes: 4_096, maxLines: 40)
                return snapshot.text.isEmpty ? nil : snapshot.text
            },
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

    init(
        paneStack: PaneStack,
        theme: WorkspaceShellTheme,
        iconResolver: WorkspaceIconResolver,
        iconConfiguration: OmuxConfigUI.Icons,
        terminalTextProvider: @escaping @MainActor (Pane) -> String?,
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
        tabStrip.identifier = NSUserInterfaceItemIdentifier("pane-tab-strip-\(paneStack.id.rawValue)")
        tabStrip.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tabStrip.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        for pane in paneStack.panes {
            let button = PaneTabButton(
                pane: pane,
                active: pane.id == paneStack.focusedPaneID,
                theme: theme,
                icon: OmuxIconRenderer(
                    configuration: iconConfiguration,
                    pointSize: 11,
                    weight: pane.id == paneStack.focusedPaneID ? .semibold : .medium
                ).render(iconResolver.icon(for: pane, terminalText: terminalTextProvider(pane))),
                showsClose: paneStack.panes.count > 1,
                onClose: {
                    try? onClosePaneTab(pane.id)
                }
            )
            button.onPress = { onSelectPaneTab(pane.id) }
            button.contextMenuProvider = { contextMenuProvider(pane) }
            tabStrip.addArrangedSubview(button)
        }

        let addButton = ChromePillButton()
        addButton.configure(symbolName: "plus", accessibilityLabel: "Add pane tab", active: false, theme: theme, compact: true)
        addButton.identifier = NSUserInterfaceItemIdentifier("pane-tab-add-\(paneStack.id.rawValue)")
        addButton.onPress = {
            try? onCreatePaneTab()
        }
        tabStrip.addArrangedSubview(addButton)

        content.addArrangedSubview(tabStrip)
        content.addArrangedSubview(NSView())
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

struct PaneTabTitleFormatter {
    static let defaultMaximumLength = 44
    private static let truncationMarker = "..."

    static func displayTitle(
        _ title: String,
        maximumLength: Int = defaultMaximumLength
    ) -> String {
        guard maximumLength > 0 else {
            return ""
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = trimmedTitle.isEmpty ? title : trimmedTitle
        guard displayTitle.count > maximumLength else {
            return displayTitle
        }

        guard maximumLength > truncationMarker.count + 1 else {
            return String(displayTitle.prefix(maximumLength))
        }

        let remainingLength = maximumLength - truncationMarker.count
        let leadingLength = max(1, remainingLength / 2)
        let trailingLength = max(1, remainingLength - leadingLength)
        return String(displayTitle.prefix(leadingLength))
            + truncationMarker
            + String(displayTitle.suffix(trailingLength))
    }
}

private extension WorkspaceShellTheme {
    func iconColor(
        for icon: OmuxRenderedIcon,
        selected: Bool,
        fallback: NSColor? = nil
    ) -> NSColor {
        guard icon.colorsEnabled else {
            return fallback ?? (selected ? shell.selectedText : shell.textSecondary)
        }

        let themedColor = color(for: icon.colorToken)
        if selected, Self.contrastRatio(themedColor, shell.selection) < 3 {
            return fallback ?? shell.selectedText
        }
        return themedColor
    }
}

@MainActor
private final class PaneTabButton: NSControl {
    var onPress: (() -> Void)?
    var contextMenuProvider: (() -> NSMenu)? {
        didSet {
            menu = contextMenuProvider?()
        }
    }

    private let titleLabel = NSTextField(labelWithString: "")
    private let iconLabel = NSTextField(labelWithString: "")
    private let iconImageView = NSImageView()
    private let closeButton = ChromePillButton()
    private let contentInsets = NSEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)
    private let interItemSpacing = CGFloat(4)
    private let iconSpacing = CGFloat(4)
    private let symbolSide = CGFloat(12)
    private let showsClose: Bool
    private let currentTheme: WorkspaceShellTheme
    private let isActiveTab: Bool
    private let renderedIcon: OmuxRenderedIcon?
    private let iconSymbolImage: NSImage?

    init(
        pane: Pane,
        active: Bool,
        theme: WorkspaceShellTheme,
        icon: OmuxRenderedIcon?,
        showsClose: Bool,
        onClose: @escaping () -> Void
    ) {
        self.showsClose = showsClose
        self.currentTheme = theme
        self.isActiveTab = active
        self.renderedIcon = icon
        self.iconSymbolImage = icon?.symbolImage()
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = 3
        identifier = NSUserInterfaceItemIdentifier("pane-tab-\(pane.id.rawValue)")
        setAccessibilityLabel(icon.map { "\($0.accessibilityLabel), \(pane.title)" } ?? pane.title)
        toolTip = pane.title
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        iconLabel.translatesAutoresizingMaskIntoConstraints = false
        iconLabel.font = icon?.font ?? .systemFont(ofSize: 11, weight: active ? .semibold : .medium)
        iconLabel.lineBreakMode = .byClipping
        iconLabel.alignment = .center
        iconLabel.stringValue = icon?.text ?? ""
        iconLabel.toolTip = icon?.accessibilityLabel
        iconLabel.textColor = icon.flatMap { theme.iconColor(for: $0, selected: active) }
            ?? (active ? theme.shell.selectedText : theme.shell.textSecondary)
        iconLabel.isHidden = icon == nil || iconSymbolImage != nil
        addSubview(iconLabel)

        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.symbolConfiguration = .init(pointSize: 11, weight: active ? .semibold : .medium)
        iconImageView.image = iconSymbolImage
        iconImageView.contentTintColor = icon.flatMap { theme.iconColor(for: $0, selected: active) }
            ?? (active ? theme.shell.selectedText : theme.shell.textSecondary)
        iconImageView.toolTip = icon?.accessibilityLabel
        iconImageView.isHidden = iconSymbolImage == nil
        addSubview(iconImageView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 11, weight: active ? .semibold : .medium)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.stringValue = PaneTabTitleFormatter.displayTitle(pane.title)
        titleLabel.toolTip = pane.title
        titleLabel.textColor = active ? theme.shell.selectedText : theme.shell.textSecondary
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(titleLabel)

        if showsClose {
            closeButton.configure(
                symbolName: "xmark",
                accessibilityLabel: "Close \(pane.title)",
                active: active,
                theme: theme,
                compact: true
            )
            closeButton.identifier = NSUserInterfaceItemIdentifier("pane-tab-close-\(pane.id.rawValue)")
            closeButton.onPress = onClose
            addSubview(closeButton)
        }

        updateVisualState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    override var isEnabled: Bool {
        didSet {
            updateVisualState()
        }
    }

    override var intrinsicContentSize: NSSize {
        let titleSize = titleLabel.intrinsicContentSize
        let iconSize = renderedIcon == nil
            ? .zero
            : (iconSymbolImage == nil ? iconLabel.intrinsicContentSize : NSSize(width: symbolSide, height: symbolSide))
        let closeSize = showsClose ? closeButton.intrinsicContentSize : .zero
        let closeWidth = showsClose ? interItemSpacing + closeSize.width : 0
        let iconWidth = renderedIcon == nil ? 0 : iconSize.width + iconSpacing
        return NSSize(
            width: iconWidth + titleSize.width + closeWidth + contentInsets.left + contentInsets.right,
            height: max(titleSize.height, iconSize.height, closeSize.height) + contentInsets.top + contentInsets.bottom
        )
    }

    override func layout() {
        super.layout()
        let contentBounds = bounds.insetBy(
            dx: contentInsets.left,
            dy: contentInsets.top
        )

        var titleMinX = contentBounds.minX
        if let renderedIcon {
            if iconSymbolImage == nil {
                let iconSize = iconLabel.intrinsicContentSize
                iconLabel.frame = NSRect(
                    x: contentBounds.minX,
                    y: round((bounds.height - iconSize.height) / 2),
                    width: iconSize.width,
                    height: iconSize.height
                )
                iconLabel.setAccessibilityLabel(renderedIcon.accessibilityLabel)
                iconImageView.frame = .zero
                titleMinX = iconLabel.frame.maxX + iconSpacing
            } else {
                iconImageView.frame = NSRect(
                    x: contentBounds.minX,
                    y: round((bounds.height - symbolSide) / 2),
                    width: symbolSide,
                    height: symbolSide
                )
                iconImageView.setAccessibilityLabel(renderedIcon.accessibilityLabel)
                iconLabel.frame = .zero
                titleMinX = iconImageView.frame.maxX + iconSpacing
            }
        } else {
            iconLabel.frame = .zero
            iconImageView.frame = .zero
        }

        if showsClose {
            let closeSize = closeButton.intrinsicContentSize
            closeButton.frame = NSRect(
                x: bounds.width - contentInsets.right - closeSize.width,
                y: round((bounds.height - closeSize.height) / 2),
                width: closeSize.width,
                height: closeSize.height
            )
            titleLabel.frame = NSRect(
                x: titleMinX,
                y: contentBounds.minY,
                width: max(0, closeButton.frame.minX - interItemSpacing - titleMinX),
                height: contentBounds.height
            )
        } else {
            titleLabel.frame = NSRect(
                x: titleMinX,
                y: contentBounds.minY,
                width: max(0, contentBounds.maxX - titleMinX),
                height: contentBounds.height
            )
            closeButton.frame = .zero
        }
    }

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

    private func updateVisualState() {
        titleLabel.textColor = isActiveTab ? currentTheme.shell.selectedText : currentTheme.shell.textSecondary
        let iconColor = renderedIcon.flatMap { currentTheme.iconColor(for: $0, selected: isActiveTab) }
            ?? titleLabel.textColor
        iconLabel.textColor = iconColor
        iconImageView.contentTintColor = iconColor
        layer?.backgroundColor = (isActiveTab ? currentTheme.shell.selection : NSColor.clear).cgColor
        layer?.borderWidth = 0
        layer?.borderColor = nil
        alphaValue = isEnabled ? 1 : 0.4
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
        setAccessibilityLabel(title)
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
        setAccessibilityLabel(accessibilityLabel)
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
        let foreground = isActive ? currentTheme.shell.selectedText : currentTheme.shell.textSecondary
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
    override var mouseDownCanMoveWindow: Bool { false }

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
    var workspaceID: WorkspaceID?
    var onDragStarted: ((SidebarItemButton, NSEvent) -> Void)?
    var onDragMoved: ((SidebarItemButton, NSEvent) -> Void)?
    var onDragEnded: ((SidebarItemButton, NSEvent) -> Void)?
    var contextMenuProvider: (() -> NSMenu?)? {
        didSet {
            menu = contextMenuProvider?()
        }
    }
    private let titleField = NSTextField(labelWithString: "")
    private let subtitleField = NSTextField(labelWithString: "")
    private let iconField = NSTextField(labelWithString: "")
    private let iconImageView = NSImageView()
    private var leadingInset: CGFloat = 12
    private var textLeadingInset: CGFloat = 12
    private var renderedIcon: OmuxRenderedIcon?
    private var iconSymbolImage: NSImage?
    private var iconSide = CGFloat(13)

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

        iconField.maximumNumberOfLines = 1
        iconField.lineBreakMode = .byClipping
        iconField.alignment = .center
        iconField.isBezeled = false
        iconField.drawsBackground = false
        iconField.isEditable = false
        iconField.isSelectable = false
        addSubview(iconField)

        iconImageView.isHidden = true
        addSubview(iconImageView)

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
        renderedIcon = item.icon
        iconSymbolImage = item.icon?.symbolImage()
        iconSide = item.kind == .workspace ? 13 : 11
        iconField.stringValue = item.icon?.text ?? ""
        iconField.font = item.icon?.font ?? .systemFont(ofSize: item.kind == .workspace ? 13 : 11, weight: .medium)
        iconField.isHidden = item.icon == nil || iconSymbolImage != nil
        iconField.toolTip = item.icon?.accessibilityLabel
        iconImageView.symbolConfiguration = .init(pointSize: iconSide, weight: item.kind == .workspace ? .semibold : .medium)
        iconImageView.image = iconSymbolImage
        iconImageView.isHidden = iconSymbolImage == nil
        iconImageView.toolTip = item.icon?.accessibilityLabel
        setAccessibilityLabel(item.icon.map { "\($0.accessibilityLabel), \(item.title)" } ?? item.title)
        titleField.textColor = item.kind == .terminal
            ? theme.shell.textMuted
            : (item.isActive ? theme.shell.selectedText : theme.shell.textSecondary)
        let iconColor = item.icon.map {
            theme.iconColor(
                for: $0,
                selected: item.isActive,
                fallback: titleField.textColor ?? theme.shell.textSecondary
            )
        } ?? titleField.textColor
        iconField.textColor = iconColor
        iconImageView.contentTintColor = iconColor
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
        let iconSpacing: CGFloat = renderedIcon == nil ? 0 : 6
        var textX = leadingInset
        if let renderedIcon {
            if iconSymbolImage == nil {
                let iconSize = iconField.intrinsicContentSize
                iconField.frame = NSRect(
                    x: leadingInset,
                    y: round((bounds.height - iconSize.height) / 2),
                    width: iconSize.width,
                    height: iconSize.height
                )
                iconField.setAccessibilityLabel(renderedIcon.accessibilityLabel)
                iconImageView.frame = .zero
                textX = iconField.frame.maxX + iconSpacing
            } else {
                iconImageView.frame = NSRect(
                    x: leadingInset,
                    y: round((bounds.height - iconSide) / 2),
                    width: iconSide,
                    height: iconSide
                )
                iconImageView.setAccessibilityLabel(renderedIcon.accessibilityLabel)
                iconField.frame = .zero
                textX = iconImageView.frame.maxX + iconSpacing
            }
        } else {
            iconField.frame = .zero
            iconImageView.frame = .zero
        }
        textLeadingInset = textX
        let labelWidth = bounds.width - textLeadingInset - trailingInset
        let titleHeight = titleField.intrinsicContentSize.height
        if subtitleField.isHidden {
            titleField.frame = NSRect(
                x: textLeadingInset,
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
                x: textLeadingInset,
                y: startY + subtitleHeight + 2,
                width: max(labelWidth, 0),
                height: titleHeight
            )
            subtitleField.frame = NSRect(
                x: textLeadingInset,
                y: startY,
                width: max(labelWidth, 0),
                height: subtitleHeight
            )
        }
    }

    override var acceptsFirstResponder: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        guard onDragStarted != nil || onDragMoved != nil || onDragEnded != nil else {
            onPress?()
            return
        }

        let initialLocation = convert(event.locationInWindow, from: nil)
        var didStartDragging = false

        while let nextEvent = window?.nextEvent(
            matching: [.leftMouseDragged, .leftMouseUp],
            until: .distantFuture,
            inMode: .eventTracking,
            dequeue: true
        ) {
            switch nextEvent.type {
            case .leftMouseDragged:
                let location = convert(nextEvent.locationInWindow, from: nil)
                let delta = hypot(location.x - initialLocation.x, location.y - initialLocation.y)
                guard delta >= 4 else {
                    continue
                }

                if didStartDragging == false {
                    didStartDragging = true
                    onDragStarted?(self, nextEvent)
                }
                onDragMoved?(self, nextEvent)

            case .leftMouseUp:
                if didStartDragging {
                    onDragEnded?(self, nextEvent)
                } else {
                    onPress?()
                }
                return

            default:
                return
            }
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        if let menu = menu ?? contextMenuProvider?() {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        } else {
            super.rightMouseDown(with: event)
        }
    }

    func setDropTarget(_ isDropTarget: Bool, theme: WorkspaceShellTheme?) {
        guard let theme else {
            return
        }
        layer?.borderWidth = isDropTarget ? 1 : 0
        layer?.borderColor = isDropTarget ? theme.shell.selection.cgColor : nil
    }

    func setDraggingPreview(_ isDragging: Bool, theme: WorkspaceShellTheme?) {
        layer?.shadowOpacity = isDragging ? 0.18 : 0
        layer?.shadowRadius = isDragging ? 8 : 0
        layer?.shadowOffset = isDragging ? CGSize(width: 0, height: -2) : .zero
        layer?.shadowColor = theme?.shell.selection.cgColor
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
