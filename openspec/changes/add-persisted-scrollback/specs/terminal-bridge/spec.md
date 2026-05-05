## ADDED Requirements

### Requirement: The bridge SHALL apply session launch environment variables
The terminal bridge SHALL accept OpenMUX-native session environment values during terminal attachment and apply them to the hosted terminal surface command using the public Ghostty surface configuration environment mechanism. The bridge SHALL keep raw Ghostty environment structures confined to bridge-owned code.

#### Scenario: Session environment reaches terminal command
- **WHEN** app-shell code attaches a session with environment values
- **THEN** the terminal command receives those values in its launch environment

#### Scenario: Environment API does not leak Ghostty types
- **WHEN** app-shell code configures terminal launch environment
- **THEN** it uses OpenMUX-native `SessionDescriptor` values and does not import or construct raw Ghostty environment structures

### Requirement: The bridge SHALL support restored-pane replay launch
The terminal bridge SHALL support launching a restored pane through an OpenMUX-owned replay command that can emit saved scrollback before the user's shell starts. This replay launch behavior SHALL remain represented outside the bridge as OpenMUX-native session/replay metadata rather than raw Ghostty command details.

#### Scenario: Restored pane command can run before shell
- **WHEN** a restored pane has replay metadata
- **THEN** the bridge launches the replay path as the terminal command before the user's shell is exec'd

#### Scenario: Replay launch preserves shell identity
- **WHEN** replay completes for a restored pane
- **THEN** the resulting interactive process is the user's configured shell started as a login shell
