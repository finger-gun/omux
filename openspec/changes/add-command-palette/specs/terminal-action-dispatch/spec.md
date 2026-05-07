## ADDED Requirements

### Requirement: Action dispatch SHALL expose palette-visible action metadata
Terminal action dispatch SHALL expose metadata for supported shortcut-backed OpenMUX actions that are safe to discover and invoke from the command palette, without exposing terminal-engine implementation types.

#### Scenario: Palette discovers shortcut-backed action
- **WHEN** command mode requests available shortcut-backed actions
- **THEN** action dispatch returns OpenMUX-native action identifiers, titles, categories, enabled state, and shortcut labels where available

#### Scenario: Palette metadata avoids Ghostty leakage
- **WHEN** the palette receives action metadata
- **THEN** the metadata contains OpenMUX-native values and no raw AppKit event objects, Ghostty enums, or terminal-engine payload structs

### Requirement: Palette command invocation SHALL use action dispatch
Shortcut-backed command palette selections SHALL invoke supported actions through the same action dispatch path as direct keyboard shortcuts.

#### Scenario: Palette invokes same action as shortcut
- **WHEN** the user selects a shortcut-backed command from command mode
- **THEN** OpenMUX dispatches the same supported action identifier that the effective shortcut would dispatch

#### Scenario: Disabled action is not dispatched
- **WHEN** the user attempts to invoke a palette action result that is disabled in the current context
- **THEN** OpenMUX does not dispatch the action and surfaces the disabled state through palette feedback
