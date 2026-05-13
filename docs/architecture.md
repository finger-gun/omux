# OpenMUX Architecture Overview

This page is the contributor-oriented map of how OpenMUX is structured today: how it **speaks** to automation and plugins, how it **renders** the shell, and how the workspace, pane, tab, and modal model fits together.

OpenMUX stays terminal-first by keeping the terminal runtime behind one bridge and reusing the same workspace model across the native shell, CLI, control plane, hooks, and plugins.

## System map

```mermaid
flowchart TD
    A[AppKit menus]
    B[Keyboard shortcuts]
    C[omux CLI]
    D[Plugin executables]

    A --> CP
    B --> CP
    C -->|JSON-RPC over Unix domain socket| CP
    D -->|JSON-RPC / omux commands| CP

    CP[OpenMUXControlPlaneService]
    CP --> WC[WorkspaceController<br/>shared shell actions]

    WC --> CORE[OmuxCore<br/>model and state]
    WC --> BRIDGE[OmuxTerminalBridge<br/>Ghostty boundary]
    WC --> HOOKS[OmuxHooks<br/>external processes]
    CORE --> WIN[WorkspaceWindowController<br/>native AppKit shell]
    BRIDGE --> WIN
```

## How OpenMUX speaks

OpenMUX has one shared action layer on purpose.

```mermaid
flowchart TD
    INPUT[omux / plugin / menu / command palette]
    INPUT --> MUTATE[WorkspaceController mutation]
    MUTATE --> STATE[update OmuxCore workspace state]
    STATE --> PUB[publish onChange and control-plane events]
    PUB --> RENDER[WorkspaceWindowController rerenders native shell]
    PUB --> RPC[omux / JSON-RPC callers receive updated state]
    PUB --> EVENTS[hooks and event subscribers observe structured events]
```

### Why this matters

- The CLI does not own a second workspace model.
- Plugins do not talk to AppKit directly.
- The native shell, command palette, menus, and `omux` all mutate the same live objects.
- `libghostty` stays behind `OmuxTerminalBridge` instead of leaking into shell code.

## How OpenMUX renders

The app window is shell-owned. Terminals and extension panes are hosted inside that shell.

```mermaid
flowchart TD
    WINDOW[NSWindow]
    WINDOW --> WWC[WorkspaceWindowController]
    WWC --> SHELL[WorkspaceShellViewController]

    SHELL --> SIDEBAR[Sidebar]
    SIDEBAR --> ROWS[workspaces and pane rows]

    SHELL --> CANVAS[Canvas]
    CANVAS --> LAYOUT[focused workspace tab rootLayout]
    LAYOUT --> SPLIT[split columns / rows]
    SPLIT --> CHILD[child split or pane stack]
    LAYOUT --> STACK[Pane stack]
    STACK --> HEADER[pane header and local pane tabs]
    STACK --> RENDERER[active pane renderer]
    RENDERER --> TERM[HostedTerminalPaneView]
    TERM --> GHOSTTY[Ghostty-backed native surface]
    RENDERER --> EXT[ExtensionPaneHostView]
    EXT --> HTML[shell-owned HTML / plugin content host]

    SHELL --> OVERLAY[Overlay layer]
    OVERLAY --> PALETTE[Command palette]
    OVERLAY --> MODALS[Floating pane modals]
    MODALS --> CHROME[Modal chrome]
    CHROME --> MODALSTACK[headerless pane stack renderer]
```

The important detail is that floating modals are **not** a second plugin UI system. A modal is another shell presentation of pane content, built from the same pane model and renderers.

## Workspace model

OpenMUX models docked and floating presentation separately, but they still reference the same pane identity concept.

```mermaid
flowchart TD
    W[Workspace]
    W --> TABS[tabs collection]
    TABS --> TAB[Tab]
    TAB --> ROOT[rootLayout: TabLayoutNode]
    ROOT --> NODE_SPLIT[split]
    ROOT --> NODE_STACK[paneStack]
    NODE_STACK --> PANES[panes collection]
    TAB --> FPID[focusedPaneID]

    W --> MODALS[floating pane modals collection]
    MODALS --> MODAL[FloatingPaneModal]
    MODAL --> FRAME[frame]
    MODAL --> MSTACK[paneStack]
    MSTACK --> MPANES[panes collection]

    W --> FTAB[focusedTabID]
    W --> FMODAL[focusedFloatingPaneModalID]
```

### Relationships

- A **workspace** owns docked tabs and any floating pane modals.
- A **tab** owns a recursive split tree.
- A **pane stack** is the leaf node of that split tree.
- A **pane** is the actual terminal or extension content identity.
- A **floating modal** owns a pane stack too, so modal content still uses pane-stack semantics.

## Pane, tab, and modal behavior

```mermaid
flowchart LR
    DOCKED[Docked pane tab]
    DOCKED --> REORDER[reorder within same stack]
    DOCKED --> MERGE[merge into another stack]
    DOCKED --> SPLIT[split into another region]
    DOCKED --> POPOUT[pop out to floating modal]
    DOCKED --> CLOSE[close]

    MODAL[Floating modal]
    MODAL --> MOVE[drag to move]
    MODAL --> MCLOSE[close]
    MODAL --> DOCKBACK[drag to outer edge to dock back]
    MODAL --> IDENTITY[preserve pane identity while changing presentation]
```

Today, the shell supports:

- docked pane stacks with local pane tabs
- floating pane modals for extension content and docked pane pop-out
- pop-out through pane-tab drag release in the center region
- pop-out through pane-tab context menus
- dock-back by dragging a floating modal to a workspace edge

Docking back into a specific existing pane stack is still follow-on work. Current dock-back targets the root layout edge of the active tab.

## Presentation and plugin ownership

Extension panes carry `presentationStyle` metadata:

- `pane-tab`
- `modal`

That metadata flows through:

- `omux extension-pane`
- bundled plugin commands such as `omux markdown-preview`
- JSON-RPC control-plane requests
- workspace persistence
- shell-driven dock / undock moves

This keeps plugin-owned panes consistent whether they were opened directly as a modal, created as a docked pane tab, or moved by the user afterward.

## Boundary summary

```mermaid
flowchart LR
    SHELL[OmuxAppShell]
    SHELL --> S1[AppKit windowing]
    SHELL --> S2[workspace chrome]
    SHELL --> S3[pane headers, tabs, modals, overlays]
    SHELL --> S4[focus orchestration]

    CORE[OmuxCore]
    CORE --> C1[workspace / tab / pane / modal model]
    CORE --> C2[layout mutations]
    CORE --> C3[focus state]
    CORE --> C4[persistence-friendly structures]

    BRIDGE[OmuxTerminalBridge]
    BRIDGE --> B1[Ghostty runtime]
    BRIDGE --> B2[terminal session attachment]
    BRIDGE --> B3[hosted terminal pane views]
    BRIDGE --> B4[terminal surface resize / input / snapshots]
```

If a change crosses those boundaries, it should do so intentionally and through shared contracts, not by reaching around them.
