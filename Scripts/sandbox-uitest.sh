#!/bin/sh
set -eu

SANDBOX_DIR="/tmp/omux-sandbox"
APP_SUPPORT_DIR="$SANDBOX_DIR/AppSupport"
WORKTREES_DIR="$SANDBOX_DIR/worktrees"
WORKSPACE_STATE_DIR="$APP_SUPPORT_DIR/WorkspaceState"
SCROLLBACK_DIR="$APP_SUPPORT_DIR/Scrollback"
BACKUPS_DIR="$APP_SUPPORT_DIR/WorkspaceBackups"

printf "[sandbox] Wiping and rebuilding %s\n" "$SANDBOX_DIR"
rm -rf "$SANDBOX_DIR"
mkdir -p "$SANDBOX_DIR" "$WORKSPACE_STATE_DIR" "$SCROLLBACK_DIR" "$BACKUPS_DIR"
mkdir -p "$SANDBOX_DIR/hooks" "$SANDBOX_DIR/themes" "$SANDBOX_DIR/plugins" "$SANDBOX_DIR/state"

# Write config.toml
cat > "$SANDBOX_DIR/config.toml" <<'EOF'
schema = 1

[workspace]
default_root_path = "/tmp/omux-sandbox/worktrees/alpha"
isolate_shell_history = false

[terminal]
font_size = 13

[ui.panes]
inactive_opacity = 0.85
EOF

# Create git worktrees
for name in alpha beta gamma; do
  dir="$WORKTREES_DIR/$name"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email "sandbox@omux"
  git -C "$dir" config user.name "Sandbox"
  printf "# %s\n" "$name" > "$dir/README.md"
  git -C "$dir" add README.md
  git -C "$dir" commit -q -m "sandbox init"
done

# Write current.json fixture
cat > "$WORKSPACE_STATE_DIR/current.json" <<'EOF'
{
  "workspaces": [
    {
      "id": "sandbox-ws-alpha",
      "generatedName": "alpha",
      "customName": null,
      "rootPath": "/tmp/omux-sandbox/worktrees/alpha",
      "tabs": [
        {
          "id": "sandbox-tab-alpha-1",
          "title": "main",
          "focusedPaneID": "sandbox-pane-alpha-1a",
          "rootLayout": {
            "split": {
              "axis": "columns",
              "proportions": [0.5, 0.5],
              "children": [
                {
                  "paneStack": {
                    "id": "sandbox-stack-alpha-1a",
                    "panes": [
                      {
                        "id": "sandbox-pane-alpha-1a",
                        "title": "",
                        "content": {
                          "type": "terminal",
                          "session": {
                            "id": "sandbox-session-alpha-1a",
                            "shell": "/bin/zsh",
                            "workingDirectory": "/tmp/omux-sandbox/worktrees/alpha",
                            "environment": {}
                          }
                        },
                        "terminalState": {}
                      }
                    ],
                    "focusedPaneID": "sandbox-pane-alpha-1a"
                  }
                },
                {
                  "paneStack": {
                    "id": "sandbox-stack-alpha-1b",
                    "panes": [
                      {
                        "id": "sandbox-pane-alpha-1b",
                        "title": "",
                        "content": {
                          "type": "terminal",
                          "session": {
                            "id": "sandbox-session-alpha-1b",
                            "shell": "/bin/zsh",
                            "workingDirectory": "/tmp/omux-sandbox/worktrees/alpha",
                            "environment": {}
                          }
                        },
                        "terminalState": {}
                      }
                    ],
                    "focusedPaneID": "sandbox-pane-alpha-1b"
                  }
                }
              ]
            }
          }
        },
        {
          "id": "sandbox-tab-alpha-2",
          "title": "logs",
          "focusedPaneID": "sandbox-pane-alpha-2a",
          "rootLayout": {
            "split": {
              "axis": "columns",
              "proportions": [0.5, 0.5],
              "children": [
                {
                  "paneStack": {
                    "id": "sandbox-stack-alpha-2a",
                    "panes": [
                      {
                        "id": "sandbox-pane-alpha-2a",
                        "title": "",
                        "content": {
                          "type": "terminal",
                          "session": {
                            "id": "sandbox-session-alpha-2a",
                            "shell": "/bin/zsh",
                            "workingDirectory": "/tmp/omux-sandbox/worktrees/alpha",
                            "environment": {}
                          }
                        },
                        "terminalState": {}
                      }
                    ],
                    "focusedPaneID": "sandbox-pane-alpha-2a"
                  }
                },
                {
                  "paneStack": {
                    "id": "sandbox-stack-alpha-2b",
                    "panes": [
                      {
                        "id": "sandbox-pane-alpha-2b",
                        "title": "",
                        "content": {
                          "type": "terminal",
                          "session": {
                            "id": "sandbox-session-alpha-2b",
                            "shell": "/bin/zsh",
                            "workingDirectory": "/tmp/omux-sandbox/worktrees/alpha",
                            "environment": {}
                          }
                        },
                        "terminalState": {}
                      }
                    ],
                    "focusedPaneID": "sandbox-pane-alpha-2b"
                  }
                }
              ]
            }
          }
        }
      ],
      "focusedTabID": "sandbox-tab-alpha-1",
      "floatingPaneModals": [],
      "focusedFloatingPaneModalID": null
    },
    {
      "id": "sandbox-ws-beta",
      "generatedName": "beta",
      "customName": null,
      "rootPath": "/tmp/omux-sandbox/worktrees/beta",
      "tabs": [
        {
          "id": "sandbox-tab-beta-1",
          "title": "main",
          "focusedPaneID": "sandbox-pane-beta-1a",
          "rootLayout": {
            "split": {
              "axis": "columns",
              "proportions": [0.5, 0.5],
              "children": [
                {
                  "paneStack": {
                    "id": "sandbox-stack-beta-1a",
                    "panes": [
                      {
                        "id": "sandbox-pane-beta-1a",
                        "title": "",
                        "content": {
                          "type": "terminal",
                          "session": {
                            "id": "sandbox-session-beta-1a",
                            "shell": "/bin/zsh",
                            "workingDirectory": "/tmp/omux-sandbox/worktrees/beta",
                            "environment": {}
                          }
                        },
                        "terminalState": {}
                      }
                    ],
                    "focusedPaneID": "sandbox-pane-beta-1a"
                  }
                },
                {
                  "paneStack": {
                    "id": "sandbox-stack-beta-1b",
                    "panes": [
                      {
                        "id": "sandbox-pane-beta-1b",
                        "title": "",
                        "content": {
                          "type": "terminal",
                          "session": {
                            "id": "sandbox-session-beta-1b",
                            "shell": "/bin/zsh",
                            "workingDirectory": "/tmp/omux-sandbox/worktrees/beta",
                            "environment": {}
                          }
                        },
                        "terminalState": {}
                      }
                    ],
                    "focusedPaneID": "sandbox-pane-beta-1b"
                  }
                }
              ]
            }
          }
        },
        {
          "id": "sandbox-tab-beta-2",
          "title": "logs",
          "focusedPaneID": "sandbox-pane-beta-2a",
          "rootLayout": {
            "split": {
              "axis": "columns",
              "proportions": [0.5, 0.5],
              "children": [
                {
                  "paneStack": {
                    "id": "sandbox-stack-beta-2a",
                    "panes": [
                      {
                        "id": "sandbox-pane-beta-2a",
                        "title": "",
                        "content": {
                          "type": "terminal",
                          "session": {
                            "id": "sandbox-session-beta-2a",
                            "shell": "/bin/zsh",
                            "workingDirectory": "/tmp/omux-sandbox/worktrees/beta",
                            "environment": {}
                          }
                        },
                        "terminalState": {}
                      }
                    ],
                    "focusedPaneID": "sandbox-pane-beta-2a"
                  }
                },
                {
                  "paneStack": {
                    "id": "sandbox-stack-beta-2b",
                    "panes": [
                      {
                        "id": "sandbox-pane-beta-2b",
                        "title": "",
                        "content": {
                          "type": "terminal",
                          "session": {
                            "id": "sandbox-session-beta-2b",
                            "shell": "/bin/zsh",
                            "workingDirectory": "/tmp/omux-sandbox/worktrees/beta",
                            "environment": {}
                          }
                        },
                        "terminalState": {}
                      }
                    ],
                    "focusedPaneID": "sandbox-pane-beta-2b"
                  }
                }
              ]
            }
          }
        }
      ],
      "focusedTabID": "sandbox-tab-beta-1",
      "floatingPaneModals": [],
      "focusedFloatingPaneModalID": null
    }
  ],
  "activeWorkspaceID": "sandbox-ws-alpha"
}
EOF

printf "[sandbox] Done. Sandbox at %s\n" "$SANDBOX_DIR"
printf "[sandbox]   OMUX_HOME=%s\n" "$SANDBOX_DIR"
printf "[sandbox]   OMUX_APP_SUPPORT_DIR=%s\n" "$APP_SUPPORT_DIR"
printf "[sandbox]   Worktrees: alpha, beta, gamma\n"
printf "[sandbox]   Workspaces: 2 (alpha, beta) x 2 tabs x 2-pane split\n"
