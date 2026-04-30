## 1. Vendored runtime setup

- [x] 1.1 Vendor the pinned Ghostty snapshot and replace the placeholder dependency layout with the files needed for local build/module integration.
- [x] 1.2 Update the package/build integration so `CGhostty` can be imported only from `OmuxTerminalBridge`.
- [x] 1.3 Document any pinned-snapshot or build-script assumptions needed for local development.

## 2. Bridge runtime integration

- [x] 2.1 Implement real `CGhosttyRuntime` app and surface lifecycle ownership behind the existing bridge boundary.
- [x] 2.2 Implement native AppKit-hosted runtime surface view creation for attached panes.
- [x] 2.3 Update bridge session coordination so runtime-hosted panes do not silently fall back to the text host when the vendored runtime is available.
- [x] 2.4 Preserve fallback hosting as an explicit unavailable/recovery path when the vendored runtime cannot be used.

## 3. Input, sizing, and docs

- [x] 3.1 Preserve focus, resize, and normalized keyboard behavior on the runtime-hosted pane path.
- [x] 3.2 Add or update tests covering runtime host creation and bridge ownership boundaries.
- [x] 3.3 Update development docs to describe the real runtime-hosted path and the remaining fallback role.
