## ADDED Requirements

### Requirement: Terminal cwd actions SHALL update durable pane state
The system SHALL apply translated terminal cwd actions to the owning OpenMUX pane's durable session working directory without exposing terminal-engine action payload types outside the terminal bridge boundary.

#### Scenario: Cwd action updates pane session directory
- **WHEN** the embedded terminal runtime reports a cwd change for a pane-backed session
- **THEN** OpenMUX updates that pane's `SessionDescriptor.workingDirectory` to the reported path before the next persistence snapshot

#### Scenario: Cwd action remains OpenMUX-native
- **WHEN** app shell, hooks, or control-plane code observes a cwd change
- **THEN** it receives OpenMUX-native pane/session IDs and path payloads rather than raw terminal-engine structs or enums
