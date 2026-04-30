## Why

OpenMUX now has a usable native shell with tabs, splits, pane stacks, and live sessions, but the current terminal surface is still a fallback text-view renderer rather than the libghostty-backed terminal promised by the manifesto. This change matters now because more shell chrome will not meaningfully improve the product until the terminal surface itself delivers native rendering, input fidelity, and a real bridge to the pinned Ghostty foundation.

## What Changes

- Introduce a real libghostty-backed pane surface hosted inside the AppKit shell.
- Define how the AppKit shell, workspace controller, and terminal bridge coordinate pane lifecycle, focus, resize, and session attachment without exposing libghostty types outside the bridge.
- Replace the current text-view-first terminal hosting path as the primary pane experience while preserving a bridge-owned fallback only where explicitly required.
- Tighten keyboard and input requirements around Ghostty surface hosting, including ISO/EU layouts, right Option / AltGr behavior, dead keys, and composition-sensitive input paths.
- Extend shell and bridge contracts so focus, paste, and resize operations target a live terminal surface rather than a transcript-like stand-in.
- Explicitly reject browser-based terminal embedding, background helper daemons as the default architecture, and any design that turns Ghostty internals into app-wide product types.

## Capabilities

### New Capabilities
- `ghostty-surface-hosting`: Hosts real libghostty-backed pane surfaces inside the AppKit shell and defines the shell-side lifecycle around them.

### Modified Capabilities
- `terminal-bridge`: Change requirements from bridge-owned PTY fallback behavior to a bridge that can create, own, and manage pinned libghostty-backed pane surfaces behind a narrow OpenMUX seam.
- `terminal-pane-hosting`: Change requirements so pane hosting is based on live terminal surfaces with correct native focus, resize, and paste/input routing rather than text-view rendering alone.
- `input-pipeline`: Change requirements so keyboard normalization and delivery remain correct when events flow into a hosted libghostty surface, especially for international layouts and composition-sensitive input.
- `macos-app-shell`: Change requirements so the native shell hosts real terminal surfaces in pane stacks while preserving AppKit-first focus and accessibility behavior.

## Impact

- Affected code: `Sources/OmuxTerminalBridge/*`, `Sources/OmuxAppShell/*`, relevant core workspace/session contracts, and developer documentation.
- Affected systems: pane lifecycle, session attachment, focus routing, resize propagation, paste/input handling, and AppKit terminal hosting.
- Dependencies: pinned Ghostty integration path and bridge-owned libghostty surface lifecycle.
- APIs/contracts: shared shell/bridge interfaces and any control-plane behavior that depends on live pane targeting.

### Goals

- Make the terminal surface itself match the manifesto’s terminal-first thesis.
- Keep libghostty behind a narrow, explicit `OmuxTerminalBridge` boundary.
- Preserve OpenMUX-native workspace concepts above the bridge.
- Improve rendering, input fidelity, and performance without introducing vendor lock-in or monolithic shell behavior.

### Non-goals

- Reworking workspace structure beyond what is necessary to host real terminal surfaces.
- Adding browser-heavy UI, webview-based terminal embedding, or AI-specific workflows.
- Introducing a full plugin runtime, persistence overhaul, or packaging/distribution changes in this slice.
- Copying cmux or any other GPL implementation; any behavioral inspiration remains clean-room only.
