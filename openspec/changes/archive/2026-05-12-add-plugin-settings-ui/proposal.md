## Why

OpenMUX now has registry-installable plugins and extension panes, but plugins can only render passive content; they cannot safely receive user actions from pane UI or contribute native app commands. A graphical settings plugin for `~/.omux/config.toml` is a useful forcing function for richer plugin contracts while keeping configuration inspectable, terminal-first, and backed by the same CLI/control-plane validation path.

## Goals

- Let external plugins render interactive extension panes whose user actions are routed through an explicit OpenMUX-owned callback contract.
- Add scriptable config read/write/apply commands so settings UI, shell scripts, and future plugins can edit configuration through the same validation and reload path.
- Allow plugins to contribute native menu items that invoke plugin commands or existing OpenMUX commands, starting with Configuration menu actions such as Open and Reload.
- Ship a registry-hosted `settings-ui` plugin in `finger-gun/omux-plugins` that edits supported OpenMUX config values through a graphical extension pane.
- Preserve terminal keyboard correctness and the libghostty bridge boundary by keeping all plugin UI and menu work in shell/control-plane layers.

## Non-goals

- Do not turn OpenMUX into a browser-heavy app or general web app host; extension pane interactivity is a constrained local plugin surface.
- Do not make settings UI the only or canonical configuration surface; `~/.omux/config.toml` remains inspectable and editable by terminal editors.
- Do not allow arbitrary JavaScript in extension panes to execute shell commands directly.
- Do not expose libghostty types, AppKit view objects, or private controller internals to plugins.
- Do not replace existing hooks with config-save hooks; config mutation should be first-class CLI/control-plane behavior.

## What Changes

- Add an extension-pane interaction contract so constrained pane UI can submit structured actions back to OpenMUX and the owning plugin.
- Add config read and apply commands, including JSON output/input, validation, atomic TOML rewrite, and live reload behavior.
- Add plugin contribution metadata for native menu items and wire plugin-contributed items into the macOS menu model with explicit command targets.
- Add a registry plugin package, `settings-ui`, to `~/projects/omux-plugins` that reads effective config, renders a settings form, and saves changes through the new config commands.
- Update docs and tests for interactive extension panes, config editing commands, plugin menu contributions, and the settings UI plugin.
- No breaking changes are intended.

## Capabilities

### New Capabilities

- `plugin-menu-contributions`: Plugin metadata and app-shell behavior for native menu items contributed by installed plugins.
- `settings-ui-plugin`: Registry-hosted graphical settings plugin behavior, supported config fields, save flow, and failure states.

### Modified Capabilities

- `extension-content-panes`: Extension panes gain a constrained interaction/callback surface while remaining shell-owned and outside the terminal bridge.
- `config-system`: Configuration gains scriptable read/apply commands that preserve validation, formatting safety, and live reload behavior.
- `omux-control-plane`: The local RPC contract gains any app-mediated operations needed for extension-pane actions and config apply/reload results.
- `macos-app-shell`: Native menus gain plugin-contributed menu sections/items without compromising keybinding coherence or terminal focus behavior.

## Impact

- Affected code: `Sources/OmuxCLI`, `Sources/OmuxConfig`, `Sources/OmuxControlPlane`, `Sources/OmuxAppShell`, extension-pane host/view code, plugin registry discovery/install code where plugin manifests need menu metadata, and tests under the corresponding test targets.
- Affected external repo: `~/projects/omux-plugins` receives a `settings-ui` package and registry catalog/README updates.
- APIs/contracts: `omux config get --json`, `omux config apply --json-file <path>` or equivalent, extension-pane action delivery, plugin manifest menu metadata, and app menu command dispatch.
- Keyboard/input: extension-pane form input must remain isolated from terminal input; terminal panes must preserve ISO/EU layouts, Option/right-Option behavior, dead keys, compose keys, text input, and IME behavior.
- Performance: plugin menu discovery and settings rendering should use local installed metadata and on-demand plugin execution; no background service, remote lookup, or long-lived web process is introduced.
