import Foundation

@MainActor
protocol WorkspaceSidebarVisibilityStoring: AnyObject {
    var isSidebarVisible: Bool { get set }
}

@MainActor
final class WorkspaceSidebarVisibilityStore: WorkspaceSidebarVisibilityStoring {
    static let shared = WorkspaceSidebarVisibilityStore()

    private let defaults: UserDefaults
    private let key = "dev.fingergun.omux.sidebarVisible"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isSidebarVisible: Bool {
        get {
            if defaults.object(forKey: key) == nil {
                return true
            }
            return defaults.bool(forKey: key)
        }
        set {
            defaults.set(newValue, forKey: key)
        }
    }
}
