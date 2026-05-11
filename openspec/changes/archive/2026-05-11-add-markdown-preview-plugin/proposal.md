## Why

Markdown is a natural fit for terminal text editors, but terminal-only workflows make it hard to see how documentation will render in GitHub-style contexts while editing. OpenMUX can improve this workflow by allowing an optional Markdown preview to live beside the editor in the same workspace without baking Markdown-specific behavior into the terminal core.

This is also a strong first demonstration of richer external plugins: the feature is useful on its own, but the underlying extension-pane contract should make future optional preview/tool panes buildable without turning OpenMUX into a browser shell.

## Goals

- Add an OpenMUX-native way to host optional non-terminal extension panes inside existing workspace tabs, split layouts, and pane-local stacks.
- Keep terminal panes and libghostty-backed sessions isolated from extension-pane rendering details.
- Expose enough local control-plane surface for external plugin processes to create and update extension panes.
- Provide a Markdown preview plugin that can open beside a terminal editor, render a local Markdown file, and hot-reload on file changes.
- Make plugin enablement explicit and optional.

## Non-goals

- Do not turn OpenMUX into a browser-first shell or general web dashboard.
- Do not add Markdown parsing, GitHub API dependencies, or preview-specific behavior to terminal-session internals.
- Do not introduce a required always-on plugin daemon beyond the running OpenMUX app and plugin processes launched for enabled functionality.
- Do not support remote browsing, arbitrary JavaScript execution, Mermaid diagrams, PDF export, or full GitHub rendering parity in the first version.
- Do not copy implementation code or file structure from GPL projects; any comparable terminal-preview behavior is clean-room behavioral inspiration only.

## What Changes

- Introduce extension/content panes as first-class OpenMUX pane content alongside terminal panes.
- Add an extension-pane host in the AppKit shell that can render plugin-owned content, initially constrained to local HTML preview content.
- Extend persistence, focus, split rendering, pane lists, and sidebar metadata so extension panes participate in workspace layout without pretending to be terminal sessions.
- Add local control-plane/CLI operations for creating, updating, and closing extension panes using OpenMUX-native identifiers.
- Add a plugin configuration surface for optional plugin enablement and plugin-specific settings.
- Add a Markdown preview plugin that watches a local Markdown file, renders it to sanitized preview HTML, updates an extension pane on changes, and opens external links through the host.
- Preserve terminal keyboard correctness by routing text input only to terminal panes while allowing preview panes to receive normal AppKit/WebKit scroll and selection input.

## Capabilities

### New Capabilities

- `extension-content-panes`: Covers non-terminal pane content, extension-pane lifecycle, rendering constraints, focus behavior, persistence behavior, and control-plane operations.
- `markdown-preview-plugin`: Covers the optional Markdown preview plugin, file watching, hot reload, renderer behavior, and plugin enablement.

### Modified Capabilities

- `workspace-layout`: Workspace split layouts must allow extension panes as visible split-tree leaf content.
- `omux-control-plane`: The local JSON-RPC/CLI surface must expose extension-pane operations for plugin-driven workflows.
- `config-system`: User configuration must support optional plugin enablement and plugin settings.

## Impact

- **Core model:** `Pane` and related workspace topology need a typed content model so terminal panes retain sessions while extension panes carry plugin-owned descriptors.
- **App shell:** `WorkspaceWindowController`/canvas rendering must host terminal views and extension content views through a common pane view abstraction.
- **Control plane and CLI:** Add methods and commands for extension-pane open/update/close and plugin discovery or invocation as needed by the Markdown preview flow.
- **Configuration:** Extend `~/.omux/config.toml` schema with opt-in plugin configuration.
- **Plugin APIs:** Establish a small external-process plugin contract that uses public control-plane calls rather than private in-process mutation.
- **Dependencies:** A constrained WebKit/AppKit preview host may be used for local HTML rendering; Markdown rendering should remain plugin-owned and swappable.
- **libghostty boundary:** No libghostty types or preview behavior should leave `OmuxTerminalBridge`; extension panes are OpenMUX shell/content concepts, not terminal-engine surfaces.
- **Keyboard/input:** Terminal input routing must remain unchanged for terminal panes, including EU/ISO layout behavior, Option/Alt semantics, right-Option behavior, dead keys, and compose keys. Preview panes may handle scroll, selection, and link activation, but must not intercept terminal text input semantics.
