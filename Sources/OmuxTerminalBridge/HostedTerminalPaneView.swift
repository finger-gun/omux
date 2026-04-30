import AppKit
import Foundation
import OmuxCore

@MainActor
protocol TerminalSurfaceContentHosting: AnyObject {
    var rootView: NSView { get }
    var focusTarget: NSView { get }
    func setFocused(_ isFocused: Bool)
    func measuredTerminalSize(in size: CGSize) -> TerminalSize
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
    private var lastMeasuredSize: MeasuredTerminalSize?

    init(
        pane: Pane,
        bridge: GhosttyTerminalBridge,
        isFocused: Bool,
        onFocus: @escaping @MainActor (PaneID) -> Void
    ) {
        self.paneID = pane.id
        self.bridge = bridge
        self.contentHost = bridge.makeHostedSurfaceContentHost(
            for: pane,
            isFocused: isFocused,
            onFocus: onFocus
        )
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        wantsLayer = true
        layer?.cornerRadius = 8
        updateFocusState(isFocused)

        let hostedView = contentHost.rootView
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostedView)
        NSLayoutConstraint.activate([
            hostedView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            hostedView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            hostedView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            hostedView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
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

    public func updateFocusState(_ isFocused: Bool) {
        contentHost.setFocused(isFocused)
        layer?.borderWidth = isFocused ? 2 : 1
        layer?.borderColor = (isFocused ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
    }
}

@MainActor
final class RuntimeTerminalSurfaceContentHost: TerminalSurfaceContentHosting {
    private let paneID: PaneID
    private let bridge: GhosttyTerminalBridge
    let rootView: NSView
    let focusTarget: NSView

    init(
        pane: Pane,
        runtimeView: NSView,
        bridge: GhosttyTerminalBridge,
        isFocused: Bool,
        onFocus: @escaping @MainActor (PaneID) -> Void
    ) {
        self.paneID = pane.id
        self.bridge = bridge
        let inputProxy = FallbackTerminalTextView(
            paneID: pane.id,
            bridge: bridge,
            isFocused: isFocused,
            onFocus: onFocus
        )
        inputProxy.drawsBackground = false
        inputProxy.alphaValue = 0.01
        inputProxy.insertionPointColor = .clear
        self.rootView = RuntimeTerminalSurfaceContainer(
            runtimeView: runtimeView,
            inputProxy: inputProxy
        )
        self.focusTarget = inputProxy
    }

    func setFocused(_ isFocused: Bool) {
        (focusTarget as? FallbackTerminalTextView)?.isFocusedPane = isFocused
        bridge.setHostedSurfaceFocused(paneID: paneID, isFocused: isFocused)
    }

    func measuredTerminalSize(in size: CGSize) -> TerminalSize {
        TerminalSize(
            columns: max(20, Int(size.width / 8)),
            rows: max(5, Int(size.height / 18))
        )
    }
}

@MainActor
private final class RuntimeTerminalSurfaceContainer: NSView {
    init(runtimeView: NSView, inputProxy: FallbackTerminalTextView) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        runtimeView.translatesAutoresizingMaskIntoConstraints = false
        inputProxy.translatesAutoresizingMaskIntoConstraints = false
        addSubview(runtimeView)
        addSubview(inputProxy)

        NSLayoutConstraint.activate([
            runtimeView.topAnchor.constraint(equalTo: topAnchor),
            runtimeView.leadingAnchor.constraint(equalTo: leadingAnchor),
            runtimeView.trailingAnchor.constraint(equalTo: trailingAnchor),
            runtimeView.bottomAnchor.constraint(equalTo: bottomAnchor),
            inputProxy.topAnchor.constraint(equalTo: topAnchor),
            inputProxy.leadingAnchor.constraint(equalTo: leadingAnchor),
            inputProxy.trailingAnchor.constraint(equalTo: trailingAnchor),
            inputProxy.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
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
        scrollView.documentView = textView

        container.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
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
}

private struct BridgeAppKitKeyEventNormalizer {
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
                modifiers: KeyModifiers(event.modifierFlags),
                phase: event.type == .keyUp ? .keyUp : .keyDown,
                isRepeat: event.isARepeat,
                isComposing: event.characters?.isEmpty ?? true
            )
        )
    }
}

private extension KeyModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var result: KeyModifiers = []
        if flags.contains(.shift) { result.insert(.leftShift) }
        if flags.contains(.control) { result.insert(.leftControl) }
        if flags.contains(.option) { result.insert(.leftOption) }
        if flags.contains(.command) { result.insert(.leftCommand) }
        if flags.contains(.function) { result.insert(.function) }
        if flags.contains(.capsLock) { result.insert(.capsLock) }
        self = result
    }
}
