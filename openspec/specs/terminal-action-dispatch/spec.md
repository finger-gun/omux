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

### Requirement: Command completion events carry OpenMUX-owned command context
Terminal action dispatch SHALL enrich command completion events with OpenMUX-owned command context when that context is available, without exposing terminal-engine payload structs outside the terminal bridge boundary.

#### Scenario: Command completion includes known command text
- **WHEN** a command completion event corresponds to a command OpenMUX sent through run-command
- **THEN** the OpenMUX-native event includes that command text

#### Scenario: Unknown command text is explicit
- **WHEN** command text is not available for a completion event
- **THEN** the OpenMUX-native event represents the command text as unavailable instead of fabricating a value

### Requirement: Command completion events include bounded output context
Terminal action dispatch SHALL attach bounded OpenMUX-owned output context to command completion events when available, and SHALL expose an explicit unavailable value when output context is not available. The output context SHALL be derived after terminal-engine action translation from OpenMUX-native runtime snapshot or history data, not from raw terminal-engine action payloads.

#### Scenario: Failure completion includes bounded output tail
- **WHEN** OpenMUX has a bounded output tail for a completed command
- **THEN** the command completion event exposes that tail as OpenMUX-owned text or an OpenMUX-owned output reference

#### Scenario: Output context is unavailable
- **WHEN** OpenMUX does not have output context for a completed command
- **THEN** the command completion event marks output context unavailable without buffering unbounded terminal history

#### Scenario: Output context uses bridge-owned snapshot text
- **WHEN** a command completion event is enriched after runtime action translation
- **THEN** OpenMUX derives output context from bounded OpenMUX-native snapshot or history data provided by the terminal bridge

#### Scenario: Output context does not leak terminal-engine payloads
- **WHEN** hooks or control-plane event subscribers consume command completion output context
- **THEN** they receive OpenMUX-native output context values rather than Ghostty action payloads, text structs, or point-selection types

### Requirement: Command failure is derived after terminal-engine translation
The system SHALL derive command-failure automation events from OpenMUX-native command completion data after terminal-engine action translation.

#### Scenario: Failure derivation avoids Ghostty leakage
- **WHEN** the app shell or hooks consume command-failure information
- **THEN** they consume OpenMUX-native exit code, duration, command, cwd, and output-context values rather than raw Ghostty action payloads

### Requirement: Terminal cwd actions SHALL update durable pane state
The system SHALL apply translated terminal cwd actions to the owning OpenMUX pane's durable session working directory without exposing terminal-engine action payload types outside the terminal bridge boundary.

#### Scenario: Cwd action updates pane session directory
- **WHEN** the embedded terminal runtime reports a cwd change for a pane-backed session
- **THEN** OpenMUX updates that pane's `SessionDescriptor.workingDirectory` to the reported path before the next persistence snapshot

#### Scenario: Cwd action remains OpenMUX-native
- **WHEN** app shell, hooks, or control-plane code observes a cwd change
- **THEN** it receives OpenMUX-native pane/session IDs and path payloads rather than raw terminal-engine structs or enums

### Requirement: Explicit terminal input actions SHALL emit OpenMUX-native input-sent events
Terminal action dispatch SHALL support an OpenMUX-native `terminal.inputSent` event for explicit input actions that OpenMUX successfully delivers to a hosted runtime surface.

#### Scenario: Action text input becomes input-sent event
- **WHEN** OpenMUX successfully delivers action-scoped text to a live terminal-backed pane
- **THEN** the system emits `terminal.inputSent` with OpenMUX-native workspace, tab, pane, session, text, and source fields

#### Scenario: Native typed input is not streamed
- **WHEN** a native terminal pane forwards user-typed text or normalized key input to Ghostty
- **THEN** OpenMUX does not emit per-character or per-key `terminal.inputSent` events

### Requirement: Input-sent payloads SHALL stay bridge-owned and OpenMUX-native
Input-sent dispatch SHALL NOT expose raw AppKit event objects, Ghostty input structs, or terminal-engine enums outside `OmuxTerminalBridge`.

#### Scenario: Input event avoids Ghostty leakage
- **WHEN** app shell, hooks, or control-plane code consumes `terminal.inputSent`
- **THEN** it receives only OpenMUX-native IDs and payload values rather than raw terminal-engine input objects

### Requirement: Input events SHALL NOT fabricate shell command text
Terminal action dispatch SHALL NOT treat terminal title changes, prompt rendering, scrollback text, or accumulated input fragments as authoritative shell command submissions.

#### Scenario: Title change remains presentation event
- **WHEN** the terminal runtime emits `terminal.titleChanged` with a value that resembles a command
- **THEN** OpenMUX continues to publish it as title metadata and does not derive command text from that title

#### Scenario: IME input is not command-parsed
- **WHEN** a user enters text through IME composition, dead keys, Option-produced layout text, paste, or shell editing shortcuts
- **THEN** OpenMUX forwards input through the runtime input path without emitting input-sent fragments or reconstructing a command line

