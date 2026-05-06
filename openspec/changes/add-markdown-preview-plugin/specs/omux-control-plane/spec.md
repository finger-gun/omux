## ADDED Requirements

### Requirement: Control plane SHALL expose extension-pane lifecycle operations
The local JSON-RPC control plane SHALL expose OpenMUX-native operations for creating, updating, focusing, and closing extension panes.

#### Scenario: Create extension pane returns identifiers
- **WHEN** a client creates an extension pane through the control plane
- **THEN** the response includes the workspace, tab, pane stack, pane, plugin ID, and content kind identifiers needed for later updates

#### Scenario: Update extension pane targets exact pane
- **WHEN** a client updates extension pane content by pane ID
- **THEN** the update applies only to that extension pane or returns a structured failure if the pane is not an extension pane

### Requirement: CLI SHALL expose extension-pane commands for scripts and plugins
The `omux` CLI SHALL expose commands that let scripts and plugin processes create and update extension panes through the public control plane.

#### Scenario: CLI creates extension pane
- **WHEN** a plugin process invokes the documented `omux` extension-pane create command
- **THEN** the CLI sends the corresponding JSON-RPC request and prints structured result data

#### Scenario: CLI updates extension pane
- **WHEN** a plugin process invokes the documented `omux` extension-pane update command with pane ID and content
- **THEN** the CLI sends the corresponding JSON-RPC request and prints structured result data

### Requirement: Terminal-mutating control-plane actions SHALL reject extension panes
Control-plane operations that require a live terminal session SHALL return structured errors when their target resolves to an extension pane.

#### Scenario: Send text to extension pane fails
- **WHEN** a client sends terminal text to an extension pane target
- **THEN** the control plane returns a structured failure and does not send the text to a different terminal

#### Scenario: Terminal history for extension pane is unavailable
- **WHEN** a client requests terminal history for an extension pane
- **THEN** the response reports explicit unavailability rather than empty terminal history as success

### Requirement: Event stream SHALL report extension-pane lifecycle events
The control-plane event stream SHALL report extension-pane lifecycle and update events using OpenMUX-native event names and identifiers.

#### Scenario: Extension pane created event
- **WHEN** an extension pane is created successfully
- **THEN** subscribers receive an event with workspace, tab, pane stack, pane, plugin ID, and content kind metadata

#### Scenario: Extension pane updated event
- **WHEN** extension pane content is updated successfully
- **THEN** subscribers receive an event identifying the updated pane and plugin
