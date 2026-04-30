import Foundation
import OmuxConfig
import OmuxTerminalBridge
import OmuxTheme

@MainActor
struct OpenMUXPreparedConfiguration: Sendable {
    let theme: WorkspaceShellTheme
    let compiledConfigURL: URL?
    let compiledHash: String?
    let diagnostics: [OmuxConfigDiagnostic]
}

struct OpenMUXConfigurationReloadResult: Sendable {
    let applied: Bool
    let diagnostics: [OmuxConfigDiagnostic]
}

@MainActor
final class OpenMUXConfigurationCoordinator {
    var onThemeChange: ((WorkspaceShellTheme) -> Void)?
    var onDiagnosticsChange: (([OmuxConfigDiagnostic]) -> Void)?

    private let bridge: GhosttyTerminalBridge
    private let evaluator: OmuxConfigurationEvaluator
    private let reloadLock = NSLock()
    private let stateLock = NSLock()
    private var currentTheme: WorkspaceShellTheme
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
        self.currentCompiledConfigURL = initialState.compiledConfigURL
        self.currentCompiledHash = initialState.compiledHash
        self.currentDiagnostics = initialState.diagnostics
    }

    static func prepareInitialState(
        evaluator: OmuxConfigurationEvaluator = OmuxConfigurationEvaluator()
    ) -> OpenMUXPreparedConfiguration {
        let evaluation = evaluator.evaluate()
        let shellTheme = evaluation.theme.map(WorkspaceShellTheme.init(theme:)) ?? .defaultTheme

        guard let output = evaluation.compilerOutput else {
            return OpenMUXPreparedConfiguration(
                theme: shellTheme,
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
                compiledConfigURL: fileURL,
                compiledHash: output.hash,
                diagnostics: evaluation.diagnostics
            )
        } catch {
            return OpenMUXPreparedConfiguration(
                theme: shellTheme,
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
            let previousHash = stateLock.withLock { currentCompiledHash }
            let shouldRefresh = previousHash != output.hash || FileManager.default.fileExists(atPath: output.fileURL.path) == false
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
                currentCompiledConfigURL = fileURL
                currentCompiledHash = output.hash
                currentDiagnostics = diagnostics
            }
            publish(theme: shellTheme, diagnostics: diagnostics)
            return OpenMUXConfigurationReloadResult(applied: shouldRefresh, diagnostics: diagnostics)
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
        publish(theme: nil, diagnostics: diagnostics)
    }

    private func publish(theme: WorkspaceShellTheme?, diagnostics: [OmuxConfigDiagnostic]) {
        if let theme {
            onThemeChange?(theme)
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
