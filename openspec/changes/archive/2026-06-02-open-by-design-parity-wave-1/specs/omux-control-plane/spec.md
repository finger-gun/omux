## MODIFIED Requirements

### Requirement: Event stream SHALL report extension-pane lifecycle events
The control-plane event stream SHALL report extension-pane lifecycle and update events using OpenMUX-native event names and identifiers.

#### Scenario: Extension pane created event
- **WHEN** an extension pane is created successfully
- **THEN** subscribers receive an event with workspace, tab, pane stack, pane, plugin ID, and content kind metadata

#### Scenario: Extension pane updated event
- **WHEN** extension pane content is updated successfully
- **THEN** subscribers receive an event identifying the updated pane and plugin

#### Scenario: Extension pane closed event
- **WHEN** an extension pane is closed successfully
- **THEN** subscribers receive an `extensionPane.closed` event identifying the closed pane and owning plugin

## ADDED Requirements

### Requirement: Event stream SHALL report successful config reload completion
The control-plane event stream SHALL report successful config apply/reload completion using the same local event surface used for other OpenMUX action events.

#### Scenario: Explicit config reload emits event
- **WHEN** `omux config reload` completes successfully
- **THEN** subscribers receive `config.reloaded` with source and applied-change payload fields

#### Scenario: Watched config reload emits event
- **WHEN** a watched config or active-theme change is applied successfully
- **THEN** subscribers receive the same `config.reloaded` event contract used by the explicit reload path
