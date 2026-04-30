# OpenMUX Development Notes

OpenMUX currently uses a Swift Package Manager workspace to establish the initial foundation, workspace shell, interactive-terminal, pane-tab-stacks, and bridge-owned surface-hosting slices described by the applied OpenSpec changes.

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
- Built runtime artifact: `Vendor/ghostty/macos/GhosttyKit.xcframework`

OpenMUX now vendors a pinned Ghostty snapshot and builds the internal `GhosttyKit` xcframework locally. `OmuxTerminalBridge` is still the only package target allowed to import `CGhostty`; the rest of the app continues to consume bridge-owned pane views and session snapshots.

To rebuild the runtime artifact locally:

```bash
Scripts/build-ghostty.sh
```

The script expects:

- `Vendor/ghostty/` to contain the pinned upstream snapshot
- Zig 0.15.2, with Homebrew `zig@0.15` preferred when available
- Xcode's Metal Toolchain component installed for the macOS xcframework build

When `GhosttyKit.xcframework` is present, hosted panes use runtime-owned native Ghostty surfaces by default. When it is absent or runtime attach fails, the bridge falls back to the internal PTY-backed text host so the shell can still render a working pane.

## Commands

```bash
make setup
make dev
make build
make test
make verify
make smoke
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

If you want one stable, native entrypoint for daily development, prefer the root `Makefile`: run `make setup` once to build the vendored Ghostty runtime, then use `make dev`, `make build`, `make test`, `make verify`, or `make smoke`.

## Workspace shell status

The current shell baseline adds:

- real bridge-backed pane views
- direct typing into the focused pane
- persistent pane-owned interactive shell sessions
- top-level workspace tabs plus split-right and split-down panes in the native shell
- pane stacks at each split leaf, with local pane tabs inside a region
- bridge-provided hosted terminal pane views embedded inside AppKit pane stacks
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

## Hosted pane path

The current pane-hosting split is:

- `OmuxAppShell` owns workspace layout, pane-stack chrome, and focus state
- `OmuxTerminalBridge` owns pane surfaces, attached sessions, resize propagation, and hosted terminal pane views
- the bridge chooses between a vendored Ghostty runtime-owned native surface host and its internal fallback host

This keeps the shell AppKit-first while preserving one narrow terminal-engine seam.

## Current limitations

The current shell is usable, but it is still intentionally narrow:

- the runtime-backed path currently keeps transcript snapshots minimal, so the fallback host remains the richer text transcript source
- the bridge-owned fallback host is still text-rendered when the vendored Ghostty runtime is unavailable or cannot attach
- ANSI/control-sequence handling is lightweight and aimed at normal shell prompts, not full-screen TUIs
- paste is supported in the pane UI, but richer clipboard workflows are still follow-on work
- close-last-local-tab is intentionally rejected for now instead of collapsing a split region
- pane-local tabs cannot yet be reordered, dragged between stacks, or restored from persisted layout state

## Guidance for future changes

1. Keep terminal lifecycle, hosted pane views, PTY ownership, input encoding, and future libghostty wiring inside `OmuxTerminalBridge`.
2. Treat direct pane input as the primary interaction model; UI chrome should enhance it, not replace it.
3. Keep pane-stack behavior in shared workspace actions so the AppKit shell, JSON-RPC, and `omux` stay aligned.
4. Preserve international keyboard correctness whenever input handling changes.
5. Keep `omux`, JSON-RPC, and the native shell pointed at the same live session objects.
