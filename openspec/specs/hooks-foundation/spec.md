# hooks-foundation Specification

## Purpose
TBD - created by archiving change macos-foundation. Update Purpose after archive.
## Requirements
### Requirement: The foundation defines stable hook categories
The system SHALL define initial hook categories for lifecycle, session, command, UI, and input events.

#### Scenario: Extension points are named and intentional
- **WHEN** a future feature or plugin needs to react to application behavior
- **THEN** it can target a documented hook category instead of relying on incidental internal coupling

### Requirement: Hooks are contracts, not implementation leaks
The system SHALL define hooks as stable behavioral contracts around OpenMUX concepts rather than exposing arbitrary internal objects or terminal-engine internals.

#### Scenario: Hook consumers depend on stable semantics
- **WHEN** a hook is invoked for external automation or future plugin behavior
- **THEN** the hook payload and lifecycle semantics are expressed in OpenMUX-native terms

### Requirement: External extensibility precedes embedded runtimes
The system SHALL support a foundation that is compatible with external hooks and plugin processes before introducing in-process scripting or WASM runtimes.

#### Scenario: Initial extensibility does not require embedded runtimes
- **WHEN** the foundation is implemented for first-phase automation
- **THEN** it can support external hook execution without requiring an embedded plugin engine inside the app process

### Requirement: Hook payloads support structured OpenMUX-native values
The hook foundation SHALL support structured payload values for hook invocations so terminal automation events can carry typed numbers, booleans, strings, arrays, objects, and nulls without flattening them to string-only metadata. Hook payload values SHALL be expressed in OpenMUX-native terms.

#### Scenario: Command-finished hook carries typed fields
- **WHEN** OpenMUX emits a hook for a terminal command-finished event
- **THEN** the hook payload can include typed fields such as numeric exit code and numeric duration without requiring string parsing by hook consumers

#### Scenario: Hook payload stays OpenMUX-native
- **WHEN** a hook consumer receives a payload derived from terminal action dispatch
- **THEN** the payload fields describe OpenMUX pane/session behavior rather than raw Ghostty action tags or Ghostty-owned structs

### Requirement: Command-failed hook is emitted for nonzero command completions
The hook foundation SHALL expose a `command-failed` command hook when OpenMUX observes a command completion with a nonzero exit code.

#### Scenario: Nonzero command completion invokes failure hook
- **WHEN** OpenMUX observes a terminal command completion with a nonzero exit code
- **THEN** it emits `command-failed` with the same OpenMUX terminal context as the command completion

#### Scenario: Successful command does not invoke failure hook
- **WHEN** OpenMUX observes a terminal command completion with exit code zero
- **THEN** it does not emit `command-failed`

### Requirement: Command hooks include automation context
Command-related hooks SHALL include OpenMUX-native identifiers and command metadata needed for hooks to call public automation APIs without guessing targets.

#### Scenario: Command-started includes target and command
- **WHEN** OpenMUX emits `command-started`
- **THEN** the hook invocation includes workspace ID, tab ID, pane ID, session ID, and command text when available

#### Scenario: Command-finished includes completion metadata
- **WHEN** OpenMUX emits `terminal-command-finished`
- **THEN** the hook payload includes exit code, duration, command text when available, cwd when available, and bounded output context or an explicit unavailable value

#### Scenario: Command-failed includes failure metadata
- **WHEN** OpenMUX emits `command-failed`
- **THEN** the hook payload includes exit code, duration, command text when available, cwd when available, and bounded output context or an explicit unavailable value

### Requirement: Hooks mutate OpenMUX only through public actions
Hook handlers SHALL use `omux` or the local JSON-RPC control plane to mutate OpenMUX state; hook stdout SHALL NOT be treated as an implicit OpenMUX command protocol.

#### Scenario: Hook writes analysis back to terminal through CLI
- **WHEN** a hook wants to display analysis in the originating terminal
- **THEN** it calls the public send-text action with the session or pane ID from the hook payload

#### Scenario: Hook stdout remains handler output
- **WHEN** a hook writes to stdout
- **THEN** OpenMUX does not interpret that stdout as a split, focus, run, or send-text instruction

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

### Requirement: Hook handlers can fetch bounded terminal history through public automation
Hook handlers SHALL be able to fetch bounded terminal history for relevant OpenMUX panes by invoking the public `omux history` CLI or equivalent local control-plane operation with identifiers from hook invocation payloads.

#### Scenario: Command hook fetches originating pane history
- **WHEN** a command-related hook receives a pane ID in its invocation payload
- **THEN** the hook handler can call `omux history <pane-id>` to fetch bounded history for that pane without depending on private app internals

#### Scenario: Hook script fetches structured history
- **WHEN** a hook handler needs machine-readable pane history
- **THEN** it can request JSON output from the public history command or control-plane operation

### Requirement: Hook invocations do not automatically include full scrollback
OpenMUX SHALL NOT attach full pane scrollback/history text to every hook invocation payload by default. Hook payloads SHALL continue to provide OpenMUX-native identifiers and bounded event context so handlers can opt in to explicit history reads.

#### Scenario: Hook payload stays lightweight
- **WHEN** OpenMUX invokes a hook for terminal activity
- **THEN** the payload includes target identifiers but does not automatically include full terminal scrollback

#### Scenario: Handler opts in to history access
- **WHEN** a hook handler needs additional output context beyond the invocation payload
- **THEN** it explicitly calls the public history surface for the target pane or workspace

### Requirement: Input-sent hook SHALL expose forwarded terminal input context
The hook foundation SHALL expose a `terminal-input-sent` input hook when OpenMUX successfully delivers explicit action-scoped terminal input to a live runtime surface.

#### Scenario: Input-sent hook receives context
- **WHEN** OpenMUX emits `terminal-input-sent`
- **THEN** the hook invocation includes category `input`, relevant workspace ID, tab ID, pane ID, session ID, and a payload containing `text`, `key`, `keyCode`, `modifiers`, `route`, and `source`

#### Scenario: Input-sent hook remains OpenMUX-native
- **WHEN** a hook handler receives `terminal-input-sent`
- **THEN** its payload describes OpenMUX terminal input context rather than raw terminal-engine structs or AppKit event objects

### Requirement: Input-sent hooks SHALL remain observational
The `terminal-input-sent` hook SHALL run through the existing external hook execution model and SHALL NOT block, approve, reject, or rewrite the input that triggered it.

#### Scenario: Hook failure does not cancel input
- **WHEN** a `terminal-input-sent` hook handler exits nonzero after input has been forwarded
- **THEN** OpenMUX reports the handler failure consistently with other hook failures and does not undo or cancel the terminal input

#### Scenario: Hook mutates through public automation
- **WHEN** a `terminal-input-sent` hook wants to react by focusing panes, sending text, fetching history, or notifying the user
- **THEN** it uses public `omux` commands or the local JSON-RPC control plane rather than hook stdout as an implicit command protocol

