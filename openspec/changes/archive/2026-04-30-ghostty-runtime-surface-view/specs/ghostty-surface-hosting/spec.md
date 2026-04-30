## MODIFIED Requirements

### Requirement: Pane regions SHALL host bridge-owned libghostty surfaces
The system SHALL host each active terminal pane region using a libghostty-backed surface created and owned by `OmuxTerminalBridge`, with the vendored runtime-backed host path serving as the normal pane experience when the pinned dependency is available and any fallback host remaining a bridge-owned unavailable or recovery path.

#### Scenario: Visible pane region uses the vendored runtime host
- **WHEN** a pane becomes visible in the native workspace shell and the vendored runtime host is available
- **THEN** the pane region hosts a bridge-owned vendored libghostty-backed terminal surface instead of the bridge fallback host

### Requirement: Surface lifecycle SHALL stay coordinated with pane lifecycle
The system SHALL coordinate vendored runtime bootstrap, surface creation, session attachment, focus activation, resize updates, and teardown with pane lifecycle transitions without requiring higher-level modules to manage terminal-engine objects directly.

#### Scenario: Pane teardown removes its runtime-hosted surface
- **WHEN** a pane is closed or replaced in the workspace layout
- **THEN** the bridge coordinates teardown of the associated vendored runtime-hosted surface and attached session resources
