## Why

OpenMUX now has the right shell and bridge seams for real Ghostty-backed panes, but the shipped path still falls back to the bridge-owned text host because `CGhostty` is neither vendored nor wired into the runtime host path. Closing that gap matters now because the product is terminal-first: real rendering, input handling, sizing, and terminal behavior need to come from the terminal engine itself rather than a fallback transcript host.

## What Changes

- Vendor the pinned Ghostty snapshot and build/module integration needed to expose `CGhostty` inside `OmuxTerminalBridge`.
- Implement a real bridge-owned `CGhosttyRuntime` host path that creates native AppKit-hosted pane surfaces from libghostty.
- Make the vendored runtime-backed pane surface the default hosted path when the pinned dependency is present, while keeping the existing fallback host as an explicit unavailable/recovery path.
- Preserve focus, resize propagation, keyboard correctness, and AppKit-first pane chrome while keeping all libghostty details behind the bridge.
- Update development docs and tests so the repo describes and verifies the real runtime-backed path instead of only the fallback seam.

## Goals

- Make visible panes use real libghostty-backed native surfaces in normal builds.
- Keep terminal-engine ownership inside `OmuxTerminalBridge`.
- Preserve international keyboard correctness and OpenMUX-native workspace ownership.
- Keep the fallback path narrow, explicit, and bridge-owned.

## Non-goals

- Adopting Ghostty's window, tab, or split model in place of OpenMUX workspace abstractions.
- Full Ghostty config-format compatibility.
- Browser, webview, or helper-daemon based terminal hosting.
- Expanding plugin or extension scope beyond the existing bridge boundary.

## Capabilities

### New Capabilities
- `ghostty-runtime-hosting`: vendored Ghostty runtime bootstrap and native AppKit-hosted surface creation for OpenMUX panes

### Modified Capabilities
- `ghostty-surface-hosting`: clarify that real vendored runtime-backed pane surfaces are the normal path, with fallback reserved for unavailable or failed runtime hosting
- `terminal-bridge`: extend bridge ownership to vendored runtime bootstrap, runtime app/surface lifecycle, and runtime-hosted pane coordination

## Impact

- Affected code: `Package.swift`, `Scripts/build-ghostty.sh`, `Vendor/ghostty/`, `Sources/OmuxTerminalBridge/*`, terminal bridge tests, and development docs
- Dependencies: vendored Ghostty snapshot and the local `CGhostty` bridge/module integration
- Systems: AppKit pane hosting, terminal lifecycle, keyboard/input routing, and resize/focus coordination
