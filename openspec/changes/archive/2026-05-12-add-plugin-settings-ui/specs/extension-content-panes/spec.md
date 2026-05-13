## ADDED Requirements

### Requirement: Extension panes SHALL support host-mediated plugin actions
The system SHALL allow extension pane content to submit structured actions to OpenMUX through a host-mediated bridge that validates pane identity, plugin ownership, action name, and payload shape before dispatch.

#### Scenario: Valid pane action is submitted
- **WHEN** a plugin-owned extension pane submits a valid action through the OpenMUX bridge
- **THEN** OpenMUX dispatches the action to the owning plugin with the pane ID, plugin ID, action name, and JSON payload

#### Scenario: Pane action uses wrong plugin
- **WHEN** an extension pane submits an action claiming a plugin ID that does not own the pane
- **THEN** OpenMUX rejects the action and does not invoke any plugin command

#### Scenario: Pane action payload is malformed
- **WHEN** extension pane content submits malformed or non-JSON action data
- **THEN** OpenMUX rejects the action and surfaces an explicit pane or diagnostic error

### Requirement: Extension pane actions SHALL preserve terminal input semantics
Interactive extension pane controls SHALL NOT change keyboard routing or text encoding for terminal panes, including ISO/EU layouts, Option/Alt behavior, right-Option semantics, dead keys, compose keys, text input, and IME integration.

#### Scenario: Terminal remains focused
- **WHEN** a terminal pane is focused and the user types with dead keys or Option combinations
- **THEN** the extension-pane action bridge does not observe or alter that input

#### Scenario: Extension pane form is focused
- **WHEN** a user types into a settings form inside an extension pane
- **THEN** the text is handled by the extension pane control and is not sent to any terminal session

### Requirement: Extension pane actions SHALL NOT execute shell text directly
The system SHALL NOT treat extension pane HTML, links, form submissions, or action payloads as shell text to execute.

#### Scenario: Action requests unsupported command
- **WHEN** an extension pane action payload contains shell text or an unsupported command request
- **THEN** OpenMUX rejects the action instead of executing the shell text
