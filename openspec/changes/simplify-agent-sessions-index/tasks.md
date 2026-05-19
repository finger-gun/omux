## 1. Data Model

- [x] 1.1 Replace Agent Sessions SQLite schema with a single normalized `agent_sessions` table for unreleased pre-release behavior.
- [x] 1.2 Update store decoding/encoding to map normalized rows to existing public model types or a slimmer internal row type.
- [x] 1.3 Remove persisted resume snapshot, transcript/message, source-state, and tombstone table dependencies from Agent Sessions store paths.

## 2. Adapter Sync and Resume

- [x] 2.1 Update adapter output to provide normalized row data plus enough information to compute resume commands from agent/raw id.
- [x] 2.2 Keep Copilot sync as a direct `sessions` table read using id, cwd, summary, and updated_at.
- [x] 2.3 Keep Codex, Gemini, Claude, and other adapters responsible for normalizing their own file/SQLite source data.
- [x] 2.4 Compute resume commands on demand from the normalized row and current config instead of persisted resume snapshots.

## 3. Query, Delete, and UI Integration

- [x] 3.1 Update list/search/sidebar queries to filter `deleted = false` and support cwd root/prefix workspace filtering.
- [x] 3.2 Change delete to mark local rows deleted without deleting upstream agent data.
- [x] 3.3 Preserve `deleted = true` during reindex while allowing metadata updates.
- [x] 3.4 Keep active/focus/status behavior as runtime pane-associated UI state.
- [x] 3.5 Preserve stable sidebar rendering and scroll position when refresh results are unchanged.

## 4. Docs and Validation

- [x] 4.1 Update public Agent Sessions documentation and configuration docs for the simplified index/delete/resume model.
- [x] 4.2 Update unit tests for normalized schema, Copilot sync, delete flag preservation, workspace-prefix queries, and resume command computation.
- [x] 4.3 Run targeted Agent Sessions tests and `make verify`.
