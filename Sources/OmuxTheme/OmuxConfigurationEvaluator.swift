import Foundation
import OmuxConfig

public struct OmuxConfigurationEvaluation: Sendable {
    public let config: OmuxConfig
    public let theme: OmuxTheme?
    public let compilerOutput: OmuxThemeCompilerOutput?
    public let diagnostics: [OmuxConfigDiagnostic]

    public init(
        config: OmuxConfig,
        theme: OmuxTheme?,
        compilerOutput: OmuxThemeCompilerOutput?,
        diagnostics: [OmuxConfigDiagnostic]
    ) {
        self.config = config
        self.theme = theme
        self.compilerOutput = compilerOutput
        self.diagnostics = diagnostics
    }

    public var hasErrors: Bool {
        diagnostics.contains(where: { $0.severity.isError })
    }
}

public struct OmuxConfigurationEvaluator {
    private let configLoader: OmuxConfigLoader
    private let themeRegistry: OmuxThemeRegistry
    private let compiler: OmuxThemeCompiler

    public init(
        configLoader: OmuxConfigLoader = OmuxConfigLoader(),
        themeRegistry: OmuxThemeRegistry = OmuxThemeRegistry(),
        compiler: OmuxThemeCompiler = OmuxThemeCompiler()
    ) {
        self.configLoader = configLoader
        self.themeRegistry = themeRegistry
        self.compiler = compiler
    }

    public func evaluate() -> OmuxConfigurationEvaluation {
        let configResult = configLoader.load()
        let requestedTheme = themeRegistry.loadTheme(named: configResult.config.theme.name)
        let shouldTryFallback = requestedTheme.theme == nil && configResult.config.theme.name != OmuxConfig.defaults.theme.name
        let fallbackTheme = shouldTryFallback
            ? themeRegistry.loadTheme(named: OmuxConfig.defaults.theme.name)
            : OmuxThemeLoadResult(theme: nil, diagnostics: [])

        let diagnostics = configResult.diagnostics + requestedTheme.diagnostics + fallbackTheme.diagnostics
        guard let theme = requestedTheme.theme ?? fallbackTheme.theme else {
            return OmuxConfigurationEvaluation(
                config: configResult.config,
                theme: nil,
                compilerOutput: nil,
                diagnostics: diagnostics
            )
        }

        let compilerOutput = compiler.compile(theme: theme, config: configResult.config)
        return OmuxConfigurationEvaluation(
            config: configResult.config,
            theme: theme,
            compilerOutput: compilerOutput,
            diagnostics: diagnostics + compilerOutput.diagnostics
        )
    }

    @discardableResult
    public func write(output: OmuxThemeCompilerOutput) throws -> URL {
        try compiler.write(output: output)
    }

    public func garbageCollect(activeFileURL: URL?) {
        compiler.garbageCollect(activeFileURL: activeFileURL)
    }
}
