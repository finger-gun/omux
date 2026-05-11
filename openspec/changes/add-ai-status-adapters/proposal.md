## Why

AI terminal tools do not consistently report progress to the terminal host: Copilot can update OpenMUX pane status through terminal-native progress events, while Codex and similar tools currently leave users guessing which panes are working, waiting for input, done, or failed. OpenMUX should make this visible through open, terminal-first adapter contracts rather than baking vendor-specific AI behavior into the app shell.

## Goals

- Let external adapters translate tool-specific activity from Codex, Claude, Copilot, and future terminal tools into OpenMUX pane status.
- Reuse the public `omux pane-status` and local JSON-RPC control plane so adapters remain inspectable, scriptable, and replaceable.
- Provide a small bundled adapter framework and at least one Codex adapter example without making OpenMUX an AI-first product.
- Keep adapter execution lightweight and opt-in, with no always-on background service when no adapter is configured.

## Non-goals

- Do not embed AI provider SDKs, browser views, or vendor-specific runtimes in the OpenMUX app process.
- Do not parse every terminal keystroke or require OpenMUX to understand arbitrary AI tool protocols in core.
- Do not replace terminal-native progress reports; adapters complement existing Ghostty/libghostty progress events.
- Do not introduce remote telemetry, cloud services, or provider lock-in.

## What Changes

- Add an AI/tool status adapter capability that defines how external adapter executables map tool activity to `working`, `indeterminate`, `needs-input`, `idle`, `error`, and `clear` pane status states.
- Add a bundled adapter runner contract for wrapper-style and observer-style adapters, starting with Codex-oriented behavior and leaving Claude/Copilot adapters as additional pluggable adapters.
- Clarify that adapters mutate OpenMUX only through public automation surfaces (`omux pane-status` or JSON-RPC), using `OMUX_PANE_ID` / `OMUX_SESSION_ID` or explicit targets.
- Extend documentation and examples so users can install or write adapters for any terminal tool that exposes output, logs, hooks, or a CLI wrapper point.
- Preserve the libghostty bridge boundary: terminal-native progress remains translated in `OmuxTerminalBridge`, while tool adapters live at the plugin/hook/control-plane layer.

## Capabilities

### New Capabilities

- `ai-status-adapters`: Defines the external adapter model for translating terminal tool state into OpenMUX pane status without vendor-specific core behavior.

### Modified Capabilities

- `omux-control-plane`: Specify pane-status automation as the stable local API adapters use to report tool progress and attention state.
- `hooks-foundation`: Specify how hooks/plugins may act as tool-status bridges using OpenMUX-native identifiers and public automation.
- `macos-app-shell`: Specify that adapter-reported pane status is rendered through the same shell chrome as terminal-native progress events.

## Impact

- Affected code: `OmuxCLI`, `OmuxControlPlane`, `OmuxAppShell`, `OmuxHooks`, plugin registry/docs, and status rendering tests.
- Public API impact: documents and hardens `omux pane-status` / JSON-RPC pane status as the supported adapter reporting surface.
- Plugin API impact: adds adapter conventions and example adapter locations without requiring in-process plugins.
- Keyboard/input impact: adapters must not alter key routing, IME composition, dead keys, Option/right-Option behavior, or terminal input delivery; any observer mode must be read-only unless it calls explicit public automation.
- Performance impact: adapters should run on demand or per configured tool process, avoid unbounded polling, and avoid long-lived background services by default.
