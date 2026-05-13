## Why

OpenMUX now has multiple shell-owned UI surfaces beyond the terminal canvas, including the command palette and extension panes, but plugins still only have one durable presentation target: a docked pane. That makes plugin workflows like Markdown preview less flexible than the rest of the workspace model and leaves no coherent path for floating tool surfaces, snapping pane tabs out of the layout, or docking them back in without inventing a second UI system.

This matters now because extension panes, pane-tab drag interactions, and command-palette overlays already exist. OpenMUX should turn those pieces into a consistent shell capability that remains terminal-first, plugin-friendly, and native instead of drifting toward ad hoc browser-like popups.

## What Changes

- Add a shell-owned floating modal presentation for pane content so extension panes can open as native overlay modals without going through the terminal bridge.
- Allow floating modal content to reuse OpenMUX pane identities so a pane can move between docked workspace layout and floating modal presentation without losing plugin or host continuity.
- Extend pane-tab drag behavior to support snapping eligible pane tabs out into floating modals and docking eligible floating content back into pane stacks.
- Add plugin/control-plane support for choosing docked-pane or modal presentation when opening extension-owned content.
- Add a Markdown preview presentation setting so the bundled plugin can open previews as either a pane tab or a modal.
- Preserve terminal input semantics, native focus behavior, and the libghostty bridge boundary while introducing floating modal surfaces.

## Capabilities

### New Capabilities
- `floating-pane-modals`: Shell-owned floating modal containers that can host pane content, preserve pane identity, and support dock/undock movement between modal and workspace presentation.

### Modified Capabilities
- `extension-content-panes`: Extension pane requirements change to support multiple shell presentation targets, including docked pane stacks and floating modal containers.
- `workspace-layout`: Workspace layout requirements change to represent floating modal presentation and preserve focus/layout intent when panes move between docked and floating states.
- `pane-tab-drag-splitting`: Pane-tab drag requirements change to support tear-out to modal presentation and docking modal content back into pane stacks.
- `markdown-preview-plugin`: Markdown preview requirements change to allow preview presentation as either a pane tab or a modal, driven by OpenMUX-native settings and plugin/control-plane contracts.

## Impact

- Affected specs: `extension-content-panes`, `workspace-layout`, `pane-tab-drag-splitting`, `markdown-preview-plugin`, plus new `floating-pane-modals`.
- Affected code will likely include `WorkspaceController`, `WorkspaceWindowController`, pane host rendering, extension-pane control-plane methods, markdown preview configuration, and Markdown preview plugin request handling.
- This should add shell-side presentation/state modeling, not a browser-heavy subsystem, background service, or libghostty-facing modal runtime.
- Keyboard and input handling must remain explicit: modal focus, ESC behavior, text entry, ISO/EU layouts, Option/right-Option behavior, dead keys, compose keys, and IME handling must not regress terminal panes behind or beside floating modals.
- Plugin/API impact: extension-pane creation and update contracts will need an inspectable presentation choice, while keeping plugin content host ownership and action validation intact.
