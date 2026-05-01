## ADDED Requirements

### Requirement: Pane chrome avoids redundant identity rows
The system SHALL avoid rendering a persistent pane status row when the only available status text is the current working directory and that information is already represented by the pane title or sidebar metadata.

#### Scenario: Suppressing cwd-only duplication
- **WHEN** a pane has a title that already identifies the terminal and its only status text is the current working directory
- **THEN** the pane does not render an additional persistent cwd-only status row

### Requirement: Pane chrome preserves transient terminal status
The system SHALL continue to render transient terminal status information in pane chrome when that information communicates progress, exit status, renderer health, or other non-identity state.

#### Scenario: Showing active progress state
- **WHEN** a pane reports active terminal progress
- **THEN** the pane chrome renders a status row describing that progress

#### Scenario: Showing exit state
- **WHEN** a pane reports that the command exited with a nonzero code
- **THEN** the pane chrome renders a status row showing the exit state
