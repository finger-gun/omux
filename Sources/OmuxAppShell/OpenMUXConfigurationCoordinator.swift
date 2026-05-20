import Foundation
import OmuxConfig
import OmuxCore
import OmuxTerminalBridge
import OmuxTheme
import OmuxVault

@MainActor
struct OpenMUXPreparedConfiguration: Sendable {
    let theme: WorkspaceShellTheme
    let persistedScrollback: OmuxConfigTerminal.PersistedScrollback
    let panes: OmuxConfigUI.Panes
    let icons: OmuxConfigUI.Icons
    let markdownPreview: OmuxConfigPlugins.MarkdownPreview
    let aiStatus: OmuxConfigPlugins.AIStatus
    let agentSessions: VaultConfiguration
    let autoCheckUpdate: Bool
    let defaultWorkspaceRootPath: String
    let isolateShellHistory: Bool
    let keyBindingRegistry: OpenMUXKeyBindingRegistry
    let compiledConfigURL: URL?
    let compiledHash: String?
    let diagnostics: [OmuxConfigDiagnostic]

    init(
        theme: WorkspaceShellTheme,
        persistedScrollback: OmuxConfigTerminal.PersistedScrollback = OmuxConfigTerminal.PersistedScrollback(),
        panes: OmuxConfigUI.Panes = OmuxConfigUI.Panes(),
        icons: OmuxConfigUI.Icons = OmuxConfigUI.Icons(),
        markdownPreview: OmuxConfigPlugins.MarkdownPreview = OmuxConfigPlugins.MarkdownPreview(),
        aiStatus: OmuxConfigPlugins.AIStatus = OmuxConfigPlugins.AIStatus(),
        agentSessions: VaultConfiguration = VaultConfiguration(),
        autoCheckUpdate: Bool = true,
        defaultWorkspaceRootPath: String,
        isolateShellHistory: Bool = OmuxConfigWorkspace.defaultIsolateShellHistory,
        keyBindingRegistry: OpenMUXKeyBindingRegistry,
        compiledConfigURL: URL?,
        compiledHash: String?,
        diagnostics: [OmuxConfigDiagnostic]
    ) {
        self.theme = theme
        self.persistedScrollback = persistedScrollback
        self.panes = panes
        self.icons = icons
        self.markdownPreview = markdownPreview
        self.aiStatus = aiStatus
        self.agentSessions = agentSessions
        self.autoCheckUpdate = autoCheckUpdate
        self.defaultWorkspaceRootPath = defaultWorkspaceRootPath
        self.isolateShellHistory = isolateShellHistory
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
    var onShellHistoryIsolationChange: ((Bool) -> Void)?
    var onPersistedScrollbackChange: ((OmuxConfigTerminal.PersistedScrollback) -> Void)?
    var onPaneConfigurationChange: ((OmuxConfigUI.Panes) -> Void)?
    var onIconConfigurationChange: ((OmuxConfigUI.Icons) -> Void)?
    var onMarkdownPreviewConfigurationChange: ((OmuxConfigPlugins.MarkdownPreview) -> Void)?
    var onAIStatusConfigurationChange: ((OmuxConfigPlugins.AIStatus) -> Void)?
    var onAgentSessionsConfigurationChange: ((VaultConfiguration) -> Void)?
    var onKeyBindingsChange: ((OpenMUXKeyBindingRegistry) -> Void)?
    var onDiagnosticsChange: (([OmuxConfigDiagnostic]) -> Void)?

    private let bridge: GhosttyTerminalBridge
    private let evaluator: OmuxConfigurationEvaluator
    private let reloadLock = NSLock()
    private let stateLock = NSLock()
    private var currentTheme: WorkspaceShellTheme
    private var currentDefaultWorkspaceRootPath: String
    private var currentIsolateShellHistory: Bool
    private var currentPersistedScrollback: OmuxConfigTerminal.PersistedScrollback
    private var currentPanes: OmuxConfigUI.Panes
    private var currentIcons: OmuxConfigUI.Icons
    private var currentMarkdownPreview: OmuxConfigPlugins.MarkdownPreview
    private var currentAIStatus: OmuxConfigPlugins.AIStatus
    private var currentAgentSessions: VaultConfiguration
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
        self.currentIsolateShellHistory = initialState.isolateShellHistory
        self.currentPersistedScrollback = initialState.persistedScrollback
        self.currentPanes = initialState.panes
        self.currentIcons = initialState.icons
        self.currentMarkdownPreview = initialState.markdownPreview
        self.currentAIStatus = initialState.aiStatus
        self.currentAgentSessions = initialState.agentSessions
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
                panes: evaluation.config.ui.panes,
                icons: evaluation.config.ui.icons,
                markdownPreview: evaluation.config.plugins.markdownPreview,
                aiStatus: evaluation.config.plugins.aiStatus,
                agentSessions: VaultConfiguration(config: evaluation.config.agentSessions),
                autoCheckUpdate: evaluation.config.autoCheckUpdate,
                defaultWorkspaceRootPath: evaluation.config.workspace.defaultRootPath,
                isolateShellHistory: evaluation.config.workspace.isolateShellHistory,
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
                panes: evaluation.config.ui.panes,
                icons: evaluation.config.ui.icons,
                markdownPreview: evaluation.config.plugins.markdownPreview,
                aiStatus: evaluation.config.plugins.aiStatus,
                agentSessions: VaultConfiguration(config: evaluation.config.agentSessions),
                autoCheckUpdate: evaluation.config.autoCheckUpdate,
                defaultWorkspaceRootPath: evaluation.config.workspace.defaultRootPath,
                isolateShellHistory: evaluation.config.workspace.isolateShellHistory,
                keyBindingRegistry: keyBindingRegistry,
                compiledConfigURL: fileURL,
                compiledHash: output.hash,
                diagnostics: evaluation.diagnostics
            )
        } catch {
            return OpenMUXPreparedConfiguration(
                theme: shellTheme,
                persistedScrollback: evaluation.config.terminal.persistedScrollback,
                panes: evaluation.config.ui.panes,
                icons: evaluation.config.ui.icons,
                markdownPreview: evaluation.config.plugins.markdownPreview,
                aiStatus: evaluation.config.plugins.aiStatus,
                agentSessions: VaultConfiguration(config: evaluation.config.agentSessions),
                autoCheckUpdate: evaluation.config.autoCheckUpdate,
                defaultWorkspaceRootPath: evaluation.config.workspace.defaultRootPath,
                isolateShellHistory: evaluation.config.workspace.isolateShellHistory,
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

    func isolateShellHistory() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return currentIsolateShellHistory
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

    func paneConfiguration() -> OmuxConfigUI.Panes {
        stateLock.lock()
        defer { stateLock.unlock() }
        return currentPanes
    }

    /// Persists a new theme to the config file and fires `onThemeChange`.
    /// Returns `false` if the identifier is unknown or the write fails.
    @discardableResult
    func setTheme(identifier: String) -> Bool {
        // Validate the theme exists
        guard WorkspaceShellTheme.named(identifier) != nil else { return false }

        let configURL = OmuxConfigPaths.configFileURL
        let raw: String
        if FileManager.default.fileExists(atPath: configURL.path),
           let existing = try? String(contentsOf: configURL, encoding: .utf8) {
            raw = existing
        } else {
            // No config file — create a minimal one
            raw = OmuxConfigTemplate.starter(themeName: identifier)
            do {
                try FileManager.default.createDirectory(
                    at: configURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try raw.write(to: configURL, atomically: true, encoding: .utf8)
            } catch {
                return false
            }
            reload()
            return true
        }

        // Replace `name = "..."` inside [theme] section
        let updated = Self.setThemeName(in: raw, to: identifier)
        do {
            try FileManager.default.createDirectory(
                at: configURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try updated.write(to: configURL, atomically: true, encoding: .utf8)
        } catch {
            return false
        }
        reload()
        return true
    }

    /// Replaces `name = "..."` under the `[theme]` table in raw TOML text.
    /// If no `[theme]` section or `name` key exists, appends/inserts them.
    private static func setThemeName(in toml: String, to identifier: String) -> String {
        let escaped = identifier
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let newNameLine = "name = \"\(escaped)\""

        var lines = toml.components(separatedBy: "\n")
        var inThemeSection = false
        var themeNameLineIndex: Int? = nil
        var themeSectionStartIndex: Int? = nil

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "[theme]" {
                inThemeSection = true
                themeSectionStartIndex = i
                continue
            }
            if inThemeSection {
                if trimmed.hasPrefix("[") {
                    break
                }
                if trimmed.hasPrefix("name") {
                    let afterName = trimmed.dropFirst(4).trimmingCharacters(in: .whitespaces)
                    if afterName.hasPrefix("=") {
                        themeNameLineIndex = i
                    }
                }
            }
        }

        if let idx = themeNameLineIndex {
            // Replace existing name line
            lines[idx] = newNameLine
            return lines.joined(separator: "\n")
        }

        if let sectionStart = themeSectionStartIndex {
            // Insert name after [theme] header
            let insertAt = sectionStart + 1
            lines.insert(newNameLine, at: insertAt)
            return lines.joined(separator: "\n")
        }

        // No [theme] section — append it
        if lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == false {
            lines.append("")
        }
        lines.append("[theme]")
        lines.append(newNameLine)
        return lines.joined(separator: "\n")
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
                    isolateShellHistory: currentIsolateShellHistory,
                    persistedScrollback: currentPersistedScrollback,
                    panes: currentPanes,
                    icons: currentIcons,
                    markdownPreview: currentMarkdownPreview,
                    aiStatus: currentAIStatus,
                    agentSessions: currentAgentSessions,
                    keyBindingRegistry: currentKeyBindingRegistry
                )
            }
            let keyBindingRegistry = OpenMUXKeyBindingRegistry.effective(overrides: evaluation.config.keyBindings)
            let defaultWorkspaceRootPath = evaluation.config.workspace.defaultRootPath
            let isolateShellHistory = evaluation.config.workspace.isolateShellHistory
            let persistedScrollback = evaluation.config.terminal.persistedScrollback
            let panes = evaluation.config.ui.panes
            let icons = evaluation.config.ui.icons
            let markdownPreview = evaluation.config.plugins.markdownPreview
            let aiStatus = evaluation.config.plugins.aiStatus
            let agentSessions = VaultConfiguration(config: evaluation.config.agentSessions)
            let shouldRefresh = previousState.hash != output.hash || FileManager.default.fileExists(atPath: output.fileURL.path) == false
            let shouldApply = shouldRefresh
                || previousState.defaultWorkspaceRootPath != defaultWorkspaceRootPath
                || previousState.isolateShellHistory != isolateShellHistory
                || previousState.persistedScrollback != persistedScrollback
                || previousState.panes != panes
                || previousState.icons != icons
                || previousState.markdownPreview != markdownPreview
                || previousState.aiStatus != aiStatus
                || previousState.agentSessions != agentSessions
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
                currentIsolateShellHistory = isolateShellHistory
                currentPersistedScrollback = persistedScrollback
                currentPanes = panes
                currentIcons = icons
                currentMarkdownPreview = markdownPreview
                currentAIStatus = aiStatus
                currentAgentSessions = agentSessions
                currentKeyBindingRegistry = keyBindingRegistry
                currentCompiledConfigURL = fileURL
                currentCompiledHash = output.hash
                currentDiagnostics = diagnostics
            }
            publish(
                theme: shellTheme,
                defaultWorkspaceRootPath: defaultWorkspaceRootPath,
                isolateShellHistory: isolateShellHistory,
                persistedScrollback: persistedScrollback,
                panes: panes,
                icons: icons,
                markdownPreview: markdownPreview,
                aiStatus: aiStatus,
                agentSessions: agentSessions,
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
        publish(
            theme: nil,
            defaultWorkspaceRootPath: nil,
            isolateShellHistory: nil,
            persistedScrollback: nil,
            panes: nil,
            icons: nil,
            markdownPreview: nil,
            aiStatus: nil,
            agentSessions: nil,
            keyBindingRegistry: nil,
            diagnostics: diagnostics
        )
    }

    private func publish(
        theme: WorkspaceShellTheme?,
        defaultWorkspaceRootPath: String?,
        isolateShellHistory: Bool?,
        persistedScrollback: OmuxConfigTerminal.PersistedScrollback?,
        panes: OmuxConfigUI.Panes?,
        icons: OmuxConfigUI.Icons?,
        markdownPreview: OmuxConfigPlugins.MarkdownPreview?,
        aiStatus: OmuxConfigPlugins.AIStatus?,
        agentSessions: VaultConfiguration?,
        keyBindingRegistry: OpenMUXKeyBindingRegistry?,
        diagnostics: [OmuxConfigDiagnostic]
    ) {
        if let theme {
            onThemeChange?(theme)
        }
        if let defaultWorkspaceRootPath {
            onWorkspaceDefaultRootChange?(defaultWorkspaceRootPath)
        }
        if let isolateShellHistory {
            onShellHistoryIsolationChange?(isolateShellHistory)
        }
        if let persistedScrollback {
            onPersistedScrollbackChange?(persistedScrollback)
        }
        if let panes {
            onPaneConfigurationChange?(panes)
        }
        if let icons {
            onIconConfigurationChange?(icons)
        }
        if let markdownPreview {
            onMarkdownPreviewConfigurationChange?(markdownPreview)
        }
        if let aiStatus {
            onAIStatusConfigurationChange?(aiStatus)
        }
        if let agentSessions {
            onAgentSessionsConfigurationChange?(agentSessions)
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
