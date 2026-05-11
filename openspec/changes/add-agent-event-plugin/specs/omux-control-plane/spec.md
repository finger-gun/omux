## ADDED Requirements

### Requirement: Control plane exposes pane status mutation
The control plane SHALL expose a provider-neutral operation for setting and clearing transient pane status through existing OpenMUX terminal selectors.

#### Scenario: Hook marks a pane working
- **WHEN** a client calls pane status with a pane selector and state `working`
- **THEN** OpenMUX records working progress for the resolved pane without sending text to the terminal

#### Scenario: Hook clears a pane status
- **WHEN** a client calls pane status with state `clear`
- **THEN** OpenMUX removes progress/status from the resolved pane

#### Scenario: Invalid target fails explicitly
- **WHEN** a pane status request cannot resolve its selector
- **THEN** OpenMUX returns a target-not-found error instead of choosing a different pane

### Requirement: CLI exposes pane-status automation
The `omux` CLI SHALL expose a `pane-status` command for hooks and plugins.

#### Scenario: Plugin marks focused pane status
- **WHEN** a plugin runs `omux pane-status --focused --state working --source plugin.example`
- **THEN** the CLI sends a pane status control-plane request for the focused terminal target

#### Scenario: Status metadata is accepted
- **WHEN** a plugin provides label, message, source, or progress value metadata
- **THEN** OpenMUX accepts the metadata for event payloads without requiring pane chrome to render it as text

### Requirement: Pane status changes are streamed as events
The control plane SHALL publish OpenMUX-native events when pane status changes.

#### Scenario: Status update appears on event stream
- **WHEN** pane status is set or cleared successfully
- **THEN** `omux events` subscribers receive a `pane.statusChanged` event with workspace, tab, pane, session, state, value, label, message, and source fields when available
