## ADDED Requirements

### Requirement: User hook directories SHALL register executable handlers by hook name
OpenMUX SHALL discover user hook handlers from direct child directories under `~/.omux/hooks/`, where each child directory name is a hook name and each executable regular file inside that directory is a handler for that hook.

#### Scenario: Executable handler is registered for matching hook
- **WHEN** `~/.omux/hooks/terminal-command-finished/10-notify` exists as an executable regular file
- **THEN** OpenMUX registers it as a handler for the `terminal-command-finished` hook

#### Scenario: Missing hooks directory is inert
- **WHEN** `~/.omux/hooks/` does not exist
- **THEN** OpenMUX starts with no user hook handlers and does not report a fatal error

### Requirement: Hook handlers SHALL be language-neutral executables
OpenMUX SHALL execute discovered hook handlers as executable files rather than interpreting them as a specific scripting language.

#### Scenario: Shell script handler uses its shebang
- **WHEN** an executable hook handler starts with `#!/usr/bin/env bash`
- **THEN** OpenMUX launches the handler directly and lets the operating system resolve the script runtime

#### Scenario: Deno TypeScript handler uses its shebang
- **WHEN** an executable hook handler starts with `#!/usr/bin/env -S deno run`
- **THEN** OpenMUX launches the handler directly without embedding Deno or treating TypeScript as a required hook format

### Requirement: Hook discovery SHALL ignore inactive entries
OpenMUX SHALL ignore hidden entries, non-executable files, and subdirectories inside hook-name directories during user hook discovery.

#### Scenario: Non-executable note is ignored
- **WHEN** `~/.omux/hooks/terminal-command-finished/README.md` exists without executable permissions
- **THEN** OpenMUX does not register it as a hook handler

#### Scenario: Hidden file is ignored
- **WHEN** `~/.omux/hooks/terminal-command-finished/.disabled` exists and is executable
- **THEN** OpenMUX does not register it as a hook handler

### Requirement: Multiple handlers for one hook SHALL run deterministically
OpenMUX SHALL run all registered handlers for a matching hook in lexicographic filename order within that hook's user directory.

#### Scenario: Numeric prefixes control order
- **WHEN** `~/.omux/hooks/terminal-command-finished/10-log` and `~/.omux/hooks/terminal-command-finished/20-notify` are both executable
- **THEN** OpenMUX runs `10-log` before `20-notify` for a `terminal-command-finished` invocation

### Requirement: User hook handlers SHALL receive structured invocation JSON
OpenMUX SHALL pass the full OpenMUX-native hook invocation to each user hook handler as JSON on stdin.

#### Scenario: Command-finished handler receives exit metadata
- **WHEN** OpenMUX invokes `terminal-command-finished` for a completed terminal command with exit code `1`
- **THEN** the handler stdin includes JSON with `name` set to `terminal-command-finished`, `category` set to `command`, the relevant workspace/tab/pane/session identifiers when available, and `payload.exitCode` set to `1`

### Requirement: User hook failures SHALL NOT stop later matching handlers
OpenMUX SHALL isolate user hook handler failures so one failing handler does not prevent later matching handlers from running and does not fail the underlying OpenMUX action.

#### Scenario: Failed first handler does not block second handler
- **WHEN** two executable handlers are registered for `terminal-command-finished` and the first handler exits non-zero
- **THEN** OpenMUX still runs the second handler for the same invocation and reports the first handler failure as a diagnostic warning
