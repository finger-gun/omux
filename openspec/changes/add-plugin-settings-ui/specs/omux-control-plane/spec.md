## ADDED Requirements

### Requirement: Control plane SHALL mediate extension-pane actions
The local control plane SHALL expose an app-internal operation for validated extension-pane actions so pane UI, app shell, and plugin command dispatch use a typed local contract.

#### Scenario: Validated pane action reaches control plane
- **WHEN** the app shell validates an extension-pane action
- **THEN** it sends a typed action request through the local control-plane path with pane ID, plugin ID, action name, and JSON payload

#### Scenario: Action dispatch fails
- **WHEN** the owning plugin command cannot be invoked or exits nonzero
- **THEN** the control plane reports a structured failure that can be shown in the extension pane

### Requirement: Control plane SHALL expose config read/apply operations
The local control plane SHALL support config read and apply operations used by the CLI and plugins, returning structured success, diagnostics, and reload status.

#### Scenario: Config apply succeeds through control plane
- **WHEN** a client submits valid config changes through the local control plane
- **THEN** the response reports the written path, reload status, and diagnostics

#### Scenario: Config apply fails through control plane
- **WHEN** a client submits invalid config changes through the local control plane
- **THEN** the response reports diagnostics and indicates that no config file replacement occurred
