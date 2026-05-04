## Why

Runtime-backed panes currently have bridge-owned scrollback capture, event dispatch, and persistence hooks, but the live `TerminalSessionSnapshot` path still exposes minimal placeholder transcript state. That leaves command completion events, `omux history`, restore context, and future automation without a reliable OpenMUX-native answer to "what text is in this pane right now?"

This matters now because the foundation has moved past shell layout and theming: the next useful layer is making terminal state durable, inspectable, and scriptable without leaking `libghostty` details outside the bridge.

## Goals

- Make runtime-backed pane snapshots expose bounded, real terminal text when the embedded runtime can provide it.
- Keep terminal text extraction behind `OmuxTerminalBridge` and return only OpenMUX-native snapshot/output-context values to shell, hooks, CLI, and control-plane code.
- Improve command-finished automation payloads so bounded output context is available when practical and explicitly unavailable otherwise.
- Reuse one bounded-text model for live snapshots, history requests, and persistence so restore context is predictable.
- Preserve performance by enforcing caller-controlled line/byte limits and avoiding unbounded transcript buffering.

## Non-goals

- Do not claim live PTY, SSH, TUI, or process restoration after app restart.
- Do not expose raw Ghostty text, selection, point, or action payload types outside `OmuxTerminalBridge`.
- Do not add background transcript indexing, cloud sync, browser surfaces, or AI-specific core behavior.
- Do not change keyboard/input routing, Option/Alt behavior, dead-key handling, or IME composition semantics.
- Do not broaden persisted scrollback exposure to hooks by default.

## What Changes

- Runtime session snapshots will carry bounded rendered terminal text derived from hosted Ghostty surfaces instead of empty placeholder transcript/current-input fields when text is available.
- The bridge snapshot contract will distinguish available bounded text from explicit unavailable state without fabricating content.
- Command completion event enrichment will source bounded output context from the improved snapshot/history path rather than an empty rendered-text placeholder.
- Workspace persistence and restore will continue to store bounded historical context only, but will benefit from the same higher-quality text extraction path.
- `omux history` and control-plane history responses will remain OpenMUX-native and bounded while reflecting richer runtime-backed pane text.
- Tests will cover successful text capture, truncation, unavailable state, command-finished output context, and persistence/restore semantics.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `terminal-bridge`: Define live runtime snapshot text semantics, bounded transcript/current-input behavior, explicit unavailable state, and bridge-boundary rules.
- `terminal-action-dispatch`: Clarify that command completion output context is populated from bounded runtime snapshot/history data when available.
- `terminal-scrollback-persistence`: Clarify that persisted historical context uses the same bounded runtime text capture semantics without implying live session restoration or hook exposure.

## Impact

- `Sources/OmuxTerminalBridge`: runtime snapshot construction, bounded text extraction helpers, and bridge-owned snapshot/result types.
- `Sources/OmuxAppShell`: command completion enrichment, workspace persistence snapshot preparation, and restore/history handling.
- `Sources/OmuxControlPlane` and `Sources/OmuxCLI`: history and event payloads stay compatible but should receive richer bounded text when available.
- Tests for bridge snapshot behavior, command output-context enrichment, persistence sanitization, and CLI/control-plane history formatting.
- No new third-party dependencies, background services, browser architecture, or vendor-specific automation paths.

## Manifest Alignment

This change is terminal-first because it improves the terminal state model itself rather than adding unrelated chrome. It is open and hackable because richer bounded snapshots make CLI, hooks, and future plugins more useful through the same local control surface. It protects performance by bounding text capture and protects the `libghostty` boundary by keeping all engine-specific text APIs inside `OmuxTerminalBridge`.
