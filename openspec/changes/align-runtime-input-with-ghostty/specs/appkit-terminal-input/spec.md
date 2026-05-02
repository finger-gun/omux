## MODIFIED Requirements

### Requirement: Command-arrow navigation reaches terminal input
Focused runtime-backed terminal panes SHALL preserve Command-Left and Command-Right as terminal-owned key events unless an explicit OpenMUX command claims them. OpenMUX SHALL NOT synthesize Control-A or Control-E substitutes for runtime-backed panes when the original Command-arrow event can be represented to Ghostty.

#### Scenario: Command-Left reaches Ghostty semantics
- **WHEN** a runtime-backed terminal pane is focused and the user presses Command-Left
- **THEN** OpenMUX SHALL forward the original key and modifier facts through the runtime input path instead of synthesizing Control-A

#### Scenario: Command-Right reaches Ghostty semantics
- **WHEN** a runtime-backed terminal pane is focused and the user presses Command-Right
- **THEN** OpenMUX SHALL forward the original key and modifier facts through the runtime input path instead of synthesizing Control-E

## ADDED Requirements

### Requirement: Runtime adapter is Ghostty-aligned
Runtime-backed terminal panes SHALL align their AppKit input adapter behavior with Ghostty macOS terminal semantics while preserving OpenMUX ownership of shell focus, shortcut interception, and native menu entry points.

#### Scenario: Terminal-owned modified key is forwarded
- **WHEN** a focused runtime-backed terminal pane receives a modified key chord that is not an OpenMUX shortcut
- **THEN** OpenMUX SHALL forward it to the Ghostty runtime input path with keycode, modifier, text, repeat, phase, and composition facts preserved where AppKit exposes them

#### Scenario: Ghostty modifier translation informs text generation
- **WHEN** Ghostty reports translated modifier state for an input event
- **THEN** OpenMUX SHALL use that translated state only for AppKit text generation while preserving original modifier identity for runtime key dispatch

### Requirement: AppKit text commands do not disappear
Runtime-backed terminal panes SHALL avoid swallowing AppKit text-command selectors produced by `interpretKeyEvents` when the original input is terminal-owned.

#### Scenario: Option Backspace is not swallowed
- **WHEN** AppKit resolves `Option+Backspace` to a text-command selector in a focused runtime-backed terminal pane
- **THEN** OpenMUX SHALL still deliver the corresponding original terminal key event to Ghostty unless an explicit OpenMUX command handled it

#### Scenario: Command Backspace is not swallowed
- **WHEN** AppKit resolves `Cmd+Backspace` to a text-command selector in a focused runtime-backed terminal pane
- **THEN** OpenMUX SHALL still deliver the corresponding original terminal key event to Ghostty unless an explicit OpenMUX command handled it

### Requirement: Ghostty-inspired behavior remains clean-room and shell-safe
OpenMUX SHALL use Ghostty's macOS app as behavioral guidance for terminal input fidelity without copying implementation code or adopting Ghostty app-shell behavior.

#### Scenario: Shell ownership remains OpenMUX-native
- **WHEN** Ghostty has app-shell behaviors for windows, tabs, splits, config, updates, or app menus
- **THEN** OpenMUX SHALL keep those behaviors rejected or translated through explicit OpenMUX-owned commands

#### Scenario: Terminal fidelity behavior may be mirrored
- **WHEN** Ghostty's macOS adapter demonstrates terminal-input behavior for IME, preedit, modifier translation, selection, or mouse input
- **THEN** OpenMUX MAY mirror the behavior through its own bridge-owned implementation
