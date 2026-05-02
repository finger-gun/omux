# Changelog

OpenMUX release notes are committed here before tagging a release. Use `Scripts/check-changes-since-release.sh` to inspect changes since the latest `v*` tag, then use `Scripts/prepare-release.sh <version>` with a reviewed changelog body to prepare the next release.

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
