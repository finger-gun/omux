import AppKit

/// A transparent `NSView` that relays mouse-down, drag, and mouse-up events to closures.
///
/// Used as drag handles and resize handles in floating pane modals. The view itself
/// does not interpret the events — callers provide the logic via the three callbacks.
@MainActor
class DraggableEventRelayView: NSView {
    var onMouseDownEvent: ((NSEvent) -> Void)?
    var onMouseDraggedEvent: ((NSEvent) -> Void)?
    var onMouseUpEvent: ((NSEvent) -> Void)?

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        onMouseDownEvent?(event)
    }

    override func mouseDragged(with event: NSEvent) {
        onMouseDraggedEvent?(event)
    }

    override func mouseUp(with event: NSEvent) {
        onMouseUpEvent?(event)
    }
}
