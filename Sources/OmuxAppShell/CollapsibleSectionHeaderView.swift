import AppKit

/// A reusable collapsible header row used by sidebar widget sections.
/// Layout: [chevron] [TITLE]  [badge]  [spacer]  [action buttons...]
/// Clicking anywhere on the header fires `onToggle`.
@MainActor
final class CollapsibleSectionHeaderView: NSView {
    private let chevronView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let badgeView = CountBadgeView()
    private var actionButtons: [NSButton] = []
    private var onToggle: (() -> Void)?
    var onDragBegan: ((NSPoint) -> Void)?  // window coords of mouseDown
    var onDragMoved: ((NSPoint) -> Void)?    // window coords point (x and y)
    var onDragEnded: (() -> Void)?

    private var mouseDownPoint: NSPoint = .zero
    private var isDragging = false
    private static let dragThreshold: CGFloat = 4

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        chevronView.symbolConfiguration = .init(pointSize: 9, weight: .semibold)
        chevronView.translatesAutoresizingMaskIntoConstraints = false
        chevronView.setContentHuggingPriority(.required, for: .horizontal)

        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        addSubview(chevronView)
        addSubview(titleLabel)
        addSubview(badgeView)

        NSLayoutConstraint.activate([
            chevronView.leadingAnchor.constraint(equalTo: leadingAnchor),
            chevronView.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevronView.widthAnchor.constraint(equalToConstant: 14),
            chevronView.heightAnchor.constraint(equalToConstant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: chevronView.trailingAnchor, constant: 4),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            badgeView.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 5),
            badgeView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // Let button clicks pass through immediately.
        if actionButtons.contains(where: { $0.frame.contains(point) }) {
            super.mouseDown(with: event)
            return
        }
        mouseDownPoint = event.locationInWindow
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if actionButtons.contains(where: { $0.frame.contains(point) }) { return }

        let dy = event.locationInWindow.y - mouseDownPoint.y
        let dx = event.locationInWindow.x - mouseDownPoint.x
        let dist = sqrt(dx * dx + dy * dy)

        if !isDragging {
            guard dist >= Self.dragThreshold else { return }
            isDragging = true
            onDragBegan?(mouseDownPoint)
        }
        onDragMoved?(event.locationInWindow)
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            isDragging = false
            onDragEnded?()
        } else {
            // No drag — treat as a tap to toggle collapse.
            let point = convert(event.locationInWindow, from: nil)
            if !actionButtons.contains(where: { $0.frame.contains(point) }) {
                onToggle?()
            }
        }
    }

    func render(
        title: String,
        count: Int? = nil,
        isCollapsed: Bool,
        actionButtons: [NSButton],
        theme: WorkspaceShellTheme,
        onToggle: @escaping () -> Void
    ) {
        self.onToggle = onToggle

        titleLabel.stringValue = title
        titleLabel.textColor = theme.shell.textMuted

        let symbol = isCollapsed ? "chevron.right" : "chevron.down"
        chevronView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        chevronView.contentTintColor = theme.shell.textMuted

        if let count {
            badgeView.isHidden = false
            badgeView.render(
                count: count,
                badgeColor: theme.shell.textMuted,
                numberColor: theme.shell.sidebarBackground
            )
        } else {
            badgeView.isHidden = true
        }

        // Remove old action buttons.
        for btn in self.actionButtons {
            btn.removeFromSuperview()
        }
        self.actionButtons = actionButtons

        // Add new action buttons from trailing edge inward.
        var previousAnchor = trailingAnchor
        for btn in actionButtons.reversed() {
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.isHidden = isCollapsed
            addSubview(btn)
            NSLayoutConstraint.activate([
                btn.trailingAnchor.constraint(equalTo: previousAnchor),
                btn.centerYAnchor.constraint(equalTo: centerYAnchor),
                btn.widthAnchor.constraint(equalToConstant: 22),
                btn.heightAnchor.constraint(equalToConstant: 22),
            ])
            previousAnchor = btn.leadingAnchor
        }
    }

    func applyTheme(_ theme: WorkspaceShellTheme) {
        chevronView.contentTintColor = theme.shell.textMuted
        titleLabel.textColor = theme.shell.textMuted
        for btn in actionButtons {
            btn.contentTintColor = theme.shell.textMuted
        }
    }
}
