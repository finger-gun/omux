## Why

Agent Sessions currently behaves like a mixed restoration/indexing subsystem: adapters collect source data, OpenMUX stores extra resume snapshots and transcript tables, and delete behavior attempts to modify upstream agent storage. This makes Copilot indexing fragile, increases UI flicker risk, and obscures the simple user problem: show local agent sessions quickly, let users resume them, and hide deleted rows safely.

This change matters now because Agent Sessions is unreleased and can still be simplified before becoming a public contract.

Because this feature has not shipped, the implementation can remove legacy Agent Sessions/Vault persistence structures without migration or backward compatibility shims.

## Goals

- Make Agent Sessions a lightweight normalized local index.
- Keep one adapter per agent, with each adapter responsible for syncing its source into OpenMUX-native rows and computing resume behavior.
- Keep sidebar and workspace filtering fast, cwd-derived, and background-friendly.
- Treat active/session-progress indicators as runtime UI state derived from panes, not database synchronization state.
- Prefer safe local deletion semantics by marking rows deleted in OpenMUX rather than deleting upstream agent history.

## Non-goals

- Do not add a browser-heavy or AI-first workflow.
- Do not add an always-running external service.
- Do not delete real upstream Copilot, Codex, Gemini, Claude, or other agent history.
- Do not persist active pane/session status in the Agent Sessions index.
- Do not change terminal input, keyboard handling, or the libghostty bridge boundary.

## What Changes

- Replace the current multi-table Agent Sessions persistence model with one normalized session index table containing the agent session facts OpenMUX needs: id, agent, source kind/path, cwd, title/summary, updated timestamp, and deleted flag.
- Reset the pre-release Agent Sessions SQLite schema without preserving old `vault_*` tables, resume snapshots, transcript tables, or source-state bookkeeping.
- Remove the need for persisted resume snapshot rows; adapters compute resume commands from normalized rows and configuration when needed.
- Change delete behavior to mark the OpenMUX row as deleted, preserving that flag across future reindex operations.
- Update listing/search/sidebar queries to use `deleted = false`, cwd root/prefix matching, and configurable row limits.
- Keep adapter sync work in the background and only notify the UI when indexed result data actually changes.
- Keep active Agent Sessions indicators as runtime UI state associated with panes and terminal progress/status updates.
- Simplify the Copilot adapter to read the `sessions` table directly, while Codex, Gemini, Claude, and other adapters continue normalizing their own file, SQLite, or CLI sources.

## Capabilities

### New Capabilities

- `agent-sessions-index`: Normalized local Agent Sessions indexing, adapter-owned sync/resume behavior, cwd-derived workspace filtering, local delete/hide semantics, and runtime active-session display.

### Modified Capabilities

<!-- None. Agent Sessions is not yet represented as an existing main spec. -->

## Impact

- Affected code:
  - `Sources/OmuxVault`: database schema, store queries, adapter contracts, delete semantics, resume lookup.
  - `Sources/OmuxAppShell`: Agent Sessions sidebar loading, workspace filtering, refresh behavior, active row status/focus behavior.
  - `Sources/OmuxCLI` and `Sources/OmuxAppShell/OpenMUXControlPlaneService.swift`: Agent Sessions list/search/resume/delete/import/export behavior where currently tied to resume snapshots or transcript tables.
  - `Sources/OmuxConfig`: existing Agent Sessions config remains, including row-limit settings.
  - `docs/agent-sessions.md` and `docs/configuration.md`: document the simpler index model and delete semantics.
  - `Tests/OmuxVaultTests`, `Tests/OmuxAppShellTests`, and related CLI/control-plane tests.
- No impact on keyboard/input correctness.
- No impact on plugin APIs except preserving current Agent Sessions config shape and documented commands.
- No impact on the libghostty bridge boundary.
