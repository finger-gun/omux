## 1. Pane Content Model

- [x] 1.1 Add terminal and extension pane content descriptors to `OmuxCore` while preserving existing terminal pane construction helpers.
- [x] 1.2 Update workspace topology, focus, split, pane-stack, and RPC serialization helpers to handle extension panes without terminal sessions.
- [x] 1.3 Update persistence encoding/decoding so existing terminal-only workspace snapshots continue to restore and extension pane descriptors survive restart.
- [x] 1.4 Add core tests for terminal pane compatibility, extension pane focus, split behavior, and terminal-target rejection.

## 2. App Shell Hosting

- [x] 2.1 Add an AppKit extension pane host view for local preview HTML and disabled/error placeholder states.
- [x] 2.2 Update workspace canvas rendering to choose terminal or extension host views by pane content kind.
- [x] 2.3 Update pane chrome/sidebar metadata so extension panes show useful titles, plugin identity, and disabled/error state.
- [x] 2.4 Add shell tests for mixed terminal/extension layouts and focus preservation.

## 3. Control Plane and CLI

- [x] 3.1 Add JSON-RPC contracts for extension-pane create, update, focus, and close operations.
- [x] 3.2 Implement workspace controller actions for extension-pane lifecycle and structured terminal-action rejection for extension targets.
- [x] 3.3 Add `omux extension-pane` CLI commands for scriptable create/update/close flows.
- [x] 3.4 Emit extension-pane lifecycle/update events through the existing event stream.
- [x] 3.5 Add control-plane and CLI tests for extension-pane success and failure cases.

## 4. Plugin Configuration

- [x] 4.1 Add plugin configuration decoding for bundled optional plugins under `~/.omux/config.toml`.
- [x] 4.2 Add Markdown preview plugin settings and diagnostics for invalid plugin configuration.
- [x] 4.3 Update `omux config init`, docs, and configuration examples with plugin defaults.
- [x] 4.4 Add configuration tests for plugin enablement, invalid settings, and live reload behavior.

## 5. Markdown Preview Plugin

- [x] 5.1 Add a bundled Markdown preview plugin command that validates local file paths and plugin enablement.
- [x] 5.2 Implement Markdown-to-safe-preview-HTML rendering with a readable default style.
- [x] 5.3 Implement file watching with hot reload and save-event coalescing.
- [x] 5.4 Wire the plugin to create or reuse an extension pane and update it through public control-plane/CLI operations.
- [x] 5.5 Add tests for readable files, missing files, unsafe HTML/script handling, and update requests.

## 6. Validation and Documentation

- [x] 6.1 Document extension-pane control-plane commands and the plugin contract.
- [x] 6.2 Document the Markdown preview workflow for editing in Helix beside a hot-reloading preview pane.
- [x] 6.3 Validate that terminal keyboard/input behavior remains unchanged for terminal panes, including Option/Alt and dead-key paths.
- [x] 6.4 Run the existing build, test, and OpenSpec validation workflows.

## 7. External Plugin CLI Registration

- [x] 7.1 Add an OpenMUX-owned plugin directory convention for user-installed executable plugin commands.
- [x] 7.2 Dispatch unknown top-level `omux` commands to registered plugin executables without allowing plugins to shadow built-in commands.
- [x] 7.3 Add `omux plugin` inspection commands for listing registered plugins and finding the plugin directory.
- [x] 7.4 Document external plugin registration and add CLI tests for dispatch, argument/environment forwarding, listing, and built-in precedence.
- [x] 7.5 Re-run existing test and OpenSpec validation workflows.

## 8. Preview Runtime Fixes

- [x] 8.1 Ensure injected local preview HTML is allowed to complete its initial WebKit load while keeping external navigation constrained.
- [x] 8.2 Allow pane chrome to close split panes containing terminal or extension content, not only pane-local tabs.
- [x] 8.3 Add app-shell regression coverage for closing the terminal pane that opened an extension preview pane.
