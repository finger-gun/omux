## ADDED Requirements

### Requirement: Themes style shell chrome and terminal palettes together
The system SHALL define themes as cohesive token sets that style both shell chrome and terminal palettes. Theme application MUST cover shell background, text, border, accent, selection, and terminal color responsibilities through one theme contract.

#### Scenario: Applying a theme to the workspace
- **WHEN** the user applies a built-in OpenMUX theme
- **THEN** the shell chrome and terminal presentation update as one coherent visual system rather than as disconnected app and terminal colors

### Requirement: OpenMUX ships curated built-in themes
The system SHALL include curated built-in themes that make the shell visually complete without requiring custom configuration. Built-in presets MUST include an OpenMUX default theme and terminal-native presets such as Catppuccin, Gruvbox, and Sonokai.

#### Scenario: Choosing a built-in theme
- **WHEN** the user selects from built-in themes
- **THEN** the available choices include the OpenMUX default plus curated presets for Catppuccin, Gruvbox, and Sonokai

### Requirement: Theme behavior preserves terminal-native readability
Themes SHALL preserve readability and low-noise shell behavior suitable for long-running terminal use. Theme definitions MUST maintain clear text contrast, restrained chrome emphasis, and terminal-first visual hierarchy.

#### Scenario: Evaluating a theme in daily terminal use
- **WHEN** a theme is active across the workspace shell and terminal panes
- **THEN** the terminal remains easy to read and the shell chrome supports orientation without becoming visually distracting
