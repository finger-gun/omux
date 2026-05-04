## ADDED Requirements

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
