# OpenMUX Development Notes

OpenMUX currently uses a Swift Package Manager workspace to establish the initial foundation, workspace shell, and interactive-terminal slices described by the applied OpenSpec changes.

## Module boundaries

| Module | Responsibility |
| --- | --- |
| `OmuxCore` | OpenMUX-native domain types for workspaces, panes, sessions, notifications, and normalized key events |
| `OmuxTerminalBridge` | The only layer allowed to depend directly on `libghostty` / `CGhostty` |
| `OmuxControlPlane` | Local JSON-RPC control plane over a Unix domain socket |
| `OmuxHooks` | Hook contracts and external process execution |
| `OmuxAppShell` | AppKit-first shell, window/workspace orchestration, and control-plane integration |
| `OmuxCLI` | `omux` command handling over the public control plane |

## Key rules

1. Keep `libghostty` behind `OmuxTerminalBridge`.
2. Normalize keyboard input before terminal or shortcut dispatch.
3. Add automation through `omux`, JSON-RPC, hooks, and external plugins before adding embedded runtimes.
4. Preserve native macOS behavior in the shell where precision matters.

## Vendored terminal engine path

- Vendored path: `Vendor/ghostty/`
- Pinned ref marker: `Vendor/ghostty/PINNED_REF`
- Build handoff script: `Scripts/build-ghostty.sh`

The current bridge uses a bridge-owned PTY-backed interactive runtime as the fallback path until the vendored Ghostty snapshot is checked in and wired through `CGhostty`. Future changes should improve rendering fidelity through the bridge without leaking Ghostty internals into higher-level modules.

## Commands

```bash
swift build
swift test
swift run omux tab
swift run omux split
swift run omux split down
swift run omux run <session-id> "pwd"
swift run omux help
swift run OpenMUXApp
```

## Workspace shell status

The current shell baseline adds:

- real bridge-backed pane views
- direct typing into the focused pane
- persistent pane-owned interactive shell sessions
- tabs plus split-right and split-down panes in the native shell
- shared workspace/session actions used by both the UI and `omux`
- command injection routed into ongoing live pane sessions
- pane resize propagation into the live terminal runtime

## Current limitations

The current interactive-terminal slice is usable, but it is still intentionally narrow:

- pane rendering is still text-view-backed rather than full libghostty rendering
- ANSI/control-sequence handling is lightweight and aimed at normal shell prompts, not full-screen TUIs
- paste is supported in the pane UI, but richer clipboard workflows are still follow-on work
- the next UX layer should build on this live session model rather than reintroducing modal command entry

## Guidance for future changes

1. Keep terminal lifecycle, PTY ownership, input encoding, and future libghostty wiring inside `OmuxTerminalBridge`.
2. Treat direct pane input as the primary interaction model; UI chrome should enhance it, not replace it.
3. Preserve international keyboard correctness whenever input handling changes.
4. Keep `omux`, JSON-RPC, and the native shell pointed at the same live session objects.
