## Context

OpenMUX already has the shell-side structure needed for a usable terminal workspace: AppKit windows, workspace tabs, nested split layouts, pane-local tab stacks, and shared UI/CLI/control-plane actions. What it does not yet have is the actual terminal surface promised by the project thesis. The current interactive fallback uses PTY-backed sessions rendered into a text view, which was the right bridge-preserving step to unblock direct typing and session continuity, but it is still an interim host rather than the intended pinned libghostty surface.

This change crosses `OmuxTerminalBridge`, `OmuxAppShell`, and the normalized input path, so it needs explicit design decisions before implementation. The primary constraint is architectural: libghostty must remain isolated behind the bridge, while the rest of the app continues to speak in OpenMUX-native concepts such as panes, sessions, focus, resize, and workspace layout. The secondary constraint is UX quality: keyboard correctness, especially ISO/EU and right-Option-sensitive behavior, cannot regress as real surface hosting replaces the text-view fallback.

## Goals / Non-Goals

**Goals:**
- Host a real libghostty-backed terminal surface inside each visible pane region in the AppKit shell.
- Keep all direct libghostty creation, attachment, callbacks, and teardown inside `OmuxTerminalBridge`.
- Preserve the existing workspace/session model so tabs, splits, pane stacks, and control-plane actions remain OpenMUX-native.
- Define one input/focus/resize path that works for real terminal surfaces without bypassing the shared normalization model.
- Retain a bridge-owned fallback path only as an implementation detail, not as the product-default pane host.

**Non-Goals:**
- Reworking the workspace layout model or pane-stack behavior beyond what hosting requires.
- Adding persistence, plugin runtime work, or distribution/signing concerns in this slice.
- Building a browser/webview terminal layer or introducing an always-on helper service outside the existing app process.
- Exposing libghostty types, handles, or lifecycle ownership directly to `OmuxAppShell`, `OmuxCore`, `omux`, or hooks.

## Decisions

### 1. The bridge owns a `TerminalSurfaceHost` abstraction, not raw Ghostty handles

`OmuxTerminalBridge` will grow an internal surface-hosting layer that can create, attach, resize, focus, and tear down a pane-backed terminal surface. The public bridge contract exposed upward will continue to use OpenMUX identifiers and bridge-defined descriptors rather than libghostty types.

**Why this way:** it preserves the manifesto’s “thin libghostty bridge” rule and keeps upstream churn localized.

**Alternatives considered:**
- **Expose libghostty handles directly to AppKit views:** rejected because it leaks the dependency boundary and makes shell code upstream-aware.
- **Let AppKit create Ghostty views directly:** rejected because it inverts ownership and makes terminal lifecycle a UI concern instead of a bridge concern.

### 2. AppKit hosts bridge-provided native views inside pane stacks

`WorkspaceWindowController` and pane-stack UI will host a bridge-provided native terminal view object inside each active pane region. Pane chrome such as local tab strips remains AppKit-owned, but the terminal surface itself becomes the primary interaction target rather than an `NSTextView` transcript.

**Why this way:** it matches the AppKit-first thesis while letting the bridge provide the actual terminal surface.

**Alternatives considered:**
- **Replace pane views with a custom drawing layer in app shell:** rejected because rendering belongs to libghostty, not the shell.
- **Use SwiftUI wrappers as the primary host:** rejected because the precision areas here are focus, keyboard routing, and native interaction semantics.

### 3. Normalized input remains the contract above the bridge, even if raw event data is also needed below it

The shell will continue to normalize macOS keyboard/text-input events into OpenMUX input events before deciding whether a key path is terminal-directed or shell-directed. Where libghostty surface hosting needs lower-level event details for fidelity, that data will be carried through bridge-owned translation helpers rather than bypassing normalization entirely.

**Why this way:** it preserves a single app-wide input model while allowing the bridge to encode terminal-engine-specific needs.

**Alternatives considered:**
- **Send raw `NSEvent` objects straight into the terminal surface:** rejected because it weakens testability and risks keyboard-behavior divergence between shell and terminal paths.
- **Force everything through text insertion only:** rejected because modifier-sensitive terminal behavior and non-text keys need richer semantics.

### 4. Focus and resize stay shell-driven, terminal effects stay bridge-driven

The shell remains the source of truth for which top-level tab, pane stack, and local pane tab is focused. When that focus changes, the shell tells the bridge which pane surface should become active. Likewise, pane geometry is measured in the AppKit host and propagated through the bridge as a resize/update event for the terminal surface and session.

**Why this way:** it keeps workspace focus logic independent from the terminal engine while still allowing the engine to react correctly.

**Alternatives considered:**
- **Let terminal surfaces decide workspace focus:** rejected because it entangles layout/focus ownership with rendering internals.
- **Let AppKit manipulate surface sizing directly without bridge coordination:** rejected because the bridge must remain authoritative for terminal lifecycle coordination.

### 5. The current PTY/text-view path becomes a fallback, not the primary pane experience

The existing interactive runtime and screen-buffer renderer remain useful as a fallback and testing aid while real surface hosting lands, but specs and app behavior will shift to treat the libghostty-backed surface as the normal path.

**Why this way:** it reduces migration risk and preserves a controlled fallback without redefining the product around it.

**Alternatives considered:**
- **Delete the fallback immediately:** rejected because it removes a proven recovery path while integrating an unstable upstream seam.
- **Keep both hosts equal indefinitely:** rejected because it muddies the product direction and weakens the terminal-first thesis.

## Risks / Trade-offs

- **[Upstream embedding API churn]** → Mitigation: keep the surface host narrow and internal to `OmuxTerminalBridge`, with minimal assumptions leaking upward.
- **[Keyboard fidelity regressions during host swap]** → Mitigation: specify ISO/EU, right Option, dead-key, and composition behavior explicitly and treat regressions as blocker-level.
- **[Focus bugs from mixing AppKit chrome with terminal-native view ownership]** → Mitigation: keep shell focus state authoritative and make responder restoration explicit at pane-stack boundaries.
- **[Fallback path complexity lingering too long]** → Mitigation: define the libghostty path as the default host in specs and keep the fallback bridge-owned rather than shell-owned.
- **[Accessibility gaps around hosted native terminal views]** → Mitigation: keep AppKit as the chrome/focus spine and add explicit accessibility considerations in the pane-hosting surface contract.

## Migration Plan

1. Add bridge-side abstractions for hosted terminal surfaces while preserving current pane/session APIs.
2. Introduce AppKit pane-host support for bridge-provided terminal views alongside the existing fallback host.
3. Route focus, resize, paste, and keyboard delivery through the new host path and validate parity with the current session model.
4. Promote libghostty-backed hosting to the default pane path once session lifecycle and input behavior are stable.
5. Keep the fallback path bridge-owned for recovery/testing until later cleanup work explicitly removes or narrows it.

Rollback is straightforward during this slice because the current PTY/text-view host already exists. If real surface hosting proves unstable, the app can revert to the fallback host without changing the workspace model or control plane.

## Open Questions

- What is the smallest bridge-level view/surface abstraction that remains stable if Ghostty’s embedding API shifts?
- Which parts of macOS text input need to be delivered as normalized OpenMUX events first versus bridge-owned raw event translations?
- How much accessibility metadata can the hosted terminal surface expose directly versus what AppKit chrome must supplement around it?
