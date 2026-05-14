# Changelog

OpenMUX release notes are committed here before tagging a release. Use `Scripts/check-changes-since-release.sh` to inspect changes since the latest `v*` tag, then use `Scripts/prepare-release.sh <version>` with a reviewed changelog body to prepare the next release.









## 0.16.0

### Added

- Added floating pane modals for extension content, including support for opening Markdown Preview as either a docked pane tab or a floating modal.
- Added pane pop-out and dock-back workflows so pane tabs can be torn out into floating modals and docked back into the workspace layout.
- Added `--modal`, `--pane-tab`, and `--presentation pane-tab|modal` to `omux markdown-preview`, plus `--presentation pane-tab|modal` to `omux extension-pane`, so plugins and scripts can choose initial pane presentation.
- Added `[plugins.markdown-preview].presentation` to OpenMUX config so Markdown Preview can default to docked or modal presentation.
- Added modal-aware control-plane workspace and pane metadata, including floating modal IDs, focused modal state, and modal frame data.

### Changed

- Added architecture and plugin documentation for modal presentation, pane ownership, and extension-pane presentation behavior.

### Fixed

- Fixed startup rendering and workspace restore so terminal surfaces are created lazily for visible panes and hidden restored panes are started when first used.
- Fixed restored workspace behavior to avoid unnecessary terminal initialization across hidden tabs and floating-only layouts.
- Fixed initial terminal snapshot handling so startup renders reuse cached terminal content more reliably.

## 0.15.2

### Changed

- Improved pane-tab drag and drop so existing pane stacks are updated more smoothly and tabs can be reordered more reliably within a stack.
- Improved workspace update performance by reconciling more layout changes in place and coalescing layout persistence work.
- Improved control-plane and workspace target resolution efficiency with faster event queues and indexed workspace, pane, tab, and session lookups.

### Fixed

- Fixed Markdown Preview watch behavior so preview panes rerender when the source Markdown file changes, including previews opened from terminal path activation.
- Fixed Markdown Preview reload behavior to preserve scroll position across preview updates and pane refreshes.
- Fixed preview and workspace lifecycle cleanup so watch tasks and extension-pane refreshes do not linger or reload unnecessarily.

## 0.15.1

### Changed

- Improved terminal startup by resolving Ghostty resources from packaged app bundles and local vendored development layouts automatically.
- Ensured managed Ghostty output keeps `shell-integration = detect` enabled so shell integration remains available for OpenMUX features.

### Fixed

- Fixed zsh integration in restored scrollback sessions by setting `ZDOTDIR` to Ghostty’s integration directory when available.
- Fixed a workspace persistence timing issue so pane working-directory updates can be persisted reliably after state restore.

## 0.15.0

### Added

- Added `omux config open` and a matching command-palette action for opening `~/.omux/config.toml` in the configured editor or macOS default text editor.
- Added remote extension registries for hooks and plugins, including default official registries, `[registries]` configuration, and `omux hooks/plugins discover`, `install`, `update`, and `uninstall` workflows.
- Added richer plugin capabilities for extension panes, including opt-in host-mediated action callbacks, native Configuration menu contributions from installed plugin manifests, and support for the registry-hosted Settings UI plugin.
- Added JSON config export/apply support through `omux config get --json` and `omux config apply --json-file`, allowing tools and plugins to edit supported settings through OpenMUX validation and reload behavior.
- Added inline workspace renaming from the sidebar by double-clicking a workspace name or choosing Rename from its context menu.

### Changed

- Updated plugin and hook documentation with registry formats, install behavior, menu contribution metadata, extension-pane action callbacks, and Settings UI usage.
- Updated getting-started and configuration docs to cover `omux config open`, registry settings, installed package receipts, and plugin-managed settings workflows.

### Fixed

- Fixed command-palette mouse navigation so hovering and clicking results updates selection and invokes the intended command without dragging the window.

## 0.14.0

### Changed

- Changed the workspace command palette shortcut from `Cmd+K` to `Cmd+P`, while keeping `Cmd+Shift+P` for command search.
- Changed custom keybinding overrides so rebinding an action automatically replaces that action's previous default chord.

### Migration notes

- If you prefer the previous workspace search shortcut, add `"cmd+k" = "command-palette.workspace"` under `[keys]` in your OpenMUX configuration.

## 0.13.0

### Added

- Added collapsible workspace sections in the sidebar so pane rows can be hidden or shown per workspace from the disclosure control or workspace context menu.

### Changed

- Changed the workspace sidebar to keep long workspace lists scrollable while leaving update notices visible.

## 0.12.0

### Added

- Added a keyboard-first command palette: `Cmd+K` opens workspace search, and `Cmd+Shift+P` opens command search for OpenMUX actions and the shared `omux` command catalog.
- Added a command-palette theme switcher with sub-palette navigation, live preview, and persisted theme selection.
- Added `omux pane-status` and the `paneStatus` control-plane API so hooks, plugins, and scripts can mark panes as working, indeterminate, error, needs-input, idle, or clear.
- Added pane status indicators in the app shell, including animated/colored orbs in pane chrome and sidebar rows.
- Added `ui.panes.idle_status_clear` to configure when idle/completed pane status indicators are removed.
- Added copy-pasteable hook examples for bootstrapping workspaces, notifications, pane status updates, recent-directory tracking, and activated-path opening.

### Changed

- Changed command and action metadata to use a shared CLI command catalog so `omux` help and the command palette stay aligned.
- Changed hook documentation to show pane-status automation and the expanded examples directory.

### Fixed

- Fixed pane-tab drag splitting so drops split the intended child pane region and preserve existing grid layouts.
- Fixed pane-tab title rendering so short titles are not unexpectedly middle-truncated.

## 0.11.0

### Added

- Added drag-and-drop pane tab layout management. Drag a pane tab to pane edges to split left, right, up, or down; drag to the title bar or canvas edges for full-span root splits; drag onto another pane stack's tab strip to merge it there.
- Added drag feedback for pane-tab moves, including a tab ghost, split and merge previews, and Escape cancellation.
- Added `[ui.panes].inactive_opacity` for configuring inactive pane dimming, plus `omux config inactive-opacity <0.0-1.0>` to update it and reload configuration from the CLI.

### Changed

- Changed active pane presentation so the focused pane only appears fully active while the OpenMUX window is key, making inactive windows visually distinct.
- Changed pane-tab closing behavior so single-pane stacks in split layouts and non-last workspace tabs can be closed where appropriate.

### Fixed

- Fixed GhosttyKit setup on Xcode 26.4 by preferring Homebrew's patched `zig@0.15` before the repo-local downloaded Zig fallback, while keeping PATH and download fallbacks available.
- Fixed CI reliability by bounding the macOS verification job runtime.

## 0.10.0

### Added

- Added a plugin ecosystem for registering external `omux` commands from `~/.omux/plugins/`, inspecting them with `omux plugin list` and `omux plugin path`, and managing configurable bundled plugins with the interactive `omux plugins` picker.
- Added extension panes and the `omux extension-pane` control-plane CLI so plugins can create, update, and close shell-owned HTML or placeholder panes without allocating terminal sessions.
- Added the bundled Markdown Preview plugin, enabled by default, with `omux markdown-preview <file>`, watch mode, pane reuse, split-axis selection, GitHub Flavored Markdown rendering, local image resolution, and JavaScript-disabled preview hosting.
- Added Command-click terminal text activation for readable local Markdown paths, plus the `terminal.textActivated` event and `input:terminal-text-activated` hook payload for plugin workflows.
- Added configurable semantic UI icons for workspace rows, terminal rows, and pane tabs through `[ui.icons]`, with a bundled Symbols Nerd Font fallback and theme-aware icon colors.
- Added `[plugins.markdown-preview]` configuration for enabling the bundled preview plugin and choosing preview renderer/theme behavior.

### Changed

- Improved workspace sidebar reordering with drag groups, animated insertion previews, and clearer drag feedback.
- Improved pane tab readability by truncating long titles in the middle and refining tab sizing behavior.
- Updated project documentation around getting started, configuration, plugin development, Markdown Preview, contributor workflows, and the roadmap.
- Updated the Ghostty build stamp to account for OpenMUX Ghostty API revision changes.

### Fixed

- Fixed persisted scrollback capture and restore to use more accurate scrollback snapshots, preserve styled terminal output where safe, and avoid replaying duplicate prompt/startup noise.
- Fixed terminal host synchronization around window/surface lifecycle so hosted Ghostty views track shell state more reliably.
- Fixed self-update downloads with progress reporting and clearer download failure errors.
- Fixed sidebar and tab controls so clicks on those controls do not accidentally drag the window.

## 0.9.0

### Added

- Added split resizing for the active pane, including menu actions and default shortcuts for equalizing splits and moving split dividers up, down, left, or right.
- Added configurable keybinding actions for pane resizing: `pane.resize-equalize`, `pane.resize-up`, `pane.resize-down`, `pane.resize-left`, and `pane.resize-right`.

### Changed

- Updated configuration documentation with the new pane-resizing shortcuts and action names.

## 0.8.0

### Fixed

- Fixed successful `omux update` installs so temporary update staging directories are cleaned up after the helper finishes installing the new app bundle.

### Changed

- Updated development documentation with the local cleanup workflow and dry-run guidance.

## 0.7.0

### Added

- Added fuzzy search to the interactive `omux theme` picker. Type to filter by theme id or display name, use Backspace to edit the filter, Enter to apply the highlighted theme, and Escape or Ctrl-C to cancel.
- Added 10 visually distinct built-in themes: `banana-blueberry`, `borland`, `c64`, `grass`, `hot-dog-stand`, `laser`, `man-page`, `matrix`, `red-sands`, and `under-the-sea`.

### Changed

- Changed the interactive theme picker so `q` is treated as search input instead of a cancel shortcut; Escape and Ctrl-C remain the cancel controls.
- Refreshed README and theme documentation to keep the root overview concise while linking to deeper configuration and theme details.

## 0.6.0

### Added

- Added persisted visual scrollback restore for terminal panes. OpenMUX now saves bounded per-pane terminal history locally and replays safe scrollback before the fresh shell prompt appears after app restart.
- Added `terminal.persist_scrollback`, `terminal.persist_scrollback_lines`, and `terminal.persist_scrollback_bytes` config settings. Persisted scrollback is enabled by default with a 4,000-line and 1 MiB per-pane cap.
- Added `omux history clear` for clearing saved terminal history, with scopes for all panes, focused pane, pane/pane-tab, tab, workspace, and session.
- Added the `terminal.history.clear` control-plane method for clearing persisted history through automation.

### Changed

- Changed workspace persistence to store larger scrollback payloads as separate Application Support files instead of embedding them in workspace JSON or UserDefaults.
- Changed restored pane launch so saved terminal output is replayed through an OpenMUX-owned wrapper before the login shell starts, with terminal reset protection and alternate-screen safety filtering.
- Changed `omux history` documentation to clarify persisted history, live terminal text, privacy considerations, and cleanup behavior.
- Changed app startup update checks so users can disable automatic checks with `auto_check_update = false`.

### Fixed

- Fixed update availability caching so OpenMUX rechecks after the installed app version changes, instead of suppressing a newer release notice because of a previous cache entry.
- Fixed update checks so they run in the background and do not block app startup.
- Fixed CLI install menu status so the app can distinguish missing, installed, stale, and externally managed `omux` CLI links.
- Fixed persisted scrollback cleanup so repeated prompt/login tail noise is deduplicated and stale trailing prompt-only lines are not restored as useful history.
- Fixed `omux history clear` so running panes clear their live screen/scrollback when available, including a local clear fallback for the pane that invoked the command.

## 0.5.0

### Added

- Added `omux version` for checking the installed OpenMUX version offline.
- Added `omux update` for installing newer GitHub Release app archives from the CLI, including release metadata lookup, SHA-256 checksum verification, temporary staging, app bundle validation, prompted OpenMUX closure, detached helper installation, rollback protection, and `/Applications` / `~/Applications` target handling without hidden privilege escalation.
- Added passive app-side update checks and a workspace sidebar notice that shows when a newer version is available and points users to `omux update`.
- Added `terminal.inputSent` events and the `terminal-input-sent` hook for explicit OpenMUX input actions such as `omux run` and `send-text`.
- Added bounded command output context to command completion and command failure hooks when recent terminal output is available.
- Added sidebar terminal-row selection for focusing pane-local tabs directly from the workspace column.
- Added more built-in themes from selected iTerm2 Color Schemes presets, including Atom One, Ayu, Fairyfloss, Firewatch, GitHub, Gruvbox hard, Material, One Half, OneNord, Snazzy, Synthwave, Tomorrow Night Eighties, Vesper, and Wez variants.

### Changed

- Changed release packaging so app and CLI artifacts include version metadata used by `omux version` and the self-update flow.
- Changed terminal action dispatch so supported runtime actions are surfaced as OpenMUX-native hooks and control-plane events instead of remaining internal bridge details.
- Changed command completion handling so hooks can receive explicit command, cwd, exit, duration, and bounded output context without treating native typing as command telemetry.
- Reorganized app menus around current workspace, pane, pane-tab, and sidebar actions.
- Expanded user and maintainer documentation for updating, release artifacts, hooks, terminal events, themes, and current development commands.

## 0.4.0

### Added

- Added `workspace.default_root_path` so first launch, new app-created workspaces, and `omux open` without a path can start from a configured directory.
- Added configurable OpenMUX keybindings through the `[keys]` table, including rebinding shortcuts and mapping a chord to `"none"` when a terminal application should receive it instead.
- Added inline pane-tab controls in pane headers, including an add button and close affordances for multi-tab stacks.
- Added CLI and control-plane coverage for closing workspaces, removing panes, cycling visible panes, and cycling pane-local tabs.

### Changed

- Changed the default shortcut ladder to make workspace, pane, and pane-tab actions more consistent: workspace creation/close use `Cmd+N` / `Cmd+Shift+N`, pane tabs use `Cmd+T` / `Cmd+W`, active panes use `Cmd+Shift+W`, and modified Backspace remains terminal-owned unless explicitly rebound.
- Changed menu shortcuts to follow the active keybinding configuration after startup and `omux config reload`.
- Changed config rendering so theme changes preserve the workspace and keybinding sections.
- Documented the new workspace root, keybinding syntax, shortcut actions, and expanded CLI command set.

## 0.3.0

### Added

- Added `omux history` for reading bounded terminal history from the active workspace, a specific pane, or all panes, with text and JSON output for scripts and hooks.
- Added the `terminal.history` control-plane method with bounded line/byte limits and per-pane metadata, including workspace, tab, pane, session, working-directory, truncation, and availability details.
- Added persisted pane scrollback snapshots so restored workspaces can retain recent terminal context without replaying commands.

### Changed

- Changed workspace restoration to preserve pane working directories when OpenMUX can recover them from terminal state.
- Changed workspace persistence to keep backups of previous snapshots before overwriting or clearing stored workspace state.
- Documented terminal history usage for development workflows and hooks, including guidance that history can contain sensitive terminal output.

### Fixed

- Fixed restored pane state so recent scrollback and working-directory context survive app relaunches more reliably.

## 0.2.0

### Added

- Added a committed release-prep workflow with `VERSION`, `CHANGELOG.md`, change inspection, release preparation scripts, and the `create-release-notes` agent skill.
- Added runtime-hosted terminal support for standard macOS edit commands, clipboard callbacks, terminal selection queries, and shell-quoted dropped-file path paste.

### Changed

- Changed terminal input routing so OpenMUX only intercepts documented app shortcuts while forwarding unclaimed Command, Option, Control, modified Backspace, arrow-key, dead-key, compose, IME, and right-Option international input paths to Ghostty with key and modifier facts preserved.
- Changed release packaging to read the product version from `VERSION` by default while still allowing `RELEASE_VERSION` overrides.

### Fixed

- Fixed runtime-hosted pane pointer handling for focus-on-click ordering, stale mouse-button release reconciliation, hover exit behavior, scroll events, and pressure events.
- Fixed preedit and committed-text handling so marked text updates, cancelled composition, and generated text are routed without duplicate terminal input.

## 0.1.0

### Added

- Added the initial native macOS OpenMUX app shell with workspaces, top-level tabs, split panes, pane-local tab stacks, and persistent interactive shell sessions.
- Added bridge-backed terminal panes through the vendored Ghostty runtime, kept behind the OpenMUX terminal bridge boundary.
- Added the local `omux` CLI and JSON-RPC control plane for opening workspaces, listing state, creating tabs and splits, targeting live sessions, sending text, running commands, raising notifications, and streaming events.
- Added external hook support and a mixed local event stream for terminal runtime events and shared workspace/session actions.
- Added OpenMUX-owned configuration and theme foundations with `~/.omux/config.toml`, user theme overrides, generated Ghostty config artifacts, built-in themes, and theme CLI commands.
- Added early keyboard-correctness support for native AppKit terminal input, including ISO layout, Option/Alt, dead-key, compose, and IME-sensitive flows.
- Added unsigned macOS release packaging for both `OpenMUX.app` and the bundled `omux` CLI, including checksums and a GitHub Release workflow.
- Added an app-bundled CLI installer so users can install `omux` from the app menu or from `/Applications/OpenMUX.app/Contents/MacOS/omux install-cli`.

### Known limitations

- Release artifacts are ad-hoc signed but not yet Developer ID signed, notarized, distributed as a DMG, or published through Homebrew.
