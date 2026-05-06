## ADDED Requirements

### Requirement: Workspace layout SHALL support non-terminal pane content
Workspace layout SHALL allow split-tree leaves and pane-local tab stacks to contain panes whose content is not backed by a terminal session.

#### Scenario: Split layout contains terminal and extension panes
- **WHEN** an extension pane is created beside a terminal pane
- **THEN** the workspace split tree preserves both panes in the same layout model without requiring the extension pane to own a terminal session

#### Scenario: Pane-local stack contains extension pane
- **WHEN** an extension pane is added to a pane-local tab stack
- **THEN** the stack can focus that pane while preserving sibling terminal panes in the same stack

### Requirement: Workspace layout operations SHALL preserve terminal-only target resolution
Workspace layout SHALL distinguish pane focus from terminal target resolution so actions that require a live terminal session fail explicitly when aimed at extension panes.

#### Scenario: Run command rejects extension pane target
- **WHEN** a caller targets an extension pane with a command-running action
- **THEN** OpenMUX returns a structured failure instead of silently choosing another terminal

#### Scenario: Split from extension pane is valid
- **WHEN** a caller requests a layout split from a focused extension pane
- **THEN** OpenMUX creates a new pane in the requested split location without needing terminal session state from the source pane

#### Scenario: Split pane containing extension content can be closed
- **WHEN** a workspace contains terminal and extension panes in separate split-tree leaves
- **THEN** pane close actions can remove either split pane and collapse the remaining layout without requiring pane-local tab siblings
