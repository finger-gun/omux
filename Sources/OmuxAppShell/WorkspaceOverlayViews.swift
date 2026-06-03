import AppKit
import OmuxConfig
import OmuxControlPlane
import OmuxCore
import OmuxVault
import QuartzCore

final class ShellOverlayHostView: NSView {
    private final class PassthroughOverlayView: NSView {
        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            let hitView = super.hitTest(point)
            return hitView === self ? nil : hitView
        }
    }

    private final class BlockingOverlayView: NSView {
        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            // When no modal content is shown, pass events through to views
            // below the overlay so terminal interaction (including drag and
            // drop) is not blocked.  When a modal IS shown the subview
            // captures the hit inside its frame; clicks outside the modal
            // still hit self, which keeps them from reaching the terminal.
            guard subviews.isEmpty == false else {
                return nil
            }
            return super.hitTest(point)
        }
    }

    private let bannerHostView = PassthroughOverlayView()
    private let paletteHostView = PassthroughOverlayView()
    private let modalHostView = BlockingOverlayView()
    private let bannerStackView = NSStackView()
    let floatingModalOverlayView = FloatingModalOverlayView()
    private var currentTheme: WorkspaceShellTheme = .defaultTheme

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        bannerHostView.translatesAutoresizingMaskIntoConstraints = false
        paletteHostView.translatesAutoresizingMaskIntoConstraints = false
        modalHostView.translatesAutoresizingMaskIntoConstraints = false
        bannerStackView.orientation = .vertical
        bannerStackView.alignment = .centerX
        bannerStackView.spacing = 10
        bannerStackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(floatingModalOverlayView)
        addSubview(bannerHostView)
        addSubview(paletteHostView)
        addSubview(modalHostView)
        bannerHostView.addSubview(bannerStackView)

        NSLayoutConstraint.activate([
            floatingModalOverlayView.topAnchor.constraint(equalTo: topAnchor),
            floatingModalOverlayView.leadingAnchor.constraint(equalTo: leadingAnchor),
            floatingModalOverlayView.trailingAnchor.constraint(equalTo: trailingAnchor),
            floatingModalOverlayView.bottomAnchor.constraint(equalTo: bottomAnchor),
            bannerHostView.topAnchor.constraint(equalTo: topAnchor),
            bannerHostView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bannerHostView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bannerHostView.bottomAnchor.constraint(equalTo: bottomAnchor),
            paletteHostView.topAnchor.constraint(equalTo: topAnchor),
            paletteHostView.leadingAnchor.constraint(equalTo: leadingAnchor),
            paletteHostView.trailingAnchor.constraint(equalTo: trailingAnchor),
            paletteHostView.bottomAnchor.constraint(equalTo: bottomAnchor),
            modalHostView.topAnchor.constraint(equalTo: topAnchor),
            modalHostView.leadingAnchor.constraint(equalTo: leadingAnchor),
            modalHostView.trailingAnchor.constraint(equalTo: trailingAnchor),
            modalHostView.bottomAnchor.constraint(equalTo: bottomAnchor),
            bannerStackView.centerXAnchor.constraint(equalTo: bannerHostView.centerXAnchor),
            bannerStackView.leadingAnchor.constraint(greaterThanOrEqualTo: bannerHostView.leadingAnchor, constant: 16),
            bannerStackView.trailingAnchor.constraint(lessThanOrEqualTo: bannerHostView.trailingAnchor, constant: -16),
            bannerStackView.bottomAnchor.constraint(equalTo: bannerHostView.bottomAnchor, constant: -16),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hitView = super.hitTest(point)
        return hitView === self ? nil : hitView
    }

    func apply(theme: WorkspaceShellTheme) {
        currentTheme = theme
        floatingModalOverlayView.apply(theme: theme)
        bannerStackView.arrangedSubviews.compactMap { $0 as? WorkspaceRestoreBannerView }.forEach { $0.apply(theme: theme) }
        paletteHostView.subviews.compactMap { $0 as? CommandPaletteView }.forEach { $0.apply(theme: theme) }
        modalHostView.subviews.compactMap { $0 as? AgentSessionPathMismatchModalView }.forEach { $0.apply(theme: theme) }
    }

    func present(workspaceRestoreBannerView bannerView: WorkspaceRestoreBannerView) {
        if bannerView.superview == nil {
            bannerStackView.addArrangedSubview(bannerView)
            NSLayoutConstraint.activate([
                bannerView.widthAnchor.constraint(lessThanOrEqualTo: bannerHostView.widthAnchor, constant: -32),
            ])
        }
        bannerView.apply(theme: currentTheme)
    }

    func dismiss(workspaceRestoreBannerView bannerView: WorkspaceRestoreBannerView) {
        if bannerView.superview === bannerStackView {
            bannerStackView.removeArrangedSubview(bannerView)
            bannerView.removeFromSuperview()
        }
    }

    func dismissWorkspaceRestoreBanners(where shouldDismiss: (WorkspaceRestoreBannerView) -> Bool) {
        let bannersToDismiss = bannerStackView.arrangedSubviews.compactMap { $0 as? WorkspaceRestoreBannerView }
            .filter(shouldDismiss)
        bannersToDismiss.forEach(dismiss)
    }

    func dismissAllWorkspaceRestoreBanners() {
        dismissWorkspaceRestoreBanners { _ in true }
    }

    func present(commandPaletteView: CommandPaletteView) {
        if commandPaletteView.superview !== paletteHostView {
            paletteHostView.addSubview(commandPaletteView)
            NSLayoutConstraint.activate([
                commandPaletteView.topAnchor.constraint(equalTo: paletteHostView.topAnchor),
                commandPaletteView.leadingAnchor.constraint(equalTo: paletteHostView.leadingAnchor),
                commandPaletteView.trailingAnchor.constraint(equalTo: paletteHostView.trailingAnchor),
                commandPaletteView.bottomAnchor.constraint(equalTo: paletteHostView.bottomAnchor),
            ])
        }
        commandPaletteView.apply(theme: currentTheme)
    }

    func dismiss(commandPaletteView: CommandPaletteView) {
        if commandPaletteView.superview === paletteHostView {
            commandPaletteView.removeFromSuperview()
        }
    }

    func present(agentSessionPathMismatchView modalView: AgentSessionPathMismatchModalView) {
        modalHostView.subviews.forEach { $0.removeFromSuperview() }
        modalView.apply(theme: currentTheme)
        modalHostView.addSubview(modalView)
        let preferredWidth = modalView.widthAnchor.constraint(equalToConstant: 460)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            modalView.centerXAnchor.constraint(equalTo: modalHostView.centerXAnchor),
            modalView.centerYAnchor.constraint(equalTo: modalHostView.centerYAnchor),
            modalView.widthAnchor.constraint(lessThanOrEqualTo: modalHostView.widthAnchor, constant: -48),
            preferredWidth,
        ])
        window?.makeFirstResponder(modalView)
    }

    func dismiss(agentSessionPathMismatchView modalView: AgentSessionPathMismatchModalView) {
        if modalView.superview === modalHostView {
            modalView.removeFromSuperview()
        }
    }
}

@MainActor
enum RestoreBannerChoice {
    case cancel
    case restoreHere
    case restoreAsNewWorkspace
}

@MainActor
final class WorkspaceRestoreBannerView: ThemedCardView {
    private let titleLabel = NSTextField(labelWithString: "Restore workspace?")
    private let messageLabel = NSTextField(labelWithString: "")
    private let cancelButton = AgentSessionModalButton(title: "Cancel", active: false)
    private let restoreHereButton = AgentSessionModalButton(title: "Restore Here", active: false)
    private let restoreNewButton = AgentSessionModalButton(title: "Restore New", active: true)
    let entry: RecentlyClosedWorkspaceEntry
    var onChoice: ((RestoreBannerChoice) -> Void)?

    init(entry: RecentlyClosedWorkspaceEntry, theme: WorkspaceShellTheme) {
        self.entry = entry
        super.init(frame: .zero)

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        messageLabel.stringValue = "\(entry.name) - \(entry.workspacePathSummary)"
        messageLabel.font = .systemFont(ofSize: 12)
        messageLabel.maximumNumberOfLines = 2
        messageLabel.lineBreakMode = .byTruncatingMiddle
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        cancelButton.onPress = { [weak self] in self?.onChoice?(.cancel) }
        restoreHereButton.onPress = { [weak self] in self?.onChoice?(.restoreHere) }
        restoreNewButton.onPress = { [weak self] in self?.onChoice?(.restoreAsNewWorkspace) }

        let textStack = NSStackView(views: [titleLabel, messageLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let buttonRow = NSStackView(views: [cancelButton, restoreHereButton, restoreNewButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 6
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        addSubview(textStack)
        addSubview(buttonRow)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(greaterThanOrEqualToConstant: 560),
            textStack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            textStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            textStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            buttonRow.leadingAnchor.constraint(greaterThanOrEqualTo: textStack.trailingAnchor, constant: 16),
            buttonRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            buttonRow.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        apply(theme: theme)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func apply(theme: WorkspaceShellTheme) {
        applyCardTheme(theme)
        titleLabel.textColor = theme.shell.textPrimary
        messageLabel.textColor = theme.shell.textSecondary
        cancelButton.apply(theme: theme)
        restoreHereButton.apply(theme: theme)
        restoreNewButton.apply(theme: theme)
    }
}

@MainActor
enum AgentSessionPathMismatchChoice {
    case resumeHere
    case openWorkspace
    case cancel
}

@MainActor
final class AgentSessionPathMismatchModalView: ThemedCardView {
    private let titleLabel = NSTextField(labelWithString: "Session Path Differs")
    private let messageLabel = NSTextField(labelWithString: "")
    private let resumeButton = AgentSessionModalButton(title: "Resume Here", active: true)
    private let openWorkspaceButton = AgentSessionModalButton(title: "Open Workspace", active: false)
    private let cancelButton = AgentSessionModalButton(title: "Cancel", active: false)
    private let workingDirectory: String?
    private let connectedPaths: [String]
    var onChoice: ((AgentSessionPathMismatchChoice) -> Void)?

    init(workingDirectory: String?, connectedPaths: [String], theme: WorkspaceShellTheme) {
        self.workingDirectory = workingDirectory
        self.connectedPaths = connectedPaths
        super.init(frame: .zero)

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let sessionPath = workingDirectory ?? "unknown"
        let currentPath = connectedPaths.isEmpty ? "unknown" : connectedPaths.joined(separator: ", ")
        messageLabel.stringValue = "This agent session was captured in:\n\(sessionPath)\n\nCurrent workspace paths:\n\(currentPath)"
        messageLabel.font = .systemFont(ofSize: 12)
        messageLabel.maximumNumberOfLines = 6
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        resumeButton.onPress = { [weak self] in self?.onChoice?(.resumeHere) }
        openWorkspaceButton.onPress = { [weak self] in self?.onChoice?(.openWorkspace) }
        cancelButton.onPress = { [weak self] in self?.onChoice?(.cancel) }
        openWorkspaceButton.isEnabled = workingDirectory != nil

        let buttonRow = NSStackView(views: [cancelButton, NSView(), openWorkspaceButton, resumeButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(messageLabel)
        addSubview(buttonRow)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            messageLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            buttonRow.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 18),
            buttonRow.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            buttonRow.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            buttonRow.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
        apply(theme: theme)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onChoice?(.cancel)
        } else if event.keyCode == 36 {
            onChoice?(.resumeHere)
        } else {
            super.keyDown(with: event)
        }
    }

    func apply(theme: WorkspaceShellTheme) {
        applyCardTheme(theme)
        titleLabel.textColor = theme.shell.textPrimary
        messageLabel.textColor = theme.shell.textSecondary
        resumeButton.apply(theme: theme)
        openWorkspaceButton.apply(theme: theme)
        cancelButton.apply(theme: theme)
    }
}

@MainActor
final class AgentSessionModalButton: NSControl {
    var onPress: (() -> Void)?
    private let titleLabel = NSTextField(labelWithString: "")
    private let title: String
    private let active: Bool
    private var theme = WorkspaceShellTheme.defaultTheme

    init(title: String, active: Bool) {
        self.title = title
        self.active = active
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 5
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 12, weight: active ? .semibold : .medium)
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func apply(theme: WorkspaceShellTheme) {
        self.theme = theme
        titleLabel.textColor = active ? theme.shell.selectedText : theme.shell.textSecondary
        layer?.backgroundColor = (active ? theme.shell.selection : theme.shell.chromeButtonBackground).cgColor
        layer?.borderWidth = active ? 0 : 1
        layer?.borderColor = theme.shell.subduedBorder.cgColor
        alphaValue = isEnabled ? 1 : 0.45
    }

    override var isEnabled: Bool {
        didSet { apply(theme: theme) }
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        onPress?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 49 {
            onPress?()
        } else {
            super.keyDown(with: event)
        }
    }
}

@MainActor
final class FloatingModalOverlayView: NSView {
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    private var currentTheme: WorkspaceShellTheme = .defaultTheme

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func apply(theme: WorkspaceShellTheme) {
        currentTheme = theme
        subviews.compactMap { $0 as? FloatingPaneModalView }.forEach { $0.apply(theme: theme) }
    }

    func render(modalViews: [FloatingPaneModalView]) {
        subviews.forEach { $0.removeFromSuperview() }
        for modalView in modalViews {
            modalView.apply(theme: currentTheme)
            addSubview(modalView)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hitView = super.hitTest(point)
        return hitView === self ? nil : hitView
    }
}

/// The draggable header bar of a `FloatingPaneModalView`.
/// Named subclass of `DraggableEventRelayView` so tests can find it by type.
@MainActor
final class FloatingPaneModalHeaderView: DraggableEventRelayView {}

@MainActor
final class FloatingPaneModalView: NSView {
    private static let minimumWidth = CGFloat(360)
    private static let minimumHeight = CGFloat(240)
    private static let resizeHandleSide = CGFloat(18)

    private let modalID: FloatingPaneModalID
    private let paneID: PaneID
    private let sourceStackID: PaneStackID
    private let dragHandleView = FloatingPaneModalHeaderView()
    private let resizeHandleView = DraggableEventRelayView()
    private let resizeHandleGlyph = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = ChromePillButton()
    private let contentHostView = NSView()
    private let onFocus: @MainActor (PaneID) -> Void
    private let onClose: @MainActor (PaneID) -> Void
    private let onDragChanged: @MainActor (PaneID, PaneStackID, FloatingPaneModalID, NSRect, Bool) -> Void
    private let onDragEnded: @MainActor (PaneID, PaneStackID, FloatingPaneModalID, NSRect, Bool) -> Void
    private var dragOrigin: CGPoint?
    private var initialFrameOrigin: CGPoint = .zero
    private var resizeOrigin: CGPoint?
    private var initialFrameSize: CGSize = .zero

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    init(
        modalID: FloatingPaneModalID,
        paneID: PaneID,
        sourceStackID: PaneStackID,
        title: String,
        contentView: NSView,
        frameModel: FloatingPaneModalFrame,
        theme: WorkspaceShellTheme,
        onFocus: @escaping @MainActor (PaneID) -> Void,
        onClose: @escaping @MainActor (PaneID) -> Void,
        onDragChanged: @escaping @MainActor (PaneID, PaneStackID, FloatingPaneModalID, NSRect, Bool) -> Void,
        onDragEnded: @escaping @MainActor (PaneID, PaneStackID, FloatingPaneModalID, NSRect, Bool) -> Void
    ) {
        self.modalID = modalID
        self.paneID = paneID
        self.sourceStackID = sourceStackID
        self.onFocus = onFocus
        self.onClose = onClose
        self.onDragChanged = onDragChanged
        self.onDragEnded = onDragEnded
        super.init(frame: NSRect(x: frameModel.x, y: frameModel.y, width: frameModel.width, height: frameModel.height))
        translatesAutoresizingMaskIntoConstraints = true
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.shadowOpacity = 0.22
        layer?.shadowRadius = 18
        layer?.shadowOffset = CGSize(width: 0, height: 10)
        layer?.masksToBounds = false

        dragHandleView.translatesAutoresizingMaskIntoConstraints = false
        dragHandleView.wantsLayer = true
        dragHandleView.layer?.cornerRadius = 12
        dragHandleView.onMouseDownEvent = { [weak self] event in
            self?.handleHeaderMouseDown(event)
        }
        dragHandleView.onMouseDraggedEvent = { [weak self] event in
            self?.handleHeaderMouseDragged(event)
        }
        dragHandleView.onMouseUpEvent = { [weak self] event in
            self?.handleHeaderMouseUp(event)
        }

        resizeHandleView.translatesAutoresizingMaskIntoConstraints = false
        resizeHandleView.onMouseDownEvent = { [weak self] event in
            self?.handleResizeMouseDown(event)
        }
        resizeHandleView.onMouseDraggedEvent = { [weak self] event in
            self?.handleResizeMouseDragged(event)
        }
        resizeHandleView.onMouseUpEvent = { [weak self] event in
            self?.handleResizeMouseUp(event)
        }
        resizeHandleView.toolTip = "Resize modal"

        resizeHandleGlyph.translatesAutoresizingMaskIntoConstraints = false
        resizeHandleGlyph.image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: "Resize modal")
        resizeHandleGlyph.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
        resizeHandleGlyph.imageScaling = .scaleProportionallyDown
        resizeHandleView.addSubview(resizeHandleGlyph)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.stringValue = title

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.configure(
            symbolName: "xmark",
            accessibilityLabel: "Close modal",
            active: false,
            theme: theme,
            compact: true
        )
        closeButton.onPress = { [weak self] in
            self?.handleClose(nil)
        }

        contentHostView.translatesAutoresizingMaskIntoConstraints = false
        contentHostView.wantsLayer = true
        contentView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(contentHostView)
        addSubview(dragHandleView)
        addSubview(resizeHandleView)
        contentHostView.addSubview(contentView)
        dragHandleView.addSubview(titleLabel)
        dragHandleView.addSubview(closeButton)

        NSLayoutConstraint.activate([
            dragHandleView.topAnchor.constraint(equalTo: topAnchor),
            dragHandleView.leadingAnchor.constraint(equalTo: leadingAnchor),
            dragHandleView.trailingAnchor.constraint(equalTo: trailingAnchor),
            dragHandleView.heightAnchor.constraint(equalToConstant: 28),

            closeButton.leadingAnchor.constraint(equalTo: dragHandleView.leadingAnchor, constant: 10),
            closeButton.centerYAnchor.constraint(equalTo: dragHandleView.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 16),

            titleLabel.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: dragHandleView.trailingAnchor, constant: -12),
            titleLabel.centerYAnchor.constraint(equalTo: dragHandleView.centerYAnchor),

            contentHostView.topAnchor.constraint(equalTo: dragHandleView.bottomAnchor, constant: 4),
            contentHostView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentHostView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentHostView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentView.topAnchor.constraint(equalTo: contentHostView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: contentHostView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: contentHostView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: contentHostView.bottomAnchor),

            resizeHandleView.widthAnchor.constraint(equalToConstant: Self.resizeHandleSide),
            resizeHandleView.heightAnchor.constraint(equalToConstant: Self.resizeHandleSide),
            resizeHandleView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            resizeHandleView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),

            resizeHandleGlyph.centerXAnchor.constraint(equalTo: resizeHandleView.centerXAnchor),
            resizeHandleGlyph.centerYAnchor.constraint(equalTo: resizeHandleView.centerYAnchor),
        ])

        apply(theme: theme)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func apply(theme: WorkspaceShellTheme) {
        layer?.backgroundColor = theme.shell.paneHeaderBackground.cgColor
        contentHostView.layer?.cornerRadius = 12
        contentHostView.layer?.masksToBounds = true
        contentHostView.layer?.backgroundColor = theme.shell.canvasBackground.cgColor
        dragHandleView.layer?.backgroundColor = theme.shell.paneHeaderBackground.cgColor
        titleLabel.textColor = theme.shell.textPrimary
        closeButton.applyTheme(theme)
        resizeHandleGlyph.contentTintColor = theme.shell.textMuted
    }

    private func handleHeaderMouseDown(_ event: NSEvent) {
        guard let superview else {
            return
        }
        onFocus(paneID)
        dragOrigin = superview.convert(event.locationInWindow, from: nil)
        initialFrameOrigin = frame.origin
    }

    private func handleHeaderMouseDragged(_ event: NSEvent) {
        guard let superview, let dragOrigin else {
            return
        }
        let location = superview.convert(event.locationInWindow, from: nil)
        let delta = CGPoint(x: location.x - dragOrigin.x, y: location.y - dragOrigin.y)
        frame.origin = CGPoint(
            x: max(0, min(initialFrameOrigin.x + delta.x, superview.bounds.width - frame.width)),
            y: max(0, min(initialFrameOrigin.y + delta.y, superview.bounds.height - frame.height))
        )
        onDragChanged(paneID, sourceStackID, modalID, frame, event.modifierFlags.contains(.command) == false)
    }

    private func handleHeaderMouseUp(_ event: NSEvent) {
        guard dragOrigin != nil else {
            return
        }
        dragOrigin = nil
        onDragEnded(paneID, sourceStackID, modalID, frame, event.modifierFlags.contains(.command) == false)
    }

    private func handleResizeMouseDown(_ event: NSEvent) {
        guard let superview else {
            return
        }
        onFocus(paneID)
        resizeOrigin = superview.convert(event.locationInWindow, from: nil)
        initialFrameSize = frame.size
        initialFrameOrigin = frame.origin
    }

    private func handleResizeMouseDragged(_ event: NSEvent) {
        guard let superview, let resizeOrigin else {
            return
        }
        let location = superview.convert(event.locationInWindow, from: nil)
        let delta = CGPoint(x: location.x - resizeOrigin.x, y: location.y - resizeOrigin.y)
        frame.size = CGSize(
            width: max(Self.minimumWidth, min(initialFrameSize.width + delta.x, superview.bounds.width - initialFrameOrigin.x)),
            height: max(Self.minimumHeight, min(initialFrameSize.height + delta.y, superview.bounds.height - initialFrameOrigin.y))
        )
        onDragChanged(paneID, sourceStackID, modalID, frame, false)
    }

    private func handleResizeMouseUp(_ event: NSEvent) {
        guard resizeOrigin != nil else {
            return
        }
        resizeOrigin = nil
        onDragEnded(paneID, sourceStackID, modalID, frame, false)
    }

    @objc private func handleClose(_ sender: Any?) {
        onClose(paneID)
    }
}
