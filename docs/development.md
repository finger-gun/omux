# OpenMUX Development Notes

OpenMUX currently uses a Swift Package Manager workspace to establish the initial foundation, workspace shell, interactive-terminal, pane-tab-stacks, and bridge-owned surface-hosting slices described by the applied OpenSpec changes.

The config/theme foundation now lives on top of **`~/.omux/config.toml`**, **`~/.omux/themes/`**, and generated Ghostty artifacts under **`~/.omux/generated/ghostty/`**. See [`docs/configuration.md`](./configuration.md) for the user-facing model.

## Module boundaries

| Module | Responsibility |
| --- | --- |
| `OmuxCore` | OpenMUX-native domain types for workspaces, panes, sessions, notifications, and normalized key events |
| `OmuxConfig` | OpenMUX config parsing, diagnostics, paths, and starter-config scaffolding |
| `OmuxTheme` | Theme registry, token vocabulary, theme compilation, and generated Ghostty config emission |
| `OmuxTerminalBridge` | The only layer allowed to depend directly on `libghostty` / `CGhostty` |
| `OmuxControlPlane` | Local JSON-RPC control plane over a Unix domain socket |
| `OmuxHooks` | Hook contracts and external process execution |
| `OmuxAppShell` | AppKit-first shell, window/workspace orchestration, and control-plane integration |
| `OmuxCLI` | `omux` command handling over the public control plane |

## Key rules

1. Keep `libghostty` behind `OmuxTerminalBridge`.
2. Normalize keyboard input before dispatch, but only claim explicit OpenMUX shortcuts; runtime terminal semantics belong to Ghostty.
3. Add automation through `omux`, JSON-RPC, hooks, and external plugins before adding embedded runtimes.
4. Preserve native macOS behavior in the shell where precision matters.

## Vendored terminal engine path

- Vendored path: `Vendor/ghostty/`
- Pinned ref marker: `Vendor/ghostty/PINNED_REF`
- Build handoff script: `Scripts/build-ghostty.sh`
- Built runtime artifact: `Vendor/ghostty/macos/GhosttyKit.xcframework`

OpenMUX now vendors a pinned Ghostty snapshot and builds the internal `GhosttyKit` xcframework locally. `OmuxTerminalBridge` is still the only package target allowed to import `CGhostty`; the rest of the app continues to consume bridge-owned pane views and session snapshots.

Runtime-backed input follows an OpenMUX-gate/Ghostty-semantics rule: the shell may intercept documented workspace, split, sidebar, focus, and native menu commands, but unclaimed terminal input is forwarded to Ghostty with original key and modifier facts preserved. OpenMUX should not synthesize shell-editing behavior for modified Backspace, Command-arrow, Option/Alt, dead-key, or IME flows when Ghostty can represent the original event.

To rebuild the runtime artifact locally:

```bash
Scripts/build-ghostty.sh
```

The script expects:

- `Vendor/ghostty/` to contain the pinned upstream snapshot
- Zig 0.15.2, with Homebrew `zig@0.15` preferred when available
- Xcode's Metal Toolchain component installed for the macOS xcframework build

`GhosttyKit.xcframework` is required for normal builds, tests, development launches, and release packaging. Run `make setup` before `swift build`, `swift test`, or `make verify`; package resolution fails fast if the vendored runtime artifact is missing. Runtime attach failures are treated as errors instead of silently downgrading panes to a non-Ghostty host.

## Commands

```bash
make setup
make dev
make build
make test
make verify
make smoke
make import-themes
make package-release
Scripts/check-changes-since-release.sh
swift build
swift test
swift run omux config doctor
swift run omux config reload
swift run omux config init
swift run omux theme
swift run omux theme nord
swift run omux theme list
swift run omux open [path]
swift run omux workspace-close [workspace-id]
swift run omux tab
swift run omux split
swift run omux split right
swift run omux split left --focused
swift run omux split down
swift run omux pane-remove [--pane <pane-id>]
swift run omux pane-tab
swift run omux pane-tab-next
swift run omux pane-tab-prev
swift run omux pane-tab-focus <pane-id>
swift run omux pane-tab-close [pane-id]
swift run omux pane-next
swift run omux pane-prev
swift run omux events
swift run omux list --full
swift run omux sessions
swift run omux panes
swift run omux history
swift run omux history <pane-id>
swift run omux history all --json
swift run omux run <session-id> "pwd"
swift run omux run --pane <pane-id> -- "pwd"
swift run omux send-text --session <session-id> -- "hello"
swift run omux install-cli [destination]
swift run omux help
swift run OpenMUXApp
```

`swift run omux theme` opens the interactive arrow-key picker when stdin/stdout are attached to a TTY; tests and non-interactive runs keep the typed number/name fallback.

If you want one stable, native entrypoint for daily development, prefer the root `Makefile`: run `make setup` once to build the vendored Ghostty runtime, then use `make dev`, `make build`, `make test`, `make verify`, or `make smoke`. Use `make import-themes` when refreshing the selected imported iTerm2 Color Schemes presets from the pinned upstream ref.

Release packaging reads the product version from the root `VERSION` file by default. Use `Scripts/check-changes-since-release.sh` to inspect release-impacting changes since the latest `v*` tag and `Scripts/prepare-release.sh <version>` with a reviewed changelog body to update `VERSION` and `CHANGELOG.md`.

For release packaging and GitHub Releases, see [docs/releasing.md](./releasing.md).

## Workspace shell status

The current shell baseline adds:

- real bridge-backed pane views
- a terminal-native shell composition with persistent sidebar navigation, sidebar-owned workspace/tab switching, no persistent top bar, flatter pane chrome, and a titlebar that visually blends into the shell surface
- direct typing into the focused pane
- persistent pane-owned interactive shell sessions behind workspace and pane navigation instead of a separate Sessions sidebar section
- split-right and split-down panes routed through native View menu commands instead of persistent shell buttons
- pane stacks at each split leaf, with local pane tabs inside a region
- token-owned shell-and-terminal theming sourced from `~/.omux/config.toml`, user theme overrides in `~/.omux/themes/`, and bundled presets including Monokai Soda, Catppuccin, Dracula, Nord, Gruvbox, One Dark, Solarized light/dark, and imported iTerm2 Color Schemes presets
- explicit config diagnostics and `omux config doctor` / `omux config reload` support through the same local control plane
- a second polish pass that tightens shell proportions, makes sidebar navigation visible/useful, and gives shell controls real intrinsic sizing
- a follow-up navigation pass that moves workspace tabs into the left rail, adds a compact sidebar workspace-creation affordance, supports workspace renaming, and disables destructive workspace/pane commands when they would empty the shell
- generated workspace labels (`Workspace 1`, `Workspace 2`, ...) with optional custom overrides that can be reset back to their generated names
- workspace-row and pane-tab context menus for localized rename and close flows
- sidebar child rows for live terminals, with git-aware repo/branch/path metadata when available and path-only fallbacks otherwise
- pane chrome that reserves its secondary status row for transient terminal state instead of duplicating cwd identity
- bridge-provided hosted terminal pane views embedded inside AppKit pane stacks
- shared workspace/session actions used by both the UI and `omux`
- command injection routed into ongoing live pane sessions
- pane resize propagation into the live terminal runtime
- keyboard-first workspace controls including `Cmd+T`/`Cmd+W` pane-tab create/close, `Cmd+D`/`Cmd+Shift+D` pane split right/down, `Cmd+Shift+W` pane remove, `Cmd+N`/`Cmd+Shift+N` workspace create/close, `Cmd+B` workspace-column toggle, `Cmd+1` through `Cmd+9` ordered workspace jumps, and `Cmd+0` previous-workspace recall

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
- `OmuxTerminalBridge` owns pane surfaces, attached sessions, resize propagation, hosted terminal pane views, and terminal palette application
- the bridge hosts a vendored Ghostty runtime-owned native surface and fails fast if that runtime is unavailable

This keeps the shell AppKit-first while preserving one narrow terminal-engine seam.

## Control-plane event stream

`omux events` now streams a mixed local event feed: OpenMUX-native `terminal.*` runtime events plus successful shared action events for the first wave of short `omux` commands.

Explicit OpenMUX input actions such as `omux run` and `send-text` publish `terminal.inputSent` after successful delivery. Native pane typing is intentionally not streamed as `terminal.inputSent`, because per-key input is noisy, sensitive, and not an authoritative shell command record; terminal title updates remain presentation metadata and are not used as command text.

Current first-wave shared action event names:

- `workspace.opened`
- `tab.created`
- `pane.split`
- `paneTab.created`
- `paneTab.focused`
- `paneTab.closed`
- `session.focused`
- `command.started`
- `notification.raised`
- `workspace.restored`

## Terminal action dispatch

OpenMUX still translates a focused first wave of Ghostty action callbacks into OpenMUX-native terminal events instead of rejecting every upcall.

The dispatch path is intentionally layered:

1. `CGhosttyRuntime` decodes supported `ghostty_action_s` values into bridge-owned `TerminalAction` records keyed by `runtimeSurfaceID`.
2. `GhosttyTerminalBridge` enriches them with `paneID` and `sessionID` and publishes typed `TerminalActionEvent` values to observers.
3. `OmuxAppShell.TerminalActionCoordinator` resolves workspace/tab context, updates pane state, performs native host-side behavior, emits structured hooks, and publishes `terminal.*` events into the shared control-plane event stream.

Supported first-wave actions:

- `PWD`
- `SET_TITLE`
- `SET_TAB_TITLE`
- `OPEN_URL`
- `DESKTOP_NOTIFICATION`
- `RING_BELL`
- `COMMAND_FINISHED`
- `PROGRESS_REPORT`
- `SHOW_CHILD_EXITED`
- `RENDERER_HEALTH`

Key boundary rules:

- Ghostty enums and payload structs stay inside `OmuxTerminalBridge`.
- Hook payloads now use `OmuxValue` instead of string-only metadata.
- Control-plane event names are OpenMUX-native (`terminal.cwdChanged`, `workspace.opened`, `command.started`, and so on) and are defined without committing to a long-lived streaming transport.
- Unsupported and app-shell ownership actions remain rejected by default.

## User hook directories

The production app initializes `ExternalHookRunner` from `~/.omux/hooks/`. Each direct child directory name is a hook name, and executable regular files inside that directory are registered as handlers. Handlers remain external processes and receive the structured `HookInvocation` JSON on stdin. The discovery layer lives in `OmuxHooks`; `OmuxAppShell` only provides the `OmuxConfigPaths.hooksDirectoryURL` path during startup. See [Hooks](./hooks.md) for the user-facing reference.

## Current limitations

The current shell is usable, but it is still intentionally narrow:

- runtime-backed transcript snapshots are still minimal until the Ghostty bridge exposes richer capture
- paste is supported in the pane UI, but richer clipboard workflows are still follow-on work
- close-last-local-tab is intentionally rejected for now instead of collapsing a split region
- pane-local tabs cannot yet be reordered, dragged between stacks, or restored from persisted layout state

## Guidance for future changes

1. Keep terminal lifecycle, hosted pane views, runtime ownership, input encoding, and libghostty wiring inside `OmuxTerminalBridge`.
2. Treat direct pane input as the primary interaction model; UI chrome should enhance it, not replace it.
3. Keep pane-stack behavior in shared workspace actions so the AppKit shell, JSON-RPC, and `omux` stay aligned.
4. Preserve international keyboard correctness whenever input handling changes.
5. Keep `omux`, JSON-RPC, and the native shell pointed at the same live session objects.
