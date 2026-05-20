## Context

OpenMUX already launches one live shell session per terminal pane and represents launch details with `SessionDescriptor(shell, workingDirectory, environment)`. The terminal bridge applies that descriptor through libghostty's surface configuration, keeping upstream types inside `OmuxTerminalBridge`.

The missing piece is workspace-level launch context. `WorkspaceController.makePane` currently creates a session from `$SHELL` and a working directory only, so shells inherit the user's normal global history behavior. For zsh and many other shells, that usually means all OpenMUX workspaces write to the same command history file unless the user's shell startup files do something more specific.

## Goals / Non-Goals

**Goals:**
- Default OpenMUX-created terminal sessions to workspace-scoped shell history.
- Reuse one history file for every pane and pane tab in a workspace.
- Keep history location deterministic, local, and under OpenMUX-owned state.
- Preserve the terminal bridge boundary by passing only OpenMUX-native session environment values.
- Provide a documented configuration opt-out.

**Non-Goals:**
- Isolating provider credentials, `HOME`, keychains, Docker, kubeconfig, or arbitrary tool state.
- Managing shell history after launch or parsing shell-specific history files.
- Changing input handling, keybindings, IME behavior, or terminal encoding.
- Adding a background service or shell integration daemon.

## Decisions

### 1) Use environment-based shell history isolation

OpenMUX will set launch environment variables on each `SessionDescriptor`:

- `OMUX_WORKSPACE_ID`
- `OMUX_WORKSPACE_ROOT`
- `OMUX_WORKSPACE_HISTORY`
- `HISTFILE` when workspace shell history isolation is enabled

This keeps behavior inspectable and uses normal shell mechanisms. It also avoids OpenMUX trying to interpret shell history formats.

**Alternative considered:** capture commands from terminal input events and maintain OpenMUX-owned command history.  
**Why not chosen:** per-key terminal input is sensitive and not an authoritative shell command stream; the existing design intentionally avoids treating native typing as structured command records.

### 2) Store history under OpenMUX state by workspace ID

Workspace history files will live under an OpenMUX-owned state path derived from the existing config home, for example:

```text
~/.omux/state/workspaces/<workspace-id>/shell-history
```

Using the workspace ID avoids path collisions and keeps renamed workspaces stable.

**Alternative considered:** derive history paths from workspace root path.  
**Why not chosen:** root paths can collide through symlinks, move over time, or contain user-sensitive names; workspace IDs are already stable OpenMUX identifiers.

### 3) Scope sharing at workspace level, not pane level

All terminal panes and pane tabs in a workspace will use the same history file. Different workspaces will use different files.

**Alternative considered:** per-pane history files.  
**Why not chosen:** splits and pane tabs in one workspace usually represent one project/context; per-pane history would make normal project workflows feel disconnected.

### 4) Reapply zsh history isolation after user startup files

OpenMUX will provide launch variables for every shell. For zsh, OpenMUX will also install an OpenMUX-owned `ZDOTDIR` shim that sources the user's original zsh startup files and then reapplies `HISTFILE="$OMUX_WORKSPACE_HISTORY"` from `.zshrc` and `.zlogin`. This keeps Ghostty's normal zsh shell integration path intact because libghostty can still preserve the OpenMUX `ZDOTDIR` through `GHOSTTY_ZSH_ZDOTDIR`.

**Alternative considered:** launching shells through wrapper scripts that force history behavior after rc files run.  
**Why not chosen:** command wrappers interfere with libghostty's shell integration and can make the persisted session shell look like the wrapper instead of the user's shell.

### 5) Add an OpenMUX config opt-out

Add `[workspace] isolate_shell_history = true` with a default of `true`. Setting it to `false` leaves `HISTFILE` untouched while still exposing `OMUX_WORKSPACE_*` context variables.

**Alternative considered:** no opt-out.  
**Why not chosen:** some users intentionally rely on global shell history across all terminals, and OpenMUX should stay composed from tools rather than enforcing one workflow.

## Risks / Trade-offs

- **[Risk] Shell rc files override `HISTFILE`** -> **Mitigation:** zsh sessions use an OpenMUX `ZDOTDIR` shim that reapplies history after normal startup files; other shells retain documented environment-based behavior.
- **[Risk] zsh `share_history` or equivalent options still make history feel shared inside one workspace** -> **Mitigation:** this is acceptable for workspace-level sharing; cross-workspace leakage is prevented when the shell honors `HISTFILE`.
- **[Risk] Existing restored workspaces need a workspace ID before session attachment** -> **Mitigation:** build session descriptors from workspace context at attach time, including restored panes.
- **[Risk] History files accumulate over time** -> **Mitigation:** store under a predictable OpenMUX state path so cleanup can be added later without changing the launch contract.

## Migration Plan

1. Add configuration parsing, defaults, validation, config generation, and docs for `workspace.isolate_shell_history`.
2. Add a small workspace shell environment helper in app-shell/core code that constructs the launch environment from workspace context.
3. Route new, split, pane-tab, and restored pane launches through that helper.
4. Add tests for config parsing, session descriptor environment, restored pane launch, and bridge propagation.
5. Keep rollback simple: disabling the config setting leaves user shell history behavior unchanged for new sessions.

## Open Questions

- Whether future cleanup commands should remove per-workspace shell history alongside OpenMUX scrollback history.
- Whether a later workspace profile feature should generalize this into named environment profiles for cloud-provider credential isolation.
