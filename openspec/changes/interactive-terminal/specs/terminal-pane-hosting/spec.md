## MODIFIED Requirements

### Requirement: The shell SHALL host real terminal-backed panes
The system SHALL host directly interactive terminal-backed panes that accept focus and in-place user input through the native AppKit shell without requiring a separate command-entry modal.

#### Scenario: Workspace window shows an interactive pane
- **WHEN** a workspace is opened in the app and the user focuses a pane
- **THEN** the pane behaves like an interactive terminal surface rather than a transcript view with secondary input UI

### Requirement: Terminal panes SHALL receive normalized input
The system SHALL route terminal pane keyboard and text-input events through the normalized input pipeline before terminal dispatch, including direct typing, editing keys, and composition-sensitive text input.

#### Scenario: Focused pane accepts direct normalized input
- **WHEN** a user types, pastes, or edits text in a focused terminal pane
- **THEN** the pane receives normalized OpenMUX input routed into the live terminal session

## ADDED Requirements

### Requirement: Terminal panes SHALL react to live session resizing
The system SHALL propagate pane size changes to the owning live terminal session so prompts and wrapped output remain usable as the window or split layout changes.

#### Scenario: Split resize updates the interactive session
- **WHEN** the user resizes the window or a split pane
- **THEN** the pane notifies the terminal session of its updated size
