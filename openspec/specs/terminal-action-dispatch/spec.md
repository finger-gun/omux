# terminal-action-dispatch Specification

## Purpose
TBD - created by archiving change terminal-action-dispatch. Update Purpose after archive.

## Requirements

### Requirement: Supported terminal-engine upcalls are translated into OpenMUX-native terminal events
The system SHALL translate supported `libghostty` action upcalls into OpenMUX-native terminal action/event values before those values leave the terminal bridge boundary. OpenMUX-native values SHALL identify the terminal event kind and carry only OpenMUX-defined payload fields.

#### Scenario: Ghostty cwd change becomes an OpenMUX terminal event
- **WHEN** the embedded runtime emits a supported `PWD` action for a hosted surface
- **THEN** the bridge emits an OpenMUX-native terminal event describing a cwd change for the corresponding pane/session without exposing Ghostty enums or structs outside `OmuxTerminalBridge`

#### Scenario: Unsupported Ghostty types stay inside the bridge
- **WHEN** shell, hooks, or control-plane code consumes a terminal event produced by action dispatch
- **THEN** that code consumes only OpenMUX-native event kinds and payload values rather than raw `ghostty_action_tag_e` values or Ghostty payload structs

### Requirement: First-wave terminal actions are honored through OpenMUX-owned outcomes
The system SHALL honor a first wave of terminal actions consisting of `PWD`, `SET_TITLE`, `SET_TAB_TITLE`, `OPEN_URL`, `DESKTOP_NOTIFICATION`, `RING_BELL`, `COMMAND_FINISHED`, `PROGRESS_REPORT`, `SHOW_CHILD_EXITED`, and `RENDERER_HEALTH` by routing them to OpenMUX-owned shell, automation, or host-side behavior.

#### Scenario: Command completion reaches automation surfaces
- **WHEN** the embedded runtime emits `COMMAND_FINISHED` for a supported hosted surface
- **THEN** OpenMUX emits a structured command-finished terminal event that is available to shell-owned automation surfaces such as hooks and future control-plane event publication

#### Scenario: Progress report reaches pane-owned UI state
- **WHEN** the embedded runtime emits `PROGRESS_REPORT` for a supported hosted surface
- **THEN** OpenMUX updates pane-owned progress state in OpenMUX chrome rather than requiring Ghostty to own shell presentation

### Requirement: App-shell Ghostty actions remain rejected unless OpenMUX explicitly translates them
The system SHALL reject Ghostty actions that presume Ghostty owns windows, tabs, splits, fullscreen, config UX, or updates unless a future OpenMUX change explicitly maps a selected action into an OpenMUX-native command.

#### Scenario: Ghostty split request is not treated as layout ownership
- **WHEN** the embedded runtime emits a Ghostty app-shell action such as `NEW_SPLIT`, `NEW_TAB`, or `TOGGLE_FULLSCREEN`
- **THEN** OpenMUX rejects the action by default and retains ownership of workspace and shell structure
