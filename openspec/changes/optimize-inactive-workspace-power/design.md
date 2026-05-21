## Context

OpenMUX currently hosts terminal panes through AppKit shell views backed by bridge-owned libghostty surfaces. A live sample of a visually idle OpenMUX process showed the main AppKit thread mostly blocked, terminal IO reader threads mostly polling, but multiple renderer threads, CVDisplayLink threads, Metal command queues, Core Animation commits, and IOSurface activity still present. That points toward presentation/rendering lifecycle work as the likely idle-power target.

The core constraint is that inactive workspaces are not inactive processes. Users may leave agents, web servers, SSH sessions, builds, or long-running shells in non-active workspaces. OpenMUX must keep those sessions live and observable while avoiding GPU/display work for surfaces the user cannot see.

## Goals / Non-Goals

**Goals:**

- Separate terminal session liveness from terminal surface presentation visibility.
- Quiesce rendering/display work for non-visible terminal surfaces.
- Keep inactive workspace PTYs, child processes, terminal state, title/progress/bell events, scrollback, hooks, and control-plane events alive.
- Keep libghostty-specific occlusion details behind `OmuxTerminalBridge`.
- Provide a repeatable before/after power profile for CPU, memory, thread count, renderer/display-link stacks, and process energy.

**Non-Goals:**

- Do not suspend, throttle, pause, kill, or detach inactive workspace child processes.
- Do not introduce a daemon, telemetry service, browser terminal, or webview-first architecture.
- Do not change keyboard routing, modifier semantics, dead-key behavior, IME behavior, or pane focus rules.
- Do not expose libghostty types or renderer concepts to `OmuxAppShell` or `OmuxCore`.

## Decisions

### D1: Model Visibility As OpenMUX Surface Presentation State

Add a bridge-facing visibility concept such as `setSurfaceVisible(paneID:isVisible:)` or `setHostedSurfacePresentationState(...)` instead of exposing libghostty occlusion directly.

Rationale: The shell knows which workspace/tab/modal/window is visible, but the bridge owns terminal-engine objects. The boundary should remain OpenMUX-native: panes and hosted surfaces are visible or hidden; libghostty occlusion is an implementation detail.

Alternative considered: Call `ghostty_surface_set_occlusion` directly from the shell. Rejected because it leaks upstream API details across the bridge boundary.

### D2: Derive Visibility From AppKit Shell State

Derive the visible terminal pane set from active workspace, focused tab, focused pane-stack tab, visible floating modals, and containing window visibility/occlusion.

Rationale: Visibility is a shell concern, not a terminal-engine layout concern. AppKit already knows whether the window is minimized/hidden/occluded, and workspace rendering already has stable pane identities.

Alternative considered: Let libghostty infer visibility from view attachment alone. Rejected because inactive workspace surfaces may remain alive but detached or reused by reconciliation, and view attachment alone does not encode OpenMUX workspace/tab visibility.

### D3: Keep Session Liveness Independent From Presentation Occlusion

Occluding a surface must not free the surface, detach the session, close the PTY, suppress IO, or disable terminal action events. The intended effect is presentation quiescing only.

Rationale: Terminal-first behavior requires background work to continue. The product would be less useful if changing workspaces paused builds, agents, shells, or servers.

Alternative considered: Destroy hidden surfaces and recreate them from scrollback when visible. Rejected because it would break live process semantics and increase complexity around terminal state restoration.

Implementation note: libghostty's VT state is renderer-independent, so occlusion is expected to preserve grid/cursor/scrollback and shell-integration-derived state. OpenMUX still must keep the embedding callbacks and effects handling alive while surfaces are hidden so action events (for example title/bell/clipboard/progress) remain observable.

### D4: Refresh On Visibility Restoration

When a hidden surface becomes visible, the bridge should mark it visible and request a presentation refresh/tick so the user sees current output without waiting for the next terminal event.

Rationale: Hidden sessions can produce output while rendering is quiesced. Reactivation should be visually current and should not depend on new output arriving.

Alternative considered: Rely only on future terminal output to repaint. Rejected because a completed background command could leave the reactivated surface stale.

### D5: Treat App Focus Separately From Surface Focus

Review `setSurfaceFocused` behavior so pane focus changes do not incorrectly report whole-app focus loss when the OpenMUX window remains active. App/window focus should be driven by window lifecycle; surface focus should be driven by pane focus.

Rationale: Focus and visibility are adjacent but not the same. Incorrect app focus signaling can alter cursor, rendering, or terminal focus reporting behavior in ways unrelated to occlusion.

Alternative considered: Continue using pane focus to drive app focus. Risky because unfocusing one pane may create app-level side effects for other live panes.

### D6: Add A Manual Measurement Profile Before Automating Heavily

Start with a documented/scriptable local profile using macOS tools:

- `ps` or `top` for CPU, memory, elapsed time, and thread count.
- `sample` for renderer, Metal, Core Animation, IOSurface, CVDisplayLink, and IO stacks.
- `powermetrics --samplers tasks --show-process-energy` where permitted for process energy.
- `vmmap -summary` for memory footprint when useful.

Rationale: macOS energy measurement is permission-sensitive and environment-dependent. A lightweight repeatable profile gives immediate before/after signal without adding a new always-on monitor or external dependency.

Alternative considered: Build in-app telemetry. Rejected for this change because it would add product surface and background work to solve a background-work problem.

## Risks / Trade-offs

- [Risk] Occlusion may stop more than rendering in the runtime. -> Mitigation: test hidden sessions with active output, title/progress updates, bells, and scrollback capture before relying on occlusion.
- [Risk] Hidden sessions may accumulate terminal state but fail to repaint when visible. -> Mitigation: explicitly refresh or tick when marking a surface visible.
- [Risk] Window occlusion notifications may be noisy or incomplete. -> Mitigation: centralize visibility derivation and make repeated visibility calls idempotent.
- [Risk] Measurement data varies by hardware, OS version, display refresh rate, and active shell workload. -> Mitigation: compare before/after profiles using the same scenario, sample duration, app build, and host machine.
- [Risk] Fixing rendering activity could mask a separate CPU issue from background indexing, update checks, or plugins. -> Mitigation: sample stacks remain part of the profile, and opt-in plugin loops such as Markdown Preview are tracked separately from default idle behavior.

## Migration Plan

1. Add tests against runtime/bridge fakes to prove visibility transitions are sent without destroying sessions.
2. Implement bridge API and runtime mapping behind `OmuxTerminalBridge`.
3. Wire AppKit shell visibility derivation into reconciliation and window lifecycle.
4. Run existing Swift tests.
5. Capture before/after manual runtime power profiles using the documented scenario.
6. Rollback strategy: disable shell visibility propagation while keeping the bridge API inert if runtime occlusion causes regressions.

## Resolved Questions

- App/window lifecycle signaling should use a combined set of notifications (`didMiniaturize` / `didDeminiaturize`, `didChangeOcclusionState`, app hide/unhide, app active/inactive) and reconcile through one idempotent visibility derivation path rather than per-notification side effects.
- Implementation should roll out in two phases: first mark inactive workspace/tab/pane-stack/modal surfaces hidden, then add full window/app occlusion gating after validation.
- Hidden-surface correctness should be enforced with explicit bridge/runtime and shell tests that keep sessions alive while validating continued action/effects flow (title/progress/bell/clipboard/child lifecycle where test infra supports it) and visible refresh on unhide.
