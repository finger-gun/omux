import AppKit

extension NSViewController {
    /// Presents a modal confirmation alert with a primary action button and a Cancel button.
    ///
    /// Displays as a sheet when a window is available; falls back to an application-modal dialog.
    ///
    /// - Parameters:
    ///   - title: The alert's `messageText`.
    ///   - message: Optional secondary `informativeText`.
    ///   - actionTitle: Title of the primary (first) button.
    ///   - alertStyle: The `NSAlert.Style`; defaults to `.warning`.
    ///   - accessoryView: Optional view to attach to the alert (e.g. a text field).
    ///   - action: Called when the user confirms.
    @MainActor
    func presentConfirmation(
        title: String,
        message: String? = nil,
        actionTitle: String,
        alertStyle: NSAlert.Style = .warning,
        accessoryView: NSView? = nil,
        action: @escaping @MainActor () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = title
        if let message { alert.informativeText = message }
        alert.alertStyle = alertStyle
        alert.addButton(withTitle: actionTitle)
        alert.addButton(withTitle: "Cancel")
        alert.accessoryView = accessoryView

        if let window = view.window {
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn { action() }
            }
            return
        }
        if alert.runModal() == .alertFirstButtonReturn { action() }
    }
}
