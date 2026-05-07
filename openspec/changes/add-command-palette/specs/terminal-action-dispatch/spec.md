## ADDED Requirements

### Requirement: Action dispatch SHALL expose palette-visible action metadata
Terminal action dispatch SHALL expose metadata for supported safe OpenMUX actions that are discoverable and invokable from the command palette, regardless of whether an action currently has an effective shortcut, without exposing terminal-engine implementation types. Built-in action command metadata MAY be declared in bundled JSON descriptors, but descriptor `command.target` values SHALL resolve to OpenMUX-native action identifiers before dispatch.

#### Scenario: Palette discovers safe action
- **WHEN** command mode requests available safe actions
- **THEN** action dispatch returns OpenMUX-native action identifiers, titles, categories, enabled state, match aliases, and shortcut labels where available

#### Scenario: Descriptor action target resolves to native action
- **WHEN** a bundled descriptor declares `command.kind` as `action`
- **THEN** OpenMUX validates `command.target` as a supported OpenMUX action identifier before exposing or invoking the result

#### Scenario: Palette metadata avoids Ghostty leakage
- **WHEN** the palette receives action metadata
- **THEN** the metadata contains OpenMUX-native values and no raw AppKit event objects, Ghostty enums, or terminal-engine payload structs

### Requirement: Palette command invocation SHALL use action dispatch
Command palette selections for OpenMUX actions SHALL invoke supported actions through the same action dispatch path as direct keyboard shortcuts.

#### Scenario: Palette invokes same action identifier as shortcut
- **WHEN** the user selects an OpenMUX action command from command mode
- **THEN** OpenMUX dispatches the same supported action identifier that an effective shortcut for that action would dispatch

#### Scenario: Disabled action is not dispatched
- **WHEN** the user attempts to invoke a palette action result that is disabled in the current context
- **THEN** OpenMUX does not dispatch the action and surfaces the disabled state through palette feedback
