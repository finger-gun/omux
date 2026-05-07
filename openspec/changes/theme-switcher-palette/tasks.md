## 1. Data Model

- [ ] 1.1 Add `isActive: Bool` field to `CommandPaletteResult` in `OmuxCore/CommandPalette.swift` (default `false`)
- [ ] 1.2 Add `.themeSwitch` case to `CommandPaletteInvocationTarget` in `OmuxCore/CommandPalette.swift`

## 2. Configuration Coordinator

- [ ] 2.1 Add `setTheme(identifier:) -> Bool` to `OpenMUXConfigurationCoordinator` — reads config, mutates `theme.name`, writes file, fires `onThemeChange`; returns `false` if theme identifier is unknown

## 3. Command Descriptor

- [ ] 3.1 Add `builtin-switch-theme.json` command descriptor to `Resources/CommandPalette/Commands/` with title "Switch Theme", category action, and `command.kind = "builtin"`, `command.target = "theme.switch"`
- [ ] 3.2 Wire `theme.switch` builtin target in `CommandPaletteCommands.swift` to produce a result with `invocationTarget: .themeSwitch`

## 4. Sub-Palette Mode on CommandPaletteView

- [ ] 4.1 Add `SubPaletteMode` enum to `CommandPaletteView` with `none` and `theme(originalTheme: WorkspaceShellTheme)` cases
- [ ] 4.2 Add `subPalettePreviewHandler: ((String) -> Void)?` and `subPaletteCommitHandler: ((String) -> Void)?` callbacks to `CommandPaletteView`
- [ ] 4.3 Add `enterThemeSubPalette(originalTheme:)` method — sets mode, clears search, replaces result provider with theme list provider, updates section label
- [ ] 4.4 Add `exitSubPalette()` method — restores top-level result provider, clears search, resets section label, resets mode to `.none`
- [ ] 4.5 Update `cancelOperation` handler: if in sub-palette mode call `exitSubPalette()` + call revert callback; otherwise dismiss palette
- [ ] 4.6 Update `updateSelection(to:)`: when in sub-palette mode, call `subPalettePreviewHandler` with the highlighted result's id
- [ ] 4.7 Update `invokeSelectedResult()`: when in sub-palette mode, call `subPaletteCommitHandler` with the selected result's id instead of `invokeResult`

## 5. Active Indicator in Result Row

- [ ] 5.1 Add `isActive` support to `CommandPaletteResultRow` — add a `NSImageView` checkmark (`checkmark` SF Symbol, accent color) pinned to trailing edge
- [ ] 5.2 Show/hide checkmark based on `result.isActive` in `applyPresentation()`
- [ ] 5.3 Update title label trailing constraint to account for checkmark width when active

## 6. Wiring in WorkspaceWindowController

- [ ] 6.1 Handle `.themeSwitch` invocation target in the `invokeResult` closure — call `paletteView.enterThemeSubPalette(originalTheme: currentTheme)`; return `.inert` to prevent palette dismissal
- [ ] 6.2 Set `subPalettePreviewHandler` on the palette view — call `updateTheme(WorkspaceShellTheme.named(id) ?? currentTheme)` for live preview
- [ ] 6.3 Set `subPaletteCommitHandler` on the palette view — call `configurationCoordinator.setTheme(identifier:)` then dismiss
- [ ] 6.4 Set revert behavior: on sub-palette exit without commit, call `updateTheme(originalTheme)` to restore

## 7. Theme Result Provider

- [ ] 7.1 Add a `themeResults(query:activeIdentifier:)` static method to `CommandPaletteSearch` in `OmuxCore` — returns `[CommandPaletteResult]` with `isActive` set for the matching theme, filtered/ranked by query
- [ ] 7.2 Use this method in `enterThemeSubPalette` to supply the sub-palette result provider

## 8. Build & Smoke Test

- [ ] 8.1 Build the project with `swift build` — resolve any compile errors
- [ ] 8.2 Manually verify: open palette → type `>switch theme` → select → theme list appears with active checkmark → arrow keys preview → Enter persists → ESC reverts and returns to command list
