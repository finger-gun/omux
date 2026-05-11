# extension-content-panes Specification

## Purpose
TBD - created by archiving change add-markdown-preview-plugin. Update Purpose after archive.
## Requirements
### Requirement: Pane content SHALL distinguish terminal and extension panes
The system SHALL model pane content with an explicit OpenMUX-native content kind that distinguishes terminal-backed panes from extension-owned panes.

#### Scenario: Terminal pane keeps session identity
- **WHEN** a pane represents an interactive terminal
- **THEN** the pane content includes the terminal session descriptor needed to attach and target the live terminal session

#### Scenario: Extension pane has no terminal session
- **WHEN** a pane represents extension-owned content
- **THEN** the pane content includes an extension pane descriptor and does not require a terminal session descriptor

### Requirement: Extension panes SHALL participate in workspace layout
The system SHALL allow extension panes to appear inside workspace tabs, split-tree leaves, and pane-local tab stacks using the same OpenMUX pane identifiers and focus model as terminal panes.

#### Scenario: Extension pane opens beside terminal editor
- **WHEN** a caller requests an extension pane split from a focused terminal pane
- **THEN** the workspace layout contains the original terminal pane and the new extension pane as visible split content

#### Scenario: Extension pane can be focused
- **WHEN** a user or control-plane action focuses an extension pane
- **THEN** the workspace focus model records that pane as the focused pane without resolving a terminal session target

### Requirement: Extension pane rendering SHALL stay outside the terminal bridge
The system SHALL render extension panes through shell-owned content hosts and SHALL NOT route extension pane rendering through `OmuxTerminalBridge` or libghostty surfaces.

#### Scenario: Terminal bridge is not used for extension content
- **WHEN** an extension pane is rendered
- **THEN** no libghostty surface is created for that pane and no Ghostty-specific type is exposed to extension content

### Requirement: Extension panes SHALL support constrained local HTML content
The system SHALL support an extension pane content type for local preview HTML with host-enforced constraints for navigation and script-sensitive behavior.

#### Scenario: Preview HTML is displayed
- **WHEN** an extension pane receives local preview HTML content
- **THEN** the pane host renders the content within the pane area

#### Scenario: External link opens outside preview pane
- **WHEN** rendered preview content requests navigation to an external URL
- **THEN** OpenMUX opens the URL through the host operating system instead of navigating the preview pane as a browser

### Requirement: Extension pane failures SHALL render explicit placeholders
The system SHALL render an explicit placeholder for extension panes whose plugin is disabled, missing, or unable to provide content.

#### Scenario: Plugin disabled during restore
- **WHEN** a workspace containing an extension pane is restored and the pane's plugin is disabled
- **THEN** the layout restores with a placeholder explaining that the plugin is disabled

#### Scenario: Plugin update fails
- **WHEN** an extension pane update fails validation
- **THEN** the pane remains visible and reports the failure instead of silently switching to unrelated content

### Requirement: Extension pane persistence SHALL preserve layout intent
The system SHALL persist extension pane descriptors with workspace state so restored layouts can preserve the user's preview/tool-pane arrangement.

#### Scenario: Extension pane descriptor survives restart
- **WHEN** a workspace containing an extension pane is saved and restored
- **THEN** the restored pane has the same pane ID, title, plugin ID, content kind, and source metadata when available

### Requirement: Extension pane input SHALL NOT change terminal keyboard semantics
The system SHALL keep terminal input routing and encoding unchanged when extension panes are introduced, including ISO/EU layouts, Option/Alt behavior, right-Option semantics, dead keys, compose keys, text input, and IME integration.

#### Scenario: Terminal pane remains first-class input target
- **WHEN** a terminal pane is focused and the user types text using a keyboard layout with dead keys or Option combinations
- **THEN** the input pipeline delivers the same terminal input as it did before extension panes existed

#### Scenario: Preview pane receives non-terminal interaction
- **WHEN** an extension preview pane is focused and the user scrolls, selects text, or activates a link
- **THEN** the extension pane handles that interaction without sending text input to a terminal session

