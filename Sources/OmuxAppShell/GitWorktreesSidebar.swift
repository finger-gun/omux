import AppKit
import OmuxConfig
import OmuxControlPlane
import OmuxCore
import OmuxVault
import QuartzCore

final class WorktreeRowButton: NSView {
    private let branchLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let deleteButton = NSButton()
    private var onNavigate: (() -> Void)?
    private var onDelete: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    private var isCurrentRepo = false
    private var isHovered = false
    private var currentTheme: WorkspaceShellTheme?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 6

        branchLabel.font = .systemFont(ofSize: 12, weight: .medium)
        branchLabel.maximumNumberOfLines = 1
        branchLabel.lineBreakMode = .byTruncatingTail
        branchLabel.translatesAutoresizingMaskIntoConstraints = false

        pathLabel.font = .systemFont(ofSize: 10)
        pathLabel.maximumNumberOfLines = 1
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.translatesAutoresizingMaskIntoConstraints = false

        deleteButton.isBordered = false
        deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Remove Worktree")
        deleteButton.imagePosition = .imageOnly
        deleteButton.isBordered = false
        deleteButton.controlSize = .small
        deleteButton.setButtonType(.momentaryChange)
        deleteButton.target = self
        deleteButton.action = #selector(deletePressed)
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.isHidden = true

        addSubview(branchLabel)
        addSubview(pathLabel)
        addSubview(deleteButton)

        NSLayoutConstraint.activate([
            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            deleteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 22),
            deleteButton.heightAnchor.constraint(equalToConstant: 22),

            branchLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            branchLabel.trailingAnchor.constraint(lessThanOrEqualTo: deleteButton.leadingAnchor, constant: -8),
            branchLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),

            pathLabel.leadingAnchor.constraint(equalTo: branchLabel.leadingAnchor),
            pathLabel.trailingAnchor.constraint(lessThanOrEqualTo: deleteButton.leadingAnchor, constant: -8),
            pathLabel.topAnchor.constraint(equalTo: branchLabel.bottomAnchor, constant: 2),
            pathLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])

    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func configure(
        worktree: GitWorktree,
        theme: WorkspaceShellTheme,
        onNavigate: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.onNavigate = onNavigate
        self.onDelete = onDelete
        self.isCurrentRepo = worktree.isCurrentRepo
        self.currentTheme = theme

        branchLabel.stringValue = worktree.branch ?? "detached HEAD"
        pathLabel.stringValue = shortenPath(worktree.path)

        branchLabel.textColor = theme.shell.textPrimary
        pathLabel.textColor = theme.shell.textMuted
        deleteButton.contentTintColor = theme.shell.textMuted
        updateBackground()
    }

    func apply(theme: WorkspaceShellTheme) {
        currentTheme = theme
        branchLabel.textColor = theme.shell.textPrimary
        pathLabel.textColor = theme.shell.textMuted
        deleteButton.contentTintColor = theme.shell.textMuted
        updateBackground()
        needsDisplay = true
    }

    private func updateBackground() {
        guard let theme = currentTheme else { return }
        if isHovered {
            layer?.backgroundColor = theme.shell.selection.withAlphaComponent(0.15).cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    // MARK: Tracking area for hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        replaceTrackingArea(&trackingArea, options: [.mouseEnteredAndExited, .activeInActiveApp])
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        deleteButton.isHidden = false
        updateBackground()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        deleteButton.isHidden = true
        updateBackground()
    }

    override func mouseDown(with event: NSEvent) {
        // hitTest routes button-area clicks to the button itself, so mouseDown
        // on the row only fires when the user clicks outside the delete button.
        onNavigate?()
    }
    @objc private func deletePressed() {
        onDelete?()
    }

    private func shortenPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

// MARK: - GitWorktreesSidebarWidget

/// A self-contained widget section for the right sidebar that lists git worktrees.
@MainActor
final class GitWorktreesSidebarWidget: NSView {
    static let collapsedHeight: CGFloat = 34   // 6 top padding + 22 header + 6 bottom padding

    override var isFlipped: Bool { true }

    let header = CollapsibleSectionHeaderView()
    private let refreshButton = NSButton()
    private let addButton = NSButton()
    private let scrollView = NSScrollView()
    private let stack = FlippedStackView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private var renderedWorktrees: [GitWorktree] = []
    private var onNavigate: ((GitWorktree) -> Void)?
    private var onDelete: ((GitWorktree) -> Void)?
    private var onCreate: (() -> Void)?
    private var onRefresh: (() -> Void)?
    private var onToggleCollapse: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        refreshButton.isBordered = false
        refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh Worktrees")
        refreshButton.target = self
        refreshButton.action = #selector(refreshPressed)

        addButton.isBordered = false
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Create Worktree")
        addButton.target = self
        addButton.action = #selector(addPressed)

        emptyLabel.font = .systemFont(ofSize: 11)
        emptyLabel.maximumNumberOfLines = 2
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false

        scrollView.configureSidebarScrollView(documentView: stack)

        addSubview(header)
        addSubview(emptyLabel)
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            header.heightAnchor.constraint(equalToConstant: 22),

            emptyLabel.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            emptyLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            emptyLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            {
                let c = scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
                c.priority = .defaultLow
                return c
            }(),

            stack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func render(
        worktrees: [GitWorktree],
        isCollapsed: Bool,
        theme: WorkspaceShellTheme,
        onNavigate: @escaping (GitWorktree) -> Void,
        onDelete: @escaping (GitWorktree) -> Void,
        onCreate: @escaping () -> Void,
        onRefresh: @escaping () -> Void,
        onToggleCollapse: @escaping () -> Void
    ) {
        self.onNavigate = onNavigate
        self.onDelete = onDelete
        self.onCreate = onCreate
        self.onRefresh = onRefresh
        self.onToggleCollapse = onToggleCollapse

        let count = worktrees.isEmpty ? nil : worktrees.count
        header.render(
            title: "GIT WORKTREES",
            count: count,
            isCollapsed: isCollapsed,
            actionButtons: [refreshButton, addButton],
            theme: theme,
            onToggle: onToggleCollapse
        )

        // The SidebarSplitView controls this widget's frame when collapsed/expanded.
        // We just show/hide the scroll content accordingly.
        scrollView.isHidden = isCollapsed
        emptyLabel.isHidden = true

        if isCollapsed {
            return
        }

        if worktrees.isEmpty {
            emptyLabel.stringValue = "No git repository"
            emptyLabel.isHidden = false
            scrollView.isHidden = true
            clearRows()
            return
        }

        if worktrees == renderedWorktrees {
            apply(theme: theme)
            return
        }
        renderedWorktrees = worktrees
        clearRows()

        for worktree in worktrees {
            let row = WorktreeRowButton()
            row.configure(
                worktree: worktree,
                theme: theme,
                onNavigate: { [weak self] in self?.onNavigate?(worktree) },
                onDelete: { [weak self] in self?.onDelete?(worktree) }
            )
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        apply(theme: theme)
    }

    func apply(theme: WorkspaceShellTheme) {
        header.applyTheme(theme)
        emptyLabel.textColor = theme.shell.textMuted
        refreshButton.contentTintColor = theme.shell.textMuted
        addButton.contentTintColor = theme.shell.textMuted
        for case let row as WorktreeRowButton in stack.arrangedSubviews {
            row.apply(theme: theme)
        }
    }

    private func clearRows() {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        renderedWorktrees = []
    }

    @objc private func refreshPressed() {
        onRefresh?()
    }

    @objc private func addPressed() {
        onCreate?()
    }
}
