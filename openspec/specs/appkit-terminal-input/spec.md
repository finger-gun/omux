# Capability: appkit-terminal-input

## Purpose

Define the AppKit-facing terminal input contract for runtime-backed and fallback terminal panes on macOS.

## Requirements

### Requirement: Runtime terminal view owns AppKit input
Runtime-backed terminal panes SHALL use the visible runtime terminal view as the AppKit first responder and interaction adapter instead of a hidden text-view overlay.

#### Scenario: Runtime pane receives focus
- **WHEN** a user focuses a runtime-backed terminal pane
- **THEN** the visible runtime terminal view SHALL become the first responder for keyboard, text-input, command, and pointer events

#### Scenario: Fallback overlay is not used for runtime input
- **WHEN** a terminal pane is backed by the embedded Ghostty runtime
- **THEN** OpenMUX SHALL NOT place a full-surface fallback text view above the runtime view to capture input

### Requirement: Dead keys and preedit are handled through AppKit text input
Runtime-backed terminal panes SHALL use AppKit text-input composition for dead keys, marked text, preedit updates, commit, and cancellation.

#### Scenario: Dead key starts preedit
- **WHEN** a user presses a macOS dead key such as `¨`, `^`, or `~`
- **THEN** OpenMUX SHALL treat the input as preedit state and SHALL NOT emit stray terminal text before AppKit commits text

#### Scenario: Composed text commits once
- **WHEN** AppKit commits composed text after a dead-key or IME sequence
- **THEN** OpenMUX SHALL send the committed text to the terminal exactly once

#### Scenario: Composition is cancelled
- **WHEN** a user cancels marked text or preedit input
- **THEN** OpenMUX SHALL clear the terminal preedit state without emitting unrelated terminal input

### Requirement: IME candidate geometry follows the terminal cursor
Runtime-backed terminal panes SHALL expose terminal cursor geometry to AppKit text input so IME candidate UI appears at the terminal insertion point.

#### Scenario: IME requests candidate position
- **WHEN** AppKit requests the first rectangle for an active marked-text range
- **THEN** OpenMUX SHALL return a rectangle derived from the runtime terminal cursor or selection geometry

### Requirement: Side-specific modifiers are preserved
OpenMUX SHALL preserve side-specific modifier identity for Shift, Control, Option, and Command when AppKit exposes it.

#### Scenario: Right Option is pressed
- **WHEN** the user presses Right Option
- **THEN** OpenMUX SHALL preserve right-Option identity when translating the event for the terminal runtime

#### Scenario: Left Option is pressed
- **WHEN** the user presses Left Option
- **THEN** OpenMUX SHALL preserve left-Option identity and SHALL NOT collapse it into right-Option state

### Requirement: Option-as-alt behavior is Ghostty-compatible
Runtime-backed terminal panes SHALL honor `macos-option-as-alt` semantics for `false`, `true`, `left`, `right`, and unset/default. OpenMUX MAY own the user-facing configuration, but runtime-backed panes SHALL pass the effective setting to Ghostty, preserve original modifier identity, request Ghostty translation modifiers, and use translated modifiers only for AppKit text generation. OpenMUX SHALL NOT hardcode layout-specific Option character mappings or invent divergent meanings for these values.

#### Scenario: Text-producing Option side remains layout-correct
- **WHEN** the effective `macos-option-as-alt` configuration leaves one Option side available for text input on the active macOS keyboard layout
- **THEN** OpenMUX SHALL preserve the text produced by AppKit for that active layout instead of substituting a hardcoded US, Swedish, German, or other layout mapping

#### Scenario: Right Option does not generate layout text when configured as Alt
- **WHEN** the effective configuration sets `macos-option-as-alt = right` and the user presses Right Option plus `d`
- **THEN** OpenMUX SHALL deliver terminal Alt/Meta `d` behavior and SHALL NOT emit the layout character `∂`

#### Scenario: Swedish ISO regression preserves left Option text
- **WHEN** the effective configuration sets `macos-option-as-alt = right` and AppKit reports Swedish ISO Left Option text such as `@`, `[`, or `]`
- **THEN** OpenMUX SHALL deliver that AppKit-reported text for Left Option input while preserving Right Option as terminal Alt/Meta input

#### Scenario: Both Option keys act as Alt
- **WHEN** the effective configuration sets `macos-option-as-alt = true`
- **THEN** OpenMUX SHALL allow Ghostty to treat both Left Option and Right Option as terminal Alt/Meta modifiers

#### Scenario: Only Left Option acts as Alt
- **WHEN** the effective configuration sets `macos-option-as-alt = left`
- **THEN** OpenMUX SHALL allow Ghostty to treat Left Option as terminal Alt/Meta while preserving Right Option for layout text input

#### Scenario: Option remains text-producing when disabled
- **WHEN** the effective configuration sets `macos-option-as-alt = false`
- **THEN** OpenMUX SHALL preserve Option-based macOS text input unless the key chord produces no printable text and Ghostty treats it as terminal Alt

### Requirement: Option-as-alt behavior has regression coverage
OpenMUX SHALL include automated regression coverage for side-specific Option preservation and Ghostty-compatible option-as-alt behavior without requiring every contributor to own every physical keyboard layout.

#### Scenario: Synthetic right Option regression
- **WHEN** tests simulate Right Option input and Ghostty translation modifiers for `macos-option-as-alt = right`
- **THEN** the tests SHALL verify that original right-Option identity reaches runtime key dispatch and translated modifiers are used only for AppKit text generation

#### Scenario: Layout text is test-injected
- **WHEN** tests simulate a layout-produced Option character
- **THEN** the tests SHALL verify OpenMUX forwards the AppKit-reported text and does not depend on hardcoded Swedish, German, US, or other layout tables

#### Scenario: Physical keyboard matrix is documented
- **WHEN** release verification is performed for this behavior
- **THEN** the verification matrix SHALL include Swedish/Nordic ISO, US, and at least one additional EU layout when available

#### Scenario: IME workflow is part of release verification
- **WHEN** release verification is performed for this behavior
- **THEN** the verification matrix SHALL include at least one IME workflow covering preedit, candidate placement, commit, and cancellation

### Requirement: Command routing preserves terminal semantics
Runtime-backed terminal panes SHALL route terminal-focused command shortcuts through AppKit responder commands and terminal runtime binding semantics rather than through generic text-view editing behavior.

#### Scenario: Command shortcut is handled by responder command
- **WHEN** a terminal pane is focused and the user presses a standard command shortcut such as Command-V
- **THEN** OpenMUX SHALL route the shortcut through the focused terminal responder command path

#### Scenario: Control chords remain terminal input
- **WHEN** a terminal pane is focused and the user presses a Control chord such as Control-C
- **THEN** OpenMUX SHALL deliver the chord as terminal input and SHALL NOT treat it as a macOS Copy command

### Requirement: Fallback input remains behaviorally compatible
Fallback terminal panes SHALL preserve the same high-level input semantics for printable text, command routing, and paste behavior where runtime-specific APIs are unavailable.

#### Scenario: Fallback pane receives printable input
- **WHEN** a fallback terminal pane is focused and the user types printable text
- **THEN** OpenMUX SHALL deliver the text to the live terminal session

#### Scenario: Fallback pane handles paste
- **WHEN** a fallback terminal pane is focused and the user invokes Paste
- **THEN** OpenMUX SHALL send clipboard text to the live terminal session through the fallback bridge path

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
