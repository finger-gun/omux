## Context

OpenMUX already has two status inputs: terminal-native progress reports translated through the narrow `OmuxTerminalBridge` boundary, and public automation through `omux pane-status` / JSON-RPC. This works for tools that emit supported terminal progress signals, but terminal AI tools such as Codex may only expose state through visible TUI text, wrapper process lifecycle, local logs, or future tool-specific event streams.

The design therefore treats AI/tool status as an extension-layer concern. Adapters are external executables or plugin commands that observe or wrap a tool, infer a small OpenMUX-native status state, and report that state through the existing public pane-status API. The preferred packaging model is one shared `ai-status` plugin host with tool-specific adapters inside it, rather than one installable plugin per AI vendor. Repository ownership is explicit: the installable plugin package lives in the official plugin registry repo (`https://github.com/finger-gun/omux-plugins`, local checkout `/Users/lejahmie/projects/omux-plugins/`), while this repo owns the OpenMUX-side control-plane, plugin discovery/enablement, shell rendering, and documentation changes that make that plugin usable.

## Goals / Non-Goals

**Goals:**

- Define a vendor-neutral adapter contract for Codex, Claude, Copilot, and future terminal tools.
- Keep adapter outputs limited to OpenMUX-native pane status states and metadata.
- Provide a shared `ai-status` plugin host and inspectable adapter examples that users can inspect, copy, replace, or disable.
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

### Decision 2: Prefer one shared `ai-status` host with adapter-owned vendor modules

The official packaging model SHALL be a shared `ai-status` plugin host that contains vendor-specific adapters such as Codex, Gemini, Claude, and future tools.

**Rationale:** Users should install and configure one AI status capability, not a separate plugin per vendor. Shared debounce, dedupe, targeting, confidence, and stale-clear behavior belong in one place, while vendor-specific matchers stay isolated in adapter modules.

**Alternatives considered:** Separate plugins per vendor would reduce host complexity but would create plugin sprawl, duplicate shared logic, and make cross-vendor behavior less consistent.

### Decision 3: Keep repository ownership explicit

The installable `ai-status` plugin host SHALL live in the official OpenMUX plugin registry repository (`https://github.com/finger-gun/omux-plugins`, local checkout `/Users/lejahmie/projects/omux-plugins/`), not in this repository. This repository SHALL only carry the OpenMUX-side work that enables that plugin: public control-plane surfaces, plugin discovery/registry integration, docs, tests, and any shell rendering changes needed for normalized pane status.

**Rationale:** This preserves the project’s plugin-first architecture and avoids accidentally re-embedding plugin code into the core repo just because OpenMUX needs host-side integration work.

**Alternatives considered:** Keeping the plugin package in this repo would blur the boundary between core product behavior and external plugin delivery, and would conflict with the existing plugin registry model.

### Decision 4: Support wrapper and observer modes

The first adapter model supports:

- wrapper mode: an adapter launches a tool command and sets status before/after execution
- observer mode: an adapter observes bounded pane history, tool logs, or tool-provided events and periodically reports status

**Rationale:** Codex-like TUIs may need output inspection, while simpler tools can be covered by a wrapper. Both models can be external processes.

**Alternatives considered:** Requiring every tool to expose a native event stream would be cleaner but would exclude useful tools today.

### Decision 5: Adapter state is normalized before it reaches shell chrome

Adapters do not choose colors, icons, animations, or sidebar layout. They only report normalized status state plus optional label/message/source metadata.

**Rationale:** The app shell stays consistent and terminal-first, and status remains usable across vendors.

**Alternatives considered:** Letting adapters render custom UI would be more flexible but risks browser-heavy plugin behavior, inconsistent chrome, and higher performance overhead.

### Decision 6: No per-keystroke terminal parsing

OpenMUX core SHALL NOT parse arbitrary typed input, IME composition, dead keys, Option/right-Option output, or shell editing state to infer adapter status.

**Rationale:** Keyboard correctness is core product behavior. Adapters can inspect explicit history snapshots or tool-owned event surfaces but must not sit in the input path.

**Alternatives considered:** Input interception could infer more state, but it would be fragile and risky for international keyboards and terminal fidelity.

## Risks / Trade-offs

- **Risk: Output pattern matching is brittle** → Keep adapter rules isolated per tool, document best-effort semantics, and prefer tool-native events when available.
- **Risk: Shared host becomes a monolith** → Keep host logic limited to normalization, debounce/dedupe, targeting, and stale-clear behavior; keep vendor rules in adapter-owned modules and tests.
- **Risk: Polling pane history wastes resources** → Require bounded polling, backoff, and process-scoped adapter lifetime; default to no observer when not configured.
- **Risk: Status gets stale** → Encourage adapters to emit `idle`, `error`, or `clear` on process exit and rely on configurable idle-clear behavior for completed work.
- **Risk: Vendor-specific behavior creeps into core** → Keep Codex/Claude/Copilot knowledge in adapter files and tests, not in `OmuxTerminalBridge` or shell layout code.
- **Risk: History inspection may expose secrets to user scripts** → Adapters must be opt-in and documented with the same privacy caveats as `omux history`.

## Migration Plan

1. Specify and document `omux pane-status` as the stable reporting surface for adapters.
2. Add `ai-status` host docs and adapter docs under plugin/hook documentation, including the repo boundary between this repo and `finger-gun/omux-plugins`.
3. Add or update the shared `ai-status` plugin host package in `finger-gun/omux-plugins` with a Codex status adapter as the first worked example.
4. Add tests proving adapter-reported status renders like terminal-native progress and does not affect keyboard/input routing.

Rollback is straightforward: remove or disable the shared `ai-status` plugin host from `finger-gun/omux-plugins` while leaving `omux pane-status` intact for existing hook/plugin users.

## Open Questions

- Should observer adapters have a shared helper for bounded history polling, or should each adapter own its polling loop initially?
- Which Codex UI strings should be treated as stable enough for the first adapter release?
- Which first-wave adapters should ship alongside the Codex worked example: Gemini, Claude, both, or docs-only placeholders?
