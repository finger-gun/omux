## ADDED Requirements

### Requirement: Registry-installed hooks SHALL use user hook directories
Registry-installed hook packages SHALL install executable handlers into the existing user hook directory layout under `~/.omux/hooks/<hook-name>/` and SHALL NOT introduce a separate runtime hook discovery path.

#### Scenario: Installed hook is locally discoverable
- **WHEN** OpenMUX installs a registry hook package for `terminal-command-finished`
- **THEN** the installed executable handlers appear under `~/.omux/hooks/terminal-command-finished/` and are discovered by the existing user hook discovery contract

#### Scenario: Runtime does not fetch registries
- **WHEN** OpenMUX emits a hook invocation
- **THEN** hook execution uses locally discovered handlers and does not contact remote registries
