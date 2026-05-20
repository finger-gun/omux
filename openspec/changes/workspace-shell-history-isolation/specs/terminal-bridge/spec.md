## ADDED Requirements

### Requirement: Bridge SHALL preserve workspace shell environment values
The terminal bridge SHALL apply workspace shell history and workspace context environment values from OpenMUX-native session descriptors without interpreting them or replacing them with bridge-owned state.

#### Scenario: Workspace environment reaches terminal command
- **WHEN** app-shell code attaches a session containing workspace context and shell history environment values
- **THEN** the terminal command receives those values in its launch environment

#### Scenario: Bridge does not own workspace history policy
- **WHEN** a session descriptor omits `HISTFILE`
- **THEN** the bridge attaches the session without inventing a workspace history value
