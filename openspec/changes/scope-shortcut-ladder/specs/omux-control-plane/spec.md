## ADDED Requirements

### Requirement: Control plane SHALL expose workspace close and pane remove commands
The local JSON-RPC control plane and `omux` CLI SHALL expose additive commands for closing workspaces and removing panes.

#### Scenario: CLI closes active workspace by default
- **WHEN** a user runs `omux workspace-close` without a workspace ID
- **THEN** the CLI requests closing the active workspace through the local control plane

#### Scenario: CLI closes explicit workspace
- **WHEN** a user runs `omux workspace-close <workspace-id>`
- **THEN** the CLI requests closing that workspace ID through the local control plane

#### Scenario: CLI removes focused pane by default
- **WHEN** a user runs `omux pane-remove` without a target selector
- **THEN** the CLI requests removal of the focused pane through the local control plane

#### Scenario: CLI removes targetable pane
- **WHEN** a user runs `omux pane-remove` with a supported terminal target selector
- **THEN** the CLI requests removal of the resolved pane through the local control plane and receives structured success or failure

#### Scenario: Existing creation commands remain available
- **WHEN** users invoke existing creation commands including `omux open`, `omux split`, and `omux pane-tab`
- **THEN** those commands continue to work without being replaced by the new close/remove commands
