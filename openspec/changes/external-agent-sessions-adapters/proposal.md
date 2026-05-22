## Why

Agent Sessions can index several built-in coding agents, but adding a new agent still requires editing core code even when the agent stores sessions in a format OpenMUX can already normalize. Users should be able to add or replace Agent Sessions adapters without waiting for a new OpenMUX release.

This matters now because OpenMUX already has the right external-process shape through plugins, hooks, CLI, and the local control plane. The missing piece is a small Agent Sessions adapter contract that lets external code normalize agent-owned data into OpenMUX's existing index.

## Goals

- Allow external adapters to contribute normalized Agent Sessions rows.
- Allow external adapters to use arbitrary agent names, including names not built into OpenMUX.
- Reindex built-in and external adapters by default.
- Let users enable or disable built-in adapters per agent.
- Let users enable or disable external adapters globally and per adapter.
- Keep OpenMUX core responsible for the index, search, delete/hide semantics, sidebar, and resume flow.
- Keep external adapter output as plain structured data rather than giving plugins database access.

## Non-goals

- Do not add an embedded plugin runtime.
- Do not let external adapters mutate the Agent Sessions schema directly.
- Do not change terminal input, keyboard handling, or the terminal bridge.
- Do not make Agent Sessions AI-first or vendor-first.
- Do not require all built-in adapters to move out of core in this change.

## What Changes

- Add manifest-declared Agent Sessions adapter capability for installed plugins.
- Add `external_adapters_enabled`, defaulting to `true`.
- Preserve existing `[agent-sessions.agents.<agent>] enabled = false` behavior as the per-built-in adapter off switch.
- Add an external adapter runner that invokes plugin-declared callbacks during reindex and reads normalized JSON rows from stdout.
- Store external adapter rows in the same normalized `agent_sessions` table.
- Treat external adapter indexing as part of normal reindex by default, with config available to disable it.
- Document the external adapter JSON contract and the replacement workflow for users who want a community adapter for a built-in agent.

## Capabilities

### Modified Capabilities

- `agent-sessions-index`: add external adapter discovery, normalized row ingestion, default built-in plus external reindexing, and adapter enablement controls.

## Impact

- `Sources/OmuxConfig`: parse Agent Sessions external adapter enable/disable overrides.
- `Sources/OmuxVault`: discover plugin-declared adapter capabilities, invoke plugin callbacks, and normalize stdout into indexed rows.
- `Sources/OmuxCLI` and control-plane behavior: keep `agent-sessions reindex` as the default entry point for built-in and external adapters.
- `docs/agent-sessions.md` and `docs/configuration.md`: document the adapter contract and config.
- Tests: config parsing, external adapter indexing, disabling external adapters, and disabling built-in adapters while using an external replacement.
