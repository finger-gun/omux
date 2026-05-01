## Context

OpenMUX currently embeds `libghostty` with `action_cb: { _, _, _ in false }` in `Sources/OmuxTerminalBridge/CGhosttyRuntime.swift`. That keeps Ghostty app-shell assumptions from leaking into OpenMUX, but it also drops useful terminal-session signals such as cwd changes, title updates, command completion, progress, and host requests like URL opening or desktop notifications.

The codebase is now in a position to do better. `OmuxTerminalBridge` already owns the only `libghostty` boundary. `OmuxAppShell` already owns workspace, pane, notification, and chrome behavior. `OmuxHooks` already provides external automation seams, and `OmuxControlPlane` already defines a local OpenMUX-native contract. The missing piece is a typed event path between the bridge and those consumers.

This change is cross-cutting, but the constraint is simple: Ghostty types stay inside `OmuxTerminalBridge`, and everything outside that module consumes OpenMUX-native terminal action/event values.

## Goals / Non-Goals

**Goals:**
- Introduce a typed OpenMUX-native terminal action/event model for selected Ghostty upcalls.
- Preserve the narrow bridge boundary by translating Ghostty actions before they leave the bridge.
- Support a first wave of high-value actions with clear user payoff: `PWD`, `SET_TITLE`, `SET_TAB_TITLE`, `OPEN_URL`, `DESKTOP_NOTIFICATION`, `RING_BELL`, `COMMAND_FINISHED`, `PROGRESS_REPORT`, `SHOW_CHILD_EXITED`, and `RENDERER_HEALTH`.
- Replace string-only hook event payloads with a structured payload type shared across automation-facing surfaces.
- Keep routing local-first, lightweight, and AppKit-owned where user-visible side effects are involved.

**Non-Goals:**
- Supporting every Ghostty action in this change.
- Giving Ghostty ownership of windows, tabs, splits, fullscreen, config UX, or updates.
- Reworking keyboard normalization or multi-key input state.
- Building a persistent control-plane subscription transport in this change.
- Introducing a background daemon, browser surface, or embedded plugin runtime.

## Decisions

### D1. Shared payload values live below hooks and control plane

Introduce a JSON-like structured value type in `OmuxCore` and use it for terminal action/event payloads, hook payloads, and control-plane event definitions.

- **Why this over `[String: String]`:** many terminal actions carry typed data (`exitCode`, `duration`, progress state, boolean health, optional titles). Flattening them into strings weakens the contract and forces every consumer to re-parse.
- **Why this over reusing `OmuxControlPlane.RPCValue`:** `OmuxHooks` depends only on `OmuxCore`, and the shared payload primitive should not force a dependency on the control-plane module.
- **Consequence:** hook payload shape changes now, while the project is still pre-release and can make the cleaner contract decision.

### D2. Translation is two-stage: runtime decode, bridge enrichment

Ghostty action translation happens in two steps:

1. `CGhosttyRuntime` decodes `ghostty_action_s` into a bridge-internal, OpenMUX-native action record keyed by `runtimeSurfaceID`.
2. `GhosttyTerminalBridge` enriches the record with `paneID` and `sessionID`, then emits a public terminal action/event to registered observers.

- **Why:** `CGhosttyRuntime` has direct access to Ghostty C types and surface mappings; `GhosttyTerminalBridge` has the stable pane/session abstractions used by the rest of OpenMUX.
- **Alternative rejected:** letting `OmuxAppShell` or hooks see raw Ghostty tags or payload structs. That would violate the bridge boundary.
- **Alternative rejected:** having `CGhosttyRuntime` call shell or hook code directly. That would couple the bridge to higher-level modules and make the runtime harder to test.

### D3. App-shell routing is owned by a dedicated coordinator, not the runtime

`OmuxAppShell` gains a small coordinator responsible for consuming bridge terminal events and fanning them out to shell state, native side effects, hooks, and future control-plane event publication.

Responsibilities:
- resolve workspace/tab context from `paneID` / `sessionID`
- update pane/tab titles and pane status state
- trigger native macOS behaviors (`NSWorkspace.open`, `UNUserNotificationCenter`, optional bell handling)
- emit structured hook invocations
- record or publish OpenMUX-native control-plane terminal events

- **Why:** this keeps the bridge narrow and keeps shell ownership in the shell. It also avoids turning `WorkspaceController` into a miscellaneous event bucket.
- **Alternative rejected:** handling shell side effects inside `OmuxTerminalBridge`. The bridge should not own AppKit chrome or external automation policy.

### D4. First-wave actions are intentionally narrow and mapped to OpenMUX outcomes

The first implementation wave is:

| Ghostty action | OpenMUX outcome |
| --- | --- |
| `PWD` | pane/session cwd event; shell can update cwd-aware labels and automation context |
| `SET_TITLE` | pane title update |
| `SET_TAB_TITLE` | pane-local or shell-visible tab label update |
| `OPEN_URL` | native URL/file open request handled by shell-owned host services |
| `DESKTOP_NOTIFICATION` | native user notification request |
| `RING_BELL` | shell bell event and optional user attention/bell handling |
| `COMMAND_FINISHED` | structured command-completed event for hooks, automation, and notifications |
| `PROGRESS_REPORT` | pane progress state for chrome and automation |
| `SHOW_CHILD_EXITED` | pane/session-ended state |
| `RENDERER_HEALTH` | pane renderer-health diagnostic state |

Everything else is explicitly either rejected or deferred. In particular, app-shell actions remain rejected by default.

- **Why:** this slice delivers real terminal fidelity and automation value without taking on Ghostty's app-shell model.
- **Alternative rejected:** shipping `CELL_SIZE`, `KEY_SEQUENCE`, `SEARCH_*`, or split/window actions in the same change. Those belong to layout, input, or future UX changes and would blur the scope.

### D5. App-target actions remain rejected by default

If Ghostty emits an app-target action for window/tab/split/fullscreen/config/update behavior, OpenMUX returns `false` unless and until a future change explicitly translates a selected action into an OpenMUX-native command.

- **Why:** OpenMUX owns workspace structure and shell behavior.
- **Consequence:** the change keeps the current safety property that embedded Ghostty cannot take over shell behavior.
- **Alternative rejected:** opportunistically translating split/tab commands now. That is product behavior, not dispatch plumbing.

### D6. Control-plane semantics are defined now; streaming transport is deferred

This change defines OpenMUX-native terminal event names and payload shapes for the control plane, but does not require a long-lived push transport in the same implementation slice.

- **Why:** the contract is the important architectural step; transport can evolve separately once the app has stable event meanings to publish.
- **What this means in practice:** terminal events are defined in OpenMUX-native terms and can be recorded or exposed by app-local services now, while client subscription over the Unix socket is a later change.
- **Alternative rejected:** building a pub/sub socket protocol immediately. That would enlarge scope and risk turning a local control plane into a heavier service boundary before we know the right consumer model.

### D7. Fallback behavior is explicit

When the fallback runtime is active because `libghostty` is unavailable, no Ghostty action stream exists. OpenMUX therefore emits no terminal action events from that runtime path unless the fallback host grows equivalent signals in a future change.

- **Why:** faking Ghostty action coverage on the fallback path would create a misleading contract.
- **Consequence:** specs must describe behavior in terms of “when the runtime emits a supported terminal action,” not as universal guarantees across all runtime paths.

## Risks / Trade-offs

- **[Hook payload shape changes]** → Update hook tests, fixtures, and documentation atomically in the same implementation change; keep the new payload model small and explicit.
- **[Cross-module coordination grows complexity]** → Keep the event path layered: runtime decode → bridge event → app-shell coordinator → side effects.
- **[Action volume could create UI churn]** → First-wave actions are low-volume; progress updates should coalesce on the shell side if needed.
- **[Workspace context is not available in the bridge]** → Resolve workspace/tab enrichment only in the shell coordinator, not in bridge types.
- **[Control-plane event delivery remains incomplete]** → Make the current change define event contracts without overcommitting to a premature transport design.

## Migration Plan

1. Add the shared structured payload type in `OmuxCore`.
2. Update `OmuxHooks` to use structured payloads for hook invocations.
3. Add bridge-owned terminal action/event types and observer registration in `OmuxTerminalBridge`.
4. Decode the supported Ghostty actions in `CGhosttyRuntime` and emit bridge events.
5. Add the app-shell coordinator that consumes bridge events and applies shell, notification, URL-open, and hook outcomes.
6. Define control-plane terminal event names/payloads in OpenMUX-native terms and wire app-local publication surfaces needed by the shell.
7. Leave unsupported and deferred Ghostty actions rejected.

Rollback is straightforward during development: restore `action_cb` rejection, remove event observers, and keep the existing shell behavior. No released user migration or compatibility shim is required.

## Open Questions

- Should `OPEN_URL` be configurable later per workspace or globally, or is native-open always correct for v1?
- Should `COMMAND_FINISHED` notifications honor a future OpenMUX config policy before shell hooks run, or should raw events always emit and policy live at the consumer layer?
- Should progress state live only in pane chrome, or also roll up into workspace/tab summaries in a follow-on change?
