## ADDED Requirements

### Requirement: The bridge exposes bounded terminal history snapshots
The terminal bridge SHALL expose an OpenMUX-native operation for reading bounded text snapshots from live terminal sessions. The operation SHALL include scrollback history and active terminal text when the renderer can provide them. The operation SHALL support caller-supplied maximum byte and line limits and SHALL report whether the returned text was truncated.

#### Scenario: Bridge captures bounded text
- **WHEN** app-shell code requests a history snapshot for a live terminal session with byte and line limits
- **THEN** the bridge returns text bounded by those limits and reports line count, byte count, and truncation status

#### Scenario: Bridge reports unavailable history
- **WHEN** the terminal surface is not live or the renderer cannot provide text
- **THEN** the bridge returns an explicit unavailable result rather than throwing away the pane metadata at the control-plane layer

### Requirement: Terminal history capture stays behind the bridge boundary
Direct terminal-engine APIs used to capture history SHALL remain confined to `OmuxTerminalBridge` implementation code. App-shell, CLI, hook, and control-plane code SHALL consume only OpenMUX-native history snapshot types.

#### Scenario: App shell consumes bridge abstraction
- **WHEN** the app shell resolves a pane for a history request
- **THEN** it obtains text through an OpenMUX bridge abstraction instead of importing or calling libghostty APIs directly

#### Scenario: CLI does not depend on renderer internals
- **WHEN** `omux history` prints captured terminal text
- **THEN** it receives OpenMUX-native history fields through the control plane and has no dependency on Ghostty symbols

### Requirement: History capture is distinct from terminal input
The terminal bridge SHALL keep history capture separate from terminal input APIs. Captured history text SHALL NOT be routed through text-input, command-running, paste, or initial-input operations.

#### Scenario: Captured history is not sent to shell
- **WHEN** OpenMUX captures terminal history for a pane
- **THEN** the bridge reads available terminal text without submitting that text to the pane's PTY or shell
