## ADDED Requirements

### Requirement: Workspace sessions SHALL isolate shell history by default
OpenMUX-created terminal sessions SHALL use workspace-scoped shell command history by default. All terminal panes and pane tabs inside the same workspace SHALL receive the same workspace history location, and sessions in different workspaces SHALL receive different history locations.

#### Scenario: New workspaces receive different shell history files
- **WHEN** OpenMUX opens two workspaces
- **THEN** each workspace's terminal session launch environment includes a different `HISTFILE` value

#### Scenario: Pane tabs share workspace history
- **WHEN** the user creates splits or pane tabs inside one workspace
- **THEN** the new terminal sessions receive the same `HISTFILE` value as the workspace's existing terminal sessions

#### Scenario: Restored workspace preserves workspace history scope
- **WHEN** OpenMUX restores saved workspaces after app restart
- **THEN** restored terminal sessions use the restored workspace's shell history location instead of another workspace's location

### Requirement: Workspace sessions SHALL expose workspace launch context
OpenMUX-created terminal sessions SHALL receive OpenMUX-native workspace context in their launch environment. The context SHALL include the workspace identifier, workspace root path, and workspace shell history path.

#### Scenario: Session launch includes workspace context
- **WHEN** OpenMUX launches a terminal session for a workspace
- **THEN** the session environment includes `OMUX_WORKSPACE_ID`, `OMUX_WORKSPACE_ROOT`, and `OMUX_WORKSPACE_HISTORY`

#### Scenario: Context follows target workspace
- **WHEN** OpenMUX creates a terminal session through a split, pane-tab creation, or workspace restore
- **THEN** the workspace context values correspond to the workspace that owns the session

### Requirement: Zsh sessions SHALL preserve workspace history after startup files
When shell history isolation is enabled for a zsh session, OpenMUX SHALL ensure normal zsh startup files can run while still reapplying the workspace shell history file after those startup files have had a chance to assign `HISTFILE`.

#### Scenario: Zsh startup overrides do not leak history across workspaces
- **WHEN** OpenMUX launches or restores a zsh-backed terminal session with shell history isolation enabled
- **THEN** the launched zsh session has startup context that reapplies `HISTFILE` to `OMUX_WORKSPACE_HISTORY` after normal zsh startup files are sourced
