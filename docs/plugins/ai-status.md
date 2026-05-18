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

The intended shape is one installable `ai-status` package with adapter-owned vendor modules behind it:

```text
omux ai-status
  ├─ codex
  ├─ gemini
  ├─ claude
  └─ future adapters
```

That keeps installation, discovery, and configuration simple for users while still isolating vendor-specific rules.

## Current first worked adapter: Codex

The first implemented adapter is Codex-oriented and supports two practical paths:

1. **Wrapper mode**
   - `omux ai-status codex wrap -- codex ...`
   - marks the pane as `working`
   - reports `idle` or `error` on process exit

2. **Observer mode**
   - the installed plugin subscribes to `terminal-title-changed` itself through its manifest
   - interprets Codex title changes as best-effort status signals
   - dedupes repeated spinner frames so `pane-status` does not get spammed
   - subscribes to `terminal-child-exited` so cached Codex observer state clears automatically when the process exits

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
