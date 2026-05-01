# hooks-foundation Specification

## Purpose
TBD - created by archiving change macos-foundation. Update Purpose after archive.
## Requirements
### Requirement: The foundation defines stable hook categories
The system SHALL define initial hook categories for lifecycle, session, command, UI, and input events.

#### Scenario: Extension points are named and intentional
- **WHEN** a future feature or plugin needs to react to application behavior
- **THEN** it can target a documented hook category instead of relying on incidental internal coupling

### Requirement: Hooks are contracts, not implementation leaks
The system SHALL define hooks as stable behavioral contracts around OpenMUX concepts rather than exposing arbitrary internal objects or terminal-engine internals.

#### Scenario: Hook consumers depend on stable semantics
- **WHEN** a hook is invoked for external automation or future plugin behavior
- **THEN** the hook payload and lifecycle semantics are expressed in OpenMUX-native terms

### Requirement: External extensibility precedes embedded runtimes
The system SHALL support a foundation that is compatible with external hooks and plugin processes before introducing in-process scripting or WASM runtimes.

#### Scenario: Initial extensibility does not require embedded runtimes
- **WHEN** the foundation is implemented for first-phase automation
- **THEN** it can support external hook execution without requiring an embedded plugin engine inside the app process

### Requirement: Hook payloads support structured OpenMUX-native values
The hook foundation SHALL support structured payload values for hook invocations so terminal automation events can carry typed numbers, booleans, strings, arrays, objects, and nulls without flattening them to string-only metadata. Hook payload values SHALL be expressed in OpenMUX-native terms.

#### Scenario: Command-finished hook carries typed fields
- **WHEN** OpenMUX emits a hook for a terminal command-finished event
- **THEN** the hook payload can include typed fields such as numeric exit code and numeric duration without requiring string parsing by hook consumers

#### Scenario: Hook payload stays OpenMUX-native
- **WHEN** a hook consumer receives a payload derived from terminal action dispatch
- **THEN** the payload fields describe OpenMUX pane/session behavior rather than raw Ghostty action tags or Ghostty-owned structs
