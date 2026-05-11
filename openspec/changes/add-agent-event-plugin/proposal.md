## Why

Developers run long-lived terminal tasks and multiple terminal agents in parallel. Ghostty-compatible tools can already report progress through terminal-native OSC progress sequences, and OpenMUX already receives those events through the terminal bridge. OpenMUX should surface that state subtly in pane chrome instead of requiring provider-specific agent plugins for the common case.

Hooks and plugins still need a public way to set the same status when a tool does not emit terminal progress sequences. A small, provider-neutral `pane-status` CLI/control-plane surface lets external automation opt in without turning OpenMUX into an AI-first shell.

## Goals

- Render terminal-native progress reports as subtle pane/tab status orbs.
- Use small status states: working, indeterminate, error, idle, and clear.
- Add a provider-neutral `omux pane-status` command and JSON-RPC method for hooks/plugins.
- Keep status transient and non-persistent.
- Keep provider-specific agent adapters outside core.
- Preserve terminal input routing and the libghostty bridge boundary.

## Non-goals

- Do not add core integrations for Codex, Claude Code, Copilot, Gemini, Aider, Cursor, or other agent providers.
- Do not scrape terminal output to infer agent state.
- Do not add an always-on watcher daemon.
- Do not make pane status durable workspace identity.
- Do not add browser/webview UI for this feature.

## What Changes

- Pane progress renders as compact status orbs in workspace/sidebar pane rows and pane tabs.
- Running/working progress pulses, error is red, and done/idle is a brief blue orb before clearing.
- `omux pane-status` exposes the same status surface for hooks and plugins through existing terminal selectors.
- The control plane publishes `pane.statusChanged` events with OpenMUX-native status fields.
- Hook documentation and examples show how external scripts can set pane status without depending on private app state.

## Impact

- **Control plane and CLI:** Adds `pane.status` JSON-RPC and `omux pane-status`.
- **App shell:** Adds small status orb chrome in pane tabs and sidebar terminal rows.
- **Hooks/plugins:** External processes can call `omux pane-status --pane ... --state ...`.
- **Persistence:** Progress/status remains transient and is not restored after restart.
- **Keyboard/input:** No terminal input, IME, Option/Alt, dead-key, compose-key, or mouse-routing changes.
- **libghostty boundary:** Uses existing OpenMUX-native terminal action mapping; no libghostty types leak into app chrome or CLI contracts.
