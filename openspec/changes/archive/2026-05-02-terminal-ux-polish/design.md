## Context

OpenMUX has moved toward a native AppKit shell hosting libghostty surfaces behind `OmuxTerminalBridge`, with `omux theme` now offering an interactive terminal picker. Several interaction gaps now show up in daily use: the picker assumes an unlimited terminal height, runtime terminal views do not currently accept file drops, Command-arrow keys are classified as generic app shortcuts, and the transparent full-size titlebar no longer gets default double-click zoom behavior.

These fixes are intentionally small and native. They should restore expected terminal and macOS behavior without introducing new dependencies, a browser UI, or wider libghostty exposure.

## Goals / Non-Goals

**Goals:**

- Keep the interactive theme picker usable in small terminal panes.
- Paste dropped file URLs into focused terminal panes as text, including image files dragged from Finder.
- Make Command-Left and Command-Right useful in focused terminal input while preserving standard Command shortcuts.
- Restore double-click titlebar zoom/maximize behavior with the existing transparent titlebar appearance.
- Add regression coverage for pure logic and event routing where AppKit allows stable tests.

**Non-Goals:**

- Inline image rendering/upload protocols for drag/drop.
- Replacing the native picker with a web or curses dependency.
- Broadly rerouting all Command-modified keys into the terminal.
- Moving libghostty C types outside `OmuxTerminalBridge`.

## Decisions

1. **Theme picker viewport is calculated as pure logic.** The picker will measure terminal rows with `ioctl(TIOCGWINSZ)` at render time, reserve rows for prompt/help, and compute a bounded visible index range. Keeping range calculation pure makes the important behavior testable without a real TTY.

2. **Dropped file URLs become shell-safe path text.** Drag/drop will accept file URLs from the pasteboard and insert path text through the existing terminal text path. Paths containing spaces or shell metacharacters will be single-quoted with internal single quotes escaped. Multiple dropped paths will be space-separated. Raw image data without a file URL remains out of scope because terminal input should not silently inject binary data.

3. **Command-arrow is a narrow terminal navigation exception.** Command-Left and Command-Right will be recognized as terminal navigation chords and converted to beginning/end-of-line control bytes for fallback PTY behavior. Runtime-hosted panes may forward the event to Ghostty when supported, but OpenMUX will retain a bridge-local fallback so the user-visible behavior is consistent. Other Command shortcuts keep existing responder/menu behavior.

4. **Titlebar behavior stays native where possible.** The workspace window will keep `.fullSizeContentView`, transparent titlebar, and hidden title. OpenMUX will re-enable native movement/zoom semantics for the titlebar/background hit region rather than adding custom maximize state or a replacement window manager.

## Risks / Trade-offs

- **Shell quoting may not match every shell dialect.** → Use POSIX single-quote escaping, which is safe for common shells and avoids executing anything automatically.
- **AppKit drag/drop tests can be hard to synthesize end-to-end.** → Extract path formatting and drop parsing seams where possible and test the behavior below the AppKit event boundary.
- **Command-arrow behavior differs between terminal apps.** → Limit the first implementation to the reported and widely expected beginning/end-of-line behavior.
- **Window double-click behavior depends on macOS user preferences.** → Prefer native AppKit zoom semantics and test OpenMUX configuration/handler behavior rather than hardcoding a custom maximize policy.
