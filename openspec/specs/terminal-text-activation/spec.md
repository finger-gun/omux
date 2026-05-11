# terminal-text-activation Specification

## Purpose
TBD - created by archiving change add-terminal-text-activation. Update Purpose after archive.
## Requirements
### Requirement: Terminal text activation SHALL require an intentional modifier gesture
OpenMUX SHALL activate terminal text only when the user performs a documented modifier-click gesture and SHALL preserve normal terminal behavior for plain pointer clicks.

#### Scenario: Command-click activates text
- **WHEN** a user Command-clicks visible terminal text in a terminal pane
- **THEN** OpenMUX attempts to identify and activate the token under the pointer

#### Scenario: Plain click stays terminal-owned
- **WHEN** a user clicks terminal text without the activation modifier
- **THEN** OpenMUX forwards the pointer event to the terminal runtime for focus, selection, TUI, or mouse-reporting behavior

#### Scenario: Command-hover indicates activatable text
- **WHEN** a user holds Command while hovering terminal text that OpenMUX can handle
- **THEN** OpenMUX shows a pointer affordance without forwarding synthetic clicks or changing plain terminal pointer behavior

### Requirement: Terminal text activation SHALL emit OpenMUX-native context
OpenMUX SHALL emit terminal text activation context using OpenMUX-native IDs and payload fields rather than terminal-engine structs.

#### Scenario: Activation event includes terminal context
- **WHEN** terminal text is activated
- **THEN** the event includes workspace ID, tab ID, pane ID, session ID, token text, modifiers, working directory, and resolved local path when available

#### Scenario: Runtime details remain behind bridge
- **WHEN** plugins, hooks, or app-shell code consume the activation event
- **THEN** they receive OpenMUX-native values and no libghostty pointer, text, or coordinate structs

### Requirement: Terminal text activation SHALL resolve local path tokens
OpenMUX SHALL resolve path-like activated text relative to the terminal pane's current or reported working directory.

#### Scenario: Relative Markdown path resolves
- **WHEN** the user activates `README.md` from a pane whose working directory is `/repo`
- **THEN** OpenMUX resolves the path to `/repo/README.md`

#### Scenario: Nonexistent path is not success-shaped
- **WHEN** the activated token does not resolve to a readable local file
- **THEN** OpenMUX emits the activation context but does not claim successful file handling

### Requirement: Markdown preview SHALL handle activated Markdown files when enabled
The bundled Markdown preview plugin SHALL handle activated readable `.md` and `.markdown` local files when the plugin is enabled.

#### Scenario: Activated Markdown opens preview
- **WHEN** the Markdown preview plugin is enabled and the user activates a readable Markdown file token
- **THEN** OpenMUX opens or updates a Markdown preview extension pane for that file

#### Scenario: Disabled Markdown plugin does not hijack activation
- **WHEN** the Markdown preview plugin is disabled and the user activates a Markdown file token
- **THEN** OpenMUX emits the activation event but does not open a Markdown preview pane

### Requirement: Terminal text activation SHALL be hook-observable
OpenMUX SHALL expose terminal text activation through the input hook category so external scripts and plugins can observe activated terminal text.

#### Scenario: Hook receives activation payload
- **WHEN** terminal text is activated
- **THEN** matching input hooks receive a `terminal-text-activated` invocation with token, cwd, resolved path, and modifier payload fields

