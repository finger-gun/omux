## Context

OpenMUX currently models visible workspace content as terminal-backed panes. A `Pane` owns a terminal `SessionDescriptor`, split-tree leaves host pane-local tab stacks, and the AppKit shell renders Ghostty-backed terminal views through `OmuxTerminalBridge`. The control plane and CLI already expose workspace, pane, session, history, and event operations using OpenMUX-native identifiers.

Markdown preview needs a pane that is visible beside a terminal editor but is not itself a terminal session. If Markdown rendering is hardcoded into the terminal pane model, OpenMUX would drift toward core feature bloat and make future preview/tool panes harder to build. The right seam is a reusable extension-content pane model with Markdown preview as the first optional plugin-style consumer.

## Goals / Non-Goals

**Goals:**

- Represent terminal panes and extension panes with an explicit OpenMUX-native pane content type.
- Preserve existing terminal-session behavior and libghostty bridge boundaries.
- Host extension panes inside the same split layout and pane-local stack system as terminal panes.
- Expose local JSON-RPC/CLI operations for creating and updating extension panes.
- Provide an optional Markdown preview plugin workflow that can open a preview next to a terminal editor and hot-reload local file changes.
- Keep plugin communication inspectable through public control-plane commands.

**Non-Goals:**

- General-purpose browsing inside OpenMUX.
- In-process third-party plugin execution, WASM runtime, or language-specific plugin SDK.
- Full GitHub rendering parity, remote GitHub integration, Mermaid rendering, PDF export, or arbitrary script execution.
- Changes to libghostty or terminal input encoding.

## Decisions

### Decision: Add a typed pane content model

`Pane` should gain a content descriptor rather than assuming every pane owns a terminal session. Terminal panes keep a `SessionDescriptor`; extension panes carry an `ExtensionPaneDescriptor` with fields such as plugin ID, title, content kind, source, and update payload metadata.

Alternatives considered:

- **Separate `ExtensionPane` tree:** avoids touching `Pane`, but duplicates layout/focus/persistence logic.
- **Optional `session` on `Pane`:** smaller edit, but makes terminal-only assumptions less type-safe.

Typed pane content is the cleanest long-term model because all workspace topology remains shared while terminal/session-specific logic stays explicit.

### Decision: Keep extension rendering behind AppKit shell, not terminal bridge

The AppKit shell should choose the hosted view based on pane content. Terminal content continues through `HostedTerminalPaneView` and `OmuxTerminalBridge`; extension content uses a new shell-owned host view.

Alternatives considered:

- **Render previews inside terminal sessions:** simple but cannot provide GitHub-style HTML preview.
- **Put WebKit into the terminal bridge:** violates the libghostty boundary and mixes unrelated responsibilities.

The shell is the correct owner because extension panes are workspace UI content, not terminal engine surfaces.

### Decision: Start with constrained local HTML extension content

The first extension host should support local HTML preview content with locked-down navigation defaults. A `WKWebView` is acceptable as an implementation detail when constrained to plugin-supplied preview content, external-link handoff, and no browser chrome.

Alternatives considered:

- **Native attributed text rendering:** safer and simpler, but too far from GitHub-style output and limited for images/tables.
- **Local HTTP server only:** easy for some plugins, but introduces more background service and token management surface than needed for the initial path.

Constrained local HTML gives good Markdown preview ergonomics while preserving the "not a browser shell" product boundary.

### Decision: Use public control-plane operations as the first plugin contract

The Markdown preview plugin should create and update extension panes through JSON-RPC/CLI commands. The app should not interpret plugin stdout as commands, and plugins should not mutate private in-process state.

Alternatives considered:

- **Embed a plugin runtime:** premature for the current project stage.
- **Reuse hooks only:** hooks are event reactions, not long-lived preview pane owners.

This follows the existing hooks/control-plane philosophy: the protocol is the platform.

### Decision: Implement Markdown preview as an optional bundled plugin workflow first

The first implementation can be a bundled, opt-in plugin command that uses public extension-pane operations. Over time, the same contract can support user-installed external plugin processes.

Alternatives considered:

- **Core `omux markdown-preview` feature with no plugin identity:** faster, but undermines the plugin demonstration goal.
- **Full third-party plugin manager first:** too broad for this feature.

Bundled optional plugin behavior proves the contracts without requiring the whole future plugin ecosystem at once.

### Decision: Let external plugins register top-level CLI commands by executable discovery

The `omux` CLI should route plugin commands through a registry. Bundled plugins register in-process command metadata, and user-installed plugins are discovered from `~/.omux/plugins/`. A user plugin can register command `foo` by installing either `~/.omux/plugins/foo` as an executable or `~/.omux/plugins/foo/plugin` as an executable. Built-in CLI commands always win on name conflicts; bundled plugin registrations win over external plugins with the same command name.

Alternatives considered:

- **Config-only command registry:** explicit but makes simple plugin installation harder and creates another stale-config failure mode.
- **PATH-only discovery:** familiar, but does not make OpenMUX plugin ownership, listing, or documentation inspectable.
- **In-process Swift registration:** unsuitable for user-created plugins and conflicts with the external-process-first plugin direction.

Executable discovery keeps user plugins language-agnostic and makes plugin commands easy to inspect, while still preserving a narrow, public CLI/control-plane contract.

### Decision: File watching belongs to the plugin

The Markdown plugin watches the source file and pushes rendered updates into its preview pane. OpenMUX core should not watch arbitrary plugin files except for its own configuration.

Alternatives considered:

- **Core app watches every extension source:** centralizes lifecycle but bloats core and couples it to Markdown semantics.

Plugin-owned watching keeps core generic and lets other plugins choose different update strategies.

## Risks / Trade-offs

- **Pane model churn** -> Keep terminal content accessors and helper methods so existing terminal behavior remains explicit and testable.
- **Keyboard/input regressions** -> Ensure terminal text input still targets only terminal panes; extension panes can receive scroll/selection/link input without changing Option/Alt, dead-key, compose, or IME handling for terminals.
- **Web content security** -> Disable arbitrary navigation/script-oriented behavior by default, sanitize rendered Markdown, and open external links outside the pane.
- **Plugin lifecycle complexity** -> Start with explicit CLI/control-plane commands and a bundled plugin command rather than a full plugin supervisor.
- **Persistence with missing plugins** -> Persist extension descriptors but render a clear disabled/missing placeholder instead of failing workspace restore.
- **Performance under hot reload** -> Bound update payload size where needed and coalesce rapid file changes in the plugin.

## Migration Plan

1. Introduce pane content descriptors while preserving default terminal pane construction.
2. Update layout, persistence, list, focus, and render paths to branch on pane content type.
3. Add extension-pane control-plane and CLI operations.
4. Add plugin configuration decoding and defaults.
5. Add the Markdown preview plugin command and renderer/watcher loop.
6. Document the optional plugin workflow.

Existing persisted terminal panes should decode as terminal content. If an extension pane cannot be restored because its plugin is unavailable or disabled, OpenMUX should restore the layout with a placeholder extension pane rather than deleting user layout state.

## Open Questions

- Which Markdown renderer should become the long-term default: a Swift-native renderer, `cmark-gfm`, or an external plugin runtime renderer?
- Should the first hot-reload transport use direct JSON-RPC HTML updates or a local custom URL scheme?
- How much GitHub-style CSS should be bundled versus plugin-provided?
