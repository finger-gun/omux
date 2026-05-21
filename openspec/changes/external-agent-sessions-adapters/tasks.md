## 1. OpenSpec Artifacts

- [x] 1.1 Create proposal, design, tasks, and Agent Sessions spec delta.

## 2. Configuration

- [x] 2.1 Add `external_adapters_enabled` to Agent Sessions config with default `true`.
- [x] 2.2 Parse `[agent-sessions.external.<adapter>]` tables with enable/disable and resume override settings.
- [x] 2.3 Preserve per-built-in adapter enable/disable behavior through `[agent-sessions.agents.<agent>] enabled`.

## 3. External Adapter Runtime

- [x] 3.1 Discover Agent Sessions adapter capabilities from installed plugin manifests.
- [x] 3.2 Add a process-based external adapter implementation that invokes plugin callbacks.
- [x] 3.3 Decode normalized JSON rows from stdout into `VaultIndexedSession` values.
- [x] 3.4 Run built-in and plugin-declared external adapters during default reindex.
- [x] 3.5 Treat external adapter failures as reindex warnings while continuing other adapters.

## 4. Docs and Tests

- [x] 4.1 Add config tests for external adapter registration and disable switches.
- [x] 4.2 Add vault tests for external adapter indexing and disable behavior.
- [x] 4.3 Document external adapter config and JSON contract.
- [x] 4.4 Run targeted config/vault tests and `make verify` if feasible.
