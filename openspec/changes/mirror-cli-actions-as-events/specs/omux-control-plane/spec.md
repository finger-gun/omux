## MODIFIED Requirements

### Requirement: The CLI controls the app through a local RPC contract
The system SHALL expose a local control plane between the OpenMUX desktop app and the `omux` CLI using JSON-RPC over a Unix domain socket for both capability requests and local event subscriptions.

#### Scenario: CLI operations use the public control boundary
- **WHEN** the `omux` CLI requests app-level behavior
- **THEN** it communicates through the local JSON-RPC control contract rather than private in-process coupling

#### Scenario: CLI event subscribers use the public control boundary
- **WHEN** the `omux` CLI subscribes to streamed OpenMUX events
- **THEN** it receives those events through the same local control-plane contract rather than a separate private transport

### Requirement: Terminal event contracts are defined in OpenMUX-native control-plane terms
The control plane SHALL define terminal event names and payload shapes in OpenMUX-native terms for local automation and streamed event delivery surfaces. These event contracts SHALL avoid Ghostty-specific enums, tags, and payload structs.

#### Scenario: Control-plane terminal event names are product-level contracts
- **WHEN** OpenMUX defines a control-plane event for terminal cwd, command completion, progress, or renderer health
- **THEN** the event name and payload shape are expressed in OpenMUX-native terms instead of Ghostty callback identifiers

#### Scenario: Terminal events remain stable inside a broader event stream
- **WHEN** terminal runtime events are published alongside shared action events through `omux events`
- **THEN** the `terminal.*` event meanings and payload fields remain stable because they are defined independently of the transport and of non-terminal event families

## ADDED Requirements

### Requirement: The control plane SHALL stream OpenMUX-native action events
The control plane SHALL stream OpenMUX-native event notifications for successful shared workspace, pane, tab, session, command, and notification actions through the same local event surface used by terminal runtime events.

#### Scenario: Subscriber observes a pane split action
- **WHEN** a shared pane split action succeeds
- **THEN** the control plane publishes a `pane.split` event with OpenMUX-native identifiers and payload fields

#### Scenario: Subscriber observes a restored workspace
- **WHEN** a shared workspace restore action succeeds
- **THEN** the control plane publishes a `workspace.restored` event through the local event stream
