# Changelog

OpenMUX release notes are committed here before tagging a release. Use `Scripts/check-changes-since-release.sh` to inspect changes since the latest `v*` tag, then use `Scripts/prepare-release.sh <version>` with a reviewed changelog body to prepare the next release.

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
