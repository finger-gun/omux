## ADDED Requirements

### Requirement: Remote plugin commands SHALL preserve bundled plugin registration
Remote plugin registry commands SHALL preserve existing bundled and external plugin registration behavior, including Markdown preview command precedence and the current `omux plugins` picker when no remote-management subcommand is supplied.

#### Scenario: Bundled markdown preview remains registered
- **WHEN** remote plugin registry support is enabled
- **THEN** the bundled Markdown preview plugin remains registered under its existing command name and cannot be shadowed by an external or remote plugin package

#### Scenario: Existing picker remains default
- **WHEN** the user runs `omux plugins` with no subcommand
- **THEN** OpenMUX opens the existing plugin picker rather than performing remote registry discovery
