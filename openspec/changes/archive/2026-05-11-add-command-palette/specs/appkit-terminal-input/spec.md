## ADDED Requirements

### Requirement: AppKit input SHALL route palette shortcuts before terminal input
The macOS app shell SHALL resolve configured command palette shortcuts as OpenMUX application commands before forwarding terminal-owned key events to the focused terminal runtime.

#### Scenario: Cmd+P opens palette from focused terminal
- **WHEN** a runtime-backed terminal pane is focused and the user presses the effective workspace-palette shortcut
- **THEN** OpenMUX opens the command palette and does not forward `Cmd+P` as terminal text input

#### Scenario: Cmd+Shift+P opens command palette from focused terminal
- **WHEN** a runtime-backed terminal pane is focused and the user presses the effective command-palette shortcut
- **THEN** OpenMUX opens the command palette with `>` prefilled and does not forward `Cmd+Shift+P` as terminal text input

### Requirement: Palette shortcut routing SHALL preserve international text input
Palette shortcut routing SHALL NOT claim Option-modified input, dead-key composition, IME preedit, or layout-produced text unless an explicit non-Option OpenMUX command shortcut matches.

#### Scenario: Option text is not captured by palette routing
- **WHEN** a focused terminal receives Option-modified input that produces layout-specific text
- **THEN** OpenMUX preserves the existing terminal input behavior and does not treat the event as a palette shortcut

#### Scenario: Active composition is not interrupted by palette search text
- **WHEN** the palette is closed and the user enters dead-key or IME composition input in the terminal
- **THEN** OpenMUX keeps routing composition through the terminal text-input path without opening or updating the palette

#### Scenario: Palette text stays inside palette while open
- **WHEN** the palette is open and the user types query text including `>`
- **THEN** OpenMUX updates the palette query and does not send that query text to the focused terminal session

#### Scenario: Rebound palette shortcut is forwarded when unclaimed
- **WHEN** the user config maps a default palette shortcut to `"none"` and a focused terminal receives that chord
- **THEN** OpenMUX does not open the palette and allows the existing terminal input routing path to handle the chord when representable
