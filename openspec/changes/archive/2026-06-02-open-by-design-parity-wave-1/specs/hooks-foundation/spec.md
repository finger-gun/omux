## ADDED Requirements

### Requirement: Hooks SHALL observe workspace restore lifecycle
The hook foundation SHALL expose a `workspace-restored` lifecycle hook when OpenMUX successfully restores a workspace through the shared restore flow.

#### Scenario: Restore emits workspace-restored hook
- **WHEN** a workspace restore action succeeds
- **THEN** matching lifecycle hooks receive `workspace-restored` with the restored workspace identifier and restore-context payload fields when available

### Requirement: Hooks SHALL observe extension-pane lifecycle transitions
The hook foundation SHALL expose stable hooks for successful extension-pane lifecycle transitions: `extension-pane-created`, `extension-pane-updated`, and `extension-pane-closed`.

#### Scenario: Extension pane create emits hook
- **WHEN** an extension pane is created successfully
- **THEN** matching hooks receive `extension-pane-created` with workspace, tab, pane, plugin, and content-kind context when available

#### Scenario: Extension pane update emits hook
- **WHEN** an extension pane update succeeds
- **THEN** matching hooks receive `extension-pane-updated` identifying the updated pane and owning plugin

#### Scenario: Extension pane close emits hook
- **WHEN** an extension pane is closed successfully
- **THEN** matching hooks receive `extension-pane-closed` identifying the closed pane and owning plugin

### Requirement: Hooks SHALL observe pane status updates
The hook foundation SHALL expose a `pane-status-updated` hook when OpenMUX successfully sets, changes, or clears transient pane status through its public pane-status path.

#### Scenario: Pane status set emits hook
- **WHEN** OpenMUX records a working, idle, needs-input, or error pane status successfully
- **THEN** matching hooks receive `pane-status-updated` with the resolved pane context and normalized status payload

#### Scenario: Pane status clear emits hook
- **WHEN** OpenMUX clears pane status successfully
- **THEN** matching hooks receive `pane-status-updated` with the resolved pane context and a payload that explicitly indicates the cleared state

### Requirement: Hooks SHALL observe successful config reload completion
The hook foundation SHALL expose a `config-reloaded` lifecycle hook when OpenMUX successfully completes a config apply/reload pass through either explicit command invocation or watched file changes.

#### Scenario: Explicit reload emits config hook
- **WHEN** the user runs `omux config reload` and the apply/reload pass succeeds
- **THEN** matching hooks receive `config-reloaded` with source metadata identifying command-triggered reload

#### Scenario: Watched reload emits config hook
- **WHEN** OpenMUX applies a valid watched config or theme-file change successfully
- **THEN** matching hooks receive `config-reloaded` with source metadata identifying the watched reload path
