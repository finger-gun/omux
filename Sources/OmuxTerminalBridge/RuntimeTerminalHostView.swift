import AppKit
import Foundation
#if canImport(CGhostty)
import CGhostty
#else
typealias ghostty_input_mouse_state_e = Int32
let GHOSTTY_MOUSE_PRESS: ghostty_input_mouse_state_e = 1
let GHOSTTY_MOUSE_RELEASE: ghostty_input_mouse_state_e = 0
#endif
import OmuxCore

@MainActor
class RuntimeTerminalHostView: NSView, RuntimeTerminalInteractionConfiguring {
    private let normalizer = BridgeAppKitKeyEventNormalizer()
    private var paneID: PaneID?
    private var onFocus: (@MainActor (PaneID) -> Void)?
    private var isFocusedPane = false

    var normalizedKeyHandler: ((NormalizedKeyEvent) -> Void)?
    var committedTextHandler: ((String) -> Void)?
    var accumulatedTextHandler: ((NormalizedKeyEvent, String) -> Void)?
    var preeditHandler: ((String?) -> Void)?
    var imeRectProvider: (() -> NSRect)?
    var translatedKeyEventProvider: ((NSEvent) -> NSEvent)?
    var copyHandler: (() -> Void)?
    var pasteHandler: (() -> Void)?
    var selectAllHandler: (() -> Void)?
    var mouseButtonHandler: ((ghostty_input_mouse_state_e, Int, KeyModifiers) -> Bool)?
    var mousePositionHandler: ((CGPoint?, KeyModifiers) -> Void)?
    var mouseScrollHandler: ((Double, Double, Bool, NSEvent.Phase) -> Void)?
    var mousePressureHandler: ((Int, Double) -> Void)?

    private(set) var markedText = NSMutableAttributedString()
    private var keyTextAccumulator: [String]?
    private var trackingAreaRef: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    func configureHostedPane(
        paneID: PaneID,
        isFocused: Bool,
        onFocus: @escaping @MainActor (PaneID) -> Void
    ) {
        self.paneID = paneID
        self.isFocusedPane = isFocused
        self.onFocus = onFocus
    }

    func updateHostedPaneFocus(_ isFocused: Bool) {
        isFocusedPane = isFocused
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if isFocusedPane == false, let paneID {
            onFocus?(paneID)
        }
        _ = handleMouseButton(event, state: GHOSTTY_MOUSE_PRESS, buttonNumber: 0)
    }

    override func mouseUp(with event: NSEvent) {
        _ = handleMouseButton(event, state: GHOSTTY_MOUSE_RELEASE, buttonNumber: 0)
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if isFocusedPane == false, let paneID {
            onFocus?(paneID)
        }
        let handled = handleMouseButton(event, state: GHOSTTY_MOUSE_PRESS, buttonNumber: 1)
        if handled == false {
            super.rightMouseDown(with: event)
        }
    }

    override func rightMouseUp(with event: NSEvent) {
        let handled = handleMouseButton(event, state: GHOSTTY_MOUSE_RELEASE, buttonNumber: 1)
        if handled == false {
            super.rightMouseUp(with: event)
        }
    }

    override func otherMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if isFocusedPane == false, let paneID {
            onFocus?(paneID)
        }
        _ = handleMouseButton(event, state: GHOSTTY_MOUSE_PRESS, buttonNumber: Int(event.buttonNumber))
    }

    override func otherMouseUp(with event: NSEvent) {
        _ = handleMouseButton(event, state: GHOSTTY_MOUSE_RELEASE, buttonNumber: Int(event.buttonNumber))
    }

    override func mouseEntered(with event: NSEvent) {
        mousePositionHandler?(convert(event.locationInWindow, from: nil), KeyModifiers.appKitModifierFlags(event.modifierFlags))
    }

    override func mouseExited(with event: NSEvent) {
        mousePositionHandler?(nil, KeyModifiers.appKitModifierFlags(event.modifierFlags))
    }

    override func mouseMoved(with event: NSEvent) {
        mousePositionHandler?(convert(event.locationInWindow, from: nil), KeyModifiers.appKitModifierFlags(event.modifierFlags))
    }

    override func mouseDragged(with event: NSEvent) {
        mouseMoved(with: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        mouseMoved(with: event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        mouseMoved(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        mouseScrollHandler?(
            event.scrollingDeltaX,
            event.scrollingDeltaY,
            event.hasPreciseScrollingDeltas,
            event.momentumPhase
        )
    }

    override func pressureChange(with event: NSEvent) {
        mousePressureHandler?(event.stage, Double(event.pressure))
    }

    override func updateTrackingAreas() {
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [
                .activeInKeyWindow,
                .inVisibleRect,
                .mouseEnteredAndExited,
                .mouseMoved,
            ],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaRef = trackingArea

        super.updateTrackingAreas()
    }

    override func keyDown(with event: NSEvent) {
        let normalizedEvent = normalizer.normalize(event)
        if normalizedEvent.route == .shortcut {
            super.keyDown(with: event)
            return
        }

        let markedTextBefore = markedText.length > 0
        let translatedEvent = translatedKeyEventProvider?(event) ?? event
        keyTextAccumulator = []
        defer { keyTextAccumulator = nil }

        interpretKeyEvents([translatedEvent])
        syncPreedit(clearIfNeeded: markedTextBefore)

        if let list = keyTextAccumulator, list.isEmpty == false {
            for text in list {
                if let accumulatedTextHandler {
                    accumulatedTextHandler(normalizedEvent, text)
                } else {
                    committedTextHandler?(text)
                }
            }
            return
        }

        var eventToSend = normalizedEvent
        if markedText.length > 0 || markedTextBefore {
            eventToSend.route = .composition
            if markedText.length > 0 {
                eventToSend.text = nil
            }
        }
        normalizedKeyHandler?(eventToSend)
    }

    override func keyUp(with event: NSEvent) {
        normalizedKeyHandler?(normalizer.normalize(event))
    }

    override func flagsChanged(with event: NSEvent) {
        normalizedKeyHandler?(normalizer.normalize(event))
    }

    func hasMarkedText() -> Bool {
        markedText.length > 0
    }

    func markedRange() -> NSRange {
        guard markedText.length > 0 else { return NSRange() }
        return NSRange(location: 0, length: markedText.length)
    }

    func selectedRange() -> NSRange {
        NSRange()
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        switch string {
        case let value as NSAttributedString:
            markedText = NSMutableAttributedString(attributedString: value)
        case let value as String:
            markedText = NSMutableAttributedString(string: value)
        default:
            return
        }

        if keyTextAccumulator == nil {
            syncPreedit()
        }
    }

    func unmarkText() {
        guard markedText.length > 0 else {
            return
        }
        markedText.mutableString.setString("")
        syncPreedit()
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        guard range.length > 0, markedText.length > 0 else {
            return nil
        }
        return markedText
    }

    func characterIndex(for point: NSPoint) -> Int {
        0
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        imeRectProvider?() ?? .zero
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        var characters = ""
        switch string {
        case let value as NSAttributedString:
            characters = value.string
        case let value as String:
            characters = value
        default:
            return
        }

        unmarkText()

        if var accumulator = keyTextAccumulator {
            accumulator.append(characters)
            keyTextAccumulator = accumulator
            return
        }

        committedTextHandler?(characters)
    }

    override func doCommand(by selector: Selector) {
    }

    @IBAction func copy(_ sender: Any?) {
        if let copyHandler {
            copyHandler()
        }
    }

    @IBAction func paste(_ sender: Any?) {
        if let pasteHandler {
            pasteHandler()
        }
    }

    @IBAction override func selectAll(_ sender: Any?) {
        if let selectAllHandler {
            selectAllHandler()
        }
    }

    private func syncPreedit(clearIfNeeded: Bool = true) {
        if markedText.length > 0 {
            preeditHandler?(markedText.string)
        } else if clearIfNeeded {
            preeditHandler?(nil)
        }
    }

    private func handleMouseButton(
        _ event: NSEvent,
        state: ghostty_input_mouse_state_e,
        buttonNumber: Int
    ) -> Bool {
        mouseButtonHandler?(state, buttonNumber, KeyModifiers.appKitModifierFlags(event.modifierFlags)) ?? false
    }
}

extension RuntimeTerminalHostView: @preconcurrency NSTextInputClient {}
