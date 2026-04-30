## 1. Bridge surface foundation

- [x] 1.1 Add bridge-owned abstractions for creating, attaching, resizing, focusing, and tearing down libghostty-backed pane surfaces without exposing libghostty types outside `OmuxTerminalBridge`.
- [x] 1.2 Integrate the pinned Ghostty hosting path into `GhosttyTerminalBridge` while preserving the existing session and pane identifiers used by the rest of the app.
- [x] 1.3 Keep or narrow the current PTY/text-view host as a bridge-owned fallback path rather than the primary pane experience.

## 2. AppKit pane hosting

- [x] 2.1 Update AppKit pane hosting so each visible pane stack can embed a bridge-provided native terminal surface view.
- [x] 2.2 Route pane focus, first-responder restoration, and resize propagation through the new hosted-surface path without moving workspace focus ownership out of the shell.
- [x] 2.3 Preserve pane-stack tab chrome and other shell UI responsibilities around the hosted terminal surface without leaking terminal-engine details into shell code.

## 3. Input and session behavior

- [x] 3.1 Update the input pipeline and shell event delivery so terminal-directed input reaches hosted libghostty surfaces through the shared normalized model and bridge-owned translation helpers.
- [x] 3.2 Verify paste, control keys, navigation keys, and composition-sensitive input still target the active live pane session through the hosted-surface path.
- [x] 3.3 Preserve right-Option / AltGr, dead-key, and ISO/EU keyboard behavior when real terminal surface hosting replaces the text-view-first pane host.

## 4. Validation and docs

- [x] 4.1 Add bridge and app-shell validation coverage for hosted surface lifecycle, pane creation/teardown, focus changes, and resize behavior.
- [x] 4.2 Add validation coverage for keyboard/input correctness on the hosted-surface path, including international-layout-sensitive behavior.
- [x] 4.3 Update developer-facing docs to describe the libghostty-backed pane host, the retained bridge boundary, and any intentionally temporary fallback behavior.
