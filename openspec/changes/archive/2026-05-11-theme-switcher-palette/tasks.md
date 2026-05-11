## 1. Data Model

- [x] 1.1 Add `isActive: Bool` field to `CommandPaletteResult` in `OmuxCore/CommandPalette.swift` (default `false`)
- [x] 1.2 Add `.themeSwitch` case to `CommandPaletteInvocationTarget` in `OmuxCore/CommandPalette.swift`

## 2. Configuration Coordinator

- [x] 2.1 Add `setTheme(identifier:) -> Bool` to `OpenMUXConfigurationCoordinator` — reads config, mutates `theme.name`, writes file, fires `onThemeChange`; returns `false` if theme identifier is unknown

## 3. Command Descriptor

- [x] 3.1 Add `builtin-switch-theme.json`
- [x] 3.2 Wire `theme.switch` builtin target

## 4. Sub-Palette Mode on CommandPaletteView

- [x] 4.1 Add `SubPaletteMode` enum to `CommandPaletteView`
- [x] 4.2 Add `subPalettePreviewHandler`, `subPaletteCommitHandler`, `subPaletteRevertHandler` callbacks
- [x] 4.3 Add `enterThemeSubPalette(originalTheme:)` method
- [x] 4.4 Add `exitSubPalette()` method
- [x] 4.5 Update `cancelOperation` handler
- [x] 4.6 Update `updateSelection(to:)` to call preview handler
- [x] 4.7 Update `invokeSelectedResult()` to call commit handler

## 5. Active Indicator in Result Row

- [x] 5.1 Add `isActive` support to `CommandPaletteResultRow` — add a `NSImageView` checkmark (`checkmark` SF Symbol, accent color) pinned to trailing edge
- [x] 5.2 Show/hide checkmark based on `result.isActive` in `applyPresentation()`
- [x] 5.3 Update title label trailing constraint to account for checkmark width when active

## 6. Wiring in WorkspaceWindowController

- [x] 6.1 Handle `.themeSwitch` invocation target in the `invokeResult` closure
- [x] 6.2 Set `subPalettePreviewHandler` on the palette view
- [x] 6.3 Set `subPaletteCommitHandler` on the palette view
- [x] 6.4 Set revert behavior: on sub-palette exit without commit, call `updateTheme(originalTheme)`

## 7. Theme Result Provider

- [x] 7.1 Add a `themeResults(query:activeIdentifier:)` static method to `CommandPaletteSearch` in `OmuxCore`
- [x] 7.2 Use this method in `enterThemeSubPalette` to supply the sub-palette result provider

## 8. Build & Smoke Test

- [x] 8.1 Build the project with `swift build` — resolve any compile errors
- [ ] 8.2 Manually verify: open palette → type `>switch theme` → select → theme list appears with active checkmark → arrow keys preview → Enter persists → ESC reverts and returns to command list
