## ADDED Requirements

### Requirement: Extension-pane lifecycle SHALL be hook-observable
The system SHALL expose extension-pane lifecycle transitions through stable OpenMUX hooks so external tools can react to extension-pane creation, update, and close outcomes without polling workspace state.

#### Scenario: Created extension pane is hook-observable
- **WHEN** an extension pane is created successfully
- **THEN** OpenMUX invokes `extension-pane-created` with workspace, tab, pane, plugin, content-kind, and presentation metadata when available

#### Scenario: Updated extension pane is hook-observable
- **WHEN** an extension pane update succeeds
- **THEN** OpenMUX invokes `extension-pane-updated` identifying the updated pane and owning plugin

#### Scenario: Closed extension pane is hook-observable
- **WHEN** an extension pane closes successfully
- **THEN** OpenMUX invokes `extension-pane-closed` identifying the closed pane and owning plugin
