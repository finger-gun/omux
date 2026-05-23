## Context

The current app shell and CLI layers contain multi-thousand-line files that mix state mutation, query resolution, event publication, UI orchestration, view composition, and utility logic. This coupling slows safe iteration and makes hotspot optimization risky, because unrelated concerns share the same mutation surfaces.

Since this change was first written, the codebase has already added several focused collaborators such as `TerminalActionCoordinator`, `ExtensionPaneActionService`, `WorkspaceLayoutPersistenceCoordinator`, `VaultIndexRefreshCoordinator`, and `OpenMUXConfigurationCoordinator`. That means the remaining refactor pressure is no longer “extract the first helper,” but rather “finish carving clear seams around the remaining oversized mutation and shell-host files.”

The change is an internal refactor focused on clear boundaries and behavior parity.

## Goals / Non-Goals

**Goals:**
- Reduce controller complexity by extracting focused collaborators with explicit interfaces.
- Keep terminal bridge boundaries and keyboard/input behavior intact.
- Improve testability by isolating pure state logic from side-effect orchestration.
- Create a dedicated publication seam for hooks and control-plane events so later open-by-design parity work can add missing transition coverage without expanding controller-wide coupling.
- Reduce `WorkspaceWindowController` file-level sprawl by separating shell/view-host composition from individual shell subviews and interaction helpers.
- Keep the work as one coordinated refactor while making controller, shell, and CLI picker slices independently landable.

**Non-Goals:**
- Changing control-plane RPC shape or workspace semantics.
- Replacing AppKit shell architecture.
- Introducing new runtime services outside existing process boundaries.
- Rewriting the shell visual design or changing command semantics as part of extraction.

## Decisions

### 1) Extract state/index management from orchestration
- Create a state-focused module responsible for workspace collection, active selection, and indexed lookup maintenance.
- Keep bridge/hook/control-plane side effects in orchestrator-level services.

**Alternative considered:** split by file size only without responsibility boundaries.  
**Why not chosen:** cosmetic splitting would retain coupling and poor test isolation.

### 2) Extract publication concerns
- Introduce dedicated event publication helpers for hook and control-plane events.
- Preserve event payload schema and ordering semantics.
- Keep the publication seam narrow and reusable so future transition wiring can attach at one boundary instead of scattering `hookRunner.emit(...)` and `publishControlPlaneEvent(...)` calls across more controller methods.

**Alternative considered:** leave event calls inline and rely on style discipline.  
**Why not chosen:** continued duplication and drift risk across large methods.

### 3) Extract shell/view-host composition from WorkspaceWindowController
- Separate top-level shell orchestration from large nested view and interaction responsibilities in `WorkspaceWindowController`.
- Prefer shell-owned modules aligned with existing concepts: sidebar, canvas/split rendering, floating modal hosting, pane headers, overlays, and shell-specific controls.
- Keep terminal surface ownership and terminal-engine boundaries unchanged; the shell continues to orchestrate OpenMUX pane/view identities only.

**Alternative considered:** leave `WorkspaceWindowController` untouched and focus only on controller logic.  
**Why not chosen:** the shell host file is now larger than the controller file and has become its own maintenance hotspot.

### 4) Unify CLI terminal picker internals
- Build one shared picker core for keyboard handling, rendering viewport, and search/filter interactions.
- Specialize only item formatting and action semantics per picker (themes/plugins).
- Treat vault resume choice as part of the same engine family if its interaction model remains aligned.

**Alternative considered:** keep duplicated picker implementations.  
**Why not chosen:** duplicates bugfix effort and increases behavioral divergence risk.

## Risks / Trade-offs

- **[Risk] Behavior drift during extraction** → **Mitigation:** parity tests for existing controller flows and CLI picker interactions.
- **[Risk] Over-abstraction in early-stage codebase** → **Mitigation:** keep extractions small and aligned with existing concepts (workspace, pane, event).
- **[Risk] Input/keyboard regression from picker unification** → **Mitigation:** preserve key parsing semantics and run existing input/CLI tests.
- **[Risk] Boundary erosion toward terminal bridge** → **Mitigation:** enforce module APIs that accept OpenMUX-native types only.
- **[Risk] Refactor improves structure but not future openness work]** → **Mitigation:** require the publication boundary to remain the single place where hook/control-plane emission is wired for controller-owned transitions.
- **[Risk] One change becomes too broad to land safely]** → **Mitigation:** organize the work into explicit controller, shell, and CLI slices with targeted parity tests and independently reviewable tasks.
- **[Risk] Test files remain monolithic enough to block safe extraction]** → **Mitigation:** let parity coverage grow more targeted by concern instead of relying only on one giant app-shell test file.

## Migration Plan

1. Define or confirm internal protocols/types for controller state/index, event publication, and extension-pane coordination.
2. Extract the controller publication seam and one state/index slice with green tests.
3. Extract one `WorkspaceWindowController` shell/view-host slice at a time with shell parity coverage.
4. Extract and switch the shared CLI picker engine while preserving existing commands.
5. Remove deprecated internal helpers after parity is established.
6. Rollback strategy: each slice remains independently reversible by module-level rewire.

## Open Questions

- Should state/index modules live under `OmuxAppShell` or move partly into `OmuxCore` later?
- How much debug-only invariant checking should remain in production builds?
- Should the publication seam expose one combined publisher interface or separate hook and control-plane publishers behind one coordinator?
- Which `WorkspaceWindowController` subdomains give the best first extraction seam: sidebar/canvas, floating modal hosting, or pane header/progress chrome?
