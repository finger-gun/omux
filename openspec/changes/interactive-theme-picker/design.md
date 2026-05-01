## Context

The CLI already lists themes from `OmuxThemeRegistry.loadThemes()` and can apply a selected theme through the existing config update plus `config reload` flow. The only missing piece is the input experience when the user runs `omux theme` without arguments.

The picker must work well in a real terminal but remain testable and script-safe. A raw-mode reader is appropriate for arrow keys, but raw terminal I/O should be isolated behind a small injectable seam so tests do not need a real TTY.

## Goals / Non-Goals

**Goals:**

- Provide an interactive arrow-key picker in TTY contexts.
- Preserve non-interactive numeric/name selection.
- Keep implementation dependency-free and macOS-native.
- Ensure terminal mode is restored after selection, cancellation, or errors.

**Non-Goals:**

- No curses/ncurses or third-party TUI framework.
- No fuzzy search or filtering in this change.
- No change to how themes are loaded or applied after selection.

## Decisions

### Use a small raw-mode terminal picker

The default picker will use `termios` raw mode to read single-key input from stdin and ANSI escape sequences to redraw the menu. It recognizes Up/Down arrows, `j`/`k`, Enter, `q`, Escape, and Ctrl-C.

Alternative considered: keep number-only input. That does not satisfy the requested UX. Another alternative was adopting a TUI library, but that adds dependency and packaging complexity for a simple list picker.

### Use an injectable picker seam

`OmuxCLICommand` will accept closures for detecting interactive support and selecting a theme interactively. Production defaults use stdin/stdout TTY checks and the raw terminal picker. Tests can inject deterministic behavior.

### Fall back outside TTYs

When stdin/stdout are not TTYs, `omux theme` keeps printing the numbered list and reading a single line. This protects scripts, tests, pipes, and automation.

## Risks / Trade-offs

- Raw terminal mode could leave the terminal in a bad state if not restored -> Use `defer` to restore original settings before returning or throwing.
- ANSI redraw can look poor in minimal terminals -> Keep output simple and provide `q`/Escape cancellation.
- Interactive behavior is hard to unit-test directly -> Test CLI flow through the injectable picker seam and keep a focused pure fallback test.

## Migration Plan

No data migration is required. Existing commands and config files continue to work.
