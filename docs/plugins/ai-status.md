# AI Status

`ai-status` is a bundled OpenMUX plugin that translates tool-specific AI/runtime signals into normalized pane status updates.

It is enabled by default and can be toggled from the plugin picker:

```sh
omux plugins
```

OpenMUX owns the host-side surfaces that make it work:

- `omux pane-status`
- plugin discovery/install UX
- shell rendering for pane status orbs
- docs and tests

The bundled plugin host owns:

- adapter selection
- noisy observer dedupe/debounce
- local state cache
- stale-to-`clear` synthesis
- vendor-specific adapter logic

## Shared host, not one plugin per vendor

The intended shape is one bundled `ai-status` host with adapter-owned vendor modules behind it:

```text
omux ai-status
  ├─ codex
  ├─ gemini
  ├─ claude
  └─ future adapters
```

That keeps discovery and configuration simple for users while still isolating vendor-specific rules.

## Current adapters

The bundled host has adapter-owned logic for Codex and Gemini passive title signals, plus a hook relay and JSONL event mappers for Codex, Gemini, and Claude.

### Passive title fallback

Passive title detection is the zero-setup fallback. It is useful when a user starts an agent manually in an existing pane and has not installed vendor hooks.

- Codex title matching is best-effort and confidence-scored because Codex title strings are not a stable cross-version API.
- Gemini title matching uses documented status icons where available.
- Unknown titles leave the current pane status unchanged.

### Hook relay

For stronger interactive-session detection, install vendor hooks explicitly:

```sh
omux ai-status hooks setup
omux ai-status hooks setup codex
omux ai-status hooks setup gemini
omux ai-status hooks setup claude
omux ai-status hooks uninstall codex
```

Hook setup is never run automatically. Codex and Gemini setup write OpenMUX-owned marker entries into vendor configuration and uninstall removes only those marker-owned entries. Claude currently follows the conservative path: OpenMUX prints guided/wrapper setup and does not silently edit Claude-owned settings.

Vendor hook entries call:

```sh
omux ai-status hook --source codex --event PermissionRequest
omux ai-status hook --source gemini --event PreToolUse
omux ai-status hook --source claude --event StopFailure
```

The command reads vendor JSON from stdin, maps it into normalized pane status, and reports through the public control plane. If the relay cannot find `OMUX_PANE_ID`, `OMUX_SESSION_ID`, or an explicit target, it no-ops so the vendor hook does not block the agent.

### Wrapper modes

Process lifecycle wrapper mode is available for Codex:

```sh
omux ai-status codex wrap -- codex ...
```

It marks the pane as `working`, runs the command, then reports `idle` or `error` based on process exit.

The host also includes parser-level support for structured JSONL/stream-json events from Codex, Gemini, and Claude. JSONL wrappers are more precise than title matching when OpenMUX controls launch, but they are secondary to hooks/passive observation for arbitrary manually-started interactive panes.

Advanced/manual entry points still exist when you need to test or replay signals directly:

```sh
omux ai-status codex title --pane <id> --title "<raw terminal title>"
omux ai-status codex clear --pane <id>
```

The shared host also exposes stale cleanup:

```sh
omux ai-status clear-stale --max-age 20
```

This lets the host synthesize `clear` for old observer-only states after session end or signal loss.

## Target resolution

When the plugin runs inside an OpenMUX-launched pane, it can target the current pane without extra lookup by using the terminal session environment already present there:

- `OMUX_PANE_ID`
- `OMUX_SESSION_ID`

If those are not available, pass an explicit OpenMUX-native target such as `--pane`, `--session`, or `--focused`.

If the host is running outside the target pane, use public discovery commands such as `omux panes`, `omux sessions`, or `omux --focused`-style targeting instead of scraping OpenMUX UI.

## Input safety

The host and adapters are observer-side integrations only. They may call `omux pane-status`, but they must not intercept or rewrite:

- IME composition
- dead keys
- compose-key sequences
- Option/right-Option text input
- paste
- terminal mouse input

If a vendor offers stronger machine-readable signals, prefer those over title or transcript heuristics.

## Failure behavior

- unknown observer signals leave the current pane status unchanged
- repeated equivalent observer signals refresh cache timestamps but do not re-emit `omux pane-status`
- wrapper mode preserves the wrapped process exit code
- control-plane failures stay external to the plugin process; they do not create private fallback paths inside OpenMUX core

## Future adapters

The host contract is designed for adapter-owned vendor modules. A future adapter should contribute:

- its preferred signal surfaces
- matcher logic
- any vendor-owned state file or log locations
- optional wrapper integration
- any plugin-owned hook callback guidance

The host keeps ownership of:

- normalized OpenMUX states
- target resolution
- dedupe/debounce
- cache format
- stale clear policy
