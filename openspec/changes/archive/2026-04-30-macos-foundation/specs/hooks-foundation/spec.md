## ADDED Requirements

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
