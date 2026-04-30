## MODIFIED Requirements

### Requirement: Native app shell owns workspace structure
The system SHALL provide a native macOS application shell that owns OpenMUX workspaces, windows, top-level tabs, pane stacks, local pane tabs, and focus relationships independently of the terminal engine.

#### Scenario: Workspace structure is modeled in app-level terms
- **WHEN** a developer creates or manipulates workspace structure
- **THEN** the system represents that structure using OpenMUX-native concepts rather than raw terminal-engine objects

### Requirement: App shell responsibilities remain separate from terminal rendering
The system SHALL keep shell responsibilities such as window lifecycle, top-level tab chrome, pane-stack-local tab chrome, pane layout, focus management, notifications, and workspace orchestration separate from terminal rendering and PTY behavior.

#### Scenario: Shell concerns do not require terminal-engine knowledge
- **WHEN** shell-level logic handles layout or focus behavior
- **THEN** that logic operates without requiring direct knowledge of terminal-engine internals
