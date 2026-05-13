## MODIFIED Requirements

### Requirement: Native app shell owns workspace structure
The system SHALL provide a native macOS application shell that owns OpenMUX workspaces, windows, tabs, pane stacks, local pane tabs, and focus relationships independently of the terminal engine, even when each visible pane region hosts a real libghostty-backed terminal surface.

#### Scenario: Workspace structure is modeled in app-level terms
- **WHEN** a developer creates or manipulates workspace structure
- **THEN** the system represents that structure using OpenMUX-native concepts rather than raw terminal-engine objects

#### Scenario: Frequent shell updates preserve focused pane continuity
- **WHEN** the app shell applies frequent non-structural workspace updates
- **THEN** OpenMUX preserves focused-pane continuity without resetting first-responder ownership away from the active pane

