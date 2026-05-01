## ADDED Requirements

### Requirement: Theme command supports interactive selection
The CLI SHALL allow users to run `omux theme` in an interactive terminal and select a theme with keyboard navigation instead of typing a number or name.

#### Scenario: Arrow selection applies highlighted theme
- **WHEN** `omux theme` runs with interactive stdin and stdout, the user moves the highlight to `nord`, and presses Enter
- **THEN** the CLI updates `~/.omux/config.toml` to set `[theme] name = "nord"` and requests a config reload

#### Scenario: Interactive selection can be cancelled
- **WHEN** `omux theme` runs with interactive stdin and stdout and the user presses Escape, `q`, or Ctrl-C
- **THEN** the CLI exits successfully without modifying the configured theme

### Requirement: Theme command remains scriptable
The CLI SHALL preserve the existing non-interactive and argument-based theme selection behavior.

#### Scenario: Explicit theme name still works
- **WHEN** the user runs `omux theme nord`
- **THEN** the CLI applies the `nord` theme without opening the interactive picker

#### Scenario: Non-TTY prompt still accepts typed input
- **WHEN** `omux theme` runs without an interactive terminal and receives `nord` as input
- **THEN** the CLI applies the `nord` theme

#### Scenario: Listing themes is unchanged
- **WHEN** the user runs `omux theme list`
- **THEN** the CLI prints available themes and does not open the interactive picker

### Requirement: Interactive picker restores terminal state
The CLI SHALL restore the original terminal input mode after the interactive picker completes, is cancelled, or fails.

#### Scenario: Raw mode is restored after Enter
- **WHEN** the user selects a theme with Enter
- **THEN** the CLI restores the terminal mode before applying the theme and returning

#### Scenario: Raw mode is restored after cancellation
- **WHEN** the user cancels the picker
- **THEN** the CLI restores the terminal mode before returning
