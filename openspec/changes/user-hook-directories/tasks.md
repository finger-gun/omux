## 1. Hook Discovery

- [x] 1.1 Add a shared OpenMUX hooks root path for `~/.omux/hooks/` consistent with existing user config/theme path conventions.
- [x] 1.2 Implement filesystem discovery that treats each direct child directory under the hooks root as a hook name.
- [x] 1.3 Filter discovered handlers to executable regular files only, ignoring hidden entries, non-executable files, and subdirectories.
- [x] 1.4 Register discovered handlers in deterministic lexicographic filename order for each hook-name directory.

## 2. Hook Execution Semantics

- [x] 2.1 Preserve direct executable launch semantics so hook files choose their runtime through shebangs or native executable format.
- [x] 2.2 Ensure each user hook handler receives the structured `HookInvocation` JSON on stdin.
- [x] 2.3 Update hook execution to isolate user hook failures so later matching handlers still run after launch errors or non-zero exits.
- [x] 2.4 Emit concise diagnostics for user hook failures without failing the underlying OpenMUX action.

## 3. App Integration

- [x] 3.1 Initialize the production `ExternalHookRunner` with descriptors discovered from the user hooks directory.
- [x] 3.2 Keep startup inert when `~/.omux/hooks/` is missing or contains no executable handlers.
- [x] 3.3 Preserve existing programmatic hook registration behavior for tests and future plugin/process integrations.

## 4. Tests and Documentation

- [x] 4.1 Add `OmuxHooks` tests for directory discovery, executable filtering, hidden-file filtering, and lexicographic ordering.
- [x] 4.2 Add hook runner tests proving a failing handler does not block later matching handlers.
- [x] 4.3 Add app-shell integration coverage showing discovered user hooks can receive a real OpenMUX hook invocation.
- [x] 4.4 Document `~/.omux/hooks/<hook-name>/` layout, executable/shebang expectations, JSON stdin payload shape, ordering, and shell/Deno examples.
- [x] 4.5 Run OpenSpec validation and the relevant Swift test targets.
