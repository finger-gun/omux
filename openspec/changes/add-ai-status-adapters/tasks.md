## 1. Pane Status Contract

- [x] 1.1 Audit `omux pane-status` and JSON-RPC pane-status behavior against the new control-plane requirements, including explicit target failures, state aliases, progress values, label/message/source fields, and local-only OpenMUX-native identifiers.
- [x] 1.2 Add or update CLI/control-plane tests that cover adapter-style calls for `working`, `indeterminate`, `needs-input`, `idle`, `error`, and `clear`.
- [x] 1.3 Update public docs for `omux pane-status` so hook and plugin authors can use it as the stable adapter reporting surface.

## 2. Bundled AI-Status Host

- [x] 2.1 Define the bundled Swift `ai-status` host module boundary, keeping vendor-specific parsing outside app-shell layout code and outside `OmuxTerminalBridge`.
- [x] 2.2 Implement host-owned normalization, confidence, debounce/dedupe, stale-clear, and source metadata handling for `working`, `indeterminate`, `needs-input`, `idle`, `error`, and `clear`.
- [x] 2.3 Keep passive terminal-title detection as the zero-setup fallback, starting with Codex and Gemini title matchers that are adapter-owned and confidence-scored.
- [x] 2.4 Document how Codex, Gemini, Claude, Copilot, and future tool adapters plug into the same bundled host without requiring one plugin per vendor.

## 3. Hook Relay And Vendor Config

- [x] 3.1 Add `omux ai-status hook --source <vendor> --event <event>` that reads vendor hook JSON from stdin, normalizes it, and reports pane status through the public control plane.
- [x] 3.2 Add `omux ai-status hooks setup|uninstall [codex|claude|gemini]` command parsing, diagnostics, command-driven setup behavior matching cmux, and explicit target-vendor validation.
- [x] 3.3 Implement Codex hook config support for `~/.codex/hooks.json` and any required `~/.codex/config.toml` hooks enablement, with OpenMUX ownership markers and uninstall that removes only OpenMUX-owned entries.
- [x] 3.4 Implement Gemini hook config support for `~/.gemini/settings.json`, with OpenMUX ownership markers and uninstall that removes only OpenMUX-owned entries.
- [x] 3.5 Implement the Claude hook strategy as wrapper-injected or guided configuration, matching cmux's conservative setup shape and avoiding silent edits to Claude-owned settings.
- [x] 3.6 Ensure hook relay failures are isolated, produce useful local diagnostics, and do not block terminal sessions, later hooks, or keyboard input delivery.

## 4. JSONL Wrapper Support

- [x] 4.1 Add a Codex JSONL wrapper parser for controlled-launch sessions, mapping documented `codex exec --json` events such as turn start/completion/failure and item progress to normalized states.
- [x] 4.2 Add a Gemini stream JSON wrapper parser for controlled-launch sessions, mapping tool, result, error, and completion events to normalized states.
- [x] 4.3 Add a Claude stream JSON wrapper parser for controlled-launch sessions, mapping assistant/stream/result/failure events to normalized states.
- [x] 4.4 Document JSONL wrappers as secondary to hooks/passive observation for arbitrary interactive panes because wrappers only help when OpenMUX launches the agent command.

## 5. Tests And Docs

- [x] 5.1 Add CLI parsing tests for `omux ai-status hook` and `omux ai-status hooks setup|uninstall`.
- [x] 5.2 Add hook config merge/uninstall tests proving OpenMUX markers preserve user-authored vendor config entries.
- [x] 5.3 Add hook payload mapping tests for Codex, Gemini, and Claude relay events.
- [x] 5.4 Add JSONL event mapping tests for Codex, Gemini, and Claude wrapper parsers.
- [x] 5.5 Add docs for hook setup, uninstall, relay payload expectations, passive title fallback, JSONL wrapper mode, privacy boundaries, and no terminal input interception.
- [x] 5.6 Verify adapter-reported status renders through the same tab/sidebar/pane chrome as terminal-native progress events and does not steal focus or alter terminal input routing.
- [x] 5.7 Run relevant Swift tests for CLI, control-plane, hooks/config management, adapter mapping, and app-shell status rendering.
- [x] 5.8 Run OpenSpec validation for `add-ai-status-adapters` and fix any spec or task formatting issues.
