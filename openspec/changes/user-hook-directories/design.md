## Context

OpenMUX already has an `OmuxHooks` module with `HookInvocation`, `HookDescriptor`, `HookRegistry`, and `ExternalHookRunner`, and the app shell emits hook invocations from workspace/session actions and terminal action dispatch. The missing piece is user-facing discovery: the production app currently creates `ExternalHookRunner()` with an empty registry, so users cannot place scripts under `~/.omux/hooks/` and have OpenMUX run them.

This change turns the internal hook foundation into a small, inspectable filesystem contract while keeping hooks out-of-process, language-neutral, and separate from the future long-running plugin model.

## Goals / Non-Goals

**Goals:**

- Discover user hook handlers from `~/.omux/hooks/<hook-name>/`.
- Allow any executable format supported by macOS process launch, including shell scripts, Python, Deno TypeScript with a shebang, and compiled binaries.
- Run all executable hook handlers for a matching hook in deterministic lexicographic filename order.
- Pass the existing structured hook invocation as JSON on stdin.
- Keep hook failures isolated so one broken script does not prevent later scripts for the same event from running.
- Integrate discovery at app startup without adding a background service or embedded runtime.

**Non-Goals:**

- No long-running plugin supervisor, plugin manifest, marketplace, or SDK.
- No embedded Deno, Node, Lua, browser, or WASM runtime.
- No hook output protocol beyond process success/failure and diagnostic logging.
- No raw access to AppKit, Swift model objects, or libghostty data structures.
- No keyboard/input remapping feature; input hooks remain consumers of OpenMUX-native hook payloads.

## Decisions

### Directory-per-hook discovery

OpenMUX will treat each direct child directory of the hooks root as a hook name:

```text
~/.omux/hooks/
  terminal-command-finished/
    10-log-duration
    20-notify-on-failure
  workspace-opened/
    10-bootstrap-layout
```

This is preferable to one executable per hook name because it lets users compose small scripts without inventing a config file, chaining wrapper, or plugin runtime. The flat hook-name layout is also easier to explain than category folders; existing hook names already carry enough domain context, such as `terminal-command-finished`, `workspace-opened`, and `pane-tab-created`.

### Executable files are the hook format

The hook runner will execute discovered regular files directly. OpenMUX will not interpret the file as Bash, TypeScript, or any other language. Scripts choose their own runtime through executable metadata, typically a shebang:

```text
#!/usr/bin/env bash
#!/usr/bin/env python3
#!/usr/bin/env -S deno run --allow-run=osascript
```

This keeps the hook contract language-neutral and preserves Deno as an ergonomic option rather than a core dependency.

### Filtering and ordering

Discovery will include only regular files that are executable by the current user and whose filenames are not hidden. It will ignore hidden entries, non-executable files, and subdirectories. Matching hook descriptors will be registered in lexicographic filename order within each hook-name directory.

This gives users a simple ordering convention:

```text
10-log
20-notify
90-cleanup
```

### Failure isolation

Today `ExternalHookRunner.emit` throws if a launch fails, which makes sense for tests and registered descriptors but is too brittle for user hook directories. User-facing hook execution should continue through later descriptors even when one descriptor fails to launch, exits non-zero, or otherwise reports an execution error. The app should surface warnings through existing stderr/logging patterns and future `doctor` output, but hook failures must not break the underlying OpenMUX action.

The implementation can achieve this either by making `ExternalHookRunner` collect per-hook outcomes or by adding a user-facing runner mode that logs and continues. The important contract is isolation, not a specific type shape.

### Payload contract

Each hook receives the JSON-encoded `HookInvocation` on stdin. The public shape should remain OpenMUX-native:

```json
{
  "category": "command",
  "name": "terminal-command-finished",
  "workspaceID": "workspace-...",
  "tabID": "tab-...",
  "paneID": "pane-...",
  "sessionID": "session-...",
  "payload": {
    "exitCode": 1,
    "durationNanoseconds": 1230000000
  },
  "occurredAt": "2026-05-02T00:50:00Z"
}
```

The JSON payload is the source of truth. Environment variables may be added later for convenience, but this change should not depend on them.

### App startup integration

`OpenMUXAppDelegate` should initialize the hook runner with descriptors discovered from the user hook directory. If the hooks root does not exist, startup should proceed with an empty registry. Discovery errors should be diagnostic warnings, not fatal launch failures.

Path ownership should follow the existing `~/.omux` convention used by config, themes, and generated artifacts. If path helpers already belong in `OmuxConfig`, hooks should reuse or extend that path model rather than hardcoding the home directory in app shell code.

## Risks / Trade-offs

- **Hook scripts can be slow** -> Keep the first implementation simple, but structure the runner so timeouts or asynchronous execution can be added without changing the filesystem contract.
- **Users may expect stdout to mutate OpenMUX** -> Document that hooks are side-effect executables; they must call `omux` or JSON-RPC explicitly for actions.
- **Non-zero exits could become noisy** -> Log concise warnings and preserve enough detail for a future `omux hooks doctor`.
- **Lexicographic ordering can surprise users without examples** -> Document numeric prefixes such as `10-`, `20-`, and `90-`.
- **Hook discovery broadens the local execution surface** -> Only execute files the user has made executable, never auto-run non-executable notes/config, and keep all payloads OpenMUX-native.

## Migration Plan

No migration is required. Existing internal hook registrations and tests continue to work. Users who have no `~/.omux/hooks/` directory see no behavior change.

## Open Questions

- Should the first implementation add a default timeout, or defer timeout behavior until hook execution telemetry exists?
- Should `omux config doctor` include hook diagnostics immediately, or should a dedicated `omux hooks doctor` come with a later plugin-management change?
