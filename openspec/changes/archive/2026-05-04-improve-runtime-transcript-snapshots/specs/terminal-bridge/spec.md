## ADDED Requirements

### Requirement: Runtime session snapshots SHALL include bounded terminal text when available
The terminal bridge SHALL populate runtime-backed session snapshots with bounded terminal text captured from the hosted surface when the runtime can provide text. The bridge SHALL expose this text through OpenMUX-native snapshot values and SHALL NOT expose terminal-engine text, point, selection, or buffer types outside `OmuxTerminalBridge`.

#### Scenario: Snapshot contains runtime text
- **WHEN** app-shell code requests a session snapshot for a live Ghostty-backed pane whose surface can provide terminal text
- **THEN** the returned OpenMUX-native snapshot includes bounded rendered text derived from that surface instead of an empty placeholder transcript

#### Scenario: Snapshot text is bounded
- **WHEN** the available terminal text exceeds the snapshot text limits
- **THEN** the returned snapshot text is truncated to those limits and the bridge records truncation through OpenMUX-native metadata or an equivalent bounded-text result

#### Scenario: Snapshot capture remains bridge-owned
- **WHEN** app-shell, control-plane, hook, or CLI code consumes a runtime session snapshot
- **THEN** that code consumes OpenMUX-native snapshot fields and does not import `CGhostty` or reference raw Ghostty text APIs

### Requirement: Runtime session snapshots SHALL represent unavailable text explicitly
The terminal bridge SHALL distinguish unavailable terminal text from an available empty terminal. The bridge SHALL avoid fabricating transcript, current-input, or rendered-text values when the runtime cannot provide text for a pane.

#### Scenario: Text capture unavailable
- **WHEN** a live runtime surface exists but terminal text capture fails or is unsupported
- **THEN** the bridge returns a snapshot with explicit unavailable text state or empty text paired with an unavailable reason rather than fabricated terminal output

#### Scenario: Empty terminal remains valid
- **WHEN** terminal text capture succeeds and the terminal has no available text
- **THEN** the bridge represents the snapshot as available empty text rather than a capture failure

## MODIFIED Requirements

### Requirement: The bridge exposes bounded terminal history snapshots
The terminal bridge SHALL expose an OpenMUX-native operation for reading bounded text snapshots from live terminal sessions. The operation SHALL include scrollback history and active terminal text when the renderer can provide them. The same bounded text semantics SHALL be usable by live session snapshots, control-plane history, command output context, and persistence callers. The operation SHALL support caller-supplied maximum byte and line limits and SHALL report whether the returned text was truncated.

#### Scenario: Bridge captures bounded text
- **WHEN** app-shell code requests a history snapshot for a live terminal session with byte and line limits
- **THEN** the bridge returns text bounded by those limits and reports line count, byte count, and truncation status

#### Scenario: Bridge reports unavailable history
- **WHEN** the runtime cannot provide terminal text for a live pane
- **THEN** the bridge returns an explicit unavailable result rather than throwing away the pane metadata at the control-plane layer

#### Scenario: Shared bounded text semantics
- **WHEN** live snapshots, command output context, history requests, or persistence request terminal text for the same pane
- **THEN** they use the same bridge-owned bounded text semantics for truncation, empty text, and unavailable state
