## ADDED Requirements

### Requirement: OpenMUX navigation shortcuts SHALL be explicitly allowlisted
The input pipeline SHALL classify only the documented pane-local tab and pane navigation key chords as OpenMUX shortcuts while preserving terminal ownership of unclaimed Control, Command, Option/Alt, dead-key, compose, and IME input.

#### Scenario: Pane-local tab shortcuts are intercepted
- **WHEN** a focused runtime-backed terminal pane receives `Cmd+T`, `Cmd+W`, or `Ctrl+Tab`
- **THEN** OpenMUX classifies the event as a shortcut and the terminal session does not receive the key chord as text input

#### Scenario: Pane cycle shortcut is intercepted
- **WHEN** a focused runtime-backed terminal pane receives `Ctrl+Shift+Tab`
- **THEN** OpenMUX classifies the event as a shortcut and the terminal session does not receive the key chord as text input

#### Scenario: Other Control chords remain terminal input
- **WHEN** a focused runtime-backed terminal pane receives a Control-modified key chord that is not an explicit OpenMUX shortcut
- **THEN** OpenMUX leaves the event terminal-owned with original key and modifier facts preserved

#### Scenario: Option and composition input remain terminal input
- **WHEN** a focused runtime-backed terminal pane receives Option/Alt text input, right-Option-sensitive input, dead-key input, compose input, or IME composition input that is not an explicit OpenMUX shortcut
- **THEN** OpenMUX preserves the intended terminal or composition route instead of treating it as pane navigation
