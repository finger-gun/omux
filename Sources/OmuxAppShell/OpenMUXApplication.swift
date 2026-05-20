import AppKit

public enum OpenMUXApplication {
    /// Set to `true` when the `OMUX_UI_TEST` environment variable is `"1"`.
    ///
    /// Used to bypass Metal/GPU-dependent initialisation (libghostty surface creation)
    /// so the app can reach its main window on headless CI runners without a GPU.
    public static let isUITestMode: Bool = ProcessInfo.processInfo.environment["OMUX_UI_TEST"] == "1"

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
