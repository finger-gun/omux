## MODIFIED Requirements

### Requirement: Terminal hosting uses AppKit-first integration
The system SHALL host terminal surfaces within an AppKit-first application shell, with SwiftUI limited to non-terminal chrome where it does not control terminal interaction semantics, and with real pane surfaces embedded as native AppKit-hosted views. Sidebar terminal navigation SHALL restore native focus to the selected hosted terminal surface.

#### Scenario: Terminal surfaces stay in native view ownership
- **WHEN** a terminal pane is displayed in the desktop application
- **THEN** the terminal surface is hosted within an AppKit-owned interaction model that preserves native focus, menus, event routing, and accessibility expectations

#### Scenario: Sidebar terminal click restores terminal focus
- **WHEN** the user clicks a sidebar terminal metadata row
- **THEN** the selected hosted terminal pane becomes the active first-responder target after the workspace shell refreshes

## ADDED Requirements

### Requirement: App menus SHALL separate workspace, pane, and view responsibilities
The native macOS shell SHALL organize menu actions by OpenMUX-native responsibility so model actions are discoverable without crowding the View menu.

#### Scenario: Workspace actions live in Workspace menu
- **WHEN** the app builds its main menu
- **THEN** workspace lifecycle, workspace movement, previous-workspace, and direct workspace jump actions appear under a Workspace menu

#### Scenario: Pane actions live in Pane menu
- **WHEN** the app builds its main menu
- **THEN** split, remove-pane, pane-tab, and pane navigation actions appear under a Pane menu

#### Scenario: View menu remains for chrome visibility
- **WHEN** the app builds its main menu
- **THEN** the View menu contains visual shell/chrome controls such as toggling the workspace column rather than workspace or pane model actions

#### Scenario: Menu split preserves shortcuts
- **WHEN** keybindings are applied or rebound
- **THEN** the moved menu items keep shortcuts from the shared keybinding registry
