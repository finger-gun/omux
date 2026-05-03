## ADDED Requirements

### Requirement: Native shell SHALL provide scoped structural shortcuts
The native macOS shell SHALL expose scoped structural shortcuts for pane tabs, pane splitting/removal, and workspace create/delete actions while preserving existing shortcuts.

#### Scenario: Pane remove shortcut is available
- **WHEN** the user invokes `Cmd+Shift+W`
- **THEN** the shell removes the active pane using the existing pane remove action

#### Scenario: Workspace close shortcut is available
- **WHEN** the user invokes `Cmd+Shift+N`
- **THEN** the shell closes/deletes the active workspace using the existing workspace delete action

#### Scenario: Existing structural shortcuts remain available
- **WHEN** the user invokes existing structural shortcuts such as `Cmd+D`, `Cmd+Shift+D`, `Cmd+T`, `Cmd+W`, or `Cmd+N`
- **THEN** the shell preserves their existing behavior

#### Scenario: Legacy Backspace pane remove shortcut is not available
- **WHEN** the user invokes `Cmd+Shift+Backspace`
- **THEN** the shell does not claim that chord as a pane-remove shortcut

#### Scenario: No duplicate pane-add shortcut is introduced
- **WHEN** the user invokes `Cmd+Shift+T`
- **THEN** the shell does not claim that chord as a pane-add shortcut
