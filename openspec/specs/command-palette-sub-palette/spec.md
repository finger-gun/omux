# command-palette-sub-palette Specification

## Purpose
TBD - created by archiving change theme-switcher-palette. Update Purpose after archive.
## Requirements
### Requirement: Command palette supports sub-palette mode
The command palette SHALL support entering a sub-palette mode in which the primary result list is replaced by a contextual secondary list. Sub-palette mode SHALL have independent preview, confirm, and cancel semantics from the top-level palette.

#### Scenario: Entering sub-palette mode
- **WHEN** the user selects a command whose invocation target triggers sub-palette mode (e.g., "Switch Theme")
- **THEN** the result list is replaced in-place with the sub-palette items, the search field is cleared, and focus remains in the search field

#### Scenario: Searching within sub-palette
- **WHEN** the user types while in sub-palette mode
- **THEN** the sub-palette result list filters to matching items, using the same ranking as the top-level palette

#### Scenario: ESC exits sub-palette, not the whole palette
- **WHEN** the user presses ESC while in sub-palette mode
- **THEN** the sub-palette is dismissed, any preview is reverted, and the top-level command list is restored; a second ESC closes the palette entirely

#### Scenario: Enter confirms selection in sub-palette
- **WHEN** the user presses Enter on a highlighted sub-palette item
- **THEN** the sub-palette commit callback is invoked with the selected item, and the palette closes

### Requirement: Sub-palette supports live preview on navigation
The command palette SHALL invoke a preview callback when the selected item changes within sub-palette mode, allowing the caller to apply a reversible side effect.

#### Scenario: Arrow key triggers preview
- **WHEN** the user moves the selection up or down within the sub-palette
- **THEN** the preview callback is called with the newly highlighted item's identifier immediately

#### Scenario: Preview is reverted on cancel
- **WHEN** the user presses ESC in sub-palette mode after previewing one or more items
- **THEN** the revert callback is called, restoring the state to what it was before sub-palette mode was entered

### Requirement: Active item is visually distinguished in sub-palette
The command palette SHALL render sub-palette result rows with a visible active indicator when the result's `isActive` flag is true.

#### Scenario: Active item shows checkmark
- **WHEN** a sub-palette result has `isActive = true`
- **THEN** the row displays a checkmark glyph in the accent color on the trailing edge

#### Scenario: Only one item is active at a time
- **WHEN** the sub-palette result list is rendered
- **THEN** at most one row has `isActive = true`

