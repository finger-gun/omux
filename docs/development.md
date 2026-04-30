# OpenMUX Development Notes

OpenMUX currently uses a Swift Package Manager workspace to establish the initial foundation, workspace shell, interactive-terminal, and pane-tab-stacks slices described by the applied OpenSpec changes.

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
swift run omux pane-tab
swift run omux pane-tab-focus <pane-id>
swift run omux pane-tab-close [pane-id]
swift run omux run <session-id> "pwd"
swift run omux help
swift run OpenMUXApp
```

## Workspace shell status

The current shell baseline adds:

- real bridge-backed pane views
- direct typing into the focused pane
- persistent pane-owned interactive shell sessions
- top-level workspace tabs plus split-right and split-down panes in the native shell
- pane stacks at each split leaf, with local pane tabs inside a region
- shared workspace/session actions used by both the UI and `omux`
- command injection routed into ongoing live pane sessions
- pane resize propagation into the live terminal runtime

## Pane stack model

The current layout tree is now:

- top-level workspace tabs
- recursive split nodes
- pane-stack leaves
- active local pane tab inside each pane stack

This keeps shell structure in `OmuxCore` and `OmuxAppShell` while the terminal bridge still only owns pane/session surfaces. Splitting acts on the active local pane tab in the focused pane stack; creating a pane-local tab stays inside the current split region.

## Current limitations

The current shell is usable, but it is still intentionally narrow:

- pane rendering is still text-view-backed rather than full libghostty rendering
- ANSI/control-sequence handling is lightweight and aimed at normal shell prompts, not full-screen TUIs
- paste is supported in the pane UI, but richer clipboard workflows are still follow-on work
- close-last-local-tab is intentionally rejected for now instead of collapsing a split region
- pane-local tabs cannot yet be reordered, dragged between stacks, or restored from persisted layout state

## Guidance for future changes

1. Keep terminal lifecycle, PTY ownership, input encoding, and future libghostty wiring inside `OmuxTerminalBridge`.
2. Treat direct pane input as the primary interaction model; UI chrome should enhance it, not replace it.
3. Keep pane-stack behavior in shared workspace actions so the AppKit shell, JSON-RPC, and `omux` stay aligned.
4. Preserve international keyboard correctness whenever input handling changes.
5. Keep `omux`, JSON-RPC, and the native shell pointed at the same live session objects.
