## Context

Agent Sessions already stores a normalized local index. The current rigid part is adapter discovery: `VaultAdapterFactory` creates a fixed list of built-in adapters, and config rejects unknown agent names. The runtime plugin model already supports external executables, but those executables do not have a first-class way to contribute normalized Agent Sessions rows.

The smallest useful design is a plugin-declared adapter callback that OpenMUX runs during Agent Sessions reindex. The plugin owns source-specific scanning and normalization. OpenMUX owns validation, upsert, hidden-row preservation, search, sidebar rendering, and resume behavior.

## Goals / Non-Goals

**Goals:**

- Keep the external adapter boundary process-based and inspectable.
- Use normalized JSON as the adapter output.
- Keep built-in adapters enabled by default.
- Keep external adapters enabled by default when configured.
- Allow built-in adapters to be disabled per agent through existing per-agent config.
- Allow external adapters to be disabled globally or individually.

**Non-goals:**

- No direct plugin access to the SQLite index.
- No schema migrations beyond the existing normalized index shape.
- No separate background adapter daemon.
- No new terminal, hook, or key handling behavior.

## Decisions

### Decision: Plugin adapters emit normalized rows

A plugin adapter callback prints a JSON array to stdout. Each object represents one session row:

```json
[
  {
    "id": "abc123",
    "title": "Fix release notes",
    "cwd": "/Users/example/project",
    "updated_at": "2026-05-21T18:00:00Z",
    "source_path": "/Users/example/.omp/agent/sessions/abc123.jsonl",
    "model": "gpt-5",
    "git_branch": "main"
  }
]
```

`id` is the adapter's raw session id. The plugin command name is the default agent name, so an OMP plugin that emits `id = "abc123"` indexes the normalized OpenMUX id `omp:abc123`.

Rationale: the adapter does only the source-specific work; OpenMUX keeps the product contract and local index behavior consistent.

### Decision: Plugin manifests register Agent Sessions adapter capability

Installed plugins can declare:

```toml
[plugin]
command = "omp"
entrypoint = "plugin"

[agent-sessions]
callback = "__omux_agent_sessions"
arguments = ["discover"]
source_kind = "omp_jsonl"
resume_command = "omp --resume {session_id}"
```

OpenMUX invokes the plugin entrypoint with `callback` plus `arguments`, and reads normalized JSON rows from stdout.

Rationale: this uses the existing plugin system and makes Agent Sessions adapters a plugin capability, not a separate registry.

### Decision: Built-in and external adapters run by default

`agent-sessions reindex` runs built-in adapters and manifest-declared external adapters when Agent Sessions is enabled. Users can disable all external adapters with `external_adapters_enabled = false` or disable one external adapter with `enabled = false` under `[agent-sessions.external.<adapter>]`.

Rationale: default behavior should include configured extension points without requiring a separate reindex command. The config switch gives users an escape hatch.

### Decision: Built-in adapters remain per-agent configurable

Existing `[agent-sessions.agents.<agent>] enabled = false` disables the built-in adapter for that agent. This lets a user replace a bundled adapter with an external one for the same ecosystem.

Rationale: community adapters can improve source handling without requiring core changes or a new release.

### Decision: External adapters register their own agent names

An adapter declared by plugin command `omp` uses `omp` as its default Agent Sessions agent name. Adapter output may override the agent per row for multi-agent adapters, but OpenMUX does not require the name to exist in core.

Rationale: OpenMUX can ship built-in defaults for common agents without treating that built-in list as the complete extension universe.

## Risks / Trade-offs

- **Risk: dynamic agent names need careful filtering and display behavior.** Mitigation: keep the stored value as the source of truth and sort dynamic names after built-in names in the sidebar filter.
- **Risk: external plugin callbacks can be slow or fail.** Mitigation: failures become reindex warnings and do not block other adapters.
- **Risk: plugin callback execution needs clear trust boundaries.** Mitigation: adapters are explicitly installed local plugins, same trust posture as hooks/plugins.
- **Risk: field contract may need richer mapping later.** Mitigation: stdout JSON is already extensible with optional fields.
