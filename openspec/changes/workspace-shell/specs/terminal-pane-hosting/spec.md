## ADDED Requirements

### Requirement: The shell SHALL host real terminal-backed panes
The system SHALL replace placeholder pane content with real terminal-backed panes hosted through the terminal bridge inside the native AppKit shell.

#### Scenario: Workspace window shows live terminal content
- **WHEN** a workspace is opened in the app
- **THEN** each visible pane hosts a real terminal surface rather than a placeholder label

### Requirement: Pane hosting SHALL use the existing bridge boundary
The system SHALL create and attach terminal surfaces for panes through the OpenMUX terminal bridge instead of directly embedding libghostty calls in higher-level shell code.

#### Scenario: Pane creation stays inside the bridge seam
- **WHEN** the shell creates a pane that needs terminal rendering
- **THEN** terminal surface creation and session attachment occur through the bridge boundary

### Requirement: Terminal panes SHALL receive normalized input
The system SHALL route terminal pane keyboard input through the normalized input pipeline before terminal dispatch.

#### Scenario: Live pane input uses the shared input model
- **WHEN** a user types into a focused terminal pane
- **THEN** the pane receives normalized OpenMUX key events rather than ad hoc raw event handling
