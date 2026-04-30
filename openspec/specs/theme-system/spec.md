# theme-system Specification

## Purpose
Define the OpenMUX-owned theme model, built-in theme catalog, and Ghostty compilation behavior.

## Requirements

### Requirement: Themes are expressed as a fixed token vocabulary
The system SHALL define a fixed, documented set of design tokens that themes assign colors to. The token set SHALL include surface tokens (`bg.canvas`, `bg.surface`, `bg.elevated`), text tokens (`fg.primary`, `fg.secondary`, `fg.muted`), border tokens (`border.subtle`, `border.strong`), an `accent` token, terminal-only tokens (`cursor`, `cursor.text`, `selection.bg`, `selection.fg`), and the full ANSI 16-color palette (`ansi.black` through `ansi.brightWhite`). Both the AppKit shell renderer and the Ghostty configuration compiler SHALL consume the same tokens.

#### Scenario: Same tokens drive shell and engine
- **WHEN** the active theme assigns `bg.canvas = "#1a1a1a"` and `fg.primary = "#eeeeee"`
- **THEN** the AppKit canvas background is `#1a1a1a`, the AppKit primary text is `#eeeeee`, the engine `background` is `#1a1a1a`, and the engine `foreground` is `#eeeeee`

#### Scenario: Token vocabulary is closed
- **WHEN** a theme file contains a token name that is not in the documented vocabulary
- **THEN** the loader emits a hard-error diagnostic naming the unknown token

### Requirement: Themes are flat and fully populated
The system SHALL require every theme file to assign a value to every token in the vocabulary. The system SHALL NOT support theme inheritance, derivation rules, or partial themes at runtime. The system SHALL load theme files as TOML.

#### Scenario: Missing token is rejected
- **WHEN** a theme file omits any token in the vocabulary
- **THEN** the loader emits a hard-error diagnostic naming each missing token, and the theme is not applied

#### Scenario: No inheritance keyword is honored
- **WHEN** a theme file declares an `extends` key or any similar inheritance directive
- **THEN** the loader emits a hard-error diagnostic stating that inheritance is not supported

### Requirement: Built-in themes ship as data
The system SHALL ship its built-in themes as TOML files bundled as package resources, not as hand-coded source constants. The initial built-in set SHALL be: `monokai-soda` (default), `catppuccin`, `dracula`, `nord`, `gruvbox`, `one-dark`, `solarized-dark`, and `solarized-light`.

#### Scenario: Default theme on first run
- **WHEN** OpenMUX starts and no theme is configured
- **THEN** the active theme is `monokai-soda`

#### Scenario: Built-in theme is selectable by name
- **WHEN** `~/.omux/config.toml` sets `[theme] name = "nord"`
- **THEN** the system loads `nord` from bundled resources and applies it

### Requirement: User themes are loaded from `~/.omux/themes/`
The system SHALL discover user theme files under `~/.omux/themes/` and make them selectable by name. When a user theme has the same name as a built-in theme, the user theme SHALL take precedence and the system SHALL emit a warning diagnostic.

#### Scenario: User theme overrides built-in
- **WHEN** the user places a file at `~/.omux/themes/dracula.toml` and sets `[theme] name = "dracula"`
- **THEN** the user file is loaded, the bundled `dracula` is shadowed, and a warning diagnostic names the override

#### Scenario: Selecting a user-only theme
- **WHEN** the user creates `~/.omux/themes/my-theme.toml` and sets `[theme] name = "my-theme"`
- **THEN** the system loads it without comparing against bundled themes

### Requirement: Tokens compile deterministically to a Ghostty configuration file
The system SHALL compile the resolved tokens of the active theme into Ghostty configuration text. The output SHALL be written to a file under `~/.omux/generated/ghostty/` whose name is derived from a stable hash of all inputs to the compilation. The same logical inputs SHALL always produce the same output path.

#### Scenario: Same inputs produce same path
- **WHEN** the same theme, the same OpenMUX version, the same OpenMUX-managed keys, and the same `[ghostty]` pass-through values are compiled twice
- **THEN** both compilations produce a file at the same path with byte-identical contents

#### Scenario: Token change produces a new path
- **WHEN** the active theme changes any token value
- **THEN** the next compilation writes to a different path; the previous file remains until garbage collection

### Requirement: Compiled output places OpenMUX-managed keys after pass-through
The system SHALL emit `[ghostty]` pass-through keys before OpenMUX-managed keys in the generated Ghostty configuration file. Because Ghostty's parser keeps the last value seen, this ordering SHALL be the mechanism by which OpenMUX-managed values override colliding pass-through values.

#### Scenario: Last write wins
- **WHEN** `[ghostty]` sets `background = "#000000"` and the active theme would emit `background = "#1a1a1a"` from `bg.canvas`
- **THEN** the generated file lists the pass-through `background` line above the theme-derived `background` line, and the engine reads `#1a1a1a`

### Requirement: Compiled Ghostty configuration files are clearly OpenMUX-owned
The system SHALL write every compiled Ghostty configuration file with a header comment that identifies it as OpenMUX-managed, names the source `~/.omux/config.toml`, names the active theme, names the OpenMUX version, names the hash, and instructs the user not to edit it directly.

#### Scenario: Header is present
- **WHEN** any file under `~/.omux/generated/ghostty/` is opened
- **THEN** its first non-blank lines are comments declaring OpenMUX ownership and the metadata listed above

### Requirement: Theme changes apply live
The system SHALL recompile and re-apply the theme without restarting terminal sessions when the active theme is changed via configuration edit, when the active theme file is edited, or when an explicit reload is requested.

#### Scenario: Switch theme by editing config
- **WHEN** the user edits `~/.omux/config.toml` to change `[theme] name` from `monokai-soda` to `nord`
- **THEN** the chrome and the engine both reflect `nord` without any terminal session being killed

#### Scenario: Edit active theme file
- **WHEN** the user edits a token value in `~/.omux/themes/<active>.toml`
- **THEN** the chrome and the engine reflect the new token value without any terminal session being killed

### Requirement: Stale generated artifacts are garbage-collected
The system SHALL remove generated Ghostty configuration files that are not the current active artifact and that are older than a documented retention threshold or were produced by a different OpenMUX build. Garbage collection SHALL run at most once per OpenMUX launch and SHALL NOT block startup.

#### Scenario: Old artifacts are removed on launch
- **WHEN** OpenMUX launches and `~/.omux/generated/ghostty/` contains files older than the retention threshold or produced by a different OpenMUX build, none of which is the current active artifact
- **THEN** those files are deleted

#### Scenario: Active artifact is never deleted
- **WHEN** garbage collection runs
- **THEN** the file currently in use by the running engine is preserved regardless of age
