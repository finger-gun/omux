import AppKit
import OmuxConfig
import OmuxControlPlane
import OmuxCore
import OmuxVault
import QuartzCore

@MainActor
final class WorkspaceVaultSidebarView: SidebarContainerView, NSSearchFieldDelegate {
    struct WorkspaceFilterItem {
        let title: String
        let filter: WorkspaceShellViewController.VaultWorkspaceFilter
    }

    struct SessionActivity: Equatable {
        let isActive: Bool
        let progress: PaneProgress
    }

    private struct SessionRowState: Equatable {
        let session: VaultSessionSummary
        let activity: SessionActivity?
    }

    let sectionHeader = CollapsibleSectionHeaderView()
    private let refreshButton = NSButton()
    let worktreesWidget = GitWorktreesSidebarWidget()
    private let agentSessionsContainer = NSView()
    let splitView = SidebarSplitView()
    private let searchContainer = NSView()
    private let searchIcon = NSImageView()
    private let searchField = AgentSessionsSearchField()
    private let filterRow = NSStackView()
    private let agentPopup = NSPopUpButton()
    private let workspacePopup = NSPopUpButton()
    private let scrollView = NSScrollView()
    private let stack = FlippedStackView()
    private let statusLabel = NSTextField(labelWithString: "")
    private var onToggle: (() -> Void)?
    private var onRefresh: (() -> Void)?
    private var onSearchChanged: ((String) -> Void)?
    private var onAgentFilterChanged: ((VaultAgentKind?) -> Void)?
    private var onWorkspaceFilterChanged: ((WorkspaceShellViewController.VaultWorkspaceFilter) -> Void)?
    private var onNeedsMore: (() -> Void)?
    private var onResume: ((String) -> Void)?
    private var onDelete: ((String) -> Void)?
    private var onToggleCollapse: (() -> Void)?
    private var currentTheme = WorkspaceShellTheme.defaultTheme
    private var renderedRows: [SessionRowState] = []
    private var renderedEmptyMessage: String?
    private var isSearchFocused = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        refreshButton.isBordered = false
        refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh Agent Sessions")
        refreshButton.target = self
        refreshButton.action = #selector(refreshPressed)
        refreshButton.translatesAutoresizingMaskIntoConstraints = false

        searchContainer.wantsLayer = true
        searchContainer.layer?.cornerRadius = 14
        searchContainer.layer?.borderWidth = 1
        searchContainer.translatesAutoresizingMaskIntoConstraints = false

        searchIcon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        searchIcon.translatesAutoresizingMaskIntoConstraints = false
        searchIcon.setContentHuggingPriority(.required, for: .horizontal)

        searchField.font = .systemFont(ofSize: 14, weight: .regular)
        searchField.isBordered = false
        searchField.focusRingType = .none
        searchField.backgroundColor = .clear
        searchField.placeholderString = "Search"
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false

        filterRow.orientation = .horizontal
        filterRow.alignment = .centerY
        filterRow.distribution = .fillEqually
        filterRow.spacing = 6
        filterRow.translatesAutoresizingMaskIntoConstraints = false

        agentPopup.isBordered = false
        agentPopup.target = self
        agentPopup.action = #selector(agentFilterChanged)
        agentPopup.translatesAutoresizingMaskIntoConstraints = false
        rebuildAgentMenu(availableAgents: [], selectedAgent: nil)

        workspacePopup.isBordered = false
        workspacePopup.target = self
        workspacePopup.action = #selector(workspaceFilterChanged)
        workspacePopup.translatesAutoresizingMaskIntoConstraints = false
        rebuildWorkspaceMenu(items: [], selectedFilter: .current)

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        scrollView.configureSidebarScrollView(documentView: stack)
        scrollView.contentView.postsBoundsChangedNotifications = true

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.maximumNumberOfLines = 1
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        filterRow.addArrangedSubview(workspacePopup)
        filterRow.addArrangedSubview(agentPopup)
        searchContainer.addSubview(searchIcon)
        searchContainer.addSubview(searchField)

        // Agent sessions container groups the header + controls into one hideable view.
        agentSessionsContainer.translatesAutoresizingMaskIntoConstraints = false
        agentSessionsContainer.addSubview(sectionHeader)
        agentSessionsContainer.addSubview(searchContainer)
        agentSessionsContainer.addSubview(filterRow)
        agentSessionsContainer.addSubview(scrollView)
        agentSessionsContainer.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            sectionHeader.topAnchor.constraint(equalTo: agentSessionsContainer.topAnchor, constant: 6),
            sectionHeader.leadingAnchor.constraint(equalTo: agentSessionsContainer.leadingAnchor, constant: 12),
            sectionHeader.trailingAnchor.constraint(equalTo: agentSessionsContainer.trailingAnchor, constant: -12),
            {
                let c = sectionHeader.heightAnchor.constraint(equalToConstant: 22)
                c.priority = .required
                return c
            }(),
            searchContainer.heightAnchor.constraint(equalToConstant: 28),
            searchContainer.topAnchor.constraint(equalTo: sectionHeader.bottomAnchor, constant: 8),
            searchContainer.leadingAnchor.constraint(equalTo: sectionHeader.leadingAnchor),
            searchContainer.trailingAnchor.constraint(equalTo: sectionHeader.trailingAnchor),
            searchIcon.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor, constant: 10),
            searchIcon.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: 14),
            searchIcon.heightAnchor.constraint(equalToConstant: 14),
            searchField.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 7),
            searchField.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor, constant: -10),
            searchField.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            searchField.heightAnchor.constraint(equalTo: searchContainer.heightAnchor),
            filterRow.heightAnchor.constraint(equalToConstant: 24),
            filterRow.topAnchor.constraint(equalTo: searchContainer.bottomAnchor, constant: 6),
            filterRow.leadingAnchor.constraint(equalTo: sectionHeader.leadingAnchor),
            filterRow.trailingAnchor.constraint(equalTo: sectionHeader.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: filterRow.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: sectionHeader.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: sectionHeader.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -6),
            statusLabel.leadingAnchor.constraint(equalTo: sectionHeader.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: sectionHeader.trailingAnchor),
            {
                // Low priority so this breaks gracefully when the container is
                // frame-collapsed to its header-only height by SidebarSplitView.
                let c = statusLabel.bottomAnchor.constraint(equalTo: agentSessionsContainer.bottomAnchor, constant: -12)
                c.priority = .defaultLow
                return c
            }(),
            stack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])

        // Layout: SidebarSplitView fills this view; it manages worktrees + agent sessions.
        addSubview(splitView)
        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: topAnchor),
            splitView.leadingAnchor.constraint(equalTo: leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Load persisted proportions (default 0.25 for worktrees, 0.75 for agent sessions).
        let worktreesProportion = CGFloat(UserDefaults.standard.double(forKey: "omux.rightSidebar.worktreesProportion").nonZero ?? 0.25)
        let agentProportion = CGFloat(UserDefaults.standard.double(forKey: "omux.rightSidebar.agentProportion").nonZero ?? 0.75)
        let total = worktreesProportion + agentProportion
        splitView.setPanels([
            SidebarSplitView.Panel(
                view: worktreesWidget,
                collapsedHeight: 34,
                isCollapsed: UserDefaults.standard.bool(forKey: "omux.rightSidebar.worktreesCollapsed"),
                proportion: worktreesProportion / total,
                defaultsKey: "omux.rightSidebar.worktreesProportion",
                panelID: "worktrees",
                headerView: worktreesWidget.header
            ),
            SidebarSplitView.Panel(
                view: agentSessionsContainer,
                collapsedHeight: 34,
                isCollapsed: UserDefaults.standard.bool(forKey: "omux.rightSidebar.agentSessionsCollapsed"),
                proportion: agentProportion / total,
                defaultsKey: "omux.rightSidebar.agentProportion",
                panelID: "agentSessions",
                headerView: sectionHeader
            ),
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollBoundsChanged(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func applyBorderLayer(theme: WorkspaceShellTheme) {
        // Draw a 1px left-edge separator matching the VSCode style
        let border = sidebarBorderLayer(named: "vaultSidebarLeftBorder")
        border.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        border.frame = CGRect(x: 0, y: 0, width: 1, height: bounds.height)
        border.autoresizingMask = [.layerMaxXMargin, .layerHeightSizable]
    }

    override func apply(theme: WorkspaceShellTheme) {
        currentTheme = theme
        super.apply(theme: theme)
        worktreesWidget.apply(theme: theme)
        splitView.applyTheme(theme)
        sectionHeader.applyTheme(theme)
        refreshButton.contentTintColor = theme.shell.textMuted
        workspacePopup.contentTintColor = theme.shell.textMuted
        agentPopup.contentTintColor = theme.shell.textMuted
        statusLabel.textColor = theme.shell.textMuted
        applySearchFieldTheme()
        applyFilterMenuTheme()
        for case let row as VaultSessionRowButton in stack.arrangedSubviews {
            row.apply(theme: theme)
        }
    }

    private func applySearchFieldTheme() {
        let colors = currentTheme.shell
        searchField.textColor = colors.textPrimary
        searchField.placeholderAttributedString = NSAttributedString(
            string: "Search",
            attributes: [
                .foregroundColor: colors.textMuted,
                .font: NSFont.systemFont(ofSize: 14, weight: .regular),
            ]
        )
        searchIcon.contentTintColor = colors.textMuted
        searchContainer.layer?.backgroundColor = colors.paneCardBackground.cgColor
        searchContainer.layer?.borderColor = (isSearchFocused ? colors.accent : colors.subduedBorder).cgColor
    }

    private func applyFilterMenuTheme() {
        let colors = currentTheme.shell
        let appearance = NSAppearance(named: colors.sidebarBackground.omuxIsDark ? .darkAqua : .aqua)
        let itemAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: colors.textPrimary,
            .font: NSFont.systemFont(ofSize: 13, weight: .regular),
        ]
        let selectedAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: colors.textMuted,
            .font: NSFont.systemFont(ofSize: 13, weight: .regular),
        ]
        for popup in [workspacePopup, agentPopup] {
            popup.appearance = appearance
            popup.menu?.appearance = appearance
            popup.contentTintColor = colors.textMuted
            if let title = popup.titleOfSelectedItem {
                popup.attributedTitle = NSAttributedString(string: title, attributes: selectedAttributes)
            }
            popup.itemArray.forEach { item in
                item.attributedTitle = NSAttributedString(string: item.title, attributes: itemAttributes)
            }
        }
    }

    func render(
        sessions: [VaultSessionSummary],
        searchQuery: String,
        selectedAgent: VaultAgentKind?,
        availableAgents: Set<VaultAgentKind>,
        workspaceFilter: WorkspaceShellViewController.VaultWorkspaceFilter,
        workspaceFilterItems: [WorkspaceFilterItem],
        isLoading: Bool,
        hasMore: Bool,
        sessionActivityByID: [String: SessionActivity],
        theme: WorkspaceShellTheme,
        isCollapsed: Bool,
        isAgentSessionsEnabled: Bool,
        onToggle: @escaping () -> Void,
        onRefresh: @escaping () -> Void,
        onSearchChanged: @escaping (String) -> Void,
        onAgentFilterChanged: @escaping (VaultAgentKind?) -> Void,
        onWorkspaceFilterChanged: @escaping (WorkspaceShellViewController.VaultWorkspaceFilter) -> Void,
        onNeedsMore: @escaping () -> Void,
        onResume: @escaping (String) -> Void,
        onDelete: @escaping (String) -> Void,
        onToggleCollapse: @escaping () -> Void
    ) {
        self.onToggle = onToggle
        self.onRefresh = onRefresh
        self.onSearchChanged = onSearchChanged
        self.onAgentFilterChanged = onAgentFilterChanged
        self.onWorkspaceFilterChanged = onWorkspaceFilterChanged
        self.onNeedsMore = onNeedsMore
        self.onResume = onResume
        self.onDelete = onDelete
        self.onToggleCollapse = onToggleCollapse

        // Hide the whole agent sessions section when vault is disabled.
        // NSStackView will remove its layout contribution automatically.
        agentSessionsContainer.isHidden = !isAgentSessionsEnabled

        guard isAgentSessionsEnabled else { return }

        sectionHeader.render(
            title: "AGENT SESSIONS",
            isCollapsed: isCollapsed,
            actionButtons: [refreshButton],
            theme: theme,
            onToggle: onToggleCollapse
        )

        // When collapsed, hide search/filter/scroll (header stays visible).
        searchContainer.isHidden = isCollapsed
        filterRow.isHidden = isCollapsed
        scrollView.isHidden = isCollapsed
        statusLabel.isHidden = isCollapsed

        if isCollapsed { return }
        if searchField.stringValue != searchQuery {
            searchField.stringValue = searchQuery
        }
        rebuildWorkspaceMenu(items: workspaceFilterItems, selectedFilter: workspaceFilter)
        rebuildAgentMenu(availableAgents: availableAgents, selectedAgent: selectedAgent)
        let scrollOrigin = scrollView.contentView.bounds.origin
        let shouldPreserveScroll = scrollView.documentView === stack && stack.frame.height > scrollView.contentView.bounds.height
        if sessions.isEmpty {
            let emptyMessage = emptyStateMessage(
                isLoading: isLoading,
                workspaceFilter: workspaceFilter,
                workspaceFilterItems: workspaceFilterItems,
                selectedAgent: selectedAgent,
                searchQuery: searchQuery
            )
            if renderedRows.isEmpty == false || renderedEmptyMessage != emptyMessage {
                clearSessionRows()
                renderedRows = []
                renderedEmptyMessage = emptyMessage
                let empty = NSTextField(labelWithString: emptyMessage)
                empty.font = .systemFont(ofSize: 11)
                empty.textColor = theme.shell.textMuted
                empty.maximumNumberOfLines = 2
                stack.addArrangedSubview(empty)
            }
        } else {
            let nextRows = Self.visibleRows(sessions: sessions, sessionActivityByID: sessionActivityByID)
            if renderedRows != nextRows {
                clearSessionRows()
                renderedRows = nextRows
                renderedEmptyMessage = nil
                for rowState in nextRows {
                    let row = VaultSessionRowButton(session: rowState.session, activity: rowState.activity)
                    row.apply(theme: theme)
                    row.onOpen = { [weak self] id in self?.onResume?(id) }
                    row.onDelete = { [weak self] id in self?.onDelete?(id) }
                    stack.addArrangedSubview(row)
                    row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
                }
            }
        }
        if isLoading {
            statusLabel.stringValue = sessions.isEmpty ? "Loading..." : "Refreshing..."
        } else if hasMore {
            statusLabel.stringValue = "Scroll for more"
        } else {
            statusLabel.stringValue = sessions.isEmpty ? "" : "\(sessions.count) sessions"
        }
        apply(theme: theme)
        restoreScrollOriginIfNeeded(scrollOrigin, preserve: shouldPreserveScroll)
    }

    private func clearSessionRows() {
        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    private func restoreScrollOriginIfNeeded(_ origin: NSPoint, preserve: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.stack.layoutSubtreeIfNeeded()
            let contentHeight = self.stack.frame.height
            let visibleHeight = self.scrollView.contentView.bounds.height
            guard contentHeight > visibleHeight + 1 else {
                self.scrollView.contentView.scroll(to: .zero)
                self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
                return
            }
            guard preserve else { return }
            let maxY = max(0, contentHeight - visibleHeight)
            let y = min(max(0, origin.y), maxY)
            self.scrollView.contentView.scroll(to: NSPoint(x: origin.x, y: y))
            self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
        }
    }

    private func emptyStateMessage(
        isLoading: Bool,
        workspaceFilter: WorkspaceShellViewController.VaultWorkspaceFilter,
        workspaceFilterItems: [WorkspaceFilterItem],
        selectedAgent: VaultAgentKind?,
        searchQuery: String
    ) -> String {
        if isLoading {
            return "Loading sessions..."
        }
        if selectedAgent != nil || searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return "No sessions match your filters/search"
        }
        switch workspaceFilter {
        case .all:
            return "No sessions across all workspaces"
        case .current:
            return "No sessions for this workspace"
        case .workspace:
            if let title = workspaceFilterItems.first(where: { $0.filter == workspaceFilter })?.title {
                return "No sessions in \(title)"
            }
            return "No sessions for this workspace"
        }
    }

    private static func visibleRows(
        sessions: [VaultSessionSummary],
        sessionActivityByID: [String: SessionActivity]
    ) -> [SessionRowState] {
        sessions
            .map { session in
                SessionRowState(session: session, activity: sessionActivityByID[session.id])
            }
            .sorted { lhs, rhs in
                let lhsActive = lhs.activity?.isActive == true
                let rhsActive = rhs.activity?.isActive == true
                if lhsActive != rhsActive {
                    return lhsActive
                }
                return lhs.session.modifiedAt > rhs.session.modifiedAt
            }
    }

    private func rebuildAgentMenu(availableAgents: Set<VaultAgentKind>, selectedAgent: VaultAgentKind?) {
        let previousAction = agentPopup.action
        agentPopup.action = nil
        agentPopup.removeAllItems()
        agentPopup.addItem(withTitle: "All agents")
        agentPopup.lastItem?.representedObject = Optional<VaultAgentKind>.none as Any
        var agents = VaultAgentKind.allCases.filter { availableAgents.contains($0) }
        agents += availableAgents
            .filter { agents.contains($0) == false }
            .sorted { $0.rawValue < $1.rawValue }
        if let selectedAgent, agents.contains(selectedAgent) == false {
            agents.append(selectedAgent)
        }
        for agent in agents {
            agentPopup.addItem(withTitle: agent.rawValue)
            agentPopup.lastItem?.representedObject = agent
        }
        if let selectedAgent,
           let item = agentPopup.itemArray.first(where: { ($0.representedObject as? VaultAgentKind) == selectedAgent }) {
            agentPopup.select(item)
        } else {
            agentPopup.selectItem(at: 0)
        }
        agentPopup.action = previousAction
    }

    private func rebuildWorkspaceMenu(
        items: [WorkspaceFilterItem],
        selectedFilter: WorkspaceShellViewController.VaultWorkspaceFilter
    ) {
        let previousAction = workspacePopup.action
        workspacePopup.action = nil
        workspacePopup.removeAllItems()
        for item in items {
            workspacePopup.addItem(withTitle: item.title)
            workspacePopup.lastItem?.representedObject = VaultWorkspaceFilterBox(item.filter)
        }
        if let item = workspacePopup.itemArray.first(where: {
            ($0.representedObject as? VaultWorkspaceFilterBox)?.filter == selectedFilter
        }) {
            workspacePopup.select(item)
        } else {
            workspacePopup.selectItem(at: 0)
        }
        workspacePopup.action = previousAction
    }

    @objc private func refreshPressed() {
        onRefresh?()
    }

    @objc private func agentFilterChanged() {
        onAgentFilterChanged?(agentPopup.selectedItem?.representedObject as? VaultAgentKind)
    }

    @objc private func workspaceFilterChanged() {
        guard let filter = (workspacePopup.selectedItem?.representedObject as? VaultWorkspaceFilterBox)?.filter else {
            return
        }
        onWorkspaceFilterChanged?(filter)
    }

    @objc private func scrollBoundsChanged(_ notification: Notification) {
        _ = notification
        let visibleMaxY = scrollView.contentView.bounds.maxY
        let contentHeight = stack.frame.height
        if contentHeight - visibleMaxY < 180 {
            onNeedsMore?()
        }
    }

}

extension WorkspaceVaultSidebarView {
    func controlTextDidBeginEditing(_ obj: Notification) {
        _ = obj
        isSearchFocused = true
        applySearchFieldTheme()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        _ = obj
        isSearchFocused = false
        applySearchFieldTheme()
    }

    func controlTextDidChange(_ obj: Notification) {
        _ = obj
        onSearchChanged?(searchField.stringValue)
    }
}

@MainActor
final class AgentSessionsSearchField: NSTextField {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let centeredCell = AgentSessionsSearchFieldCell()
        centeredCell.isEditable = true
        centeredCell.isSelectable = true
        centeredCell.isBordered = false
        centeredCell.backgroundColor = NSColor.clear
        centeredCell.focusRingType = NSFocusRingType.none
        centeredCell.usesSingleLineMode = true
        centeredCell.lineBreakMode = NSLineBreakMode.byClipping
        cell = centeredCell
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}

@MainActor
final class AgentSessionsSearchFieldCell: NSTextFieldCell {
    private func centeredRect(for rect: NSRect) -> NSRect {
        let size = cellSize(forBounds: rect)
        let y = rect.minY + (rect.height - size.height) / 2
        return NSRect(x: rect.minX, y: y, width: rect.width, height: size.height)
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        centeredRect(for: rect)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: centeredRect(for: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: centeredRect(for: rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.drawInterior(withFrame: centeredRect(for: cellFrame), in: controlView)
    }
}

@MainActor
final class VaultSessionRowButton: NSControl {
    private let session: VaultSessionSummary
    private let activity: WorkspaceVaultSidebarView.SessionActivity?
    private let titleLabel = NSTextField(labelWithString: "")
    private let activeLabel = NSTextField(labelWithString: "ACTIVE")
    private let statusOrb = PaneProgressOrbView()
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let dateLabel = NSTextField(labelWithString: "")
    private let openButton = NSButton()
    private let deleteButton = NSButton()
    var onOpen: ((String) -> Void)?
    var onDelete: ((String) -> Void)?

    init(session: VaultSessionSummary, activity: WorkspaceVaultSidebarView.SessionActivity?) {
        self.session = session
        self.activity = activity
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 6
        focusRingType = .exterior
        setAccessibilityRole(.group)
        setAccessibilityLabel(session.title.isEmpty ? session.id : session.title)

        let displayTitle = session.title.isEmpty ? session.id : session.title
        titleLabel.stringValue = displayTitle
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        activeLabel.font = .systemFont(ofSize: 9, weight: .semibold)
        activeLabel.alignment = .right
        activeLabel.maximumNumberOfLines = 1
        activeLabel.translatesAutoresizingMaskIntoConstraints = false
        activeLabel.isHidden = activity?.isActive != true

        statusOrb.translatesAutoresizingMaskIntoConstraints = false
        statusOrb.isHidden = activity == nil

        let folderName = session.workingDirectory.map { URL(fileURLWithPath: $0).lastPathComponent }.flatMap { $0.isEmpty ? nil : $0 } ?? "unknown"
        subtitleLabel.stringValue = "\(session.agent.rawValue) · \(folderName)"
        subtitleLabel.font = .systemFont(ofSize: 10)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.maximumNumberOfLines = 1
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        dateLabel.stringValue = Self.formattedDate(session.modifiedAt)
        dateLabel.font = .systemFont(ofSize: 10)
        dateLabel.lineBreakMode = .byTruncatingTail
        dateLabel.maximumNumberOfLines = 1
        dateLabel.translatesAutoresizingMaskIntoConstraints = false

        let openTitle = activity?.isActive == true ? "Focus Session" : "Open Session"
        let openSymbol = activity?.isActive == true ? "scope" : "arrow.up.right.square"
        openButton.title = ""
        openButton.image = NSImage(systemSymbolName: openSymbol, accessibilityDescription: openTitle)
        openButton.imagePosition = .imageOnly
        openButton.toolTip = openTitle
        openButton.isBordered = false
        openButton.controlSize = .small
        openButton.setButtonType(.momentaryChange)
        openButton.setAccessibilityLabel(openTitle)
        openButton.target = self
        openButton.action = #selector(openSession)
        openButton.translatesAutoresizingMaskIntoConstraints = false

        deleteButton.title = ""
        deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete Session")
        deleteButton.imagePosition = .imageOnly
        deleteButton.isBordered = false
        deleteButton.controlSize = .small
        deleteButton.setButtonType(.momentaryChange)
        deleteButton.setAccessibilityLabel("Delete Session")
        deleteButton.target = self
        deleteButton.action = #selector(deleteSession)
        deleteButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(activeLabel)
        addSubview(statusOrb)
        addSubview(subtitleLabel)
        addSubview(dateLabel)
        addSubview(openButton)
        addSubview(deleteButton)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 62),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: openButton.leadingAnchor, constant: -8),
            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            deleteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 22),
            deleteButton.heightAnchor.constraint(equalToConstant: 22),
            openButton.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -4),
            openButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            openButton.widthAnchor.constraint(equalToConstant: 22),
            openButton.heightAnchor.constraint(equalToConstant: 22),
            activeLabel.trailingAnchor.constraint(lessThanOrEqualTo: openButton.leadingAnchor, constant: -8),
            activeLabel.centerYAnchor.constraint(equalTo: dateLabel.centerYAnchor),
            statusOrb.trailingAnchor.constraint(equalTo: activeLabel.leadingAnchor, constant: -6),
            statusOrb.centerYAnchor.constraint(equalTo: dateLabel.centerYAnchor),
            statusOrb.widthAnchor.constraint(equalToConstant: PaneProgressOrbView.side),
            statusOrb.heightAnchor.constraint(equalToConstant: PaneProgressOrbView.side),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: openButton.leadingAnchor, constant: -8),
            dateLabel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 2),
            dateLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            dateLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusOrb.leadingAnchor, constant: -6),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private static func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    func apply(theme: WorkspaceShellTheme) {
        layer?.backgroundColor = NSColor.clear.cgColor
        titleLabel.textColor = theme.shell.textPrimary
        subtitleLabel.textColor = theme.shell.textMuted
        dateLabel.textColor = theme.shell.textMuted
        activeLabel.textColor = theme.shell.accent
        openButton.contentTintColor = theme.shell.textMuted
        deleteButton.contentTintColor = theme.shell.textMuted
        statusOrb.configure(progress: activity?.progress, theme: theme)
        needsDisplay = true
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    override func mouseDown(with event: NSEvent) {
        _ = event
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 49 {
            onOpen?(session.id)
        } else if event.keyCode == 51 {
            onDelete?(session.id)
        } else {
            super.keyDown(with: event)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let openItem = NSMenuItem(title: activity?.isActive == true ? "Focus Session" : "Open Session", action: #selector(openSession), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        let deleteItem = NSMenuItem(title: "Delete Session…", action: #selector(deleteSession), keyEquivalent: "")
        deleteItem.target = self
        menu.addItem(deleteItem)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func accessibilityPerformPress() -> Bool {
        onOpen?(session.id)
        return true
    }

    @objc private func openSession() {
        onOpen?(session.id)
    }

    @objc private func deleteSession() {
        onDelete?(session.id)
    }
}

private extension NSColor {
    var omuxIsDark: Bool {
        let color = usingColorSpace(.sRGB) ?? usingColorSpace(.deviceRGB) ?? self
        let luminance = 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
        return luminance < 0.5
    }
}

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}
