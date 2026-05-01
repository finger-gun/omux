## ADDED Requirements

### Requirement: Hook payloads support structured OpenMUX-native values
The hook foundation SHALL support structured payload values for hook invocations so terminal automation events can carry typed numbers, booleans, strings, arrays, objects, and nulls without flattening them to string-only metadata. Hook payload values SHALL be expressed in OpenMUX-native terms.

#### Scenario: Command-finished hook carries typed fields
- **WHEN** OpenMUX emits a hook for a terminal command-finished event
- **THEN** the hook payload can include typed fields such as numeric exit code and numeric duration without requiring string parsing by hook consumers

#### Scenario: Hook payload stays OpenMUX-native
- **WHEN** a hook consumer receives a payload derived from terminal action dispatch
- **THEN** the payload fields describe OpenMUX pane/session behavior rather than raw Ghostty action tags or Ghostty-owned structs

