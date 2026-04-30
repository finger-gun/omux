import AppKit

public enum OpenMUXApplication {
    @MainActor
    public static func main() {
        let application = NSApplication.shared
        let delegate = OpenMUXAppDelegate()
        application.setActivationPolicy(.regular)
        application.delegate = delegate
        application.activate(ignoringOtherApps: true)
        application.run()
    }
}
