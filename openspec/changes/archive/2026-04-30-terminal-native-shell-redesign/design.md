## Context

OpenMUX already has the functional architecture for a native terminal workspace: an AppKit-first shell, workspace/session state, split-pane layout, pane-local tab stacks, and a narrow libghostty bridge. What it does not yet have is a cohesive visual shell. The current workspace UI is a scaffold built from generic AppKit controls and minimal pane framing, which is good enough for proving flows but not yet aligned with the product thesis in the manifesto or the desired visual direction.

This redesign must solve more than aesthetics. It needs to define how OpenMUX becomes visually intentional while still feeling terminal-native, open, and composable. The user explicitly wants to avoid a VS Code-like experience where application chrome dominates and the terminal becomes a subordinate panel. That means the redesign has to protect terminal density, preserve a sense of freedom, and keep shell chrome lightweight and supportive rather than managerial.

The design also has to respect current architecture constraints. The AppKit shell and workspace model should remain the composition root. Terminal hosting must stay behind the existing bridge boundary. Theme behavior must style the shell and the terminal coherently without leaking product chrome concerns into libghostty-facing code. The result should be a shell architecture that is visually stronger but still modular, testable, and incremental to implement.

## Goals / Non-Goals

**Goals:**
- Define a terminal-native shell composition for sidebar, top bar, workspace canvas, and pane presentation.
- Preserve the terminal as the dominant surface and keep shell chrome visually quiet, informative, and low-friction.
- Introduce a token-based theme architecture that styles shell chrome and terminal palettes as one coherent product theme.
- Define built-in theme preset expectations for a strong OpenMUX default plus curated presets such as Catppuccin, Gruvbox, and Sonokai.
- Keep the redesign compatible with AppKit-first rendering, existing workspace/layout state, and the current libghostty bridge boundary.
- Support incremental delivery so layout, pane chrome, and themes can land in clear slices without rewriting the app shell.

**Non-Goals:**
- Replacing the AppKit-first architecture with SwiftUI-only, webview-first, or browser-heavy UI technology.
- Expanding the libghostty bridge or coupling shell presentation directly to terminal runtime internals.
- Designing a general plugin/theme marketplace or arbitrary user theme import flow in the first slice.
- Turning OpenMUX into an editor-like or dashboard-heavy environment with dense tool panels and workflow-specific product chrome.
- Defining every animation, icon, or pixel-perfect visual detail up front.

## Decisions

### 1. Organize the redesign around a shell/chrome/canvas hierarchy

The visual shell will be treated as three layered concerns:
1. shell chrome for global orientation and switching
2. workspace chrome for pane-level structure and context
3. terminal presentation for the content users are actually here to work in

This yields a component map centered on a dedicated shell composition root:

```text
WorkspaceWindowController
└── WorkspaceShellViewController
    ├── SidebarView
    ├── TopBarView
    └── WorkspaceCanvasView
        └── Split / pane-stack rendering
            └── PaneCardView
                ├── PaneHeaderView
                └── HostedTerminalPaneView
```

**Why this decision:** The current shell already has the right state boundaries but not the right visual composition. Separating shell chrome from pane chrome and terminal hosting lets the redesign strengthen the product shell without contaminating terminal bridge code.

**Alternatives considered:**
- **Restyle existing controls in place:** fast, but likely to preserve a scaffold-like feel and limit how terminal-native the product can feel.
- **Push shell chrome into terminal host views:** simpler initially, but couples UI framing to runtime hosting and muddies the bridge boundary.

### 2. Keep navigation persistent but visually secondary

The redesign will introduce a persistent sidebar and a quiet top bar, but both must remain subordinate to terminal work. Sidebar content will focus on workspace/session orientation and quick switching. The top bar will provide light contextual metadata and global actions without becoming a toolbar-heavy command center.

**Why this decision:** The app needs stronger orientation and structure, especially as workspaces and pane stacks grow. At the same time, the user explicitly wants to avoid an IDE-like shell where chrome encloses the terminal. Persistent navigation should guide, not dominate.

**Alternatives considered:**
- **No sidebar at all:** preserves visual simplicity, but gives up the stronger navigation model that the target shell needs.
- **Feature-dense management sidebar:** increases discoverability for every action, but pushes the product toward a dashboard/IDE feeling.

### 3. Move pane presentation away from generic AppKit segmented controls

Pane stacks should evolve from generic segmented controls and utility buttons toward a dedicated pane header and local tab strip model. Pane chrome must surface title, focus, local tab context, and lightweight actions while remaining slim and visually quiet.

**Why this decision:** The current `NSSegmentedControl` approach is good for scaffolding, but it makes the pane area feel like default UI controls glued onto terminals. A dedicated pane chrome layer is necessary to get the desired visual hierarchy and product character.

**Alternatives considered:**
- **Keep segmented controls and just recolor them:** lowest cost, but not enough to reach the target shell identity.
- **Hide all pane chrome:** maximizes terminal density, but weakens orientation once multiple pane-local tabs and splits exist.

### 4. Use token-driven themes that style shell and terminal together

Themes will be defined as cohesive token sets, not just terminal color palettes. Each theme will include shell tokens such as backgrounds, borders, text, selection, and accent colors, plus the terminal palette used by the hosted runtime. Built-in themes will ship as product-quality presets instead of expecting raw user configuration from day one.

**Why this decision:** The user wants themes tightly connected to the redesign, and familiar terminal-native presets such as Catppuccin, Gruvbox, and Sonokai are part of the expected feel. If shell chrome and terminal colors are configured separately, the result will feel disconnected and less intentional.

**Alternatives considered:**
- **Terminal palette only:** easier to implement, but leaves the app shell visually inconsistent.
- **Arbitrary theme import first:** flexible, but adds surface area before the core theme model is stable.

### 5. Encode “terminal-native” as an explicit UX guardrail

The redesign will treat “terminal-native” as a normative design rule: shell chrome may improve orientation, focus, and navigation, but it must not make the terminal feel secondary, enclosed, or workflow-managed like an IDE panel system. The terminal remains the dominant working surface, and the UI frames it rather than containing it.

**Why this decision:** This is the core experiential constraint that differentiates OpenMUX from editor-like terminal integrations. Without an explicit guardrail, later implementation work could meet visual requirements while still missing the product feel.

**Alternatives considered:**
- **Rely on taste during implementation:** flexible, but too easy to drift toward generic app patterns.
- **Reject shell chrome entirely:** protects terminal primacy, but blocks the navigation and product polish the redesign is meant to add.

### 6. Roll the redesign out in structure-first slices

Implementation should progress in this order:
1. shell composition and layout hierarchy
2. pane chrome and focus states
3. token-based theme system
4. built-in theme presets and later customization polish

**Why this decision:** Theme work depends on stable structural layers. If colors and presets land before the shell hierarchy is defined, the product will accrue styling on top of unfinished composition rather than a coherent design system.

**Alternatives considered:**
- **Theme-first rollout:** attractive for quick wins, but likely to create churn once layout and pane chrome change.
- **All-at-once redesign:** visually cohesive in theory, but harder to ship safely and review incrementally.

## Risks / Trade-offs

- **[Shell chrome grows too heavy]** → Keep explicit terminal-dominance requirements in the specs and use sidebar/top-bar scope limits to prevent IDE-like sprawl.
- **[Theme system leaks into terminal bridge internals]** → Keep shell theme resolution in app-shell layers and pass only terminal palette data across the bridge boundary.
- **[Custom pane chrome increases implementation complexity]** → Roll out structure-first and keep the first pane-header model focused on title, tabs, focus, and minimal actions.
- **[Redesign becomes polish-only without improving orientation]** → Require persistent workspace/session navigation and explicit hierarchy rules, not only color and spacing changes.
- **[Visual ambition hurts performance]** → Prefer AppKit-native composition, avoid browser-style rendering layers, and keep chrome lightweight without unnecessary background work.
- **[Theme presets feel disconnected from shell behavior]** → Define shell and terminal tokens in one theme contract and require built-in themes to cover both layers.

## Migration Plan

1. Land the OpenSpec for shell composition, navigation, pane chrome, and theme behavior.
2. Implement the structural shell changes in `OmuxAppShell` without changing terminal engine boundaries.
3. Add pane-header and local-tab presentation changes while preserving existing workspace and session state models.
4. Introduce theme tokens and one default theme, then layer in curated built-in presets.
5. Add later customization work only after the built-in theme contract is proven and stable.

Because the project is still early, migration is primarily a matter of evolving shell composition rather than translating large amounts of existing user-facing state.

## Open Questions

- Should the first top bar include theme switching controls, or should theme selection wait for a dedicated settings surface?
- Should the sidebar remain always visible in v1 of the redesign, or should collapse/compact behavior be part of the first implementation slice?
- How much pane metadata should appear in headers before the UI starts to feel too busy for a terminal-first shell?
- Which theme should serve as the canonical OpenMUX default: a custom product theme only, or a curated community-inspired variant?
