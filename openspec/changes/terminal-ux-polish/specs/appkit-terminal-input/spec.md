## ADDED Requirements

### Requirement: Terminal panes paste dropped file paths
Runtime-backed and fallback terminal panes SHALL accept dropped file URLs and paste their paths as terminal input text without executing the paths.

#### Scenario: Dropped image file inserts path text
- **WHEN** the user drops an image file from Finder onto a focused terminal pane
- **THEN** OpenMUX sends the image file path as text input to that pane

#### Scenario: Dropped paths are shell-safe
- **WHEN** a dropped file path contains spaces or shell metacharacters
- **THEN** OpenMUX quotes or escapes the path before inserting it as terminal input text

### Requirement: Command-arrow navigation reaches terminal input
Focused terminal panes SHALL handle Command-Left and Command-Right as terminal line-boundary navigation while preserving other Command shortcuts as AppKit responder/menu commands.

#### Scenario: Command-Left moves to beginning of terminal input
- **WHEN** a terminal pane is focused and the user presses Command-Left
- **THEN** OpenMUX sends beginning-of-line terminal input for that pane

#### Scenario: Command-Right moves to end of terminal input
- **WHEN** a terminal pane is focused and the user presses Command-Right
- **THEN** OpenMUX sends end-of-line terminal input for that pane

#### Scenario: Standard command shortcuts remain shortcuts
- **WHEN** a terminal pane is focused and the user presses a standard shortcut such as Command-V
- **THEN** OpenMUX routes the shortcut through the existing AppKit responder command path
