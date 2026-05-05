import Foundation
import OmuxConfig
import OmuxCore
import OmuxTerminalBridge
import OmuxTheme

@MainActor
struct OpenMUXPreparedConfiguration: Sendable {
    let theme: WorkspaceShellTheme
    let persistedScrollback: OmuxConfigTerminal.PersistedScrollback
    let icons: OmuxConfigUI.Icons
    let autoCheckUpdate: Bool
    let defaultWorkspaceRootPath: String
    let keyBindingRegistry: OpenMUXKeyBindingRegistry
    let compiledConfigURL: URL?
    let compiledHash: String?
    let diagnostics: [OmuxConfigDiagnostic]

    init(
        theme: WorkspaceShellTheme,
        persistedScrollback: OmuxConfigTerminal.PersistedScrollback = OmuxConfigTerminal.PersistedScrollback(),
        icons: OmuxConfigUI.Icons = OmuxConfigUI.Icons(),
        autoCheckUpdate: Bool = true,
        defaultWorkspaceRootPath: String,
        keyBindingRegistry: OpenMUXKeyBindingRegistry,
        compiledConfigURL: URL?,
        compiledHash: String?,
        diagnostics: [OmuxConfigDiagnostic]
    ) {
        self.theme = theme
        self.persistedScrollback = persistedScrollback
        self.icons = icons
        self.autoCheckUpdate = autoCheckUpdate
        self.defaultWorkspaceRootPath = defaultWorkspaceRootPath
        self.keyBindingRegistry = keyBindingRegistry
        self.compiledConfigURL = compiledConfigURL
        self.compiledHash = compiledHash
        self.diagnostics = diagnostics
    }
}

struct OpenMUXConfigurationReloadResult: Sendable {
    let applied: Bool
    let diagnostics: [OmuxConfigDiagnostic]
}

@MainActor
final class OpenMUXConfigurationCoordinator {
    var onThemeChange: ((WorkspaceShellTheme) -> Void)?
    var onWorkspaceDefaultRootChange: ((String) -> Void)?
    var onPersistedScrollbackChange: ((OmuxConfigTerminal.PersistedScrollback) -> Void)?
    var onIconConfigurationChange: ((OmuxConfigUI.Icons) -> Void)?
    var onKeyBindingsChange: ((OpenMUXKeyBindingRegistry) -> Void)?
    var onDiagnosticsChange: (([OmuxConfigDiagnostic]) -> Void)?

    private let bridge: GhosttyTerminalBridge
    private let evaluator: OmuxConfigurationEvaluator
    private let reloadLock = NSLock()
    private let stateLock = NSLock()
    private var currentTheme: WorkspaceShellTheme
    private var currentDefaultWorkspaceRootPath: String
    private var currentPersistedScrollback: OmuxConfigTerminal.PersistedScrollback
    private var currentIcons: OmuxConfigUI.Icons
    private var currentKeyBindingRegistry: OpenMUXKeyBindingRegistry
    private var currentCompiledConfigURL: URL?
    private var currentCompiledHash: String?
    private var currentDiagnostics: [OmuxConfigDiagnostic]

    init(
        bridge: GhosttyTerminalBridge,
        initialState: OpenMUXPreparedConfiguration,
        evaluator: OmuxConfigurationEvaluator = OmuxConfigurationEvaluator()
    ) {
        self.bridge = bridge
        self.evaluator = evaluator
        self.currentTheme = initialState.theme
        self.currentDefaultWorkspaceRootPath = initialState.defaultWorkspaceRootPath
        self.currentPersistedScrollback = initialState.persistedScrollback
        self.currentIcons = initialState.icons
        self.currentKeyBindingRegistry = initialState.keyBindingRegistry
        self.currentCompiledConfigURL = initialState.compiledConfigURL
        self.currentCompiledHash = initialState.compiledHash
        self.currentDiagnostics = initialState.diagnostics
    }

    static func prepareInitialState(
        evaluator: OmuxConfigurationEvaluator = OmuxConfigurationEvaluator()
    ) -> OpenMUXPreparedConfiguration {
        let evaluation = evaluator.evaluate()
        let shellTheme = evaluation.theme.map(WorkspaceShellTheme.init(theme:)) ?? .defaultTheme
        let keyBindingRegistry = OpenMUXKeyBindingRegistry.effective(overrides: evaluation.config.keyBindings)

        guard let output = evaluation.compilerOutput else {
            return OpenMUXPreparedConfiguration(
                theme: shellTheme,
                persistedScrollback: evaluation.config.terminal.persistedScrollback,
                icons: evaluation.config.ui.icons,
                autoCheckUpdate: evaluation.config.autoCheckUpdate,
                defaultWorkspaceRootPath: evaluation.config.workspace.defaultRootPath,
                keyBindingRegistry: keyBindingRegistry,
                compiledConfigURL: nil,
                compiledHash: nil,
                diagnostics: evaluation.diagnostics
            )
        }

        do {
            let fileURL = try evaluator.write(output: output)
            evaluator.garbageCollect(activeFileURL: fileURL)
            return OpenMUXPreparedConfiguration(
                theme: shellTheme,
                persistedScrollback: evaluation.config.terminal.persistedScrollback,
                icons: evaluation.config.ui.icons,
                autoCheckUpdate: evaluation.config.autoCheckUpdate,
                defaultWorkspaceRootPath: evaluation.config.workspace.defaultRootPath,
                keyBindingRegistry: keyBindingRegistry,
                compiledConfigURL: fileURL,
                compiledHash: output.hash,
                diagnostics: evaluation.diagnostics
            )
        } catch {
            return OpenMUXPreparedConfiguration(
                theme: shellTheme,
                persistedScrollback: evaluation.config.terminal.persistedScrollback,
                icons: evaluation.config.ui.icons,
                autoCheckUpdate: evaluation.config.autoCheckUpdate,
                defaultWorkspaceRootPath: evaluation.config.workspace.defaultRootPath,
                keyBindingRegistry: keyBindingRegistry,
                compiledConfigURL: nil,
                compiledHash: nil,
                diagnostics: evaluation.diagnostics + [
                    OmuxConfigDiagnostic(
                        severity: .error,
                        message: "Failed to write compiled Ghostty config: \(error.localizedDescription)"
                    ),
                ]
            )
        }
    }

    func diagnostics() -> [OmuxConfigDiagnostic] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return currentDiagnostics
    }

    func defaultWorkspaceRootPath() -> String {
        stateLock.lock()
        defer { stateLock.unlock() }
        return currentDefaultWorkspaceRootPath
    }

    func keyBindingRegistry() -> OpenMUXKeyBindingRegistry {
        stateLock.lock()
        defer { stateLock.unlock() }
        return currentKeyBindingRegistry
    }

    func iconConfiguration() -> OmuxConfigUI.Icons {
        stateLock.lock()
        defer { stateLock.unlock() }
        return currentIcons
    }

    @discardableResult
    func reload() -> OpenMUXConfigurationReloadResult {
        reloadLock.lock()
        defer { reloadLock.unlock() }

        let evaluation = evaluator.evaluate()
        guard let theme = evaluation.theme, let output = evaluation.compilerOutput else {
            updateDiagnostics(evaluation.diagnostics)
            return OpenMUXConfigurationReloadResult(applied: false, diagnostics: evaluation.diagnostics)
        }

        guard evaluation.hasErrors == false else {
            updateDiagnostics(evaluation.diagnostics)
            return OpenMUXConfigurationReloadResult(applied: false, diagnostics: evaluation.diagnostics)
        }

        do {
            let previousState = stateLock.withLock {
                (
                    hash: currentCompiledHash,
                    defaultWorkspaceRootPath: currentDefaultWorkspaceRootPath,
                    persistedScrollback: currentPersistedScrollback,
                    icons: currentIcons,
                    keyBindingRegistry: currentKeyBindingRegistry
                )
            }
            let keyBindingRegistry = OpenMUXKeyBindingRegistry.effective(overrides: evaluation.config.keyBindings)
            let defaultWorkspaceRootPath = evaluation.config.workspace.defaultRootPath
            let persistedScrollback = evaluation.config.terminal.persistedScrollback
            let icons = evaluation.config.ui.icons
            let shouldRefresh = previousState.hash != output.hash || FileManager.default.fileExists(atPath: output.fileURL.path) == false
            let shouldApply = shouldRefresh
                || previousState.defaultWorkspaceRootPath != defaultWorkspaceRootPath
                || previousState.persistedScrollback != persistedScrollback
                || previousState.icons != icons
                || previousState.keyBindingRegistry != keyBindingRegistry
            let fileURL: URL
            var diagnostics = evaluation.diagnostics

            if shouldRefresh {
                fileURL = try evaluator.write(output: output)
                diagnostics += try bridge.refreshCompiledConfig(path: fileURL)
                evaluator.garbageCollect(activeFileURL: fileURL)
            } else {
                fileURL = output.fileURL
            }

            let shellTheme = WorkspaceShellTheme(theme: theme)
            stateLock.withLock {
                currentTheme = shellTheme
                currentDefaultWorkspaceRootPath = defaultWorkspaceRootPath
                currentPersistedScrollback = persistedScrollback
                currentIcons = icons
                currentKeyBindingRegistry = keyBindingRegistry
                currentCompiledConfigURL = fileURL
                currentCompiledHash = output.hash
                currentDiagnostics = diagnostics
            }
            publish(
                theme: shellTheme,
                defaultWorkspaceRootPath: defaultWorkspaceRootPath,
                persistedScrollback: persistedScrollback,
                icons: icons,
                keyBindingRegistry: keyBindingRegistry,
                diagnostics: diagnostics
            )
            return OpenMUXConfigurationReloadResult(applied: shouldApply, diagnostics: diagnostics)
        } catch {
            let diagnostics = evaluation.diagnostics + [
                OmuxConfigDiagnostic(
                    severity: .error,
                    message: "Failed to reload configuration: \(error.localizedDescription)"
                ),
            ]
            updateDiagnostics(diagnostics)
            return OpenMUXConfigurationReloadResult(applied: false, diagnostics: diagnostics)
        }
    }

    private func updateDiagnostics(_ diagnostics: [OmuxConfigDiagnostic]) {
        stateLock.withLock {
            currentDiagnostics = diagnostics
        }
        publish(theme: nil, defaultWorkspaceRootPath: nil, persistedScrollback: nil, icons: nil, keyBindingRegistry: nil, diagnostics: diagnostics)
    }

    private func publish(
        theme: WorkspaceShellTheme?,
        defaultWorkspaceRootPath: String?,
        persistedScrollback: OmuxConfigTerminal.PersistedScrollback?,
        icons: OmuxConfigUI.Icons?,
        keyBindingRegistry: OpenMUXKeyBindingRegistry?,
        diagnostics: [OmuxConfigDiagnostic]
    ) {
        if let theme {
            onThemeChange?(theme)
        }
        if let defaultWorkspaceRootPath {
            onWorkspaceDefaultRootChange?(defaultWorkspaceRootPath)
        }
        if let persistedScrollback {
            onPersistedScrollbackChange?(persistedScrollback)
        }
        if let icons {
            onIconConfigurationChange?(icons)
        }
        if let keyBindingRegistry {
            OpenMUXShortcutClassifier.updateKeyBindings(keyBindingRegistry)
            onKeyBindingsChange?(keyBindingRegistry)
        }
        onDiagnosticsChange?(diagnostics)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
