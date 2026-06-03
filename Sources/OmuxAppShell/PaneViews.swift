import AppKit
import OmuxAIStatusPlugin
import OmuxConfig
import OmuxControlPlane
import OmuxCore
import OmuxTerminalBridge
import OmuxVault
import QuartzCore
import WebKit

@MainActor
protocol WorkspacePaneRendering: AnyObject {
    var rootPaneView: NSView { get }
    var focusTarget: NSView { get }
    var representedPaneID: PaneID { get }
    func updateFocusState(_ isFocused: Bool)
    func apply(theme: WorkspaceShellTheme)
}

extension HostedTerminalPaneView: WorkspacePaneRendering {
    var rootPaneView: NSView { self }

    func apply(theme: WorkspaceShellTheme) {
        apply(themePalette: theme.terminalPalette)
    }
}

@MainActor
final class ExtensionPaneHostView: NSView, WorkspacePaneRendering, WKNavigationDelegate, WKScriptMessageHandler {
    private struct ScrollPosition {
        let x: Double
        let y: Double
    }

    private static var scrollPositionBySource: [String: ScrollPosition] = [:]
    private let paneID: PaneID
    private var descriptor: ExtensionPaneDescriptor
    private var scrollStateSource: String
    private let onFocus: @MainActor (PaneID) -> Void
    private let onAction: @MainActor (ExtensionPaneActionRequest) -> Void
    private let container = NSView()
    private let placeholderLabel = NSTextField(wrappingLabelWithString: "")
    private let webView: WKWebView
    private var isLoadingInjectedHTML = false
    private var pendingScrollPosition: ScrollPosition?
    private var lastRenderedHTML: String?

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
        self.scrollStateSource = descriptor.source ?? pane.id.rawValue
        self.onFocus = onFocus
        self.onAction = onAction

        let configuration = WKWebViewConfiguration()
        let allowsContentJavaScript = descriptor.actionsEnabled || descriptor.pluginID == "dev.fingergun.markdown-preview"
        configuration.defaultWebpagePreferences.allowsContentJavaScript = allowsContentJavaScript
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.scrollStateBridgeScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
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
        webView.configuration.userContentController.add(
            WeakScriptMessageHandler(delegate: self),
            name: "omuxScrollState"
        )
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

    func update(
        pane: Pane,
        descriptor: ExtensionPaneDescriptor,
        isFocused: Bool,
        theme: WorkspaceShellTheme
    ) {
        self.descriptor = descriptor
        self.scrollStateSource = descriptor.source ?? pane.id.rawValue
        apply(theme: theme)
        updateFocusState(isFocused)
        renderContent(theme: theme)
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
        restorePendingScrollPosition()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoadingInjectedHTML = false
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "omuxScrollState",
           let position = Self.scrollPosition(from: message.body) {
            Self.scrollPositionBySource[scrollStateSource] = position
            return
        }

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
            lastRenderedHTML = nil
            return
        }

        placeholderLabel.isHidden = true
        webView.isHidden = false
        if lastRenderedHTML == html {
            return
        }
        pendingScrollPosition = Self.scrollPositionBySource[scrollStateSource]
        isLoadingInjectedHTML = true
        lastRenderedHTML = html
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    private func restorePendingScrollPosition() {
        guard let pendingScrollPosition else {
            return
        }
        self.pendingScrollPosition = nil
        webView.evaluateJavaScript(
            "window.scrollTo(\(pendingScrollPosition.x), \(pendingScrollPosition.y));",
            completionHandler: nil
        )
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

    private static var scrollStateBridgeScript: String {
        """
        (() => {
          const post = () => {
            try {
              window.webkit.messageHandlers.omuxScrollState.postMessage({
                x: window.scrollX || 0,
                y: window.scrollY || 0
              });
            } catch (_) {}
          };
          window.addEventListener('scroll', post, { passive: true });
          window.addEventListener('beforeunload', post);
          window.addEventListener('pagehide', post);
          window.addEventListener('load', post);
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

    private static func scrollPosition(from body: Any) -> ScrollPosition? {
        guard let object = body as? [String: Any] else {
            return nil
        }

        let x: Double
        if let value = object["x"] as? Double {
            x = value
        } else if let value = object["x"] as? Int {
            x = Double(value)
        } else {
            return nil
        }

        let y: Double
        if let value = object["y"] as? Double {
            y = value
        } else if let value = object["y"] as? Int {
            y = Double(value)
        } else {
            return nil
        }

        return ScrollPosition(x: x, y: y)
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
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
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
    private var paneContentView: NSView
    private var paneRenderer: any WorkspacePaneRendering
    private let paneCardView = PaneCardView()
    private var headerView: PaneHeaderView?
    private var splitPreviewView: PaneSplitPreviewView?
    private var mergePreviewView: PaneMergePreviewView?
    private let showsHeader: Bool

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
        terminalTextProvider: @escaping @MainActor (Pane) -> String?,
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
        onExtensionPaneAction: @escaping @MainActor (ExtensionPaneActionRequest) -> Void,
        onRenamePaneTab: ((PaneID, String) -> Void)? = nil,
        onClearPaneTabAlias: ((PaneID) -> Void)? = nil,
        showsHeader: Bool = true
    ) {
        self.showsHeader = showsHeader
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

        let headerView = showsHeader ? PaneHeaderView(
            paneStack: paneStack,
            theme: theme,
            iconResolver: iconResolver,
            iconConfiguration: iconConfiguration,
            terminalTextProvider: terminalTextProvider,
            onSelectPaneTab: onSelectPaneTab,
            onCreatePaneTab: onCreatePaneTab,
            canCloseSinglePaneStack: canCloseSinglePaneStack,
            onClosePane: onClosePane,
            contextMenuProvider: contextMenuProvider,
            canStartPaneTabDrag: canStartPaneTabDrag,
            onPaneTabDragStarted: onPaneTabDragStarted,
            onPaneTabDragMoved: onPaneTabDragMoved,
            onPaneTabDragEnded: onPaneTabDragEnded,
            onPaneTabDragCancelled: onPaneTabDragCancelled,
            onRenamePaneTab: onRenamePaneTab,
            onClearPaneTabAlias: onClearPaneTabAlias
        ) : nil
        self.headerView = headerView
        headerView?.scrollActiveTabToVisible()
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

    func update(
        paneStack: PaneStack,
        focusedPaneID: PaneID,
        windowIsKey: Bool,
        inactiveOpacity: Double,
        bridge: GhosttyTerminalBridge,
        theme: WorkspaceShellTheme,
        iconResolver: WorkspaceIconResolver,
        iconConfiguration: OmuxConfigUI.Icons,
        terminalTextProvider: @escaping @MainActor (Pane) -> String?,
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
        onExtensionPaneAction: @escaping @MainActor (ExtensionPaneActionRequest) -> Void,
        onRenamePaneTab: ((PaneID, String) -> Void)? = nil,
        onClearPaneTabAlias: ((PaneID) -> Void)? = nil,
        showsHeader: Bool = true
    ) {
        precondition(showsHeader == self.showsHeader, "PaneStackView header visibility cannot change during reconciliation.")
        self.paneStackID = paneStack.id
        let activePane = paneStack.focusedPane ?? paneStack.panes[0]

        if paneRenderer.representedPaneID != activePane.id {
            if let descriptor = activePane.extensionPane {
                let extensionPaneView = ExtensionPaneHostView(
                    pane: activePane,
                    descriptor: descriptor,
                    isFocused: activePane.id == focusedPaneID,
                    theme: theme,
                    onFocus: onFocus,
                    onAction: onExtensionPaneAction
                )
                paneRenderer = extensionPaneView
                paneContentView = extensionPaneView
            } else {
                let terminalPaneView = bridge.makeHostedPaneView(
                    for: activePane,
                    isFocused: activePane.id == focusedPaneID,
                    themePalette: theme.terminalPalette,
                    onFocus: onFocus,
                    onTextActivation: onTextActivation,
                    onTextActivationHover: onTextActivationHover
                )
                paneRenderer = terminalPaneView
                paneContentView = terminalPaneView
            }
        } else if let descriptor = activePane.extensionPane,
                  let extensionPaneView = paneRenderer as? ExtensionPaneHostView {
            extensionPaneView.update(
                pane: activePane,
                descriptor: descriptor,
                isFocused: activePane.id == focusedPaneID,
                theme: theme
            )
        }

        let headerView = showsHeader ? PaneHeaderView(
            paneStack: paneStack,
            theme: theme,
            iconResolver: iconResolver,
            iconConfiguration: iconConfiguration,
            terminalTextProvider: terminalTextProvider,
            onSelectPaneTab: onSelectPaneTab,
            onCreatePaneTab: onCreatePaneTab,
            canCloseSinglePaneStack: canCloseSinglePaneStack,
            onClosePane: onClosePane,
            contextMenuProvider: contextMenuProvider,
            canStartPaneTabDrag: canStartPaneTabDrag,
            onPaneTabDragStarted: onPaneTabDragStarted,
            onPaneTabDragMoved: onPaneTabDragMoved,
            onPaneTabDragEnded: onPaneTabDragEnded,
            onPaneTabDragCancelled: onPaneTabDragCancelled,
            onRenamePaneTab: onRenamePaneTab,
            onClearPaneTabAlias: onClearPaneTabAlias
        ) : nil
        self.headerView = headerView
        headerView?.scrollActiveTabToVisible()
        paneRenderer.updateFocusState(activePane.id == focusedPaneID)
        paneCardView.configure(
            headerView: headerView,
            statusText: activePane.terminalState.statusSummary,
            paneRenderer: paneRenderer,
            theme: theme,
            focused: activePane.id == focusedPaneID,
            windowIsKey: windowIsKey,
            inactiveOpacity: inactiveOpacity
        )
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
        guard showsHeader else { return false }
        let localPoint = convert(windowPoint, from: nil)
        guard bounds.contains(localPoint) else { return false }
        let threshold = ShellLayoutMetrics.paneHeaderHeight + 4
        return isFlipped ? localPoint.y <= threshold : localPoint.y >= bounds.height - threshold
    }

    func paneTabInsertionIndex(forWindowPoint windowPoint: NSPoint) -> Int? {
        headerView?.insertionIndex(forWindowPoint: windowPoint)
    }
}

@MainActor
final class PaneSplitPreviewView: NSView {
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
final class PaneMergePreviewView: NSView {
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
        headerView: PaneHeaderView?,
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
        headerView?.heightAnchor.constraint(equalToConstant: ShellLayoutMetrics.paneHeaderHeight).isActive = true
        statusLabel.stringValue = statusText ?? ""
        statusLabel.textColor = theme.shell.textMuted
        statusLabel.isHidden = statusText == nil

        if let headerView {
            container.addArrangedSubview(headerView)
            headerView.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true

        }
        if statusText != nil {
            container.addArrangedSubview(statusLabel)
            statusLabel.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
        }
        container.addArrangedSubview(paneView)
        paneView.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true

        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderWidth = 0
        layer?.borderColor = nil
        alphaValue = (focused && windowIsKey) ? 1.0 : inactiveOpacity
    }
}

@MainActor
final class PaneHeaderView: NSView {
    private let tabStrip = NSStackView()
    private let tabScrollView = NSScrollView()
    private var paneTabButtons: [PaneTabButton] = []
    private let inlineAddButton = ChromePillButton()
    private let pinnedAddButton = ChromePillButton()
    private var contentTrailingToSuperviewConstraint: NSLayoutConstraint?
    private var contentTrailingToPinnedConstraint: NSLayoutConstraint?
    private static let tabMinWidth: CGFloat = 130
    private static let tabMaxWidth: CGFloat = 200

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
        onPaneTabDragCancelled: (() -> Void)? = nil,
        onRenamePaneTab: ((PaneID, String) -> Void)? = nil,
        onClearPaneTabAlias: ((PaneID) -> Void)? = nil
    ) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = theme.shell.topBarBackground.cgColor

        let bottomBorder = CALayer()
        bottomBorder.name = "tabBarBottomBorder"
        bottomBorder.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        bottomBorder.frame = CGRect(x: 0, y: 0, width: 0, height: 1)
        bottomBorder.autoresizingMask = [.layerWidthSizable]
        layer?.addSublayer(bottomBorder)

        let content = NSStackView()
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 0
        content.translatesAutoresizingMaskIntoConstraints = false

        tabStrip.orientation = .horizontal
        tabStrip.alignment = .centerY
        tabStrip.spacing = 0
        tabStrip.distribution = .fill
        tabStrip.translatesAutoresizingMaskIntoConstraints = false
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
            if let onRenamePaneTab {
                button.onRename = { newName in onRenamePaneTab(pane.id, newName) }
            }
            if let onClearPaneTabAlias {
                button.onClearAlias = { onClearPaneTabAlias(pane.id) }
            }
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
            paneTabButtons.append(button)
        }

        // Keep tab visuals balanced like 08efd4d while preserving a usable
        // minimum hit target once multiple tabs are open.
        let tabWidthConstraints: [NSLayoutConstraint] = {
            guard !paneTabButtons.isEmpty else { return [] }
            let first = paneTabButtons[0]
            let count = CGFloat(paneTabButtons.count)
            let shouldEnforceMinWidth = paneTabButtons.count > 1
            var constraints: [NSLayoutConstraint] = []
            for button in paneTabButtons {
                let equalShare = button.widthAnchor.constraint(
                    equalTo: tabScrollView.widthAnchor,
                    multiplier: 1.0 / count
                )
                equalShare.priority = .defaultHigh
                let maxWidth = button.widthAnchor.constraint(lessThanOrEqualToConstant: Self.tabMaxWidth)
                constraints.append(contentsOf: [equalShare, maxWidth])
                if shouldEnforceMinWidth {
                    let minWidth = button.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.tabMinWidth)
                    minWidth.priority = .required
                    constraints.append(minWidth)
                }
                if button !== first {
                    let sameWidth = button.widthAnchor.constraint(equalTo: first.widthAnchor)
                    sameWidth.priority = .defaultHigh
                    constraints.append(sameWidth)
                }
            }
            return constraints
        }()

        inlineAddButton.configure(symbolName: "plus", accessibilityLabel: "Add pane tab", active: false, theme: theme, compact: true)
        inlineAddButton.identifier = NSUserInterfaceItemIdentifier("pane-tab-add-\(paneStack.id.rawValue)")
        inlineAddButton.onPress = {
            try? onCreatePaneTab()
        }
        tabStrip.addArrangedSubview(inlineAddButton)

        pinnedAddButton.configure(symbolName: "plus", accessibilityLabel: "Add pane tab", active: false, theme: theme, compact: true)
        pinnedAddButton.identifier = NSUserInterfaceItemIdentifier("pane-tab-add-pinned-\(paneStack.id.rawValue)")
        pinnedAddButton.onPress = {
            try? onCreatePaneTab()
        }
        pinnedAddButton.translatesAutoresizingMaskIntoConstraints = false
        pinnedAddButton.isHidden = true

        tabScrollView.translatesAutoresizingMaskIntoConstraints = false
        tabScrollView.hasHorizontalScroller = false
        tabScrollView.hasVerticalScroller = false
        tabScrollView.autohidesScrollers = true
        tabScrollView.drawsBackground = false
        tabScrollView.borderType = .noBorder
        tabScrollView.horizontalScrollElasticity = .allowed
        tabScrollView.verticalScrollElasticity = .none
        // Allow XCUITest to reach PaneTabButton children directly without the scroll view
        // intercepting the hit test.
        tabScrollView.setAccessibilityElement(false)
        tabScrollView.documentView = tabStrip
        tabScrollView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tabScrollView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            tabStrip.topAnchor.constraint(equalTo: tabScrollView.contentView.topAnchor),
            tabStrip.bottomAnchor.constraint(equalTo: tabScrollView.contentView.bottomAnchor),
            tabStrip.leadingAnchor.constraint(equalTo: tabScrollView.contentView.leadingAnchor),
            tabScrollView.heightAnchor.constraint(equalToConstant: ShellLayoutMetrics.paneHeaderHeight - 1),
        ])

        content.addArrangedSubview(tabScrollView)
        addSubview(pinnedAddButton)
        addSubview(content)
        NSLayoutConstraint.activate(tabWidthConstraints)

        let trailingToSuperview = content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8)
        let trailingToPinned = content.trailingAnchor.constraint(equalTo: pinnedAddButton.leadingAnchor, constant: -4)
        self.contentTrailingToSuperviewConstraint = trailingToSuperview
        self.contentTrailingToPinnedConstraint = trailingToPinned

        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            trailingToSuperview,
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            pinnedAddButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            pinnedAddButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        updateAddButtonMode()
    }

    func scrollActiveTabToVisible() {
        guard let activeButton = paneTabButtons.first(where: { $0.isActivePaneTab }) else {
            return
        }
        let targetRect = activeButton.convert(activeButton.bounds, to: tabStrip)
        tabScrollView.contentView.scrollToVisible(targetRect)
        tabScrollView.reflectScrolledClipView(tabScrollView.contentView)
    }

    override func layout() {
        super.layout()
        updateAddButtonMode()
    }

    private func updateAddButtonMode() {
        guard bounds.width > 0 else {
            return
        }

        // Measure using the strip content width while inline add is present.
        let overflow = tabStrip.fittingSize.width > tabScrollView.contentView.bounds.width + 1

        inlineAddButton.isHidden = overflow
        pinnedAddButton.isHidden = !overflow

        contentTrailingToSuperviewConstraint?.isActive = !overflow
        contentTrailingToPinnedConstraint?.isActive = overflow
    }

    func insertionIndex(forWindowPoint windowPoint: NSPoint) -> Int {
        let pointInTabStrip = tabStrip.convert(windowPoint, from: nil)
        for (index, button) in paneTabButtons.enumerated() {
            let frame = button.convert(button.bounds, to: tabStrip)
            if pointInTabStrip.x < frame.midX {
                return index
            }
        }
        return paneTabButtons.count
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

extension WorkspaceShellTheme {
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
