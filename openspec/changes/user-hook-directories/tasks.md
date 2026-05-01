## 1. Hook Discovery

- [ ] 1.1 Add a shared OpenMUX hooks root path for `~/.omux/hooks/` consistent with existing user config/theme path conventions.
- [ ] 1.2 Implement filesystem discovery that treats each direct child directory under the hooks root as a hook name.
- [ ] 1.3 Filter discovered handlers to executable regular files only, ignoring hidden entries, non-executable files, and subdirectories.
- [ ] 1.4 Register discovered handlers in deterministic lexicographic filename order for each hook-name directory.

## 2. Hook Execution Semantics

- [ ] 2.1 Preserve direct executable launch semantics so hook files choose their runtime through shebangs or native executable format.
- [ ] 2.2 Ensure each user hook handler receives the structured `HookInvocation` JSON on stdin.
- [ ] 2.3 Update hook execution to isolate user hook failures so later matching handlers still run after launch errors or non-zero exits.
- [ ] 2.4 Emit concise diagnostics for user hook failures without failing the underlying OpenMUX action.

## 3. App Integration

- [ ] 3.1 Initialize the production `ExternalHookRunner` with descriptors discovered from the user hooks directory.
- [ ] 3.2 Keep startup inert when `~/.omux/hooks/` is missing or contains no executable handlers.
- [ ] 3.3 Preserve existing programmatic hook registration behavior for tests and future plugin/process integrations.

## 4. Tests and Documentation

- [ ] 4.1 Add `OmuxHooks` tests for directory discovery, executable filtering, hidden-file filtering, and lexicographic ordering.
- [ ] 4.2 Add hook runner tests proving a failing handler does not block later matching handlers.
- [ ] 4.3 Add app-shell integration coverage showing discovered user hooks can receive a real OpenMUX hook invocation.
- [ ] 4.4 Document `~/.omux/hooks/<hook-name>/` layout, executable/shebang expectations, JSON stdin payload shape, ordering, and shell/Deno examples.
- [ ] 4.5 Run OpenSpec validation and the relevant Swift test targets.
