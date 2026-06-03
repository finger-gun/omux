import AppKit
import OmuxConfig
import OmuxCore
import QuartzCore

@MainActor
final class WorkspacesSidebarWidget: NSView {
    static let collapsedHeight: CGFloat = 34   // 6 top + 22 header + 6 bottom

    override var isFlipped: Bool { true }

    let header = CollapsibleSectionHeaderView()
    private let workspacesSection = WorkspaceSidebarSectionView()
    private let scrollView = NSScrollView()
    private let scrollContent = NSStackView()

    /// Forwarded to outer render call to get access to the section.
    var sectionView: WorkspaceSidebarSectionView { workspacesSection }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        scrollContent.orientation = .vertical
        scrollContent.alignment = .leading
        scrollContent.distribution = .fill
        scrollContent.spacing = 0
        scrollContent.translatesAutoresizingMaskIntoConstraints = false

        scrollView.configureSidebarScrollView(documentView: scrollContent)
        // Allow SidebarSplitView to compress this widget vertically.
        scrollView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        scrollContent.addArrangedSubview(workspacesSection)
        addSubview(header)
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            header.heightAnchor.constraint(equalToConstant: 22),

            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            {
                let c = scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
                c.priority = .defaultLow
                return c
            }(),
            scrollContent.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            scrollContent.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            scrollContent.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor, constant: -12),
            scrollContent.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),
            workspacesSection.widthAnchor.constraint(equalTo: scrollContent.widthAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func render(
        workspaceItems: [SidebarItem],
        isCollapsed: Bool,
        theme: WorkspaceShellTheme,
        onCreateWorkspace: @escaping @MainActor () -> Void,
        onDeleteWorkspace: @escaping @MainActor () -> Void,
        canDeleteWorkspace: Bool,
        onMoveWorkspace: @escaping @MainActor (WorkspaceID, Int) -> Void,
        onToggleWorkspaceExpansion: @escaping @MainActor (WorkspaceID) -> Void,
        onRenameWorkspace: @escaping @MainActor (WorkspaceID, String) -> Void,
        onSelectWorkspace: @escaping @MainActor (WorkspaceID) -> Void,
        onSelectPane: @escaping @MainActor (PaneID) -> Void,
        onToggleCollapse: @escaping @MainActor () -> Void
    ) {
        let count = workspaceItems.filter { $0.kind == .workspace }.count
        header.render(
            title: "WORKSPACES",
            count: count,
            isCollapsed: isCollapsed,
            actionButtons: {
                let btn = NSButton()
                btn.isBordered = false
                btn.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Create workspace")
                btn.target = self
                btn.action = #selector(createWorkspacePressed)
                btn.contentTintColor = theme.shell.textMuted
                btn.translatesAutoresizingMaskIntoConstraints = false
                self._onCreateWorkspace = onCreateWorkspace
                return [btn]
            }(),
            theme: theme,
            onToggle: onToggleCollapse
        )

        scrollView.isHidden = isCollapsed

        workspacesSection.apply(theme: theme)
        workspacesSection.renderButtons(
            items: workspaceItems,
            title: "WORKSPACES",
            count: count,
            emptyState: "No workspaces open",
            theme: theme,
            accessories: [],
            onMoveWorkspace: onMoveWorkspace,
            onToggleWorkspaceExpansion: onToggleWorkspaceExpansion,
            onRenameWorkspace: onRenameWorkspace,
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

    func apply(theme: WorkspaceShellTheme) {
        header.applyTheme(theme)
        workspacesSection.apply(theme: theme)
    }

    private var _onCreateWorkspace: (() -> Void)?

    @objc private func createWorkspacePressed() {
        _onCreateWorkspace?()
    }
}

@MainActor
final class WorkspaceSidebarView: SidebarContainerView {
    let workspacesWidget = WorkspacesSidebarWidget()
    let splitView = SidebarSplitView()
    private let updateNoticeView = SidebarUpdateNoticeView()

    /// Height constraint on updateNoticeView; set to 0 when hidden so splitView fills full height.
    private var noticeHeightConstraint: NSLayoutConstraint?
    /// Bottom padding constraint between updateNoticeView and sidebar bottom; active only when visible.
    private var noticeBottomConstraint: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        updateNoticeView.isHidden = true
        updateNoticeView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(splitView)
        addSubview(updateNoticeView)

        // Load persisted proportion for the workspaces panel (default 1.0 — only panel).
        let workspacesProportion = CGFloat(
            UserDefaults.standard.double(forKey: "omux.leftSidebar.workspacesProportion").nonZero ?? 1.0
        )
        splitView.setPanels([
            SidebarSplitView.Panel(
                view: workspacesWidget,
                collapsedHeight: WorkspacesSidebarWidget.collapsedHeight,
                isCollapsed: UserDefaults.standard.bool(forKey: "omux.leftSidebar.workspacesCollapsed"),
                proportion: workspacesProportion,
                defaultsKey: "omux.leftSidebar.workspacesProportion",
                panelID: "workspaces",
                headerView: workspacesWidget.header
            ),
        ])

        // splitView fills from top down to the top edge of updateNoticeView.
        // When updateNoticeView is hidden, its height collapses to 0 (noticeHeightConstraint),
        // so splitView naturally fills the full sidebar height.
        let noticeBottom = updateNoticeView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        let noticeHeight = updateNoticeView.heightAnchor.constraint(equalToConstant: 0)
        noticeBottomConstraint = noticeBottom
        noticeHeightConstraint = noticeHeight

        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: topAnchor),
            splitView.leadingAnchor.constraint(equalTo: leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: updateNoticeView.topAnchor),

            updateNoticeView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            updateNoticeView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            noticeBottom,
            noticeHeight,
        ])
    }

    func makeWorkspacesPanel(sidebarNamespace: String) -> SidebarSplitView.Panel {
        let proportion = CGFloat(
            UserDefaults.standard.double(forKey: "\(sidebarNamespace).workspacesProportion").nonZero ?? 1.0
        )
        return SidebarSplitView.Panel(
            view: workspacesWidget,
            collapsedHeight: WorkspacesSidebarWidget.collapsedHeight,
            isCollapsed: UserDefaults.standard.bool(forKey: "\(sidebarNamespace).workspacesCollapsed"),
            proportion: proportion,
            defaultsKey: "\(sidebarNamespace).workspacesProportion",
            panelID: "workspaces",
            headerView: workspacesWidget.header
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func applyBorderLayer(theme: WorkspaceShellTheme) {
        layer?.borderWidth = 0
        // Draw a 1px right-edge separator matching the VSCode style
        let border = sidebarBorderLayer(named: "sidebarRightBorder")
        border.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        border.frame = CGRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height)
        border.autoresizingMask = [.layerMinXMargin, .layerHeightSizable]
    }

    override func apply(theme: WorkspaceShellTheme) {
        super.apply(theme: theme)
        workspacesWidget.apply(theme: theme)
        splitView.applyTheme(theme)
        updateNoticeView.apply(theme: theme)
    }

    func render(
        workspaceItems: [SidebarItem],
        isWorkspacesCollapsed: Bool,
        theme: WorkspaceShellTheme,
        onSelectWorkspace: @escaping @MainActor (WorkspaceID) -> Void,
        onCreateWorkspace: @escaping @MainActor () -> Void,
        onDeleteWorkspace: @escaping @MainActor () -> Void,
        canDeleteWorkspace: Bool,
        updateAvailability: OpenMUXUpdateAvailability?,
        onMoveWorkspace: @escaping @MainActor (WorkspaceID, Int) -> Void,
        onToggleWorkspaceExpansion: @escaping @MainActor (WorkspaceID) -> Void,
        onRenameWorkspace: @escaping @MainActor (WorkspaceID, String) -> Void,
        onSelectPane: @escaping @MainActor (PaneID) -> Void,
        onToggleWorkspacesCollapse: @escaping @MainActor () -> Void
    ) {
        apply(theme: theme)

        splitView.setCollapsed(isWorkspacesCollapsed, panelID: "workspaces")
        workspacesWidget.render(
            workspaceItems: workspaceItems,
            isCollapsed: isWorkspacesCollapsed,
            theme: theme,
            onCreateWorkspace: onCreateWorkspace,
            onDeleteWorkspace: onDeleteWorkspace,
            canDeleteWorkspace: canDeleteWorkspace,
            onMoveWorkspace: onMoveWorkspace,
            onToggleWorkspaceExpansion: onToggleWorkspaceExpansion,
            onRenameWorkspace: onRenameWorkspace,
            onSelectWorkspace: onSelectWorkspace,
            onSelectPane: onSelectPane,
            onToggleCollapse: onToggleWorkspacesCollapse
        )
        updateNoticeView.render(updateAvailability: updateAvailability)

        // When notice is visible, remove the zero-height constraint so its intrinsic size is used
        // and a 12pt bottom gap is applied. When hidden, collapse to zero height so splitView
        // expands to fill the full sidebar.
        if updateAvailability != nil {
            noticeHeightConstraint?.isActive = false
            noticeBottomConstraint?.constant = -12
        } else {
            noticeHeightConstraint?.isActive = true
            noticeBottomConstraint?.constant = 0
        }
    }

    var updateNoticeTextForTesting: String? {
        updateNoticeView.noticeTextForTesting
    }
}

@MainActor
final class SidebarUpdateNoticeView: NSView {
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
final class WorkspaceSidebarSectionView: NSView {
    private struct WorkspaceDragGroup {
        let workspaceID: WorkspaceID
        var buttons: [SidebarItemButton]
    }

    private let titleLabel = NSTextField(labelWithString: "")
    private let itemStack = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private var accessoryButtons: [ChromePillButton] = []
    private var itemButtons: [SidebarItemButton] = []
    private var workspaceButtons: [SidebarItemButton] = []
    private var workspaceDragGroups: [WorkspaceDragGroup] = []
    private var currentTheme: WorkspaceShellTheme?
    private var reorderHandler: ((WorkspaceID, Int) -> Void)?
    private var draggingWorkspaceID: WorkspaceID?

    /// The header row (title + accessory buttons). Lives outside the scroll view
    /// so it stays visible and receives mouse events regardless of scroll position.
    let headerView = NSStackView()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        headerView.orientation = .horizontal
        headerView.alignment = .centerY
        headerView.translatesAutoresizingMaskIntoConstraints = false

        itemStack.orientation = .vertical
        itemStack.alignment = .leading
        itemStack.spacing = 2
        itemStack.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        emptyLabel.font = .systemFont(ofSize: 11, weight: .regular)
        emptyLabel.maximumNumberOfLines = 2
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        headerView.addArrangedSubview(titleLabel)
        headerView.addArrangedSubview(NSView())

        addSubview(itemStack)
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            itemStack.topAnchor.constraint(equalTo: topAnchor),
            itemStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            itemStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            itemStack.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyLabel.topAnchor.constraint(equalTo: topAnchor),
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
        onRenameWorkspace: @escaping (WorkspaceID, String) -> Void,
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
            headerView.removeArrangedSubview(accessoryButton)
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
            headerView.addArrangedSubview(button)
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
                button.onRename = { newName in
                    onRenameWorkspace(workspaceID, newName)
                }
                button.onBeginRename = { [weak button] in
                    button?.beginInlineRename()
                }
                // Override context menu to wire Rename… to inline rename
                let itemProvider = item.contextMenuProvider
                button.contextMenuProvider = { [weak button] in
                    guard let menu = itemProvider?() else { return nil }
                    if let renameItem = menu.item(withTitle: "Rename…") {
                        renameItem.onSelect { [weak button] in
                            button?.beginInlineRename()
                        }
                    }
                    return menu
                }
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
        let candidateCenterYs = candidateButtons.map { button in
            button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil).y
        }
        return WorkspaceSidebarDragPlanner.insertionIndex(
            candidateCenterYs: candidateCenterYs,
            pointerY: event.locationInWindow.y
        )
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
final class VaultWorkspaceFilterBox {
    let filter: WorkspaceShellViewController.VaultWorkspaceFilter

    init(_ filter: WorkspaceShellViewController.VaultWorkspaceFilter) {
        self.filter = filter
    }
}

@MainActor
final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

private extension NSColor {
    var omuxIsDark: Bool {
        let color = usingColorSpace(.sRGB) ?? usingColorSpace(.deviceRGB) ?? self
        let luminance = 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
        return luminance < 0.5
    }
}

private extension Double {
    /// Returns nil if the value is zero (for UserDefaults default-value detection).
    var nonZero: Double? { self == 0 ? nil : self }
}
