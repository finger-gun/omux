## ADDED Requirements

### Requirement: Control plane SHALL expose pane navigation capabilities
The control plane SHALL expose capability-oriented JSON-RPC methods for cycling pane-local tabs and panes using OpenMUX-native workspace, tab, pane stack, pane, and session identifiers.

#### Scenario: Pane-local tab next operation returns focused context
- **WHEN** a client invokes the next pane-local tab operation
- **THEN** the response identifies the focused workspace, tab, pane stack, pane, and session after navigation

#### Scenario: Pane-local tab previous operation returns focused context
- **WHEN** a client invokes the previous pane-local tab operation
- **THEN** the response identifies the focused workspace, tab, pane stack, pane, and session after navigation

#### Scenario: Pane next operation returns focused context
- **WHEN** a client invokes the next pane operation
- **THEN** the response identifies the focused workspace, tab, pane stack, pane, and session after navigation

#### Scenario: Pane previous operation returns focused context
- **WHEN** a client invokes the previous pane operation
- **THEN** the response identifies the focused workspace, tab, pane stack, pane, and session after navigation

#### Scenario: Navigation target failure is explicit
- **WHEN** a navigation request cannot resolve a valid workspace, tab, pane stack, pane, or session target
- **THEN** the control plane returns a structured failure instead of silently choosing another target

### Requirement: CLI SHALL expose every new shared navigation action
The `omux` CLI SHALL expose commands for opening the configured default root and for cycling pane-local tabs and panes through the public control-plane contract.

#### Scenario: CLI opens configured root
- **WHEN** the user runs `omux open` without a path
- **THEN** the CLI sends a workspace open request that allows the app to resolve the configured default root

#### Scenario: CLI cycles pane-local tabs
- **WHEN** the user runs `omux pane-tab-next` or `omux pane-tab-prev`
- **THEN** the CLI invokes the corresponding pane-local tab navigation method through the control plane

#### Scenario: CLI cycles panes
- **WHEN** the user runs `omux pane-next` or `omux pane-prev`
- **THEN** the CLI invokes the corresponding pane navigation method through the control plane
