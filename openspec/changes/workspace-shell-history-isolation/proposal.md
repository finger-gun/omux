## Why

Developers often use separate OpenMUX workspaces for separate projects or environments, but shell command history currently follows the user's global shell configuration. That makes unrelated workspace commands appear together and weakens the safety boundary users expect when switching between production, staging, and local contexts.

## Goals

- Make OpenMUX-launched interactive shells use workspace-scoped command history by default.
- Keep panes and pane tabs within the same workspace sharing that workspace's shell history.
- Expose enough OpenMUX-native launch environment for shell startup files and hooks to identify workspace context.
- Provide an explicit configuration escape hatch for users who prefer their shell's existing global history behavior.

## Non-goals

- Isolating cloud provider credential stores, `HOME`, keychains, Docker config, kubeconfig, or arbitrary tool state.
- Adding background services, shell daemons, or in-process shell management.
- Changing keyboard/input routing or terminal encoding behavior.
- Leaking libghostty launch details outside the terminal bridge boundary.

## What Changes

- OpenMUX assigns each workspace a stable shell history file path under OpenMUX-owned state storage.
- New and restored terminal sessions receive workspace context environment variables, including the workspace ID and root path.
- When history isolation is enabled, shell sessions receive `HISTFILE` pointing at the workspace-scoped history file.
- The same workspace history location is reused by panes, splits, and pane tabs inside that workspace.
- Users can disable workspace shell history isolation through configuration.
- Documentation clarifies that shell startup files can override OpenMUX-provided history variables.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `workspace-session-actions`: Terminal session launch semantics now include workspace-scoped shell history environment for OpenMUX-created sessions.
- `terminal-bridge`: Session launch environment continues to be applied through OpenMUX-native descriptors, now including workspace context/history keys.
- `config-system`: Configuration includes an opt-out for default workspace shell history isolation.

## Impact

- `OmuxCore` session/workspace model may need a small OpenMUX-native launch metadata addition or helper.
- `OmuxAppShell` must build session descriptors with workspace-aware environment values for new and restored panes.
- `OmuxConfig` must parse, validate, generate, and document the opt-out setting.
- `OmuxTerminalBridge` should remain the only layer that passes launch environment into libghostty.
- Tests should cover new pane creation, restored pane launch, bridge environment propagation, and configuration parsing.

This aligns with OpenMUX's terminal-first and hackable direction: the terminal remains a real user shell, while OpenMUX provides predictable, inspectable launch context rather than hidden shell emulation.
