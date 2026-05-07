## ADDED Requirements

### Requirement: Workspace actions SHALL support palette-driven workspace switching
Workspace/session actions SHALL expose enough workspace metadata for the command palette to search switchable workspaces and activate the selected workspace through the shared action model.

#### Scenario: Palette lists switchable workspaces
- **WHEN** the command palette opens in workspace mode
- **THEN** OpenMUX provides workspace results with stable workspace identifiers, display names, paths when available, and active state

#### Scenario: Palette switches selected workspace
- **WHEN** the user selects a workspace result
- **THEN** OpenMUX activates that workspace through the shared workspace/session action model and emits the corresponding success-shaped action event

#### Scenario: Missing workspace selection fails explicitly
- **WHEN** a palette selection references a workspace that no longer exists
- **THEN** OpenMUX returns a structured failure and leaves the active workspace unchanged

### Requirement: Workspace palette search SHALL not mutate terminal sessions
Workspace-mode palette search SHALL be read-only until the user selects a result.

#### Scenario: Typing a workspace query is read-only
- **WHEN** the user types in the palette search field without selecting a result
- **THEN** OpenMUX does not create, close, focus, or send input to any terminal session
