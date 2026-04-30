## MODIFIED Requirements

### Requirement: The shell SHALL host real terminal-backed panes
The system SHALL replace the fallback text-view pane experience with real libghostty-backed panes hosted through the terminal bridge inside the native AppKit shell, while allowing any fallback host to remain a bridge-owned recovery path rather than the normal pane experience.

#### Scenario: Workspace window shows live terminal surface content
- **WHEN** a workspace is opened in the app
- **THEN** each visible pane hosts a real libghostty-backed terminal surface rather than a shell-rendered transcript substitute

### Requirement: Pane hosting SHALL use the existing bridge boundary
The system SHALL create, attach, focus, resize, and tear down terminal surfaces for panes through the OpenMUX terminal bridge instead of directly embedding libghostty calls in higher-level shell code.

#### Scenario: Pane creation stays inside the bridge seam
- **WHEN** the shell creates a pane that needs terminal rendering
- **THEN** terminal surface lifecycle and session attachment occur through the bridge boundary

### Requirement: Terminal panes SHALL receive normalized input
The system SHALL route terminal pane keyboard input through the normalized input pipeline before terminal dispatch, with any terminal-engine-specific translation occurring inside the bridge rather than in shell view code.

#### Scenario: Live pane input uses the shared input model
- **WHEN** a user types into a focused terminal pane
- **THEN** the pane receives OpenMUX-normalized keyboard intent before bridge-owned terminal translation is applied
