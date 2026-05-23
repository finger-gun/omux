# OpenMUX Development Notes

This page is the detailed contributor reference. If you are setting up the repo for the first time, start with the [Developer quick start](./developer.md). For a system-level map of how the shell, control plane, workspace model, and modal presentation fit together, see the [Architecture overview](./architecture.md).

OpenMUX uses a Swift Package Manager workspace for the native app shell, CLI, control plane, hooks, plugins, and terminal bridge. The vendored Ghostty runtime remains behind `OmuxTerminalBridge`.

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
make app
make dev
make build
make test
make verify
make ui-test
make smoke
make power-profile
make import-themes
make package-release
Scripts/check-changes-since-release.sh
swift build
swift test
swift run omux config doctor
swift run omux config open
swift run omux config reload
swift run omux config get --json
swift run omux config init
swift run omux theme
swift run omux theme nord
swift run omux theme list
swift run omux plugins
swift run omux plugins discover
swift run omux plugins install <plugin-id>
swift run omux plugin list
swift run omux plugin path
swift run omux agent-sessions open
swift run omux agent-sessions list
swift run omux agent-sessions search "release notes"
swift run omux ai-status hooks setup
swift run omux hooks discover
swift run omux hooks install <hook-id>
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
swift run omux history clear
swift run omux history clear --workspace <workspace-id>
swift run omux run <session-id> "pwd"
swift run omux run --pane <pane-id> -- "pwd"
swift run omux send-text --session <session-id> -- "hello"
swift run omux worktree <branch>
swift run omux install-cli [destination]
swift run omux help
swift run OpenMUXApp
Scripts/capture-openmux-power-profile.sh --label manual
```

`swift run omux theme` opens the interactive fuzzy-search arrow-key picker when stdin/stdout are attached to a TTY; tests and non-interactive runs keep the typed number/name fallback.

`swift run omux plugins` opens the interactive plugin picker when stdin/stdout are attached to a TTY; tests and non-interactive runs keep the typed number/name fallback. Registry discovery and installs use explicit subcommands such as `omux plugins discover` and `omux plugins install <plugin-id>`. Bundled and registry-hosted plugin behavior is documented in [Plugin index](./plugins/index.md), and the external plugin/extension-pane contract is documented in [Plugin ecosystem](./plugins.md).

Command-palette action entries are described by bundled JSON files under `Sources/OmuxAppShell/Resources/CommandPalette/Commands/`. Each descriptor uses a `command` object with a `kind` and target identifier resolved by app code, not a shell string. CLI entries are generated from `OpenMUXCLICommandCatalog`, which also feeds `omux help`, so command-mode search covers the full typed CLI surface without maintaining a separate allow-list.

For local cleanup while developing, run `Scripts/uninstall-local.sh --dry-run` to inspect what would be removed, then `make uninstall-local` to remove local app bundles, CLI links, `~/.omux`, OpenMUX Application Support state, preferences, caches, saved app state, and update staging leftovers.

If you want one stable, native entrypoint for daily development, prefer the root `Makefile`: run `make setup` once to build the vendored Ghostty runtime, then use `make dev`, `make build`, `make test`, `make verify`, or `make smoke`. Use `make import-themes` when refreshing the selected imported iTerm2 Color Schemes presets from the pinned upstream ref.

For local packaged-app testing, use `make install-local-release`. It runs the release packager, unpacks the newest `dist/release/OpenMUX-*-macos-unsigned.zip`, then hands the quit/copy/relaunch phase to a detached helper so the command is safe to run from inside OpenMUX. Set `SKIP_PACKAGE=1` to install the newest existing archive, `RELAUNCH=0` to leave the app closed, or `TARGET_APP="$HOME/Applications/OpenMUX.app"` for a user-local install.

Release packaging reads the product version from the root `VERSION` file by default. Use `Scripts/check-changes-since-release.sh` to inspect release-impacting changes since the latest `v*` tag and `Scripts/prepare-release.sh <version>` with a reviewed changelog body to update `VERSION` and `CHANGELOG.md`.

For release packaging and GitHub Releases, see [docs/releasing.md](./releasing.md).

## Workspace shell status

The current shell baseline adds:

- real bridge-backed pane views
- a terminal-native shell composition with persistent sidebar navigation, sidebar-owned workspace/tab switching, no persistent top bar, flatter pane chrome, and a titlebar that visually blends into the shell surface
- direct typing into the focused pane
- persistent pane-owned interactive shell sessions behind workspace and pane navigation instead of a separate terminal-session sidebar section
- split-right and split-down panes routed through native menu commands instead of persistent shell buttons
- pane stacks at each split leaf, with local pane tabs inside a region
- token-owned shell-and-terminal theming sourced from `~/.omux/config.toml`, user theme overrides in `~/.omux/themes/`, and bundled presets including Monokai Soda, Catppuccin, Dracula, Nord, Gruvbox, One Dark, Solarized light/dark, and imported iTerm2 Color Schemes presets
- explicit config diagnostics and `omux config doctor` / `omux config reload` support through the same local control plane
- a second polish pass that tightens shell proportions, makes sidebar navigation visible/useful, and gives shell controls real intrinsic sizing
- a follow-up navigation pass that moves workspace tabs into the left rail, adds a compact sidebar workspace-creation affordance, supports workspace renaming, and disables destructive workspace/pane commands when they would empty the shell
- generated workspace labels (`Workspace 1`, `Workspace 2`, ...) with optional custom overrides that can be reset back to their generated names
- isolated per-workspace shell history by default, so OpenMUX-launched shells avoid sharing one global history file across unrelated workspaces
- workspace-row and pane-tab context menus for localized rename and close flows
- sidebar child rows for live terminals, with git-aware repo/branch/path metadata when available and path-only fallbacks otherwise
- pane chrome that reserves its secondary status row for transient terminal state instead of duplicating cwd identity
- bridge-provided hosted terminal pane views embedded inside AppKit pane stacks
- shared workspace/session actions used by both the UI and `omux`
- command injection routed into ongoing live pane sessions
- pane resize propagation into the live terminal runtime
- drag-and-drop terminal insertion for text, URLs, and local files without automatically submitting Return
- keyboard-first workspace controls including `Cmd+P` workspace search, `Cmd+Shift+P` command search with a leading `>` prefix, `Cmd+T`/`Cmd+W` pane-tab create/close, `Cmd+Shift+G` worktree pane-tab creation, `Cmd+D`/`Cmd+Shift+D` pane split right/down, `Cmd+Shift+W` pane remove, `Cmd+N`/`Cmd+Shift+N` workspace create/close, `Cmd+B` workspace-column toggle, `Cmd+1` through `Cmd+9` ordered workspace jumps, and `Cmd+0` previous-workspace recall

## Pane stack model

The current layout tree is now:

- top-level workspace tabs
- recursive split nodes
- pane-stack leaves
- active local pane tab inside each pane stack

This keeps shell structure in `OmuxCore` and `OmuxAppShell` while the terminal bridge still only owns pane/session surfaces. Splitting acts on the active local pane tab in the focused pane stack; creating a pane-local tab stays inside the current split region.

`WorkspaceShellViewController` now applies keyed reconciliation for identity-stable pane stacks, so non-structural updates (pane status/title/content changes) reuse existing pane hosts instead of rebuilding the full canvas subtree. Structural layout changes still take the full rebuild path.

## Hosted pane path

The current pane-hosting split is:

- `OmuxAppShell` owns workspace layout, pane-stack chrome, and focus state
- `OmuxTerminalBridge` owns pane surfaces, attached sessions, resize propagation, hosted terminal pane views, and terminal palette application
- the bridge hosts a vendored Ghostty runtime-owned native surface and fails fast if that runtime is unavailable

This keeps the shell AppKit-first while preserving one narrow terminal-engine seam.

## Control-plane event stream

`omux events` now streams a mixed local event feed: OpenMUX-native `terminal.*` runtime events plus successful shared action events for the first wave of short `omux` commands.

Control-plane terminal event subscriptions now use a FIFO queue with head-indexed dequeue semantics (instead of repeated front-removal on an array). This preserves publish order and cancellation behavior while avoiding O(n) churn under sustained streams.

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
- `extensionPane.created`
- `extensionPane.updated`
- `extensionPane.closed`

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
- paste and drag/drop insertion are supported in the pane UI, but richer clipboard workflows are still follow-on work
- pane-tab drag behavior supports same-stack reorder, cross-stack merge, splitting, and modal pop-out, but still needs further polish for large-stack ergonomics
- floating pane modals reuse pane-stack renderers and can host popped-out pane tabs or plugin-owned extension panes without adding a second rendering stack
- workspace, split, pane-stack, and session restore exists, but still needs polish under more workflows

## Guidance for future changes

1. Keep terminal lifecycle, hosted pane views, runtime ownership, input encoding, and libghostty wiring inside `OmuxTerminalBridge`.
2. Treat direct pane input as the primary interaction model; UI chrome should enhance it, not replace it.
3. Keep pane-stack behavior in shared workspace actions so the AppKit shell, JSON-RPC, and `omux` stay aligned.
4. Preserve international keyboard correctness whenever input handling changes.
5. Keep `omux`, JSON-RPC, and the native shell pointed at the same live session objects.

## Performance invariants

- Workspace layout persistence in `OpenMUXAppDelegate` must be scheduled through `WorkspaceLayoutPersistenceCoordinator` so bursty `onChange` updates are coalesced. Lifecycle boundaries that need durability (quit, power-off, full-state writes) should call the coordinator flush path.
- `WorkspaceController` pane/session/tab/workspace target resolution should prefer `WorkspaceLookupIndexStore` and keep its invalidation aligned with every state mutation. If new mutations are added, update lookup-store invalidation in the same change.
- Controller-owned hook invocation and control-plane event emission should attach through `WorkspaceControllerPublication` so future open-by-design work extends one seam instead of reintroducing scattered inline wiring.

## Runtime power profile

Use this profile when changing hidden-surface rendering, display-link activity, or other visually idle runtime behavior.

For a shareable capture that you can run in a separate terminal while you use the app normally, use:

```bash
make power-profile
```

Or, if you want a label in the output directory and report:

```bash
Scripts/capture-openmux-power-profile.sh --label pre-opt
Scripts/capture-openmux-power-profile.sh --label post-opt --powermetrics
```

The script waits for `OpenMUXApp`, records branch/commit metadata, logs lightweight process snapshots while you work, and writes a final `report.md` plus raw artifacts under `.build/power-profile/` when you stop it with Ctrl-C.

### Scenario

Keep the scenario stable before and after the change:

1. Launch `OpenMUXApp`.
2. Create at least three workspaces.
3. Leave only one workspace visible.
4. In at least one inactive workspace, run a live but low-duty-cycle command such as:

```bash
while true; do printf 'hidden tick %s\n' "$(date +%T)"; sleep 5; done
```

5. In another inactive workspace, keep a second long-lived process alive, for example:

```bash
python3 -m http.server 8123
```

Record any deviations from that setup when you compare runs.

### Capture commands

Create a scratch directory first:

```bash
mkdir -p .build/power-profile
APP_PID="$(pgrep -x OpenMUXApp | tail -n 1)"
```

Then collect the comparable metrics:

```bash
ps -o pid=,etime=,%cpu=,rss=,thcount=,state=,command= -p "$APP_PID" \
  | tee .build/power-profile/openmux.ps.txt

top -l 1 -pid "$APP_PID" -stats pid,command,cpu,mem,threads,time \
  | tee .build/power-profile/openmux.top.txt

sample "$APP_PID" 5 1 \
  > .build/power-profile/openmux.sample.txt 2>&1 || true

vmmap -summary "$APP_PID" \
  > .build/power-profile/openmux.vmmap.txt 2>&1 || true
```

Optional process-energy capture:

```bash
sudo powermetrics --samplers tasks --show-process-energy -n 1 -i 1000 \
  > .build/power-profile/openmux.powermetrics.txt 2>&1 || true
```

If `powermetrics`, `vmmap`, or another command is unavailable or permission-restricted, keep the rest of the profile and record the missing measurement in the run notes instead of substituting fabricated data.

### Baseline for `optimize-inactive-workspace-power`

The baseline observation for this change was:

- main AppKit thread mostly blocked
- terminal IO reader threads mostly polling
- renderer/display activity still present in sampled stacks, including CVDisplayLink, Metal command queues, Core Animation commits, and IOSurface work

Treat that as the before-change reference when a fresh local pre-change capture is unavailable.

### After-change comparison

For the after profile, re-run the same scenario and compare:

- `%CPU`, RSS, elapsed runtime, and thread count
- whether sampled stacks still show renderer, CVDisplayLink, Metal, Core Animation, or IOSurface activity while inactive workspaces are hidden
- whether the inactive-workspace commands above stayed live and produced output when you switched back

Classify remaining background work explicitly as one of:

- expected visible-surface work
- unresolved hidden-surface work
- unrelated background work

## UI tests

OpenMUX has an XCUIAutomation GUI test suite that launches a sandboxed debug build of the app and drives it through the accessibility tree.

### Running the tests

Install XcodeGen before running the UI test target:

```bash
brew install xcodegen
```

```bash
# Full suite
make ui-test

# Single test class
make ui-test UI_TEST=PaneTests

# Single test method
make ui-test UI_TEST=PaneTests/testDragPaneTabToCreateSplit
```

`make ui-test` builds the app, wraps it into `.build/UITestApp/OpenMUX.app` with bundle ID `dev.fingergun.omux.debug`, registers it with `lsregister`, regenerates the Xcode project, and runs `xcodebuild test`.

Results land in `.build/ui-test-results.xcresult`. On CI the suite runs as a separate workflow (`.github/workflows/ui-tests.yml`) and only triggers for UI-relevant changes, including app shell sources, app entrypoint sources, UI tests, project generation files, build scripts, workflow files, and package metadata.

### Structure

| File | Purpose |
| --- | --- |
| `Tests/OmuxUITests/OmuxUITestsBase.swift` | Base class — launches the debug app, waits for `omux.mainWindow`, tears down |
| `Tests/OmuxUITests/A11yID+UITests.swift` | Mirror of `A11yID` constants for use in test targets |
| `Tests/OmuxUITests/*Tests.swift` | One file per feature area |

Each test class inherits `OmuxUITestsBase`. The `app` property is the running `XCUIApplication`.

### Accessibility identifiers

UI-testable elements get stable identifiers via `A11yID` in `Sources/OmuxAppShell/A11yID.swift`. Fixed identifiers are `static let` string constants; dynamic ones use a prefix constant (e.g. `A11yID.paneTabPrefix`) combined with a stable ID.

Set identifiers on `NSView` subclasses with:

```swift
setAccessibilityIdentifier(A11yID.myElement)
setAccessibilityRole(.button)   // or .group for containers
setAccessibilityElement(true)
```

Mirror every constant added to `A11yID.swift` in `A11yID+UITests.swift` so the test target can reference them without importing `OmuxAppShell`.

### Querying elements

Use `app.descendants(matching: .any).matching(predicate)` for elements with dynamic identifiers (role-based queries like `app.buttons` are unreliable for custom `NSView` subclasses):

```swift
nonisolated(unsafe) let pred = NSPredicate(format: "identifier BEGINSWITH %@", A11yID.paneTabPrefix)
let tabs = app.descendants(matching: .any).matching(pred)
```

For fixed identifiers use `app.groups[A11yID.commandPalette.rawValue]` directly.

### Adding a new test

1. Add accessibility identifiers to `A11yID.swift` for any new elements, and mirror them in `A11yID+UITests.swift`.
2. Add `setAccessibilityRole`, `setAccessibilityElement(true)`, and `setAccessibilityIdentifier` calls to the relevant `NSView` subclass.
3. Add a method to an existing `*Tests.swift` file, or create a new one that subclasses `OmuxUITestsBase`.
4. Verify locally with `make ui-test UI_TEST=MyTests/testMyNewTest` before pushing.
