import AppKit
import OmuxConfig
import OmuxCore
import OmuxTerminalBridge
import QuartzCore
import WebKit

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
        initialPanes: OmuxConfigUI.Panes = OmuxConfigUI.Panes(),
        initialIcons: OmuxConfigUI.Icons = OmuxConfigUI.Icons(),
        sidebarVisibilityStore: any WorkspaceSidebarVisibilityStoring = WorkspaceSidebarVisibilityStore.shared,
        onExtensionPaneAction: @escaping @MainActor (ExtensionPaneActionRequest) -> Void = { _ in }
    ) {
        self.controller = controller
        self.rootViewController = WorkspaceShellViewController(
            controller: controller,
            initialTheme: initialTheme,
            initialPanes: initialPanes,
            initialIcons: initialIcons,
            sidebarVisibilityStore: sidebarVisibilityStore,
            onExtensionPaneAction: onExtensionPaneAction
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

    func updatePanes(_ panes: OmuxConfigUI.Panes) {
        rootViewController.updatePanes(panes)
    }

    func toggleSidebarVisibility() {
        rootViewController.toggleSidebarVisibility()
    }

    func presentRenameWorkspacePrompt(workspaceID: WorkspaceID? = nil) {
        rootViewController.presentRenameWorkspacePrompt(workspaceID: workspaceID)
    }

    func presentCommandPalette(initialQuery: String, keyBindings: OpenMUXKeyBindingRegistry) {
        rootViewController.presentCommandPalette(initialQuery: initialQuery, keyBindings: keyBindings)
    }

    var themeCommitHandler: ((String) -> Void)? {
        get { rootViewController.themeCommitHandler }
        set { rootViewController.themeCommitHandler = newValue }
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
    private var currentPanes: OmuxConfigUI.Panes
    private var currentIcons: OmuxConfigUI.Icons
    private var isSidebarVisible: Bool
    private var windowIsKey: Bool = false
    private var focusRestoreGeneration: UInt = 0
    private var terminalIconRefreshTimer: Timer?
    private var renderedIconKindByPaneID: [PaneID: OmuxSemanticIcon.Kind] = [:]
    private var commandPaletteView: CommandPaletteView?
    private var collapsedWorkspaceIDs = Set<WorkspaceID>()
    private let onExtensionPaneAction: @MainActor (ExtensionPaneActionRequest) -> Void

    var themeCommitHandler: ((String) -> Void)?

    init(
        controller: WorkspaceController,
        initialTheme: WorkspaceShellTheme,
        initialPanes: OmuxConfigUI.Panes,
        initialIcons: OmuxConfigUI.Icons,
        sidebarVisibilityStore: any WorkspaceSidebarVisibilityStoring,
        onExtensionPaneAction: @escaping @MainActor (ExtensionPaneActionRequest) -> Void
    ) {
        self.controller = controller
        self.currentTheme = initialTheme
        self.currentPanes = initialPanes
        self.currentIcons = initialIcons
        self.sidebarVisibilityStore = sidebarVisibilityStore
        self.isSidebarVisible = sidebarVisibilityStore.isSidebarVisible
        self.onExtensionPaneAction = onExtensionPaneAction
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

    override func viewDidAppear() {
        super.viewDidAppear()
        let nc = NotificationCenter.default
        nc.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: view.window
        )
        nc.addObserver(
            self,
            selector: #selector(windowDidResignKey(_:)),
            name: NSWindow.didResignKeyNotification,
            object: view.window
        )
        windowIsKey = view.window?.isKeyWindow ?? false
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: view.window)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: view.window)
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        windowIsKey = true
        if let workspace = currentWorkspace { update(workspace: workspace) }
    }

    @objc private func windowDidResignKey(_ notification: Notification) {
        windowIsKey = false
        if let workspace = currentWorkspace { update(workspace: workspace) }
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
        let allWorkspaces = controller.allWorkspaces()
        let workspaceIDs = Set(allWorkspaces.map(\.id))
        collapsedWorkspaceIDs = collapsedWorkspaceIDs.intersection(workspaceIDs)
        if previousWorkspaceID != nil, previousWorkspaceID != workspace.id {
            collapsedWorkspaceIDs.remove(workspace.id)
        }
        currentWorkspace = workspace
        apply(theme: currentTheme)

        let workspaceItems = makeWorkspaceSidebarItems(
            workspaces: allWorkspaces,
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
            onToggleWorkspaceExpansion: { [weak self] workspaceID in
                self?.toggleWorkspaceExpansion(workspaceID)
            },
            onSelectPane: { [weak self] paneID in
                _ = self?.controller.focus(paneID: paneID)
            }
        )

        let layout = workspace.focusedTab.map {
            makeLayoutView(
                for: $0.rootLayout,
                focusedPaneID: $0.focusedPaneID,
                windowIsKey: windowIsKey,
                inactiveOpacity: currentPanes.inactiveOpacity,
                canCloseSinglePaneStack: $0.panes.count > 1 || workspace.tabs.count > 1
            )
        }
        canvasView.render(layoutView: layout?.view, theme: currentTheme)
        renderedIconKindByPaneID = iconKindSignature(for: workspace)

        if shouldRestoreFocus, let focusedPaneView = layout?.focusedPaneView {
            focusRestoreGeneration &+= 1
            let generation = focusRestoreGeneration

            if let window = view.window {
                window.makeFirstResponder(focusTarget(for: focusedPaneView))
            } else {
                DispatchQueue.main.async { [weak self, weak focusedPaneView] in
                    guard let self,
                          let focusedPaneView,
                          self.focusRestoreGeneration == generation
                    else {
                        return
                    }

                    self.view.window?.makeFirstResponder(self.focusTarget(for: focusedPaneView))
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

    func updatePanes(_ panes: OmuxConfigUI.Panes) {
        currentPanes = panes
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
        pane.terminalState.reportedWorkingDirectory
            ?? pane.terminalSession?.workingDirectory
            ?? pane.extensionPane?.source
            ?? pane.id.rawValue
    }

    private func apply(theme: WorkspaceShellTheme) {
        view.layer?.backgroundColor = theme.shell.windowBackground.cgColor
        view.window?.backgroundColor = theme.shell.windowBackground
        sidebarView.apply(theme: theme)
        canvasView.apply(theme: theme)
        commandPaletteView?.apply(theme: theme)
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
              let paneView = findHostedPaneView(in: canvasView, paneID: paneID)
        else {
            return false
        }

        let focusTarget = focusTarget(for: paneView)
        return firstResponder === focusTarget || firstResponder.isDescendant(of: focusTarget)
    }

    private func findHostedPaneView(in rootView: NSView, paneID: PaneID) -> NSView? {
        if let paneView = rootView as? any WorkspacePaneRendering, paneView.representedPaneID == paneID {
            return paneView.rootPaneView
        }
        for subview in rootView.subviews {
            if let paneView = findHostedPaneView(in: subview, paneID: paneID) {
                return paneView
            }
        }

        return nil
    }

    private func focusTarget(for paneView: NSView) -> NSView {
        (paneView as? any WorkspacePaneRendering)?.focusTarget ?? paneView
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
            let isExpanded = collapsedWorkspaceIDs.contains(workspace.id) == false
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
                progress: nil,
                title: workspace.name,
                subtitle: nil,
                isActive: workspace.id == activeWorkspace.id,
                isExpanded: isExpanded,
                action: .workspace(workspace.id),
                contextMenuProvider: { [weak self] in
                    guard let self else { return NSMenu() }
                    return makeWorkspaceContextMenu(for: workspace)
                }
            )

            let terminalItems = isExpanded ? workspace.tabs
                .flatMap { tab in
                    tab.panes.map { pane -> SidebarItem in
                        let paneIcon = iconResolver.icon(for: pane, terminalText: terminalText(pane))
                        let metadata = metadataResolver.metadata(for: pane, icon: paneIcon)
                        let paneStack = tab.rootLayout.paneStack(containingPaneID: pane.id)
                        return SidebarItem(
                            kind: .terminal,
                            identifier: pane.id.rawValue,
                            icon: renderedIcon(for: metadata.icon, pointSize: 11, weight: .medium),
                            progress: pane.terminalState.progress,
                            title: metadata.title,
                            subtitle: metadata.subtitle,
                            isActive: workspace.id == activeWorkspace.id && pane.id == activeWorkspace.focusedPane?.id,
                            isExpanded: nil,
                            action: .pane(pane.id),
                            contextMenuProvider: { [weak self] in
                                guard let self, let paneStack else { return NSMenu() }
                                return makePaneTabContextMenu(
                                    pane: pane,
                                    paneStack: paneStack,
                                    canCloseSinglePaneStack: tab.panes.count > 1 || workspace.tabs.count > 1
                                )
                            }
                        )
                    }
                } : []

            return [workspaceItem] + terminalItems
        }
    }

    private func toggleWorkspaceExpansion(_ workspaceID: WorkspaceID) {
        if collapsedWorkspaceIDs.contains(workspaceID) {
            collapsedWorkspaceIDs.remove(workspaceID)
        } else {
            collapsedWorkspaceIDs.insert(workspaceID)
        }

        if let workspace = currentWorkspace {
            update(workspace: workspace)
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

    func presentCommandPalette(initialQuery: String, keyBindings: OpenMUXKeyBindingRegistry) {
        let previousResponder = view.window?.firstResponder
        let paletteView: CommandPaletteView
        if let existing = commandPaletteView {
            paletteView = existing
        } else {
            paletteView = CommandPaletteView()
            commandPaletteView = paletteView
            view.addSubview(paletteView)
            NSLayoutConstraint.activate([
                paletteView.topAnchor.constraint(equalTo: view.topAnchor),
                paletteView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                paletteView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                paletteView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        }
        paletteView.apply(theme: currentTheme)

        let configOpenContext = resolvedConfigOpenContext()
        paletteView.iconProvider = { id in
            id == "cli:omux.config.open" ? configOpenContext?.icon : nil
        }

        paletteView.resultProvider = { [weak self] query in
            guard let self else { return [] }
            let parsed = CommandPaletteParsedQuery(rawText: query)
            switch parsed.mode {
            case .workspace:
                return CommandPaletteSearch.workspaceResults(
                    query: parsed.matchingText,
                    workspaces: controller.commandPaletteWorkspaces()
                )
            case .command:
                return CommandPaletteSearch.commandResults(
                    query: parsed.matchingText,
                    commands: CommandPaletteCommandCatalog.commands(
                        controller: controller,
                        keyBindings: keyBindings,
                        subtitleOverrides: configOpenContext.map { ["cli:omux.config.open": $0.subtitle] } ?? [:]
                    )
                )
            }
        }

        var themeBeforeSubPalette: WorkspaceShellTheme? = nil

        paletteView.invokeResult = { [weak self] result in
            guard let self else { return .failed("Window is unavailable") }
            if result.invocationTarget == .action(.sidebarToggle) {
                toggleSidebarVisibility()
                return .invoked
            }
            if result.invocationTarget == .themeSwitch {
                themeBeforeSubPalette = currentTheme
                paletteView.enterThemeSubPalette(originalTheme: currentTheme)
                return .inert
            }
            if result.invocationTarget == .configOpen {
                NSWorkspace.shared.open(OmuxConfigPaths.configFileURL)
                return .invoked
            }
            return controller.invokeCommandPaletteResult(result)
        }

        paletteView.subPalettePreviewHandler = { [weak self] identifier in
            guard let self else { return }
            if let theme = WorkspaceShellTheme.named(identifier) {
                updateTheme(theme)
            }
        }

        paletteView.subPaletteCommitHandler = { [weak self] identifier in
            themeBeforeSubPalette = nil
            self?.themeCommitHandler?(identifier)
        }

        paletteView.subPaletteRevertHandler = { [weak self] in
            guard let self else { return }
            if let saved = themeBeforeSubPalette {
                updateTheme(saved)
                themeBeforeSubPalette = nil
            }
        }

        paletteView.dismissHandler = { [weak self, weak paletteView] in
            if self?.commandPaletteView === paletteView {
                self?.commandPaletteView = nil
            }
        }
        paletteView.present(initialQuery: initialQuery, restoring: previousResponder)
    }

    private struct ConfigOpenContext {
        let subtitle: String
        let icon: NSImage
    }

    private func resolvedConfigOpenContext() -> ConfigOpenContext? {
        guard let appURL = resolveDefaultAppForTOML() else { return nil }
        let appBundle = Bundle(url: appURL)
        let appName = appBundle?.infoDictionary?["CFBundleDisplayName"] as? String
            ?? appBundle?.infoDictionary?["CFBundleName"] as? String
            ?? appURL.deletingPathExtension().lastPathComponent
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        return ConfigOpenContext(subtitle: "Opens in \(appName)", icon: icon)
    }

    private func resolveDefaultAppForTOML() -> URL? {
        let configURL = OmuxConfigPaths.configFileURL
        if FileManager.default.fileExists(atPath: configURL.path) {
            return NSWorkspace.shared.urlForApplication(toOpen: configURL)
        }
        let probe = FileManager.default.temporaryDirectory.appendingPathComponent("omux-probe.toml")
        guard (try? "".write(to: probe, atomically: true, encoding: .utf8)) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: probe) }
        return NSWorkspace.shared.urlForApplication(toOpen: probe)
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
        let expansionTitle = collapsedWorkspaceIDs.contains(workspace.id)
            ? "Expand Workspace Panes"
            : "Collapse Workspace Panes"
        menu.addItem(withTitle: expansionTitle, action: nil, keyEquivalent: "").onSelect { [weak self] in
            self?.toggleWorkspaceExpansion(workspace.id)
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
        paneStack: PaneStack,
        canCloseSinglePaneStack: Bool
    ) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Rename…", action: nil, keyEquivalent: "").onSelect { [weak self] in
            self?.presentRenamePanePrompt(paneID: pane.id, currentTitle: pane.title)
        }

        let closeItem = menu.addItem(withTitle: "Close", action: nil, keyEquivalent: "")
        closeItem.isEnabled = paneStack.panes.count > 1 || canCloseSinglePaneStack
        closeItem.onSelect { [weak self] in
            _ = try? self?.controller.closePane(paneID: pane.id)
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
        focusedPaneID: PaneID,
        windowIsKey: Bool,
        inactiveOpacity: Double,
        canCloseSinglePaneStack: Bool
    ) -> (view: NSView, focusedPaneView: NSView?, representativePaneID: PaneID?) {
        switch node {
        case .paneStack(let paneStack):
            let stackView = PaneStackView(
                paneStack: paneStack,
                focusedPaneID: focusedPaneID,
                windowIsKey: windowIsKey,
                inactiveOpacity: inactiveOpacity,
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
                canCloseSinglePaneStack: canCloseSinglePaneStack,
                onClosePane: { [weak self] paneID in
                    _ = try self?.controller.closePane(paneID: paneID)
                },
                contextMenuProvider: { [weak self] pane in
                    guard let self else { return NSMenu() }
                    return makePaneTabContextMenu(
                        pane: pane,
                        paneStack: paneStack,
                        canCloseSinglePaneStack: canCloseSinglePaneStack
                    )
                },
                onFocus: { [weak self] paneID in
                    _ = self?.controller.focus(paneID: paneID)
                },
                canStartPaneTabDrag: { [weak self] paneID in
                    self?.canStartPaneTabDrag(paneID: paneID, sourceStackID: paneStack.id) ?? false
                },
                onPaneTabDragStarted: { [weak self] button, paneID, stackID, _ in
                    self?.beginPaneTabDrag(button: button, paneID: paneID, sourceStackID: stackID)
                },
                onPaneTabDragMoved: { [weak self] _, _, event in
                    self?.updatePaneTabDrag(with: event)
                },
                onPaneTabDragEnded: { [weak self] _, _, event in
                    self?.endPaneTabDrag(with: event)
                },
                onPaneTabDragCancelled: { [weak self] in
                    self?.cancelPaneTabDrag()
                },
                onTextActivation: { [weak self] request in
                    self?.controller.handleTerminalTextActivation(request) ?? false
                },
                onTextActivationHover: { [weak self] request in
                    self?.controller.canHandleTerminalTextActivation(request) ?? false
                },
                onExtensionPaneAction: { [weak self] request in
                    self?.onExtensionPaneAction(request)
                }
            )
            return (
                stackView,
                paneStack.focusedPaneID == focusedPaneID ? stackView.focusedPaneView : nil,
                paneStack.panes.first?.id
            )

        case .split(let axis, let proportions, let children):
            var focusedPaneView: NSView?
            var childViews: [NSView] = []
            var childPaneIDs: [PaneID] = []

            for child in children {
                let childLayout = makeLayoutView(
                    for: child,
                    focusedPaneID: focusedPaneID,
                    windowIsKey: windowIsKey,
                    inactiveOpacity: inactiveOpacity,
                    canCloseSinglePaneStack: canCloseSinglePaneStack
                )
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

    // MARK: - Pane Tab Drag

    private enum PaneTabDropIntent {
        case split(PaneSplitDropDirection)
        case splitAtRoot(PaneSplitDropDirection)
        case merge
    }

    private struct PaneTabDragState {
        let paneID: PaneID
        let sourceStackID: PaneStackID
        weak var sourceButton: NSView?
        var targetStackID: PaneStackID?
        var dropIntent: PaneTabDropIntent?
        var ghostView: NSView?
    }
    private var paneTabDragState: PaneTabDragState?

    private func canStartPaneTabDrag(paneID: PaneID, sourceStackID: PaneStackID) -> Bool {
        guard let tab = currentWorkspace?.focusedTab else {
            return false
        }
        return PaneTabDragReadiness.canStart(
            paneID: paneID,
            sourceStackID: sourceStackID,
            in: tab,
            attachedSessionExists: controller.terminalBridge.attachedSession(for: paneID) != nil
        )
    }

    private func beginPaneTabDrag(button: NSView, paneID: PaneID, sourceStackID: PaneStackID) {
        guard canStartPaneTabDrag(paneID: paneID, sourceStackID: sourceStackID) else {
            return
        }
        clearPaneTabSplitPreview()
        let ghost = makePaneTabDragGhost(for: button)
        paneTabDragState = PaneTabDragState(
            paneID: paneID,
            sourceStackID: sourceStackID,
            sourceButton: button,
            targetStackID: nil,
            dropIntent: nil,
            ghostView: ghost
        )
    }

    private func updatePaneTabDrag(with event: NSEvent) {
        guard var dragState = paneTabDragState else { return }
        updatePaneTabDragGhost(dragState.ghostView, with: event)
        clearPaneTabSplitPreview()

        // Title bar zone (above the canvas) → full-width split above all panes.
        let canvasFrameInWindow = canvasView.convert(canvasView.bounds, to: nil)
        if event.locationInWindow.y > canvasFrameInWindow.maxY {
            canvasView.setRootSplitPreview(.up, theme: currentTheme)
            dragState.targetStackID = nil
            dragState.dropIntent = .splitAtRoot(.up)
            paneTabDragState = dragState
            return
        }

        // Resolve the pane under the cursor first — merge takes highest priority.
        if let targetView = paneStackView(atWindowLocation: event.locationInWindow),
           let targetStackID = targetView.paneStackID
        {
            // Hovering over the tab strip of a different pane → merge into that stack.
            if targetStackID != dragState.sourceStackID,
               targetView.isWindowPointInHeader(event.locationInWindow)
            {
                targetView.setMergePreview(theme: currentTheme)
                dragState.targetStackID = targetStackID
                dragState.dropIntent = .merge
                paneTabDragState = dragState
                return
            }

            // Canvas outer-edge zone — but only when NOT in another pane's header.
            let canvasPoint = canvasView.convert(event.locationInWindow, from: nil)
            if let rootDirection = PaneSplitDropIntentResolver.outerEdgeDirection(for: canvasPoint, in: canvasView.bounds) {
                canvasView.setRootSplitPreview(rootDirection, theme: currentTheme)
                dragState.targetStackID = nil
                dragState.dropIntent = .splitAtRoot(rootDirection)
                paneTabDragState = dragState
                return
            }

            // Otherwise resolve directional split intent from edge distance.
            let point = targetView.convert(event.locationInWindow, from: nil)
            if let direction = PaneSplitDropIntentResolver.direction(for: point, in: targetView.bounds) {
                targetView.setSplitPreview(direction, theme: currentTheme)
                dragState.targetStackID = targetStackID
                dragState.dropIntent = .split(direction)
                paneTabDragState = dragState
                return
            }
        }

        dragState.targetStackID = nil
        dragState.dropIntent = nil
        paneTabDragState = dragState
    }

    private func endPaneTabDrag(with event: NSEvent) {
        updatePaneTabDrag(with: event)
        guard let dragState = paneTabDragState else {
            clearPaneTabSplitPreview()
            return
        }

        defer {
            dragState.ghostView?.removeFromSuperview()
            paneTabDragState = nil
            clearPaneTabSplitPreview()
        }

        guard let intent = dragState.dropIntent else { return }

        switch intent {
        case .splitAtRoot(let direction):
            _ = try? controller.movePaneTabToRootSplit(
                paneID: dragState.paneID,
                sourceStackID: dragState.sourceStackID,
                direction: direction
            )
        case .split(let direction):
            guard let targetStackID = dragState.targetStackID else { return }
            _ = try? controller.movePaneTabToSplit(
                paneID: dragState.paneID,
                sourceStackID: dragState.sourceStackID,
                targetStackID: targetStackID,
                direction: direction
            )
        case .merge:
            guard let targetStackID = dragState.targetStackID else { return }
            _ = try? controller.movePaneTabToStack(
                paneID: dragState.paneID,
                sourceStackID: dragState.sourceStackID,
                targetStackID: targetStackID
            )
        }
    }

    private func cancelPaneTabDrag() {
        guard let dragState = paneTabDragState else { return }
        dragState.ghostView?.removeFromSuperview()
        paneTabDragState = nil
        clearPaneTabSplitPreview()
    }

    private func paneStackView(atWindowLocation location: NSPoint) -> PaneStackView? {
        paneStackView(in: canvasView, atWindowLocation: location)
    }

    private func paneStackView(in root: NSView, atWindowLocation location: NSPoint) -> PaneStackView? {
        for subview in root.subviews.reversed() {
            if let match = paneStackView(in: subview, atWindowLocation: location) {
                return match
            }
        }
        guard let stackView = root as? PaneStackView else { return nil }
        let point = stackView.convert(location, from: nil)
        return stackView.bounds.contains(point) ? stackView : nil
    }

    private func clearPaneTabSplitPreview() {
        canvasView.clearRootSplitPreview()
        clearPaneTabSplitPreview(in: canvasView)
    }

    private func clearPaneTabSplitPreview(in root: NSView) {
        if let stackView = root as? PaneStackView {
            stackView.clearSplitPreview()
            stackView.clearMergePreview()
        }
        root.subviews.forEach { clearPaneTabSplitPreview(in: $0) }
    }

    private func makePaneTabDragGhost(for button: NSView) -> NSView? {
        guard let contentView = button.window?.contentView else { return nil }
        let size = button.bounds.size
        guard size.width > 0, size.height > 0 else { return nil }

        let snapshot = NSImage(size: size, flipped: false) { [weak button] _ in
            guard let layer = button?.layer else { return false }
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            layer.render(in: ctx)
            return true
        }

        let ghost = NSImageView(image: snapshot)
        ghost.wantsLayer = true
        ghost.layer?.opacity = 0.82
        ghost.layer?.cornerRadius = 3
        ghost.layer?.shadowOpacity = 0.28
        ghost.layer?.shadowRadius = 10
        ghost.layer?.shadowColor = NSColor.black.cgColor
        ghost.layer?.shadowOffset = CGSize(width: 0, height: -3)

        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        ghost.frame = buttonFrameInWindow
        contentView.addSubview(ghost, positioned: NSWindow.OrderingMode.above, relativeTo: nil)
        return ghost
    }

    private func updatePaneTabDragGhost(_ ghost: NSView?, with event: NSEvent) {
        guard let ghost else { return }
        let cursor = event.locationInWindow
        ghost.frame.origin = NSPoint(
            x: cursor.x - ghost.frame.width / 2,
            y: cursor.y - ghost.frame.height / 2
        )
    }
}

private struct PaneSplitDropIntentResolver {
    static let outerEdgeThreshold: CGFloat = 40

    static func direction(for point: NSPoint, in bounds: NSRect) -> PaneSplitDropDirection? {
        guard bounds.width > 0, bounds.height > 0, bounds.contains(point) else { return nil }
        let distances: [(PaneSplitDropDirection, CGFloat)] = [
            (.left, point.x - bounds.minX),
            (.right, bounds.maxX - point.x),
            (.up, bounds.maxY - point.y),
            (.down, point.y - bounds.minY),
        ]
        return distances.min { $0.1 < $1.1 }?.0
    }

    /// Returns a direction if `point` falls within the outer-edge drop zone of `bounds`.
    /// This zone triggers a root-level layout wrap regardless of which pane is under the cursor.
    /// Note: `.up` is excluded here — it is triggered by the window title bar instead.
    static func outerEdgeDirection(for point: NSPoint, in bounds: NSRect) -> PaneSplitDropDirection? {
        guard bounds.width > 0, bounds.height > 0, bounds.contains(point) else { return nil }
        let t = outerEdgeThreshold
        if point.y <= bounds.minY + t { return .down }
        if point.x <= bounds.minX + t { return .left }
        if point.x >= bounds.maxX - t { return .right }
        return nil
    }
}

enum PaneTabDragReadiness {
    static func canStart(
        paneID: PaneID,
        sourceStackID: PaneStackID,
        in tab: Tab,
        attachedSessionExists: Bool
    ) -> Bool {
        guard let sourceStack = tab.rootLayout.paneStack(id: sourceStackID),
              let pane = sourceStack.panes.first(where: { $0.id == paneID })
        else {
            return false
        }

        // Don't drag if this is the only tab in the only pane stack — nothing to split into.
        if sourceStack.panes.count == 1, tab.rootLayout.visiblePaneIDs.count == 1 {
            return false
        }

        if let extensionPane = pane.extensionPane {
            return extensionPane.status == .ready
        }

        return pane.isTerminal && attachedSessionExists && pane.terminalState.reportedTitle != nil
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
    let progress: PaneProgress?
    let title: String
    let subtitle: String?
    let isActive: Bool
    let isExpanded: Bool?
    let action: Action
    let contextMenuProvider: (() -> NSMenu)?

    init(
        kind: Kind,
        identifier: String,
        icon: OmuxRenderedIcon?,
        progress: PaneProgress?,
        title: String,
        subtitle: String?,
        isActive: Bool,
        isExpanded: Bool? = nil,
        action: Action,
        contextMenuProvider: (() -> NSMenu)?
    ) {
        self.kind = kind
        self.identifier = identifier
        self.icon = icon
        self.progress = progress
        self.title = title
        self.subtitle = subtitle
        self.isActive = isActive
        self.isExpanded = isExpanded
        self.action = action
        self.contextMenuProvider = contextMenuProvider
    }

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
    private let scrollView = NSScrollView()
    private let updateNoticeView = SidebarUpdateNoticeView()
    private let container = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        container.orientation = .vertical
        container.alignment = .leading
        container.distribution = .fill
        container.spacing = 0
        container.translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = workspacesSection
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        scrollView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        addSubview(container)
        container.addArrangedSubview(scrollView)
        container.addArrangedSubview(updateNoticeView)
        updateNoticeView.isHidden = true

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            container.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            container.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            scrollView.widthAnchor.constraint(equalTo: container.widthAnchor),
            updateNoticeView.widthAnchor.constraint(equalTo: container.widthAnchor),
            workspacesSection.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            workspacesSection.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            workspacesSection.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            workspacesSection.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            workspacesSection.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),
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
        onToggleWorkspaceExpansion: @escaping @MainActor (WorkspaceID) -> Void,
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
            onToggleWorkspaceExpansion: onToggleWorkspaceExpansion,
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
        onToggleWorkspaceExpansion: @escaping (WorkspaceID) -> Void,
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
            button.onToggleExpansion = {
                if let workspaceID = item.workspaceID {
                    onToggleWorkspaceExpansion(workspaceID)
                }
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
    private var rootSplitPreview: PaneSplitPreviewView?

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

    func setRootSplitPreview(_ direction: PaneSplitDropDirection, theme: WorkspaceShellTheme) {
        if rootSplitPreview == nil {
            let preview = PaneSplitPreviewView()
            addSubview(preview, positioned: NSWindow.OrderingMode.above, relativeTo: nil)
            rootSplitPreview = preview
        }
        rootSplitPreview?.update(direction: direction, theme: theme, in: bounds)
    }

    func clearRootSplitPreview() {
        rootSplitPreview?.removeFromSuperview()
        rootSplitPreview = nil
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
private protocol WorkspacePaneRendering: AnyObject {
    var rootPaneView: NSView { get }
    var focusTarget: NSView { get }
    var representedPaneID: PaneID { get }
    func updateFocusState(_ isFocused: Bool)
    func apply(theme: WorkspaceShellTheme)
}

extension HostedTerminalPaneView: WorkspacePaneRendering {
    fileprivate var rootPaneView: NSView { self }

    fileprivate func apply(theme: WorkspaceShellTheme) {
        apply(themePalette: theme.terminalPalette)
    }
}

@MainActor
private final class ExtensionPaneHostView: NSView, WorkspacePaneRendering, WKNavigationDelegate, WKScriptMessageHandler {
    private let paneID: PaneID
    private let descriptor: ExtensionPaneDescriptor
    private let onFocus: @MainActor (PaneID) -> Void
    private let onAction: @MainActor (ExtensionPaneActionRequest) -> Void
    private let container = NSView()
    private let placeholderLabel = NSTextField(wrappingLabelWithString: "")
    private let webView: WKWebView
    private var isLoadingInjectedHTML = false

    init(
        pane: Pane,
        descriptor: ExtensionPaneDescriptor,
        isFocused: Bool,
        theme: WorkspaceShellTheme,
        onFocus: @escaping @MainActor (PaneID) -> Void,
        onAction: @escaping @MainActor (ExtensionPaneActionRequest) -> Void
    ) {
        self.paneID = pane.id
        self.descriptor = descriptor
        self.onFocus = onFocus
        self.onAction = onAction

        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = descriptor.actionsEnabled
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        if descriptor.actionsEnabled {
            configuration.userContentController.addUserScript(
                WKUserScript(
                    source: Self.bridgeScript(paneID: pane.id, pluginID: descriptor.pluginID),
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true
                )
            )
        }
        self.webView = WKWebView(frame: .zero, configuration: configuration)

        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true

        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.cornerRadius = 6
        addSubview(container)

        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        if descriptor.actionsEnabled {
            webView.configuration.userContentController.add(
                WeakScriptMessageHandler(delegate: self),
                name: "omuxAction"
            )
        }
        container.addSubview(webView)

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.alignment = .center
        placeholderLabel.lineBreakMode = .byWordWrapping
        placeholderLabel.maximumNumberOfLines = 0
        container.addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            container.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            container.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 360),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 280),

            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            placeholderLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            placeholderLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            placeholderLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
        ])

        apply(theme: theme)
        updateFocusState(isFocused)
        renderContent(theme: theme)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    var rootPaneView: NSView { self }
    var focusTarget: NSView { webView }
    var representedPaneID: PaneID { paneID }

    override func mouseDown(with event: NSEvent) {
        onFocus(paneID)
        window?.makeFirstResponder(focusTarget)
        super.mouseDown(with: event)
    }

    func updateFocusState(_ isFocused: Bool) {
        layer?.borderWidth = 0
    }

    func apply(theme: WorkspaceShellTheme) {
        layer?.backgroundColor = theme.terminalPalette.backgroundColor.cgColor
        container.layer?.backgroundColor = theme.terminalPalette.backgroundColor.cgColor
        placeholderLabel.textColor = theme.shell.textSecondary
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        if isLoadingInjectedHTML, navigationAction.navigationType == .other {
            isLoadingInjectedHTML = false
            decisionHandler(.allow)
            return
        }

        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url,
           ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
        }
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoadingInjectedHTML = false
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoadingInjectedHTML = false
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoadingInjectedHTML = false
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "omuxAction",
              let actionRequest = Self.actionRequest(
                from: message.body,
                expectedPaneID: paneID,
                expectedPluginID: descriptor.pluginID
              )
        else {
            return
        }
        onAction(actionRequest)
    }

    private func renderContent(theme: WorkspaceShellTheme) {
        guard descriptor.status == .ready,
              descriptor.contentKind == .html,
              let html = descriptor.html,
              html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else {
            webView.isHidden = true
            placeholderLabel.isHidden = false
            placeholderLabel.stringValue = placeholderMessage
            return
        }

        placeholderLabel.isHidden = true
        webView.isHidden = false
        isLoadingInjectedHTML = true
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    private var placeholderMessage: String {
        if let message = descriptor.message?.trimmingCharacters(in: .whitespacesAndNewlines), message.isEmpty == false {
            return message
        }

        switch descriptor.status {
        case .ready:
            return "Waiting for \(descriptor.pluginID) content."
        case .disabled:
            return "\(descriptor.pluginID) is disabled."
        case .error:
            return "\(descriptor.pluginID) could not render this pane."
        }
    }

    private var baseURL: URL? {
        descriptor.source.map { URL(fileURLWithPath: $0).deletingLastPathComponent() }
    }

    private static func bridgeScript(paneID: PaneID, pluginID: String) -> String {
        let paneJSONString = javascriptString(paneID.rawValue)
        let pluginJSONString = javascriptString(pluginID)
        return """
        (() => {
          const paneID = \(paneJSONString);
          const pluginID = \(pluginJSONString);
          window.omux = Object.freeze({
            submitAction(action, payload = {}) {
              window.webkit.messageHandlers.omuxAction.postMessage({ paneID, pluginID, action, payload });
            }
          });
        })();
        """
    }

    private static func javascriptString(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let string = String(data: data, encoding: .utf8)
        else {
            return "\"\""
        }
        return string
    }

    private static func actionRequest(
        from body: Any,
        expectedPaneID: PaneID,
        expectedPluginID: String
    ) -> ExtensionPaneActionRequest? {
        guard let object = body as? [String: Any],
              let paneID = object["paneID"] as? String,
              let pluginID = object["pluginID"] as? String,
              let action = object["action"] as? String,
              paneID == expectedPaneID.rawValue,
              pluginID == expectedPluginID,
              let payload = omuxValue(from: object["payload"] ?? [:])
        else {
            return nil
        }
        return ExtensionPaneActionRequest(
            paneID: expectedPaneID,
            pluginID: expectedPluginID,
            action: action,
            payload: payload
        )
    }

    private static func omuxValue(from value: Any) -> OmuxValue? {
        switch value {
        case let string as String:
            return .string(string)
        case let bool as Bool:
            return .bool(bool)
        case let int as Int:
            return .integer(int)
        case let number as NSNumber:
            return CFGetTypeID(number) == CFBooleanGetTypeID() ? .bool(number.boolValue) : .double(number.doubleValue)
        case let array as [Any]:
            var result: [OmuxValue] = []
            for item in array {
                guard let converted = omuxValue(from: item) else {
                    return nil
                }
                result.append(converted)
            }
            return .array(result)
        case let object as [String: Any]:
            var result: [String: OmuxValue] = [:]
            for (key, nestedValue) in object {
                guard let converted = omuxValue(from: nestedValue) else {
                    return nil
                }
                result[key] = converted
            }
            return .object(result)
        case _ as NSNull:
            return .null
        default:
            return nil
        }
    }
}

@MainActor
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var delegate: (any WKScriptMessageHandler)?

    init(delegate: any WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

@MainActor
final class PaneStackView: NSView {
    private let paneContentView: NSView
    private let paneRenderer: any WorkspacePaneRendering
    private let paneCardView = PaneCardView()
    private var splitPreviewView: PaneSplitPreviewView?
    private var mergePreviewView: PaneMergePreviewView?

    var paneStackID: PaneStackID?

    init(
        paneStack: PaneStack,
        focusedPaneID: PaneID,
        windowIsKey: Bool,
        inactiveOpacity: Double,
        bridge: GhosttyTerminalBridge,
        theme: WorkspaceShellTheme,
        iconResolver: WorkspaceIconResolver,
        iconConfiguration: OmuxConfigUI.Icons,
        onSelectPaneTab: @escaping @MainActor (PaneID) -> Void,
        onCreatePaneTab: @escaping @MainActor () throws -> Void,
        canCloseSinglePaneStack: Bool,
        onClosePane: @escaping @MainActor (PaneID) throws -> Void,
        contextMenuProvider: @escaping @MainActor (Pane) -> NSMenu,
        onFocus: @escaping @MainActor (PaneID) -> Void,
        canStartPaneTabDrag: @escaping @MainActor (PaneID) -> Bool,
        onPaneTabDragStarted: ((NSView, PaneID, PaneStackID, NSEvent) -> Void)? = nil,
        onPaneTabDragMoved: ((PaneID, PaneStackID, NSEvent) -> Void)? = nil,
        onPaneTabDragEnded: ((PaneID, PaneStackID, NSEvent) -> Void)? = nil,
        onPaneTabDragCancelled: (() -> Void)? = nil,
        onTextActivation: @escaping @MainActor (TerminalTextActivationRequest) -> Bool,
        onTextActivationHover: @escaping @MainActor (TerminalTextActivationRequest) -> Bool,
        onExtensionPaneAction: @escaping @MainActor (ExtensionPaneActionRequest) -> Void
    ) {
        let activePane = paneStack.focusedPane ?? paneStack.panes[0]
        if let descriptor = activePane.extensionPane {
            let extensionPaneView = ExtensionPaneHostView(
                pane: activePane,
                descriptor: descriptor,
                isFocused: activePane.id == focusedPaneID,
                theme: theme,
                onFocus: onFocus,
                onAction: onExtensionPaneAction
            )
            self.paneRenderer = extensionPaneView
            self.paneContentView = extensionPaneView
        } else {
            let terminalPaneView = bridge.makeHostedPaneView(
                for: activePane,
                isFocused: activePane.id == focusedPaneID,
                themePalette: theme.terminalPalette,
                onFocus: onFocus,
                onTextActivation: onTextActivation,
                onTextActivationHover: onTextActivationHover
            )
            self.paneRenderer = terminalPaneView
            self.paneContentView = terminalPaneView
        }
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        self.paneStackID = paneStack.id

        let headerView = PaneHeaderView(
            paneStack: paneStack,
            theme: theme,
            iconResolver: iconResolver,
            iconConfiguration: iconConfiguration,
            terminalTextProvider: { pane in
                guard pane.isTerminal else {
                    return nil
                }
                let snapshot = bridge.terminalTextSnapshot(for: pane.id, maxBytes: 4_096, maxLines: 40)
                return snapshot.text.isEmpty ? nil : snapshot.text
            },
            onSelectPaneTab: onSelectPaneTab,
            onCreatePaneTab: onCreatePaneTab,
            canCloseSinglePaneStack: canCloseSinglePaneStack,
            onClosePane: onClosePane,
            contextMenuProvider: contextMenuProvider,
            canStartPaneTabDrag: canStartPaneTabDrag,
            onPaneTabDragStarted: onPaneTabDragStarted,
            onPaneTabDragMoved: onPaneTabDragMoved,
            onPaneTabDragEnded: onPaneTabDragEnded,
            onPaneTabDragCancelled: onPaneTabDragCancelled
        )
        paneCardView.configure(
            headerView: headerView,
            statusText: activePane.terminalState.statusSummary,
            paneRenderer: paneRenderer,
            theme: theme,
            focused: activePane.id == focusedPaneID,
            windowIsKey: windowIsKey,
            inactiveOpacity: inactiveOpacity
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

    var focusedPaneView: NSView {
        paneContentView
    }

    func setSplitPreview(_ direction: PaneSplitDropDirection, theme: WorkspaceShellTheme) {
        clearMergePreview()
        if splitPreviewView == nil {
            let preview = PaneSplitPreviewView()
            addSubview(preview, positioned: NSWindow.OrderingMode.above, relativeTo: nil)
            splitPreviewView = preview
        }
        splitPreviewView?.update(direction: direction, theme: theme, in: bounds)
    }

    func setMergePreview(theme: WorkspaceShellTheme) {
        clearSplitPreview()
        if mergePreviewView == nil {
            let preview = PaneMergePreviewView()
            addSubview(preview, positioned: NSWindow.OrderingMode.above, relativeTo: nil)
            mergePreviewView = preview
        }
        mergePreviewView?.update(theme: theme, headerHeight: ShellLayoutMetrics.paneHeaderHeight, in: bounds)
    }

    func clearSplitPreview() {
        splitPreviewView?.removeFromSuperview()
        splitPreviewView = nil
    }

    func clearMergePreview() {
        mergePreviewView?.removeFromSuperview()
        mergePreviewView = nil
    }

    func isWindowPointInHeader(_ windowPoint: NSPoint) -> Bool {
        let localPoint = convert(windowPoint, from: nil)
        guard bounds.contains(localPoint) else { return false }
        let threshold = ShellLayoutMetrics.paneHeaderHeight + 4
        return isFlipped ? localPoint.y <= threshold : localPoint.y >= bounds.height - threshold
    }
}

@MainActor
private final class PaneSplitPreviewView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 4
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var mouseDownCanMoveWindow: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(direction: PaneSplitDropDirection, theme: WorkspaceShellTheme, in bounds: NSRect) {
        let half: CGFloat
        let region: NSRect
        switch direction {
        case .left:
            half = bounds.width / 2
            region = NSRect(x: bounds.minX, y: bounds.minY, width: half, height: bounds.height)
        case .right:
            half = bounds.width / 2
            region = NSRect(x: bounds.minX + half, y: bounds.minY, width: half, height: bounds.height)
        case .up:
            half = bounds.height / 2
            region = NSRect(x: bounds.minX, y: bounds.minY + half, width: bounds.width, height: half)
        case .down:
            half = bounds.height / 2
            region = NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: half)
        }
        frame = region
        layer?.backgroundColor = theme.shell.selection.withAlphaComponent(0.35).cgColor
        layer?.borderColor = theme.shell.selection.withAlphaComponent(0.8).cgColor
        layer?.borderWidth = 1.5
    }
}

@MainActor
private final class PaneMergePreviewView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 3
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var mouseDownCanMoveWindow: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(theme: WorkspaceShellTheme, headerHeight: CGFloat, in bounds: NSRect) {
        let region: NSRect
        if isFlipped {
            region = NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: headerHeight)
        } else {
            region = NSRect(x: bounds.minX, y: bounds.maxY - headerHeight, width: bounds.width, height: headerHeight)
        }
        frame = region
        layer?.backgroundColor = theme.shell.selection.withAlphaComponent(0.45).cgColor
        layer?.borderColor = theme.shell.selection.withAlphaComponent(0.9).cgColor
        layer?.borderWidth = 1.5
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

    fileprivate func configure(
        headerView: PaneHeaderView,
        statusText: String?,
        paneRenderer: any WorkspacePaneRendering,
        theme: WorkspaceShellTheme,
        focused: Bool,
        windowIsKey: Bool,
        inactiveOpacity: Double
    ) {
        container.arrangedSubviews.forEach { view in
            container.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        paneRenderer.apply(theme: theme)
        let paneView = paneRenderer.rootPaneView
        paneView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        paneView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
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
        container.addArrangedSubview(paneView)
        paneView.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true

        let showActiveBorder = focused && windowIsKey
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderWidth = 0
        layer?.borderColor = nil
        alphaValue = showActiveBorder ? 1.0 : inactiveOpacity
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
        canCloseSinglePaneStack: Bool,
        onClosePane: @escaping @MainActor (PaneID) throws -> Void,
        contextMenuProvider: @escaping @MainActor (Pane) -> NSMenu,
        canStartPaneTabDrag: @escaping @MainActor (PaneID) -> Bool,
        onPaneTabDragStarted: ((NSView, PaneID, PaneStackID, NSEvent) -> Void)? = nil,
        onPaneTabDragMoved: ((PaneID, PaneStackID, NSEvent) -> Void)? = nil,
        onPaneTabDragEnded: ((PaneID, PaneStackID, NSEvent) -> Void)? = nil,
        onPaneTabDragCancelled: (() -> Void)? = nil
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
                progress: pane.terminalState.progress,
                showsClose: paneStack.panes.count > 1 || canCloseSinglePaneStack,
                onClose: {
                    try? onClosePane(pane.id)
                }
            )
            button.onPress = { onSelectPaneTab(pane.id) }
            button.contextMenuProvider = { contextMenuProvider(pane) }
            if onPaneTabDragStarted != nil {
                button.canStartDrag = { canStartPaneTabDrag(pane.id) }
                button.onDragStarted = { [weak button] _, event in
                    guard let button else { return }
                    onPaneTabDragStarted?(button, pane.id, paneStack.id, event)
                }
                button.onDragMoved = { _, event in onPaneTabDragMoved?(pane.id, paneStack.id, event) }
                button.onDragEnded = { _, event in onPaneTabDragEnded?(pane.id, paneStack.id, event) }
                button.onDragCancelled = { _ in onPaneTabDragCancelled?() }
            }
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

@MainActor
final class PaneProgressOrbView: NSView {
    static let side = CGFloat(7)
    private static let pulseAnimationKey = "omux.progress.orb.pulse"

    private(set) var progressStateForTesting: PaneProgressState?
    private(set) var progressColorForTesting: NSColor?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = Self.side / 2
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.side, height: Self.side)
    }

    func configure(progress: PaneProgress?, theme: WorkspaceShellTheme) {
        progressStateForTesting = progress?.state
        guard let progress else {
            isHidden = true
            progressColorForTesting = nil
            layer?.removeAnimation(forKey: Self.pulseAnimationKey)
            setAccessibilityLabel(nil)
            return
        }

        isHidden = false
        let progressColor = color(for: progress.state, theme: theme)
        progressColorForTesting = progressColor
        layer?.backgroundColor = progressColor.cgColor
        setAccessibilityLabel(accessibilityLabel(for: progress.state))
        updatePulse(for: progress.state)
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    private func color(for state: PaneProgressState, theme: WorkspaceShellTheme) -> NSColor {
        switch state {
        case .active, .indeterminate:
            return theme.shell.accent
        case .error:
            return .systemRed
        case .needsInput:
            return .systemYellow
        case .paused:
            return .systemBlue
        }
    }

    private func accessibilityLabel(for state: PaneProgressState) -> String {
        switch state {
        case .active, .indeterminate:
            return "Pane working"
        case .error:
            return "Pane progress error"
        case .needsInput:
            return "Pane needs user input"
        case .paused:
            return "Pane idle"
        }
    }

    private func updatePulse(for state: PaneProgressState) {
        layer?.removeAnimation(forKey: Self.pulseAnimationKey)
        layer?.opacity = 1
        guard state == .active || state == .indeterminate else {
            return
        }
        guard NSWorkspace.shared.accessibilityDisplayShouldReduceMotion == false else {
            return
        }

        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.35
        pulse.toValue = 1
        pulse.duration = 0.9
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer?.add(pulse, forKey: Self.pulseAnimationKey)
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
    var onDragStarted: ((PaneTabButton, NSEvent) -> Void)?
    var onDragMoved: ((PaneTabButton, NSEvent) -> Void)?
    var onDragEnded: ((PaneTabButton, NSEvent) -> Void)?
    var onDragCancelled: ((PaneTabButton) -> Void)?
    var canStartDrag: (() -> Bool)?
    var contextMenuProvider: (() -> NSMenu)? {
        didSet {
            menu = contextMenuProvider?()
        }
    }

    private let titleLabel = NSTextField(labelWithString: "")
    private let iconLabel = NSTextField(labelWithString: "")
    private let iconImageView = NSImageView()
    private let progressOrb = PaneProgressOrbView()
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
    private let progress: PaneProgress?

    init(
        pane: Pane,
        active: Bool,
        theme: WorkspaceShellTheme,
        icon: OmuxRenderedIcon?,
        progress: PaneProgress?,
        showsClose: Bool,
        onClose: @escaping () -> Void
    ) {
        self.showsClose = showsClose
        self.currentTheme = theme
        self.isActiveTab = active
        self.renderedIcon = icon
        self.iconSymbolImage = icon?.symbolImage()
        self.progress = progress
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = 3
        identifier = NSUserInterfaceItemIdentifier("pane-tab-\(pane.id.rawValue)")
        setAccessibilityLabel(icon.map { "\($0.accessibilityLabel), \(pane.title)" } ?? pane.title)
        toolTip = pane.title
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        progressOrb.identifier = NSUserInterfaceItemIdentifier("pane-tab-progress-\(pane.id.rawValue)")
        progressOrb.configure(progress: progress, theme: theme)
        addSubview(progressOrb)

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
        titleLabel.lineBreakMode = .byClipping
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
        let progressWidth = progress == nil ? 0 : PaneProgressOrbView.side + iconSpacing
        let iconWidth = renderedIcon == nil ? 0 : iconSize.width + iconSpacing
        return NSSize(
            width: progressWidth + iconWidth + titleSize.width + closeWidth + contentInsets.left + contentInsets.right,
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
        if progress != nil {
            progressOrb.frame = NSRect(
                x: contentBounds.minX,
                y: round((bounds.height - PaneProgressOrbView.side) / 2),
                width: PaneProgressOrbView.side,
                height: PaneProgressOrbView.side
            )
            titleMinX = progressOrb.frame.maxX + iconSpacing
        } else {
            progressOrb.frame = .zero
        }

        if let renderedIcon {
            if iconSymbolImage == nil {
                let iconSize = iconLabel.intrinsicContentSize
                iconLabel.frame = NSRect(
                    x: titleMinX,
                    y: round((bounds.height - iconSize.height) / 2),
                    width: iconSize.width,
                    height: iconSize.height
                )
                iconLabel.setAccessibilityLabel(renderedIcon.accessibilityLabel)
                iconImageView.frame = .zero
                titleMinX = iconLabel.frame.maxX + iconSpacing
            } else {
                iconImageView.frame = NSRect(
                    x: titleMinX,
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
        guard isEnabled else { return }

        guard onDragStarted != nil || onDragMoved != nil || onDragEnded != nil else {
            onPress?()
            return
        }

        let initialLocation = convert(event.locationInWindow, from: nil)
        var didStartDragging = false

        while let nextEvent = window?.nextEvent(
            matching: [.leftMouseDragged, .leftMouseUp, .keyDown],
            until: .distantFuture,
            inMode: .eventTracking,
            dequeue: true
        ) {
            switch nextEvent.type {
            case .keyDown where nextEvent.keyCode == 53: // Escape
                if didStartDragging {
                    onDragCancelled?(self)
                }
                return

            case .leftMouseDragged:
                let location = convert(nextEvent.locationInWindow, from: nil)
                let delta = hypot(location.x - initialLocation.x, location.y - initialLocation.y)
                guard delta >= 4 else { continue }
                if !didStartDragging {
                    guard canStartDrag?() ?? true else {
                        continue
                    }
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
    var onToggleExpansion: (() -> Void)?
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
    private let disclosureImageView = NSImageView()
    private let iconField = NSTextField(labelWithString: "")
    private let iconImageView = NSImageView()
    private let progressOrb = PaneProgressOrbView()
    private var leadingInset: CGFloat = 12
    private var textLeadingInset: CGFloat = 12
    private var renderedIcon: OmuxRenderedIcon?
    private var iconSymbolImage: NSImage?
    private var iconSide = CGFloat(13)
    private var progress: PaneProgress?
    private var showsDisclosure = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        progressOrb.identifier = NSUserInterfaceItemIdentifier("sidebar-pane-progress")
        addSubview(progressOrb)

        disclosureImageView.isHidden = true
        addSubview(disclosureImageView)

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
            leadingInset = 6
            subtitleField.font = .systemFont(ofSize: 11, weight: .regular)
        case .terminal:
            titleField.font = .systemFont(ofSize: 10, weight: .regular)
            subtitleField.font = .systemFont(ofSize: 10, weight: .regular)
            leadingInset = 22
        }

        titleField.stringValue = item.title
        progress = item.progress
        progressOrb.configure(progress: item.progress, theme: theme)
        renderedIcon = item.icon
        iconSymbolImage = item.icon?.symbolImage()
        iconSide = item.kind == .workspace ? 13 : 11
        showsDisclosure = item.kind == .workspace && item.isExpanded != nil
        let disclosureSymbol = item.isExpanded == false ? "chevron.right" : "chevron.down"
        disclosureImageView.symbolConfiguration = .init(pointSize: 9, weight: .semibold)
        disclosureImageView.image = NSImage(systemSymbolName: disclosureSymbol, accessibilityDescription: nil)
        disclosureImageView.isHidden = !showsDisclosure
        disclosureImageView.setAccessibilityLabel(item.isExpanded == false ? "Expand workspace panes" : "Collapse workspace panes")
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
        disclosureImageView.contentTintColor = item.isActive ? theme.shell.selectedText : theme.shell.textMuted
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
        if progress != nil {
            let progressX = max(0, leadingInset - PaneProgressOrbView.side - 5)
            progressOrb.frame = NSRect(
                x: progressX,
                y: round((bounds.height - PaneProgressOrbView.side) / 2),
                width: PaneProgressOrbView.side,
                height: PaneProgressOrbView.side
            )
        } else {
            progressOrb.frame = .zero
        }
        if showsDisclosure {
            let disclosureSide: CGFloat = 11
            disclosureImageView.frame = NSRect(
                x: textX,
                y: round((bounds.height - disclosureSide) / 2),
                width: disclosureSide,
                height: disclosureSide
            )
            textX = disclosureImageView.frame.maxX + 4
        } else {
            disclosureImageView.frame = .zero
        }
        if let renderedIcon {
            if iconSymbolImage == nil {
                let iconSize = iconField.intrinsicContentSize
                iconField.frame = NSRect(
                    x: textX,
                    y: round((bounds.height - iconSize.height) / 2),
                    width: iconSize.width,
                    height: iconSize.height
                )
                iconField.setAccessibilityLabel(renderedIcon.accessibilityLabel)
                iconImageView.frame = .zero
                textX = iconField.frame.maxX + iconSpacing
            } else {
                iconImageView.frame = NSRect(
                    x: textX,
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
        if showsDisclosure,
           disclosureImageView.frame.insetBy(dx: -5, dy: -5).contains(convert(event.locationInWindow, from: nil)) {
            onToggleExpansion?()
            return
        }

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
