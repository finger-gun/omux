## Context

OpenMUX already has two status inputs: terminal-native progress reports translated through the narrow `OmuxTerminalBridge` boundary, and public automation through `omux pane-status` / JSON-RPC. This works for tools that emit supported terminal progress signals, but terminal AI tools such as Codex, Gemini, and Claude may expose state through terminal titles, explicit vendor hooks, wrapper process lifecycle, local logs, or tool-specific event streams.

The design therefore treats AI/tool status as an adapter concern above the terminal bridge. The preferred packaging model is one bundled Swift `ai-status` host with tool-specific adapters inside it, rather than one installable plugin per AI vendor. The host starts with zero-setup passive title fallback, then adds explicit user-managed hook setup and a hook relay for stronger interactive-session detection. JSONL wrappers remain supported for controlled-launch sessions, but they are secondary because they only help when OpenMUX launches the agent command.

## Goals / Non-Goals

**Goals:**

- Define a vendor-neutral adapter contract for Codex, Gemini, Claude, Copilot, and future terminal tools.
- Keep adapter outputs limited to OpenMUX-native pane status states and metadata.
- Provide a bundled `ai-status` host and inspectable adapter examples that users can inspect, copy, replace, or disable.
- Provide explicit vendor hook setup/uninstall and hook relay commands that users run intentionally.
- Avoid extra work when no adapter is configured.
- Preserve keyboard/input correctness by making observer adapters read-only unless they explicitly call public automation.

**Non-Goals:**

- Embed AI SDKs or vendor-specific runtimes in the OpenMUX app.
- Build a browser-heavy sidecar UI for AI tools.
- Guarantee perfect state inference for every TUI; adapters provide best-effort status.
- Replace terminal-native progress reports from tools that already emit them.
- Add network services, telemetry, or a daemon that runs independently of user-configured adapter use.

## Decisions

### Decision 1: Adapters report through `omux pane-status`

Adapters SHALL use the public CLI or equivalent JSON-RPC operation to report `working`, `indeterminate`, `needs-input`, `idle`, `error`, and `clear`.

**Rationale:** This keeps the contract inspectable and scriptable, reuses existing pane targeting, and avoids new private coupling between plugin code and app internals.

**Alternatives considered:** A private in-process Swift adapter API would be faster for bundled adapters but would make user adapters less hackable and would pull vendor behavior into core.

### Decision 2: Prefer one bundled `ai-status` host with adapter-owned vendor modules

The official packaging model SHALL be a bundled Swift `ai-status` host that contains vendor-specific adapters such as Codex, Gemini, Claude, and future tools.

**Rationale:** Users should configure one AI status capability, not a separate plugin per vendor. Shared debounce, dedupe, targeting, confidence, and stale-clear behavior belong in one place, while vendor-specific matchers stay isolated in adapter modules. Bundling the host also avoids making first-wave status support depend on a separate plugin registry checkout.

**Alternatives considered:** Separate plugins per vendor would reduce host complexity but would create plugin sprawl, duplicate shared logic, and make cross-vendor behavior less consistent.

### Decision 3: Make hook setup explicit and marker-owned

OpenMUX SHALL expose `omux ai-status hooks setup|uninstall [codex|claude|gemini]` for command-driven hook installation. Setup SHALL add only OpenMUX-owned hook entries for vendors where direct config edits are safe and marker-owned, and uninstall SHALL remove only entries identifiable by OpenMUX markers. Claude SHALL initially follow the cmux-style conservative path: wrapper-injected or guided hook configuration, not silent edits to Claude-owned settings.

**Rationale:** cmux’s current architecture shows that explicit hook setup plus a socket/CLI relay is practical for normal interactive sessions. The setup must be deliberate because it edits vendor-owned configuration files, and marker-based uninstall prevents OpenMUX from deleting user-authored hook entries.

**Alternatives considered:** Automatically patching vendor configs on first launch would be more seamless but would be surprising and risky. Requiring users to hand-edit every config would preserve control but make first-wave support too fragile.

### Decision 4: Normalize vendor hook stdin through one relay

Vendor hook entries SHALL invoke `omux ai-status hook --source <vendor> --event <event>` and pass the vendor hook payload on stdin. The relay SHALL normalize vendor payloads into host events and then report pane status through the public control plane.

**Rationale:** A single relay keeps vendor config snippets small, inspectable, and consistent. It also gives OpenMUX one place to validate input, map vendor events, dedupe repeated updates, and preserve timeout behavior.

**Alternatives considered:** Writing separate hook binaries per vendor would increase install surface and duplicate normalization logic.

### Decision 5: Support observer and controlled-launch wrapper modes

The first adapter model supports:

- wrapper mode: an adapter launches a tool command and sets status before/after execution
- JSONL wrapper mode: an adapter launches a known noninteractive or structured-output command and parses JSONL events
- hook mode: a vendor hook invokes the OpenMUX relay during a normal interactive session
- observer mode: an adapter observes terminal-title changes, bounded pane history, tool logs, or tool-provided events and periodically reports status

**Rationale:** Hooks are the strongest path for ordinary interactive sessions once explicitly installed. Title observation gives a useful zero-setup fallback. JSONL wrappers are robust but only apply when OpenMUX controls launch.

**Alternatives considered:** Requiring every tool to expose a native event stream would be cleaner but would exclude useful tools today.

### Decision 6: Adapter state is normalized before it reaches shell chrome

Adapters do not choose colors, icons, animations, or sidebar layout. They only report normalized status state plus optional label/message/source metadata.

**Rationale:** The app shell stays consistent and terminal-first, and status remains usable across vendors.

**Alternatives considered:** Letting adapters render custom UI would be more flexible but risks browser-heavy plugin behavior, inconsistent chrome, and higher performance overhead.

### Decision 7: No per-keystroke terminal parsing

OpenMUX core SHALL NOT parse arbitrary typed input, IME composition, dead keys, Option/right-Option output, or shell editing state to infer adapter status.

**Rationale:** Keyboard correctness is core product behavior. Adapters can inspect explicit history snapshots or tool-owned event surfaces but must not sit in the input path.

**Alternatives considered:** Input interception could infer more state, but it would be fragile and risky for international keyboards and terminal fidelity.

## Risks / Trade-offs

- **Risk: Output pattern matching is brittle** → Keep adapter rules isolated per tool, document best-effort semantics, and prefer tool-native events when available.
- **Risk: Shared host becomes a monolith** → Keep host logic limited to normalization, debounce/dedupe, targeting, and stale-clear behavior; keep vendor rules in adapter-owned modules and tests.
- **Risk: Vendor config edits surprise users** → Require explicit `hooks setup`, use marker-owned entries, and make uninstall remove only OpenMUX-owned blocks.
- **Risk: Polling pane history wastes resources** → Require bounded polling, backoff, and process-scoped adapter lifetime; default to no observer when not configured.
- **Risk: Status gets stale** → Encourage adapters to emit `idle`, `error`, or `clear` on process exit and rely on configurable idle-clear behavior for completed work.
- **Risk: Vendor-specific behavior creeps into core** → Keep Codex/Claude/Copilot knowledge in adapter files and tests, not in `OmuxTerminalBridge` or shell layout code.
- **Risk: History inspection may expose secrets to user scripts** → Adapters must be opt-in and documented with the same privacy caveats as `omux history`.

## Migration Plan

1. Specify and document `omux pane-status` as the stable reporting surface for adapters.
2. Add bundled `ai-status` host docs and adapter docs under plugin/hook documentation.
3. Implement passive Codex title detection as the first zero-setup fallback, keeping title matchers adapter-owned and confidence-scored.
4. Add `omux ai-status hooks setup|uninstall [codex|claude|gemini]` and marker-based vendor config management.
5. Add `omux ai-status hook --source <vendor> --event <event>` to normalize vendor hook stdin and report pane status.
6. Add JSONL wrapper parsers for Codex, Gemini, and Claude as controlled-launch support.
7. Add tests proving adapter-reported status renders like terminal-native progress and does not affect keyboard/input routing.

Rollback is straightforward: disable the bundled `ai-status` feature and remove OpenMUX-owned vendor hook entries with `omux ai-status hooks uninstall`, while leaving `omux pane-status` intact for existing hook/plugin users.

## Open Questions

- Which Codex UI strings should be treated as stable enough for the first adapter release?
- Should observer adapters have a shared helper for bounded history polling, or should each adapter own its polling loop initially?
