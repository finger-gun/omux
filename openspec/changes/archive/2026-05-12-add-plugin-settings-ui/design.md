## Context

OpenMUX already supports extension panes as shell-owned local HTML content, a local JSON-RPC control plane, registry-installed external plugins, and a TOML configuration file at `~/.omux/config.toml`. The current plugin model is intentionally simple: external plugin commands can create or update panes, but pane content is passive and cannot safely send structured user actions back to OpenMUX or the owning plugin. Native menus are also owned by the app shell and do not currently expose plugin-contributed commands.

The settings UI plugin needs these seams to mature without compromising the product direction. The terminal remains the primary surface; the settings UI is a graphical companion for people who want discoverable configuration. The canonical config stays TOML, and all writes go through OpenMUX validation and reload paths.

## Goals / Non-Goals

**Goals:**

- Add a constrained extension-pane action bridge for plugin-owned panes.
- Add config read/apply CLI and control-plane operations that validate before writing and reload after successful writes.
- Add plugin manifest metadata for native menu contributions and surface those items in AppKit menus.
- Add a `settings-ui` package to the plugin registry that renders a local form for supported config fields and saves through the new commands.
- Keep plugin APIs inspectable, testable, and local-first.

**Non-Goals:**

- No browser-style marketplace, remote UI loading, or arbitrary web app runtime.
- No direct file writes from extension-pane JavaScript to `~/.omux/config.toml`.
- No plugin access to AppKit objects, controller instances, terminal surfaces, or libghostty types.
- No support for editing every possible `[ghostty]` pass-through key in the first UI.
- No replacement of terminal-editor workflows; users can still open and edit `config.toml` directly.

## Decisions

### Use a host-mediated extension-pane action bridge

Extension pane HTML may submit a structured action to OpenMUX only through a host-installed bridge. The action payload includes the pane ID, plugin ID, action name, and JSON-like data. OpenMUX verifies that the pane exists, that the plugin ID owns the pane, and that the action is allowed for that pane before dispatching.

Alternative considered: allow arbitrary links or forms to launch shell commands. This is rejected because it makes HTML content a command execution surface and would blur the boundary between rendered content and local automation.

### Dispatch pane actions to plugin commands as JSON

For external plugins, the first callback mechanism should invoke the plugin entrypoint with a reserved subcommand such as `__omux_action` and pass the action JSON on stdin. The plugin remains an ordinary process and can call public `omux` commands to mutate state. This keeps the contract terminal-friendly and avoids embedding a plugin runtime.

Alternative considered: keep a long-lived plugin daemon per pane. This is rejected for the first slice because it adds lifecycle, performance, and failure-management complexity. If future plugins need streaming interaction, the action contract can evolve without invalidating this one-shot callback model.

### Keep config mutation behind OpenMUX-owned commands

Add `omux config get --json` and `omux config apply --json-file <path>` backed by control-plane operations. `get` returns effective values plus enough metadata for UI labels/defaults. `apply` accepts only OpenMUX-owned supported keys in a typed JSON shape, rewrites TOML atomically, validates the rewritten file, reloads it, and preserves unsupported/user-authored TOML where possible.

Alternative considered: let the settings plugin parse and rewrite TOML itself. This is rejected because config validation, preservation, diagnostics, and live reload belong in OpenMUX.

### Store plugin menu contributions in plugin manifests

Registry plugin manifests can declare menu contributions under TOML tables. Installed plugin metadata remains local, and app menu construction reads local installed manifests/receipts, not remote registries. Each menu item declares a stable title, location, and command target. The first target type invokes a plugin command with arguments; a second target type may invoke a safe built-in OpenMUX command by identifier.

Alternative considered: have plugins mutate menus at runtime. This is rejected because menu structure should be deterministic, local, inspectable, and cheap to build.

### Put settings UI in the plugin registry

`settings-ui` lives in `finger-gun/omux-plugins` as an installable external plugin. It should use plain HTML/CSS/JavaScript only for form behavior and the OpenMUX bridge for save actions. The plugin opens an extension pane, renders current settings, handles save callbacks, writes a temporary JSON apply file, invokes `omux config apply`, and updates the pane with success or diagnostics.

Alternative considered: bundle settings UI into the app. This is rejected for now because the goal is to strengthen plugin extension points and keep core behavior focused.

## Risks / Trade-offs

- [Risk] Extension-pane actions become an accidental arbitrary command surface. → Mitigation: host validates pane ownership, action names, plugin IDs, and dispatches only through explicit plugin registry metadata.
- [Risk] Config rewrites destroy user comments or unknown formatting. → Mitigation: prefer targeted TOML rewrites for supported OpenMUX-owned tables and back up the previous file before atomic replacement; document that unsupported complex formatting may be normalized only in edited sections.
- [Risk] Interactive panes interfere with terminal keyboard behavior. → Mitigation: extension-pane focus is isolated from terminal surfaces, and tests cover terminal input preservation for Option/right-Option, dead keys, compose keys, and IME-sensitive paths where applicable.
- [Risk] Plugin menus become slow or flaky if plugin processes run during menu construction. → Mitigation: menus are built from local manifests only; plugin commands run only when a menu item is invoked.
- [Risk] Settings UI appears authoritative for every option. → Mitigation: first version clearly labels supported settings, keeps an "Open Config" action, and preserves direct TOML editing as canonical.

## Migration Plan

1. Add new CLI/control-plane commands and tests without changing existing config behavior.
2. Add extension-pane action support behind explicit content/bridge behavior; existing passive panes continue to render unchanged.
3. Extend plugin manifest parsing for optional menu metadata; existing plugin manifests remain valid.
4. Add native menu rendering for installed plugin contributions.
5. Add the `settings-ui` registry plugin and docs.

Rollback is straightforward: remove the registry plugin package and leave passive panes/config commands intact. The manifest metadata is optional, so existing installed plugins are unaffected.

## Open Questions

- Which config fields should the first `settings-ui` expose beyond theme, workspace default root, inactive pane opacity, scrollback settings, bundled plugin enablement, and registry URLs?
- Should menu contributions support key equivalents in the first slice, or should keybinding integration wait until plugin commands have a richer action registry?
- Should `config apply` preserve comments exactly for edited keys, or is section-level normalization acceptable for the initial implementation?
