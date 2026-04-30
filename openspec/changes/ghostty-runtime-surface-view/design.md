## Context

The previous `ghostty-surface-integration` change moved pane hosting behind `OmuxTerminalBridge` and taught the AppKit shell to embed a bridge-provided hosted pane view. That change intentionally stopped at the hosting seam: `CGhosttyRuntime.makeHostedSurfaceView(...)` still returns `nil`, the repo does not vendor a Ghostty snapshot beyond `Vendor/ghostty/PINNED_REF`, and visible panes therefore still use the bridge-owned fallback text host.

This change finishes the runtime path. It must do so without leaking libghostty types outside `OmuxTerminalBridge`, without replacing OpenMUX-native workspace abstractions with Ghostty layout concepts, and without regressing keyboard correctness for ISO/EU layouts and right-Option-sensitive input.

## Goals / Non-Goals

**Goals:**
- Vendor the pinned Ghostty snapshot needed to build and expose `CGhostty`.
- Let `CGhosttyRuntime` create and own native AppKit-hosted pane surfaces.
- Keep the real runtime host path inside the existing bridge boundary and hosted-pane seam.
- Preserve a bridge-owned fallback path when the vendored runtime is unavailable or initialization fails.
- Keep focus, resize, and input behavior consistent between runtime-backed and fallback-hosted panes.

**Non-Goals:**
- Replacing OpenMUX workspace/tab/pane models with Ghostty's own layout model.
- Adding Ghostty config compatibility as a user-facing feature.
- Removing the fallback host entirely.
- Expanding this change into hooks, plugins, persistence, or control-plane redesign.

## Decisions

### 1. Vendor the pinned Ghostty snapshot instead of relying on a machine-local install

OpenMUX already documents a vendored terminal-engine path and a pinned reference. This change will make that real by checking in the pinned snapshot and wiring the build/module integration from the repository tree.

**Why:** A vendored snapshot keeps the bridge inspectable, reproducible, and aligned with the product's "open by design" and "performance is a feature" principles. A hidden machine-local install would make the real terminal path fragile and non-reproducible.

**Alternatives considered:**
- **System-installed Ghostty library**: rejected because it makes builds and bug reports machine-dependent.
- **Continue stubbing `CGhosttyRuntime`**: rejected because it preserves the architectural seam but not the actual terminal-first experience.

### 2. Keep all upstream runtime state inside `OmuxTerminalBridge`

The bridge will own vendored Ghostty app/runtime objects, pane-surface objects, and any AppKit host views needed to embed them. Higher layers will continue to interact only in terms of OpenMUX-native panes, sessions, surfaces, and normalized input.

**Why:** This preserves the narrow bridge boundary and keeps the shell AppKit-first without making the shell understand libghostty internals.

**Alternatives considered:**
- **Expose raw Ghostty handles to the shell**: rejected because it violates the bridge boundary.
- **Move surface management into `OmuxAppShell`**: rejected because terminal lifecycle would leak into the shell layer.

### 3. Do not run two independent live terminal sessions for one pane

The runtime-backed path must become the real hosted terminal for that pane, not a visual layer on top of a separate fallback PTY session. If snapshot, command injection, or resize behavior cannot be satisfied from the vendored runtime path, those bridge abstractions need to adapt rather than mirror two live sessions.

**Why:** Dual sessions would desynchronize shell state, working directory, scrollback, and automation behavior.

**Alternatives considered:**
- **Keep the current `InteractiveTerminalRuntimeSession` as the "real" session and layer a Ghostty view on top**: rejected because libghostty's embedded surface lifecycle is not a cosmetic renderer for an arbitrary external PTY in the current bridge design.

### 4. Keep fallback explicit and bridge-owned

The fallback text host remains important for unsupported environments, broken vendored builds, and testability. The bridge will keep deciding between runtime-backed hosting and fallback hosting, but the docs and tests will treat fallback as an unavailable/recovery path rather than the normal terminal experience.

**Why:** This preserves resilience while making the intended production path clear.

## Risks / Trade-offs

- **[Vendored Ghostty snapshot is large and build-sensitive]** -> Keep build integration scripted, pinned, and documented; limit touched surfaces to the bridge path.
- **[Upstream embedded runtime APIs may not map cleanly to the current session/snapshot model]** -> Adapt the bridge session abstraction where needed rather than faking a second session underneath.
- **[Keyboard and composition behavior could regress when switching from fallback text input to runtime-backed input]** -> Preserve normalized-input tests and add runtime-host-specific coverage where the vendored path can be exercised.
- **[Runtime host initialization may fail at build time or run time]** -> Keep the existing fallback host path and make failure explicit in code and docs.

## Migration Plan

1. Vendor the pinned Ghostty snapshot and expose the local build/module integration.
2. Extend `CGhosttyRuntime` with real app/surface/view lifecycle code.
3. Update bridge session/host coordination so runtime-backed panes are the real hosted path.
4. Preserve fallback behavior behind the bridge.
5. Update docs and tests to describe the real-host default path.

## Open Questions

- Which parts of the current snapshot/control-plane model can be satisfied directly from the vendored Ghostty embedded surface API versus needing a bridge-side adaptation?
- What is the narrowest acceptable build integration for `CGhostty` inside SwiftPM without spreading upstream build details across unrelated modules?
