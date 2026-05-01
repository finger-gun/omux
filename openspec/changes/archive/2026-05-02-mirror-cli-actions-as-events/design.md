## Context

`omux events` currently streams only `terminal.*` notifications produced by the terminal-action path. That leaves a mismatch between what OpenMUX can do through shared workspace/session actions and what automation can observe through the control plane. `WorkspaceController` already owns the core action surface used by the app shell and `omux`, and it already emits hooks for many of those actions, but there is no parallel control-plane event publication path for them.

This change is cross-cutting because it touches `OmuxAppShell`, `OmuxControlPlane`, and `OmuxCLI`, and because the current control-plane event envelope is terminal-shaped: it assumes `paneID` and `sessionID` are always present. A broader event stream needs to stay OpenMUX-native, preserve the `libghostty` bridge boundary, and avoid turning local automation into a heavyweight service.

## Goals / Non-Goals

**Goals:**
- Make `omux events` a generic local event stream for both terminal runtime events and successful shared workspace/session actions.
- Define first-wave action/event parity for the short `omux` commands that mutate app state or trigger user-visible shell behavior.
- Keep event names, payloads, and contextual IDs OpenMUX-native and stable for hooks, CLI consumers, and future plugins.
- Emit the same action events whether an operation is invoked from the CLI or through the native shell using the same controller-owned action path.
- Keep the event path local-first, lightweight, and explicit.

**Non-Goals:**
- Turning the event stream into a command-input surface or replay bus.
- Emitting events for arbitrary terminal output such as `ls` text or TUI redraws.
- Adding browser surfaces, remote transports, background daemons, or vendor-specific automation services.
- Expanding the `libghostty` bridge boundary or exposing Ghostty app-shell actions outside `OmuxTerminalBridge`.
- Reworking keyboard normalization, text input, or other input-pipeline behavior.

## Decisions

### D1. Generalize the control-plane event envelope beyond terminal-only context

Replace the terminal-specific control-plane event model with a generic OpenMUX event envelope that can carry `name`, structured payload, and optional `workspaceID`, `tabID`, `paneID`, and `sessionID` context.

- **Why:** action events such as `notification.raised` or `workspace.restored` do not always have a meaningful pane/session pair, while workspace-opening and pane-splitting events do. A generic envelope avoids fabricating IDs.
- **Alternative rejected:** forcing every event to provide `paneID` and `sessionID`. That would make non-terminal events awkward and produce misleading contracts.
- **Alternative rejected:** creating a second parallel stream for non-terminal events. That would fragment the local automation surface and weaken the terminal-first control-plane story.

### D2. Publish shared action events at controller-owned action boundaries

Successful shared actions should emit control-plane events from the same `WorkspaceController` methods that already own state changes and hook emission.

- **Why:** `WorkspaceController` is where CLI and UI already converge for workspace opening, tab creation, pane splitting, pane-tab operations, session focus, command injection, notifications, and workspace restore.
- **Alternative rejected:** synthesizing action events in `OmuxCLI`. That would miss UI-originated actions and break parity.
- **Alternative rejected:** publishing from `OpenMUXControlPlaneService` only. The service sees requests, but not native-shell invocations that bypass the CLI.

### D3. Keep terminal runtime events and shared action events distinct but co-streamed

The existing terminal action path remains layered as runtime decode -> bridge event -> app-shell coordinator -> control-plane publication, while controller-owned action events publish through the same generic event bus.

- **Why:** terminal runtime signals and shared workspace actions have different ownership and semantics. Co-streaming them is useful; collapsing them into one internal source is not.
- **Alternative rejected:** treating terminal runtime events as workspace action events. A terminal title change or bell is not the same thing as a user-invoked control-plane action.

### D4. First-wave parity follows the existing short-command surface

The first parity slice covers the mutating short `omux` commands and their native-shell equivalents:

| Command / shared action | Event |
| --- | --- |
| `open <path>` | `workspace.opened` |
| `tab` | `tab.created` |
| `split [right\|down]` | `pane.split` |
| `pane-tab` | `paneTab.created` |
| `pane-tab-focus <pane-id>` | `paneTab.focused` |
| `pane-tab-close [pane-id]` | `paneTab.closed` |
| `focus <session-id>` | `session.focused` |
| `run <session-id> <command>` | `command.started` |
| `notify <title> [body]` | `notification.raised` |
| `restore <workspace-id>` | `workspace.restored` |

- **Why:** these are the commands that already represent controller-owned app actions and therefore have a clean parity story.
- **Alternative rejected:** including read-only or local-only commands such as `list`, `events`, `help`, `theme`, or `install-cli`. Those are not user-action events in the same sense.

### D5. Parity is observational, not reversible command execution

“And vice versa” is interpreted as contract parity: every first-wave shared action emits a corresponding event, and every first-wave user-triggered action event corresponds to a shared OpenMUX action. The event stream does not become an input mechanism that replays events back into actions.

- **Why:** keeping events observational preserves explicit control-plane commands and avoids conflating state change notification with authority to mutate app state.
- **Alternative rejected:** accepting streamed events as commands. That would complicate RPC semantics, security, and failure handling for little immediate payoff.

### D6. Only successful controller-owned outcomes emit action events

Action events are emitted only after the action has been accepted and applied. Validation failures and no-op requests do not publish success-shaped events.

- **Why:** event consumers need a reliable “this happened” contract, not an ambiguous intent log.
- **Examples:** failed `focus` requests, invalid `pane-tab-close`, or a restore targeting a missing workspace should not publish parity events; `command.started` should publish only when command injection succeeds.

### D7. Existing hooks and new control-plane events should stay aligned, not identical

Where hooks already exist (`workspace-opened`, `pane-created`, `pane-tab-created`, `pane-tab-closed`, `pane-focused`, `command-started`, `notification-raised`), the new control-plane events should carry the same domain meaning but use stable event-stream naming and generic envelope rules.

- **Why:** this keeps CLI automation and hook automation conceptually aligned without forcing identical storage or transport shapes.
- **Alternative rejected:** deriving event names mechanically from hook names. Hook naming and stream naming serve different consumers and should remain free to use the clearest convention for each surface.

## Risks / Trade-offs

- **[Generic event envelope churn]** -> Migrate terminal events and new action events together so `omux events` keeps one clear contract instead of mixed legacy and new shapes.
- **[Event duplication with hooks]** -> Keep hooks as execution side effects and control-plane events as observation surfaces; document the distinction clearly.
- **[Naming becomes a long-lived contract too early]** -> Restrict the first wave to existing shared actions and keep names product-level and sparse.
- **[High-volume event spam]** -> Limit parity to successful action outcomes and continue treating raw terminal output as non-events.
- **[Context ambiguity for app-level events]** -> Allow optional IDs in the envelope and require only the context that genuinely exists for the action.

## Migration Plan

1. Replace the terminal-only control-plane event type with a generic event envelope in `OmuxControlPlane`.
2. Update the app-shell event broadcaster and `omux events` subscription path to stream the generic event type.
3. Add a small `WorkspaceController` helper for publishing action events alongside existing state updates and hook emission.
4. Wire first-wave controller-owned actions to emit their corresponding events with action-specific payloads.
5. Adapt terminal runtime publication so existing `terminal.*` events also use the generic envelope.
6. Update CLI tests, control-plane tests, and app-shell tests to cover mixed action and terminal event streaming.
7. Refresh developer documentation so `omux events` is described as a generic control-plane event stream.

Rollback remains straightforward while unreleased: restore the terminal-only event type, remove action publication calls, and keep hooks as the only non-terminal automation surface.

## Open Questions

- Should `focus <session-id>` and `pane-tab-focus <pane-id>` intentionally emit different event names (`session.focused` vs `paneTab.focused`), or should they collapse to one pane-focus event in implementation?
- Should `restore` emit only `workspace.restored`, or also emit a focus-like event when it changes the active workspace?
- Do we want a later second wave for read-only observability events such as config reload or theme application, or should the event stream remain action-focused?
