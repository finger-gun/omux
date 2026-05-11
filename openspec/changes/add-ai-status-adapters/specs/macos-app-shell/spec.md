## ADDED Requirements

### Requirement: Native shell SHALL render adapter-reported pane status consistently
The native macOS shell SHALL render pane status reported by adapters through the same pane chrome, tab strip, and sidebar status surfaces used for terminal-native progress events.

#### Scenario: Adapter working status shows active orb
- **WHEN** an adapter reports `working` status for a pane
- **THEN** the native shell shows the same active progress affordance used for terminal-native working progress

#### Scenario: Adapter needs-input status shows attention orb
- **WHEN** an adapter reports `needs-input` status for a pane
- **THEN** the native shell shows an attention affordance that remains associated with that pane until status changes or idle-clear policy removes it

#### Scenario: Adapter status does not shift tab identity
- **WHEN** the native shell renders an adapter-reported status orb in a sidebar terminal row or pane tab
- **THEN** the status affordance does not reduce the space reserved for pane title and subtitle identity when existing leading gutter space is available

### Requirement: Adapter status SHALL preserve terminal-first interaction
Rendering adapter-reported status SHALL NOT alter terminal focus, keyboard routing, mouse routing, or text input dispatch.

#### Scenario: Status update does not steal focus
- **WHEN** an adapter reports a new pane status while the user is typing in any terminal pane
- **THEN** OpenMUX updates shell chrome without changing the focused pane or moving keyboard focus

#### Scenario: Status rendering is not an input handler
- **WHEN** a pane has adapter-reported status
- **THEN** the status rendering does not intercept IME composition, dead keys, Option/right-Option input, paste, or terminal mouse reporting
