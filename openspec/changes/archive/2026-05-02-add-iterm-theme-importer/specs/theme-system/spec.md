## ADDED Requirements

### Requirement: Built-in themes can be generated from a manifest
The theme system SHALL provide a repository-maintained import path that transforms selected upstream Ghostty-format iTerm2 Color Schemes files into OpenMUX theme TOML resources. The import path SHALL be driven by a checked-in manifest that declares the OpenMUX theme name, upstream source name, and display name for each imported built-in theme.

#### Scenario: Manifest row generates theme resource
- **WHEN** the import script processes a manifest row for `tokyo-night-storm`
- **THEN** it writes an OpenMUX TOML theme resource named `tokyo-night-storm.toml` with the declared display name and complete token set

#### Scenario: Import source is inspectable
- **WHEN** a generated theme resource is opened for review
- **THEN** comments in the file identify the upstream repository, upstream ref, and upstream source theme name

### Requirement: Imported themes validate required source colors
The import path SHALL validate that each upstream source file contains `background`, `foreground`, `cursor-color`, `cursor-text`, `selection-background`, `selection-foreground`, and all ANSI `palette` entries from 0 through 15 before writing an OpenMUX theme file.

#### Scenario: Missing source color fails import
- **WHEN** an upstream source file omits `palette = 12=...`
- **THEN** the import script fails with an error naming the missing palette index and does not silently generate a partial OpenMUX theme

### Requirement: Imported themes derive OpenMUX chrome tokens deterministically
The import path SHALL copy terminal-facing tokens directly from upstream Ghostty colors and SHALL derive OpenMUX-only shell chrome tokens using deterministic rules documented in the importer or its adjacent documentation.

#### Scenario: Terminal colors are preserved
- **WHEN** an upstream source declares `background = #1a1b26`, `foreground = #c0caf5`, and `palette = 4=#7aa2f7`
- **THEN** the generated OpenMUX theme uses those exact values for `bg.canvas`, `fg.primary`, and `ansi.blue`

#### Scenario: Chrome tokens are derived predictably
- **WHEN** the same upstream source is imported twice with the same manifest and upstream ref
- **THEN** derived tokens such as `bg.elevated`, `border.subtle`, and `accent` are byte-identical in both generated files

## MODIFIED Requirements

### Requirement: Built-in themes ship as data
The system SHALL ship its built-in themes as TOML files bundled as package resources, not as hand-coded source constants. The built-in set SHALL include `monokai-soda` (default), `catppuccin`, `dracula`, `nord`, `gruvbox`, `one-dark`, `solarized-dark`, `solarized-light`, `tokyo-night-storm`, `github-dark`, `everforest-dark`, `ayu-mirage`, `cobalt2`, `doom-one`, `horizon`, `kanagawa-wave`, `rose-pine`, `flexoki-dark`, `catppuccin-macchiato`, `catppuccin-frappe`, `github-dark-dimmed`, `nightfox`, `carbonfox`, `duskfox`, `material-ocean`, `monokai-pro`, `gruvbox-material-dark`, and `tokyonight-moon`.

#### Scenario: Default theme on first run
- **WHEN** OpenMUX starts and no theme is configured
- **THEN** the active theme is `monokai-soda`

#### Scenario: Built-in theme is selectable by name
- **WHEN** `~/.omux/config.toml` sets `[theme] name = "nord"`
- **THEN** the system loads `nord` from bundled resources and applies it

#### Scenario: Imported built-in theme is selectable by name
- **WHEN** `~/.omux/config.toml` sets `[theme] name = "tokyo-night-storm"`
- **THEN** the system loads `tokyo-night-storm` from bundled resources and applies it
