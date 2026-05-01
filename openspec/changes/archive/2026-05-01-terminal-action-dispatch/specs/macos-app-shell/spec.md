## ADDED Requirements

### Requirement: The native shell surfaces terminal action outcomes without surrendering shell ownership
The native macOS shell SHALL consume supported terminal action events and apply the resulting user-visible behavior through OpenMUX-owned shell state, pane chrome, and native host integrations rather than delegating shell ownership to the terminal engine.

#### Scenario: Pane title updates stay shell-owned
- **WHEN** OpenMUX receives a supported title-change terminal event for a pane
- **THEN** the native shell updates the corresponding pane or tab label through OpenMUX-owned shell state rather than letting the terminal engine own shell chrome directly

#### Scenario: Native host side effects stay shell-owned
- **WHEN** OpenMUX receives a supported terminal event requesting URL opening, a desktop notification, or bell behavior
- **THEN** the native shell performs the host-side behavior through macOS-native integrations while preserving OpenMUX ownership of workspace and pane structure

### Requirement: The native shell surfaces pane status from supported terminal events
The native macOS shell SHALL surface pane-local status for supported terminal events including progress, child-exited state, and renderer health so the user can understand terminal state from OpenMUX chrome.

#### Scenario: Pane shows terminal progress state
- **WHEN** OpenMUX receives a supported progress-report terminal event for a pane
- **THEN** the shell updates pane-owned status or chrome for that pane without requiring Ghostty-owned app UI

#### Scenario: Pane shows session-ended or unhealthy state
- **WHEN** OpenMUX receives a supported child-exited or renderer-health terminal event for a pane
- **THEN** the shell updates pane-owned status to reflect the ended or unhealthy session state
