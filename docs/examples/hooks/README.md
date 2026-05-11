# Hook Examples

These are copy-pasteable OpenMUX hook handlers. Install one by copying the file into the matching directory under `~/.omux/hooks/` and making it executable.

For example:

```bash
mkdir -p ~/.omux/hooks/command-failed
cp docs/examples/hooks/command-failed/20-notify-on-failure ~/.omux/hooks/command-failed/
chmod +x ~/.omux/hooks/command-failed/20-notify-on-failure
```

Most examples use `jq` to read the hook JSON payload. Install it with Homebrew if needed:

```bash
brew install jq
```

| Example | Hook | What it does |
| --- | --- | --- |
| `workspace-opened/10-bootstrap-git-workspace` | `workspace-opened` | Creates a practical three-pane layout for Git projects and runs read-only startup commands. |
| `command-failed/20-notify-on-failure` | `command-failed` | Raises an OpenMUX notification when a command exits nonzero. |
| `terminal-command-finished/30-notify-long-command` | `terminal-command-finished` | Notifies when a long-running command finishes. |
| `terminal-command-finished/40-mark-pane-status` | `terminal-command-finished` | Marks the pane with a red error orb or brief blue idle orb when a command finishes. Hooks can use `needs-input` for a yellow user-action orb. |
| `terminal-cwd-changed/10-remember-recent-directory` | `terminal-cwd-changed` | Maintains `~/.omux/recent-directories` from live pane directory changes. |
| `terminal-text-activated/10-open-resolved-path` | `terminal-text-activated` | Opens Command-clicked local paths in a configurable macOS editor app. |

These scripts intentionally use the public `omux` CLI and local filesystem side effects. They do not depend on AppKit internals, libghostty types, or private control-plane details.
