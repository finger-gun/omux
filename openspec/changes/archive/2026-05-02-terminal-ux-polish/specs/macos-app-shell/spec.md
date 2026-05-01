## ADDED Requirements

### Requirement: Transparent titlebar preserves native double-click zoom
Workspace windows SHALL preserve native macOS double-click titlebar zoom/maximize behavior while using the transparent full-size-content titlebar appearance.

#### Scenario: Titlebar double-click requests window zoom
- **WHEN** the user double-clicks the workspace window titlebar or unified titlebar background region
- **THEN** OpenMUX invokes the native window zoom behavior for that window

#### Scenario: Titlebar appearance remains integrated
- **WHEN** a workspace window is displayed
- **THEN** the titlebar region remains visually integrated with the shell background
