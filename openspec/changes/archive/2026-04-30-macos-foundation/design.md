## Context

OpenMUX is still in its foundation stage, so the main risk is not missing a feature but hardening the wrong architecture too early. The manifesto and research both point to the same starting shape: a macOS-only v1, an AppKit-first desktop shell, a narrow bridge around pinned libghostty, a local `omux` CLI that controls the app over JSON-RPC on a Unix domain socket, and hookable extension seams that stay out of the terminal core.

The design must preserve four core constraints. First, the terminal is the product, so terminal fidelity, keyboard correctness, and stable long-running sessions matter more than feature breadth. Second, libghostty is a strong foundation but an unstable embedding surface, so upstream details must stay behind a single bridge module. Third, OpenMUX wants openness and hackability, so it needs explicit lifecycle and extension seams early. Fourth, keyboard/input behavior for ISO and EU layouts is a blocker-level concern and cannot be deferred until after architecture is set.

## Goals / Non-Goals

**Goals:**
- Establish a stable architectural baseline for future implementation changes.
- Separate OpenMUX-native domain concepts from libghostty-specific implementation details.
- Define the native app shell, terminal bridge, input pipeline, CLI/RPC, and hook seams as independent but connected capabilities.
- Make keyboard normalization and international-layout correctness a first-class architectural requirement.
- Keep the extension model compatible with external hooks first and richer plugin runtimes later.

**Non-Goals:**
- Designing the complete visual UI or shipping all v1 user-facing features.
- Defining every CLI command, pane interaction, or persistence schema in full detail.
- Committing to an in-process plugin runtime or WASM host in this change.
- Supporting browser-heavy shells, webview-first architecture, or Mac App Store constraints.

## Decisions

### 1. Use an AppKit-first macOS shell with selective SwiftUI

OpenMUX will treat AppKit as the primary shell for windows, focus, menus, event routing, and terminal hosting. SwiftUI is allowed for settings, lightweight chrome, and other non-terminal surfaces where it reduces boilerplate without owning the terminal interaction model.

**Why this decision:** The research shows AppKit is the best fit for terminal-first keyboard handling, focus control, and native macOS semantics. This also aligns with the project goal of keeping the terminal surface native and precise rather than filtered through a web or wrapper architecture.

**Alternatives considered:**
- **SwiftUI-only:** simpler for chrome, but too indirect for the terminal surface and low-level input correctness.
- **Tauri/Electron:** faster for generic application UI, but in conflict with terminal-first performance and keyboard fidelity.
- **Cross-platform-native stack first:** attractive later, but premature for the current v1 direction.

### 2. Isolate libghostty behind one narrow bridge capability

Only one dedicated OpenMUX layer may depend directly on libghostty types and APIs. The rest of the system will speak in OpenMUX-native concepts such as workspaces, panes, tabs, sessions, key events, and hooks.

**Why this decision:** libghostty is the right technical foundation, but its full embedding API is not yet a polished general-purpose surface. A narrow bridge protects the product from upstream churn and keeps the rest of the architecture testable and easier to reason about.

**Alternatives considered:**
- **Use libghostty types directly across the app:** simplest early on, but creates high coupling and upgrade pain.
- **Write a full terminal engine:** directly conflicts with the “build on strong foundations” principle.

### 3. Normalize keyboard input before terminal dispatch

Keyboard and text input will flow through a normalized OpenMUX input layer before reaching the terminal bridge or higher-level keybinding logic. This layer will preserve left/right modifier identity where relevant and define explicit behavior for ISO layouts, Alt/Option usage, dead keys, and compose-like flows.

**Why this decision:** International-first behavior is a manifesto-level requirement, not optional polish. The architecture needs one place where AppKit events become OpenMUX key semantics so terminal dispatch, shortcuts, and hooks all operate on the same model.

**Alternatives considered:**
- **Handle key logic ad hoc in views:** easier to start, but creates inconsistent behavior and makes regression testing harder.
- **Let libghostty own all key interpretation:** workable for some terminal paths, but insufficient for app-level shortcuts and OpenMUX-specific behaviors.

### 4. Define `omux` + JSON-RPC as the local control plane

The automation and control boundary between the desktop app and the CLI will be a local JSON-RPC protocol over a Unix domain socket, with `omux` as the primary client.

**Why this decision:** This keeps control-plane behavior explicit, transport-lightweight, scriptable, and independent from internal implementation details. It also gives future changes a stable automation seam for focus, session, split, notification, and restoration workflows.

**Alternatives considered:**
- **Direct in-process CLI reuse only:** simpler initially, but weaker as a user-facing automation contract.
- **gRPC:** stronger typing but heavier than needed for a local desktop app/CLI pair.
- **XPC as the primary contract:** too macOS-specific and more appropriate for helper/service internals than the main plugin/control API.

### 5. Start extensibility with hook contracts, not embedded plugin runtimes

OpenMUX will define lifecycle, session, command, UI, and input hook categories first. These hooks form the foundation for external automation and later plugin evolution.

**Why this decision:** The manifesto prefers buildable systems over feature-bloated cores. Hooks create stable seams early without forcing the project into an embedded JS or WASM runtime before the product model is stable.

**Alternatives considered:**
- **In-process scripting first:** maximizes flexibility early, but increases trust, safety, and lifecycle complexity.
- **Delay extensibility entirely:** simpler now, but works against the project’s open-by-design thesis.

### 6. Organize the foundation around separable capabilities

The foundation will be captured as five linked capabilities: `macos-app-shell`, `terminal-bridge`, `input-pipeline`, `omux-control-plane`, and `hooks-foundation`.

**Why this decision:** These boundaries map directly to future implementation streams and keep later OpenSpecs focused. They also reflect the contract edges the rest of the app will rely on.

**Alternatives considered:**
- **One giant “foundation” spec:** simpler to start, but too vague and difficult to evolve safely.
- **Many tiny highly granular capabilities immediately:** precise, but unnecessarily fragmented at this stage.

## Risks / Trade-offs

- **[libghostty embedding instability]** → Keep the bridge narrow, pin upstream deliberately, and avoid leaking raw libghostty concepts outside the terminal boundary.
- **[Foundation scope grows into full product scope]** → Keep this change focused on contracts and architecture, not full end-user feature delivery.
- **[Keyboard model complexity]** → Centralize normalization and require explicit ISO/EU layout scenarios in the specs from the start.
- **[Hook design becomes too abstract to implement]** → Define concrete hook categories and lifecycle touchpoints, but defer full plugin runtime design.
- **[CLI/RPC contract ossifies too early]** → Keep the control plane minimal and capability-oriented, with a clear boundary that can evolve without exposing internal app state directly.

## Migration Plan

1. Adopt this change as the architectural baseline for implementation work.
2. Create the initial app, CLI, and package/module scaffolding around the five foundation capabilities.
3. Implement the terminal bridge and input normalization early so user-facing features do not bypass those boundaries.
4. Layer workspace shell, RPC handlers, and hook registration on top of those foundation seams.
5. Add persistence, notifications, and richer extension capabilities in later changes without rewriting the base architecture.

Because the project is pre-implementation, migration is primarily about aligning future work to these contracts rather than moving existing production behavior.

## Open Questions

- What exact package/module names should be used in the first implementation slice?
- Should the first bridge integration use a prebuilt XCFramework flow or a local pinned build step?
- Which subset of `omux` commands should be implemented in the first vertical slice after the foundation scaffolding exists?
- How much app state should be directly addressable over RPC versus mediated through higher-level commands?
