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
        onFocus: @escaping @MainActor (PaneID) -> Void,
        terminalSizeProvider: @escaping @MainActor () -> TerminalSize?,
        onTextActivation: (@MainActor (TerminalTextActivationRequest) -> Bool)?,
        onTextActivationHover: (@MainActor (TerminalTextActivationRequest) -> Bool)?
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
        onFocus: @escaping @MainActor (PaneID) -> Void,
        onTextActivation: (@MainActor (TerminalTextActivationRequest) -> Bool)? = nil,
        onTextActivationHover: (@MainActor (TerminalTextActivationRequest) -> Bool)? = nil
    ) {
        self.paneID = pane.id
        self.bridge = bridge
        self.themePalette = themePalette
        self.contentHost = bridge.makeHostedSurfaceContentHost(
            for: pane,
            isFocused: isFocused,
            themePalette: themePalette,
            onFocus: onFocus,
            terminalSizeProvider: { [weak bridge] in bridge?.terminalSize(for: pane.id) },
            onTextActivation: onTextActivation,
            onTextActivationHover: onTextActivationHover
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
        onFocus: @escaping @MainActor (PaneID) -> Void,
        terminalSizeProvider: @escaping @MainActor () -> TerminalSize?,
        onTextActivation: (@MainActor (TerminalTextActivationRequest) -> Bool)?,
        onTextActivationHover: (@MainActor (TerminalTextActivationRequest) -> Bool)?
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
            onFocus: onFocus,
            terminalSizeProvider: terminalSizeProvider,
            onTextActivation: onTextActivation,
            onTextActivationHover: onTextActivationHover
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
