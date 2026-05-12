## 1. Config read/apply foundation

- [ ] 1.1 Add typed config export models for supported settings, defaults metadata, source path, and diagnostics.
- [ ] 1.2 Implement `omux config get --json` using the existing config loader and diagnostics.
- [ ] 1.3 Implement `omux config apply --json-file <path>` with supported-key validation, atomic TOML rewrite, previous-file backup, and unchanged-file preservation on failure.
- [ ] 1.4 Wire config read/apply through the local control plane so app-mediated callers receive structured success, diagnostics, and reload status.
- [ ] 1.5 Add config CLI/control-plane tests for successful export, diagnostics export, valid apply, invalid apply, backup creation, and preservation of unedited settings.

## 2. Extension-pane action bridge

- [ ] 2.1 Define OpenMUX-native extension-pane action request/response models with pane ID, plugin ID, action name, and JSON payload.
- [ ] 2.2 Add host-side bridge support for extension pane content to submit actions without exposing shell execution, AppKit objects, or terminal bridge internals.
- [ ] 2.3 Validate pane ownership, plugin identity, action names, and payload shape before dispatching actions.
- [ ] 2.4 Dispatch validated actions to external plugin entrypoints using a reserved action invocation mode with JSON on stdin.
- [ ] 2.5 Add tests for valid action dispatch, wrong-plugin rejection, malformed payload rejection, plugin failure reporting, and no shell-text execution.
- [ ] 2.6 Add keyboard/input regression coverage showing terminal input semantics remain unchanged around extension-pane interactions.

## 3. Plugin menu contributions

- [ ] 3.1 Extend plugin manifest parsing to support optional native menu contribution metadata for installed plugins.
- [ ] 3.2 Preserve backward compatibility for existing plugin manifests without menu metadata.
- [ ] 3.3 Build deterministic app-shell menu items from local installed plugin metadata without executing plugin processes.
- [ ] 3.4 Support plugin command targets and allowed built-in OpenMUX command targets for menu items.
- [ ] 3.5 Add Configuration menu items for opening settings UI, opening config, and reloading config where declared by plugin metadata.
- [ ] 3.6 Add tests for manifest parsing, invalid target diagnostics, menu refresh after install/uninstall, menu invocation, and terminal focus preservation.

## 4. Settings UI registry plugin

- [ ] 4.1 Add a `settings-ui` package to `~/projects/omux-plugins` with catalog entry, manifest, executable plugin, and README updates.
- [ ] 4.2 Implement `omux settings-ui` to fetch config JSON and create an extension pane with a local settings form.
- [ ] 4.3 Implement settings form save actions through the extension-pane action bridge and `omux config apply`.
- [ ] 4.4 Render success, validation diagnostics, and load/apply failures inside the settings pane.
- [ ] 4.5 Include plugin menu contribution metadata for Configuration menu entry points.
- [ ] 4.6 Validate local registry discovery/install and plugin registration for `settings-ui`.

## 5. Documentation and validation

- [ ] 5.1 Update OpenMUX docs for config get/apply, extension-pane action callbacks, plugin menu contributions, and the settings UI plugin.
- [ ] 5.2 Update `~/projects/omux-plugins` README with `settings-ui` usage, trust notes, and local testing commands.
- [ ] 5.3 Run relevant config, CLI, control-plane, app shell, extension pane, and plugin tests.
- [ ] 5.4 Run strict OpenSpec validation for `add-plugin-settings-ui`.
