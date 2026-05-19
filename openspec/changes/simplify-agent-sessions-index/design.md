## Context

Agent Sessions is unreleased and currently has implementation complexity that is not needed for the intended product behavior. The current store persists sessions, transcript turns, resume snapshots, deleted-session tombstones, import/source state, and adapter-specific source metadata. This makes simple operations like listing Copilot sessions harder to reason about and creates room for timestamp drift, over-eager UI refreshes, and brittle source deletion behavior.

The desired model is a local normalized index: adapters read each agent's own history format, normalize rows into OpenMUX, and the UI/CLI query those normalized rows. The database is not the source of truth for agent history and does not need to preserve pre-release schemas.

## Goals / Non-Goals

**Goals:**

- Use one adapter per agent as the boundary for reading/syncing agent session history.
- Store Agent Sessions in one normalized SQLite table.
- Keep resume behavior adapter/config driven rather than snapshot driven.
- Treat delete as a local hide flag (`deleted = true`) that is preserved across reindex.
- Use cwd/root-prefix queries to derive workspace membership at read time.
- Keep active/progress status as runtime UI state associated with panes.
- Avoid UI flicker by refreshing rows only after background index/search work produces changed result data.

**Non-Goals:**

- No migration from prior pre-release `vault_*` tables.
- No attempt to delete real upstream agent sessions.
- No persisted transcripts or transcript previews in the Agent Sessions index.
- No persisted active-session state.
- No changes to terminal input, keyboard handling, or the libghostty bridge.

## Decisions

### Decision: Replace multi-table persistence with one normalized table

Use a single `agent_sessions` table:

```text
id          TEXT PRIMARY KEY -- OpenMUX id, e.g. "copilot:<raw_id>"
raw_id      TEXT NOT NULL
agent       TEXT NOT NULL
source_kind TEXT NOT NULL
source_path TEXT
cwd         TEXT
title       TEXT NOT NULL
updated_at_ms INTEGER NOT NULL
deleted     INTEGER NOT NULL DEFAULT 0
indexed_at_ms INTEGER NOT NULL
```

Rationale: the sidebar, palette, CLI list/search, workspace filtering, resume, and delete/hide flows only need these facts. Resume snapshots and message tables duplicate adapter knowledge.

Alternative considered: keep current tables but ignore unused ones. Rejected because unreleased features should not preserve accidental complexity.

### Decision: Preserve local deletion as a row flag during sync

Adapters may re-discover hidden sessions. Reindex MUST upsert current metadata while preserving `deleted = true` for existing hidden rows.

Rationale: users can hide rows from OpenMUX without risking upstream data loss, and reindex remains idempotent.

Alternative considered: tombstone table. Rejected because a boolean on the normalized row is simpler and sufficient.

### Decision: Adapter-owned resume behavior

Resume uses the normalized row's `agent` and `raw_id` plus config/templates. The store does not persist resume snapshots.

Rationale: each adapter knows the agent's resume semantics; persisting snapshots introduces drift and stale commands.

Alternative considered: keep `vault_resume_snapshots`. Rejected because it duplicates data and is not needed for unreleased behavior.

### Decision: Workspace membership is query-time cwd prefix matching

The app derives a workspace root from pane cwd values and workspace root path, then queries sessions where `cwd = root OR cwd LIKE root || '/%'`.

Rationale: a session belongs to a workspace because its cwd is within that workspace root. Persisting workspace/session relationships would become stale.

Alternative considered: store workspace IDs on session rows. Rejected because workspaces are user/app state while agent sessions are external history.

### Decision: Runtime active status stays out of the DB

When OpenMUX opens/resumes an Agent Session, the UI tracks `paneID -> sessionID`. Existing pane progress/status update flows provide the orb state for active rows.

Rationale: active status changes frequently, is derived from terminal runtime state, and should not cause Agent Sessions DB writes.

Alternative considered: persist active rows in DB. Rejected because it would be stale after app restart/pane close.

### Decision: Copilot indexing reads `sessions` directly

The Copilot adapter reads `id`, `cwd`, `summary`, and `updated_at` from `~/.copilot/session-store.db`, sorted by `updated_at`. It does not join `turns` for normal session summary indexing.

Rationale: Copilot's `sessions` table already contains exactly the summary rows the sidebar needs.

Alternative considered: combine session and turn timestamps. Rejected because it produced confusing ordering and is unnecessary for listing.

## Risks / Trade-offs

- **Risk: Removing transcript persistence removes preview data.** → Mitigation: keep transcript preview out of this change; if needed later, add an adapter-specific preview capability with explicit requirements.
- **Risk: Resetting schema loses pre-release local hidden/imported data.** → Mitigation: acceptable because the feature has not shipped and no compatibility is required.
- **Risk: cwd prefix matching can include nested projects.** → Mitigation: normalize paths and use project-like/common roots derived from workspace panes; this matches the intended workspace scope.
- **Risk: Some adapters may not have reliable cwd values.** → Mitigation: adapters should leave cwd nil when unknown; workspace-scoped queries naturally exclude unknown cwd rows while all-workspace views can still show them.
