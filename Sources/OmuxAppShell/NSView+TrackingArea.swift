import AppKit

extension NSView {
    /// Creates and installs a fresh tracking area covering `bounds`, replacing `existing`.
    ///
    /// Prefer this over manually managing a stored `NSTrackingArea` property — it removes
    /// the old area, creates a new one with the given options, and stores it back.
    ///
    /// - Parameters:
    ///   - existing: In-out reference to the stored tracking area property. Pass `nil` on first call.
    ///   - options: Tracking area options. Defaults to `.mouseEnteredAndExited, .activeAlways`.
    func replaceTrackingArea(_ existing: inout NSTrackingArea?, options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]) {
        if let old = existing { removeTrackingArea(old) }
        guard !bounds.isEmpty else { return }
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        existing = area
    }
}
