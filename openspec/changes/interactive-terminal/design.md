## Context

OpenMUX currently renders pane-shaped terminal views, but the session model is still transcript-driven: panes append strings, `Run Command` opens a modal, and each command executes as a one-off subprocess. That leaves the UI structurally close to a terminal workspace while missing the core behavior that makes the product usable.

This change crosses `OmuxTerminalBridge`, `OmuxAppShell`, `OmuxCore`, `OmuxControlPlane`, and `OmuxCLI`, so it benefits from a design pass before coding. The most important constraints are:

- preserve the bridge seam so terminal lifecycle and upstream engine details stay in `OmuxTerminalBridge`
- keep keyboard correctness as a blocker-level concern
- move closer to libghostty-backed behavior without spreading raw engine concepts into the app shell
- deliver a coherent vertical slice now, not a large polished shell around fake interaction

## Goals / Non-Goals

**Goals:**
- Introduce persistent pane-owned interactive shell sessions instead of one-off command launches.
- Make focused terminal panes accept direct input, enter, backspace, paste, resize, and focus transitions without modal command entry.
- Route pane input through the normalized input pipeline and translate normalized events into session input inside the bridge.
- Keep `omux` and the JSON-RPC control plane pointed at the same live sessions used by the native shell.
- Provide a bridge-owned fallback interactive runtime that works now while keeping the door open for deeper libghostty integration later.

**Non-Goals:**
- Full `docs/vision.png` shell chrome such as sidebar navigation, event timeline, or command palette.
- A complete terminal emulator feature set with alternate screen apps, mouse reporting, or full ANSI/VT coverage.
- Browser-based UI, new background services, or privileged AI integrations.
- Replacing the long-term libghostty direction; this is a usable interactive slice, not an architectural pivot away from it.

## Decisions

### 1. Add a bridge-owned interactive session runtime backed by a PTY

The bridge will own persistent pane session lifecycle through a small runtime object that:

- opens a PTY pair
- spawns the configured shell in interactive mode
- reads output asynchronously from the PTY master
- writes user input bytes back to that PTY
- tears the session down when the pane is closed

**Why this approach:** it gives us real ongoing shell sessions with history, prompts, and session continuity today, while still fitting the manifesto’s “terminal first” requirement.

**Alternatives considered:**
- **Keep one-off `Process` calls**: rejected because it does not create a usable terminal interaction model.
- **Wait for full libghostty rendering first**: rejected because the repo needs a working vertical slice sooner; UX work on top of fake terminal behavior would compound the wrong abstraction.
- **Move PTY/session logic into the app shell**: rejected because it breaks the bridge boundary and couples UI code to terminal runtime details.

### 2. Keep rendering simple, but make state terminal-shaped instead of transcript-shaped

The first interactive slice will keep AppKit text-based pane rendering, but the bridge will stop publishing only “transcript + currentInput.” Instead it will maintain a lightweight terminal screen model that can absorb common shell output behavior:

- printable text
- carriage return
- newline
- backspace/delete
- a small subset of ANSI control sequences needed for prompts and line refresh

**Why this approach:** it makes direct typing and prompt redraws usable without pretending this is already a complete emulator.

**Alternatives considered:**
- **Raw PTY bytes straight into `NSTextView`**: rejected because shell redraws and ANSI output would look broken immediately.
- **Build a full emulator in this change**: rejected as too large and too far from the repo’s current stage.

### 3. Move command execution onto live sessions, not around them

`runCommand` will stay as a public action, but it will inject text into the live session as if typed, followed by return, instead of launching a separate shell command path. The UI’s primary flow becomes direct pane input; the command modal is removed.

**Why this approach:** it keeps UI and automation aligned on one session model.

**Alternatives considered:**
- **Keep modal command entry as a parallel path**: rejected because it preserves the wrong UX center of gravity.
- **Remove `runCommand` entirely**: rejected because the control plane should remain useful for automation and agents.

### 4. Translate normalized events to terminal input in the bridge

The app shell will continue producing normalized key events. The bridge becomes responsible for mapping them into bytes/control sequences for the PTY runtime:

- text input sends UTF-8 bytes
- return sends `\r`
- backspace sends DEL
- arrows/home/end send standard escape sequences
- composition-sensitive flows only send text once composition resolves
- shortcut-routed events remain outside terminal dispatch

**Why this approach:** it preserves one input model for UI, terminal, hooks, and future keymaps while keeping terminal-specific encoding in the bridge.

**Alternatives considered:**
- **Map `NSEvent` directly in `TerminalTextView`**: rejected because it bypasses the shared input pipeline and weakens international-layout guarantees.

### 5. Add explicit resize and focus hooks to live pane sessions

Pane views will notify the controller when size changes, and the controller will forward terminal resize events to the bridge. Focus changes stay in the workspace model and remain observable through hooks.

**Why this approach:** interactive shells and future rendering layers need actual size updates to behave predictably.

## Risks / Trade-offs

- **[Risk] The lightweight screen model will not cover full-screen TUIs or rich ANSI behavior yet** → **Mitigation:** scope the change around usable shell interaction, document the limitation, and keep the rendering logic isolated so a libghostty-backed surface can replace it later.
- **[Risk] PTY lifecycle bugs could leak processes or file descriptors** → **Mitigation:** make the bridge the sole owner of spawn/read/write/teardown, add teardown tests, and avoid duplicating lifecycle logic in the shell.
- **[Risk] Input regressions for EU/ISO layouts and composition paths** → **Mitigation:** preserve normalized input routing, add tests for right-Option, dead-key/composition, paste, and editing keys at the bridge/session layer.
- **[Risk] `NSTextView` still imposes UX rough edges compared with a real terminal surface** → **Mitigation:** keep the implementation minimal and use it as a stepping stone, not as the final rendering architecture.

## Migration Plan

1. Extend the bridge data model from transcript snapshots to live interactive session snapshots.
2. Replace the one-off command execution path with PTY-backed persistent sessions and bridge-owned input/output handling.
3. Update pane hosting so terminal views become directly focusable/editable from the user’s point of view and drop the command modal.
4. Keep `runCommand` and related control-plane calls, but route them through the same live session input path.
5. Add tests and update developer documentation to make the new interaction model the baseline for future changes.

Rollback is straightforward during development: revert to the archived `workspace-shell` state, because this change stays inside the existing module boundaries and does not require a data migration.

## Open Questions

- How much ANSI/control-sequence handling is needed to keep the default macOS shell prompt readable in practice?
- Should paste land as a dedicated control-plane/session action now, or remain UI-only until a broader clipboard-focused change?
- When libghostty is wired in for real rendering, should the bridge keep the lightweight screen model as a fallback runtime for tests, or replace it entirely?
