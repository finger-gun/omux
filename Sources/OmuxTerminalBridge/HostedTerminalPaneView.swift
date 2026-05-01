import AppKit
import Foundation
import OmuxCore

@MainActor
protocol TerminalSurfaceContentHosting: AnyObject {
    var rootView: NSView { get }
    var focusTarget: NSView { get }
    func setFocused(_ isFocused: Bool)
    func apply(themePalette: TerminalThemePalette)
    func measuredTerminalSize(in size: CGSize) -> TerminalSize
}

@MainActor
protocol RuntimeTerminalInteractionConfiguring: AnyObject {
    func configureHostedPane(
        paneID: PaneID,
        isFocused: Bool,
        onFocus: @escaping @MainActor (PaneID) -> Void
    )
    func updateHostedPaneFocus(_ isFocused: Bool)
}

public struct TerminalThemePalette: @unchecked Sendable {
    public let backgroundColor: NSColor
    public let foregroundColor: NSColor
    public let cursorColor: NSColor
    public let selectionColor: NSColor

    public init(
        backgroundColor: NSColor,
        foregroundColor: NSColor,
        cursorColor: NSColor,
        selectionColor: NSColor
    ) {
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
        self.cursorColor = cursorColor
        self.selectionColor = selectionColor
    }
}

extension TerminalThemePalette: Equatable {
    public static func == (lhs: TerminalThemePalette, rhs: TerminalThemePalette) -> Bool {
        lhs.backgroundColor.isEqual(rhs.backgroundColor)
            && lhs.foregroundColor.isEqual(rhs.foregroundColor)
            && lhs.cursorColor.isEqual(rhs.cursorColor)
            && lhs.selectionColor.isEqual(rhs.selectionColor)
    }
}

public extension TerminalThemePalette {
    static let defaultDark = TerminalThemePalette(
        backgroundColor: NSColor(calibratedRed: 0.05, green: 0.07, blue: 0.1, alpha: 1.0),
        foregroundColor: NSColor(calibratedRed: 0.91, green: 0.93, blue: 0.96, alpha: 1.0),
        cursorColor: .controlAccentColor,
        selectionColor: NSColor(calibratedRed: 0.14, green: 0.2, blue: 0.3, alpha: 1.0)
    )
}

private enum TerminalLayoutMetrics {
    static let hostedContentInset: CGFloat = 4
    static let runtimeSurfaceInset: CGFloat = 0
    static let fallbackScrollInset: CGFloat = 0
    static let fallbackTextInset = NSSize(width: 8, height: 8)
}

@MainActor
public final class HostedTerminalPaneView: NSView {
    private struct MeasuredTerminalSize: Equatable {
        let columns: Int
        let rows: Int
    }

    private let paneID: PaneID
    private let bridge: GhosttyTerminalBridge
    private let contentHost: any TerminalSurfaceContentHosting
    private var themePalette: TerminalThemePalette
    private var lastMeasuredSize: MeasuredTerminalSize?

    init(
        pane: Pane,
        bridge: GhosttyTerminalBridge,
        isFocused: Bool,
        themePalette: TerminalThemePalette = .defaultDark,
        onFocus: @escaping @MainActor (PaneID) -> Void
    ) {
        self.paneID = pane.id
        self.bridge = bridge
        self.themePalette = themePalette
        self.contentHost = bridge.makeHostedSurfaceContentHost(
            for: pane,
            isFocused: isFocused,
            themePalette: themePalette,
            onFocus: onFocus
        )
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        updateFocusState(isFocused)
        contentHost.apply(themePalette: themePalette)

        let hostedView = contentHost.rootView
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostedView)
        NSLayoutConstraint.activate([
            hostedView.topAnchor.constraint(equalTo: topAnchor, constant: TerminalLayoutMetrics.hostedContentInset),
            hostedView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: TerminalLayoutMetrics.hostedContentInset),
            hostedView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -TerminalLayoutMetrics.hostedContentInset),
            hostedView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -TerminalLayoutMetrics.hostedContentInset),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 360),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 280),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    public override func layout() {
        super.layout()

        let terminalSize = contentHost.measuredTerminalSize(in: contentHost.rootView.bounds.size)
        let measured = MeasuredTerminalSize(columns: terminalSize.columns, rows: terminalSize.rows)
        guard measured != lastMeasuredSize else {
            return
        }

        lastMeasuredSize = measured
        try? bridge.resize(paneID: paneID, columns: terminalSize.columns, rows: terminalSize.rows)
    }

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(contentHost.focusTarget)
        super.mouseDown(with: event)
    }

    public var focusTarget: NSView {
        contentHost.focusTarget
    }

    public var representedPaneID: PaneID {
        paneID
    }

    public func updateFocusState(_ isFocused: Bool) {
        contentHost.setFocused(isFocused)
        layer?.borderWidth = 0
        layer?.backgroundColor = themePalette.backgroundColor.cgColor
    }

    public func apply(themePalette: TerminalThemePalette) {
        self.themePalette = themePalette
        contentHost.apply(themePalette: themePalette)
        layer?.backgroundColor = themePalette.backgroundColor.cgColor
    }
}

@MainActor
final class RuntimeTerminalSurfaceContentHost: TerminalSurfaceContentHosting {
    private let paneID: PaneID
    private let bridge: GhosttyTerminalBridge
    private let runtimeView: NSView
    let rootView: NSView
    let focusTarget: NSView

    init(
        pane: Pane,
        runtimeView: NSView,
        bridge: GhosttyTerminalBridge,
        isFocused: Bool,
        themePalette: TerminalThemePalette,
        onFocus: @escaping @MainActor (PaneID) -> Void
    ) {
        self.paneID = pane.id
        self.bridge = bridge
        self.runtimeView = runtimeView
        self.rootView = RuntimeTerminalSurfaceContainer(
            runtimeView: runtimeView,
            themePalette: themePalette
        )
        self.focusTarget = runtimeView
        (runtimeView as? any RuntimeTerminalInteractionConfiguring)?.configureHostedPane(
            paneID: pane.id,
            isFocused: isFocused,
            onFocus: onFocus
        )
    }

    func setFocused(_ isFocused: Bool) {
        (runtimeView as? any RuntimeTerminalInteractionConfiguring)?.updateHostedPaneFocus(isFocused)
        bridge.setHostedSurfaceFocused(paneID: paneID, isFocused: isFocused)
    }

    func measuredTerminalSize(in size: CGSize) -> TerminalSize {
        TerminalSize(
            columns: max(20, Int(size.width / 8)),
            rows: max(5, Int(size.height / 18))
        )
    }

    func apply(themePalette: TerminalThemePalette) {
        (rootView as? RuntimeTerminalSurfaceContainer)?.apply(themePalette: themePalette)
    }
}

@MainActor
private final class RuntimeTerminalSurfaceContainer: NSView {
    init(runtimeView: NSView, themePalette: TerminalThemePalette) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = themePalette.backgroundColor.cgColor

        runtimeView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(runtimeView)

        NSLayoutConstraint.activate([
            runtimeView.topAnchor.constraint(equalTo: topAnchor, constant: TerminalLayoutMetrics.runtimeSurfaceInset),
            runtimeView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: TerminalLayoutMetrics.runtimeSurfaceInset),
            runtimeView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -TerminalLayoutMetrics.runtimeSurfaceInset),
            runtimeView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -TerminalLayoutMetrics.runtimeSurfaceInset),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func apply(themePalette: TerminalThemePalette) {
        layer?.backgroundColor = themePalette.backgroundColor.cgColor
    }
}

@MainActor
final class FallbackTerminalSurfaceContentHost: TerminalSurfaceContentHosting {
    private let textView: FallbackTerminalTextView
    private let scrollView = NSScrollView()
    private let bridge: GhosttyTerminalBridge
    private let paneID: PaneID
    private var observerToken: UUID?

    let rootView: NSView

    init(
        pane: Pane,
        bridge: GhosttyTerminalBridge,
        isFocused: Bool,
        themePalette: TerminalThemePalette,
        onFocus: @escaping @MainActor (PaneID) -> Void
    ) {
        self.bridge = bridge
        self.paneID = pane.id
        self.textView = FallbackTerminalTextView(
            paneID: pane.id,
            bridge: bridge,
            isFocused: isFocused,
            onFocus: onFocus
        )
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        self.rootView = container

        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false

        textView.isEditable = false
        textView.isSelectable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.backgroundColor = .clear
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = TerminalLayoutMetrics.fallbackTextInset
        scrollView.documentView = textView
        apply(themePalette: themePalette)

        container.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor, constant: TerminalLayoutMetrics.fallbackScrollInset),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: TerminalLayoutMetrics.fallbackScrollInset),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -TerminalLayoutMetrics.fallbackScrollInset),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -TerminalLayoutMetrics.fallbackScrollInset),
        ])

        observerToken = bridge.addObserver(for: pane.id) { [weak textView] snapshot in
            DispatchQueue.main.async {
                textView?.string = snapshot.renderedText
                textView?.scrollToEndOfDocument(nil)
            }
        }
    }

    deinit {
        if let observerToken {
            bridge.removeObserver(for: paneID, token: observerToken)
        }
    }

    var focusTarget: NSView {
        textView
    }

    func setFocused(_ isFocused: Bool) {
        textView.isFocusedPane = isFocused
    }

    func apply(themePalette: TerminalThemePalette) {
        scrollView.backgroundColor = themePalette.backgroundColor
        textView.backgroundColor = themePalette.backgroundColor
        textView.textColor = themePalette.foregroundColor
        textView.insertionPointColor = themePalette.cursorColor
        rootView.layer?.backgroundColor = themePalette.backgroundColor.cgColor
    }

    func measuredTerminalSize(in size: CGSize) -> TerminalSize {
        let font = textView.font ?? .monospacedSystemFont(ofSize: 12, weight: .regular)
        let glyphSize = ("W" as NSString).size(withAttributes: [.font: font])
        return TerminalSize(
            columns: max(20, Int(size.width / max(glyphSize.width, 1))),
            rows: max(5, Int(size.height / max(glyphSize.height, 1)))
        )
    }
}

private final class FallbackTerminalTextView: NSTextView {
    private let paneID: PaneID
    private let bridge: GhosttyTerminalBridge
    private let onFocus: @MainActor (PaneID) -> Void
    var isFocusedPane: Bool
    private let normalizer = BridgeAppKitKeyEventNormalizer()

    init(
        paneID: PaneID,
        bridge: GhosttyTerminalBridge,
        isFocused: Bool,
        onFocus: @escaping @MainActor (PaneID) -> Void
    ) {
        self.paneID = paneID
        self.bridge = bridge
        self.isFocusedPane = isFocused
        self.onFocus = onFocus
        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)
        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)
        super.init(frame: .zero, textContainer: textContainer)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func apply(themePalette: TerminalThemePalette) {
        backgroundColor = themePalette.backgroundColor
        textColor = themePalette.foregroundColor
        insertionPointColor = themePalette.cursorColor
        selectedTextAttributes = [
            .backgroundColor: themePalette.selectionColor,
            .foregroundColor: themePalette.foregroundColor,
        ]
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if isFocusedPane == false {
            onFocus(paneID)
        }
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let normalizedEvent = normalizer.normalize(event)
        if TerminalCommandArrowNavigation.controlText(for: normalizedEvent) != nil {
            do {
                try bridge.handle(normalizedEvent, inPane: paneID)
            } catch {
                NSSound.beep()
            }
            return
        }

        if normalizedEvent.route == .shortcut {
            super.keyDown(with: event)
            return
        }

        do {
            try bridge.handle(normalizedEvent, inPane: paneID)
        } catch {
            NSSound.beep()
        }
    }

    override func paste(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            super.paste(sender)
            return
        }

        do {
            try bridge.send(text: text, toPane: paneID)
        } catch {
            NSSound.beep()
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        TerminalDroppedFileText.pasteText(from: sender.draggingPasteboard) == nil ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let text = TerminalDroppedFileText.pasteText(from: sender.draggingPasteboard) else {
            return false
        }

        window?.makeFirstResponder(self)
        if isFocusedPane == false {
            onFocus(paneID)
        }

        do {
            try bridge.send(text: text, toPane: paneID)
            return true
        } catch {
            NSSound.beep()
            return false
        }
    }
}

struct BridgeAppKitKeyEventNormalizer {
    private let normalizer: any KeyEventNormalizing

    init(normalizer: any KeyEventNormalizing = DefaultKeyEventNormalizer()) {
        self.normalizer = normalizer
    }

    func normalize(_ event: NSEvent) -> NormalizedKeyEvent {
        normalizer.normalize(
            RawKeyInput(
                keyCode: event.keyCode,
                characters: event.characters ?? "",
                charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
                modifiers: KeyModifiers(appKitEvent: event),
                phase: .appKitPhase(for: event),
                isRepeat: event.isARepeat,
                isComposing: event.type == .keyDown && (event.characters?.isEmpty ?? true)
            )
        )
    }
}
