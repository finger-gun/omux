## ADDED Requirements

### Requirement: Workspace actions SHALL support direct ordered workspace switching
The system SHALL support direct switching to open workspaces by visible workspace order so keyboard-driven users can jump to the first nine visible workspaces without traversing the sidebar manually.

#### Scenario: User jumps to a numbered workspace
- **WHEN** the shell invokes a direct workspace-switch action for positions `1` through `9`
- **THEN** the corresponding visible workspace becomes active if one exists at that position

#### Scenario: Missing numbered workspace is ignored safely
- **WHEN** the shell invokes a direct workspace-switch action for a position that has no visible workspace
- **THEN** the active workspace remains unchanged

### Requirement: Workspace actions SHALL support previous-active workspace recall
The system SHALL track enough shell-owned workspace activation history to let the user return to the previous active workspace with a dedicated command.

#### Scenario: User returns to the previous active workspace
- **WHEN** the shell invokes the previous-workspace action after the user has switched from one workspace to another
- **THEN** the workspace that was active immediately before the current one becomes active again

#### Scenario: Previous-workspace command is inert without history
- **WHEN** the shell invokes the previous-workspace action before any prior workspace switch exists
- **THEN** the active workspace remains unchanged
