## Why

OpenMUX already emits structured hook invocations internally, but users cannot yet drop scripts into `~/.omux/hooks/` and have them run. This leaves a gap between the manifesto's promise of a hackable terminal workspace and the current implementation, especially for common terminal-first automations such as reacting to command completion, workspace opening, pane focus, or terminal notifications.

## Goals

- Make hooks directly usable by end users through a small filesystem convention.
- Preserve hooks as language-neutral executable contracts: Bash, Python, Deno TypeScript, compiled binaries, and other executable formats can all participate through shebangs or native executables.
- Keep hook execution out-of-process and OpenMUX-native, using structured JSON payloads rather than internal Swift, AppKit, or libghostty objects.
- Provide deterministic multi-hook behavior so users can compose several scripts for the same event without a plugin framework.

## Non-goals

- Do not introduce an embedded scripting runtime, browser-based plugin surface, or long-running plugin host in this change.
- Do not make Deno, TypeScript, Node, Bash, or any other language the required hook format.
- Do not expose libghostty types, AppKit view objects, or mutable workspace internals to hook scripts.
- Do not make hooks a command-input bus; hooks may call `omux` or the local control plane explicitly if they want to perform actions.

## What Changes

- Add a user-facing hook discovery convention under `~/.omux/hooks/<hook-name>/`.
- Treat each executable regular file inside a hook-name directory as one hook handler for that event.
- Run multiple hook handlers for the same event in deterministic lexicographic filename order.
- Pass the existing structured `HookInvocation` payload as JSON on stdin to every hook executable.
- Ignore non-executable files, hidden entries, and subdirectories so users can keep notes or disabled scripts near active hooks.
- Surface hook execution failures without preventing later matching hooks from running.
- Document that hook scripts choose their own runtime through executable metadata such as shebangs.
- Preserve the existing internal `HookRegistry` and `ExternalHookRunner` model while adding filesystem discovery and app startup registration.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `hooks-foundation`: Extend the hook foundation from code-level registered descriptors to user-facing filesystem hook directories with deterministic executable discovery and JSON invocation semantics.

## Impact

- `OmuxHooks`: add discovery logic for `~/.omux/hooks/<hook-name>/`, descriptor creation, filtering, and deterministic ordering.
- `OmuxAppShell`: initialize `ExternalHookRunner` with descriptors discovered from the user hook directory.
- `OmuxConfig` or shared path helpers: expose the OpenMUX hooks directory path consistently with existing `~/.omux` paths if appropriate.
- Tests: cover hook discovery, executable filtering, ordering, JSON payload delivery, and failure isolation.
- Documentation: explain hook directory layout, executable/shebang expectations, stdin JSON payloads, and examples for shell and Deno TypeScript.
- Keyboard/input correctness: no direct change to key handling; input-related hooks must continue to receive OpenMUX-native normalized values rather than raw AppKit or terminal-engine internals.
- Plugin APIs: this strengthens the external-hooks layer that later plugin/process work can build on without committing OpenMUX to a single runtime.
- libghostty bridge boundary: no change; terminal-engine upcalls remain translated into OpenMUX-native hook names and payload values before hooks see them.
