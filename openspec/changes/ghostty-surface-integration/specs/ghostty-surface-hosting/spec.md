## ADDED Requirements

### Requirement: Pane regions SHALL host bridge-owned libghostty surfaces
The system SHALL host each active terminal pane region using a libghostty-backed surface created and owned by `OmuxTerminalBridge`, while keeping the containing workspace and pane-stack structure in OpenMUX-native shell code.

#### Scenario: Visible pane region uses a real terminal surface
- **WHEN** a pane becomes visible in the native workspace shell
- **THEN** the pane region hosts a bridge-owned libghostty-backed terminal surface instead of a shell-rendered transcript substitute

### Requirement: Surface hosts SHALL integrate with AppKit-first pane chrome
The system SHALL embed bridge-provided terminal surfaces inside an AppKit-first pane host so pane-stack tab chrome, focus behavior, menus, and accessibility remain native macOS responsibilities.

#### Scenario: Terminal surface lives inside native pane chrome
- **WHEN** a pane stack is rendered in the macOS app shell
- **THEN** the terminal surface is hosted within an AppKit-owned pane container rather than a browser or webview architecture

### Requirement: Surface lifecycle SHALL stay coordinated with pane lifecycle
The system SHALL coordinate surface creation, session attachment, focus activation, resize updates, and teardown with pane lifecycle transitions without requiring higher-level modules to manage terminal-engine objects directly.

#### Scenario: Pane teardown removes its hosted surface
- **WHEN** a pane is closed or replaced in the workspace layout
- **THEN** the bridge coordinates teardown of the associated hosted terminal surface and attached session resources
