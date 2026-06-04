#!/bin/sh
set -eu

SANDBOX_DIR="/tmp/omux-sandbox"
APP_SUPPORT_DIR="$SANDBOX_DIR/AppSupport"
WORKTREES_DIR="$SANDBOX_DIR/worktrees"
WORKSPACE_STATE_DIR="$APP_SUPPORT_DIR/WorkspaceState"
SCROLLBACK_DIR="$APP_SUPPORT_DIR/Scrollback"
BACKUPS_DIR="$APP_SUPPORT_DIR/WorkspaceBackups"

printf "[sandbox:demo] Wiping and rebuilding %s\n" "$SANDBOX_DIR"
rm -rf "$SANDBOX_DIR"
mkdir -p "$SANDBOX_DIR" "$WORKSPACE_STATE_DIR" "$SCROLLBACK_DIR" "$BACKUPS_DIR"
mkdir -p "$SANDBOX_DIR/hooks" "$SANDBOX_DIR/themes" "$SANDBOX_DIR/plugins" "$SANDBOX_DIR/state"

# Write config.toml
cat > "$SANDBOX_DIR/config.toml" <<'EOF'
schema = 1

[workspace]
default_root_path = "/tmp/omux-sandbox/worktrees/omux"
isolate_shell_history = false

[terminal]
font_size = 13

[ui.panes]
inactive_opacity = 0.85
EOF

# ── OpenMUX repo ────────────────────────────────────────────────────────────
setup_repo() {
  name="$1"; shift
  dir="$WORKTREES_DIR/$name"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email "demo@omux"
  git -C "$dir" config user.name "Demo"
  # write files passed as "path:content" pairs
  while [ $# -gt 0 ]; do
    filepath="${1%%:*}"
    content="${1#*:}"
    mkdir -p "$dir/$(dirname "$filepath")"
    printf '%s\n' "$content" > "$dir/$filepath"
    shift
  done
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "initial commit"
}

setup_repo omux \
  "README.md:# OpenMUX" \
  "Makefile:# OpenMUX build" \
  "Sources/OmuxCore/WorkspaceModel.swift:// workspace model" \
  "Sources/OmuxAppShell/OpenMUXAppDelegate.swift:// app delegate" \
  "Package.swift:// swift-tools-version: 5.9"

# ── Client projects ──────────────────────────────────────────────────────────
setup_repo northlight \
  "README.md:# Northlight" \
  "package.json:{\"name\":\"northlight\"}" \
  "src/index.ts:// entry point" \
  "src/components/Hero.tsx:// hero section"

setup_repo vaultpay \
  "README.md:# VaultPay" \
  "go.mod:module vaultpay" \
  "cmd/server/main.go:// api server" \
  "internal/payments/processor.go:// payment processing"

setup_repo fieldnotes \
  "README.md:# Fieldnotes" \
  "pyproject.toml:[project]" \
  "fieldnotes/app.py:# flask app" \
  "fieldnotes/models.py:# database models"

# ── Workspace fixture ────────────────────────────────────────────────────────
cat > "$WORKSPACE_STATE_DIR/current.json" <<'EOF'
{
  "workspaces": [
    {
      "id": "demo-ws-omux",
      "generatedName": "omux",
      "customName": "OpenMUX",
      "rootPath": "/tmp/omux-sandbox/worktrees/omux",
      "tabs": [
        {
          "id": "demo-tab-omux-dev",
          "title": "dev",
          "focusedPaneID": "demo-pane-omux-dev-l",
          "rootLayout": {
            "split": {
              "axis": "columns",
              "proportions": [0.6, 0.4],
              "children": [
                {
                  "paneStack": {
                    "id": "demo-stack-omux-dev-l",
                    "panes": [
                      {
                        "id": "demo-pane-omux-dev-l",
                        "title": "",
                        "content": {
                          "type": "terminal",
                          "session": {
                            "id": "demo-session-omux-dev-l",
                            "shell": "/bin/zsh",
                            "workingDirectory": "/tmp/omux-sandbox/worktrees/omux",
                            "environment": {}
                          }
                        },
                        "terminalState": {}
                      }
                    ],
                    "focusedPaneID": "demo-pane-omux-dev-l"
                  }
                },
                {
                  "paneStack": {
                    "id": "demo-stack-omux-dev-r",
                    "panes": [
                      {
                        "id": "demo-pane-omux-dev-r",
                        "title": "",
                        "content": {
                          "type": "terminal",
                          "session": {
                            "id": "demo-session-omux-dev-r",
                            "shell": "/bin/zsh",
                            "workingDirectory": "/tmp/omux-sandbox/worktrees/omux",
                            "environment": {}
                          }
                        },
                        "terminalState": {}
                      }
                    ],
                    "focusedPaneID": "demo-pane-omux-dev-r"
                  }
                }
              ]
            }
          }
        },
        {
          "id": "demo-tab-omux-logs",
          "title": "logs",
          "focusedPaneID": "demo-pane-omux-logs",
          "rootLayout": {
            "paneStack": {
              "id": "demo-stack-omux-logs",
              "panes": [
                {
                  "id": "demo-pane-omux-logs",
                  "title": "",
                  "content": {
                    "type": "terminal",
                    "session": {
                      "id": "demo-session-omux-logs",
                      "shell": "/bin/zsh",
                      "workingDirectory": "/tmp/omux-sandbox/worktrees/omux",
                      "environment": {}
                    }
                  },
                  "terminalState": {}
                }
              ],
              "focusedPaneID": "demo-pane-omux-logs"
            }
          }
        }
      ],
      "focusedTabID": "demo-tab-omux-dev",
      "floatingPaneModals": [],
      "focusedFloatingPaneModalID": null
    },
    {
      "id": "demo-ws-northlight",
      "generatedName": "northlight",
      "customName": "Northlight",
      "rootPath": "/tmp/omux-sandbox/worktrees/northlight",
      "tabs": [
        {
          "id": "demo-tab-northlight-dev",
          "title": "dev",
          "focusedPaneID": "demo-pane-northlight-dev-l",
          "rootLayout": {
            "split": {
              "axis": "columns",
              "proportions": [0.5, 0.5],
              "children": [
                {
                  "paneStack": {
                    "id": "demo-stack-northlight-dev-l",
                    "panes": [
                      {
                        "id": "demo-pane-northlight-dev-l",
                        "title": "",
                        "content": {
                          "type": "terminal",
                          "session": {
                            "id": "demo-session-northlight-dev-l",
                            "shell": "/bin/zsh",
                            "workingDirectory": "/tmp/omux-sandbox/worktrees/northlight",
                            "environment": {}
                          }
                        },
                        "terminalState": {}
                      }
                    ],
                    "focusedPaneID": "demo-pane-northlight-dev-l"
                  }
                },
                {
                  "paneStack": {
                    "id": "demo-stack-northlight-dev-r",
                    "panes": [
                      {
                        "id": "demo-pane-northlight-dev-r",
                        "title": "",
                        "content": {
                          "type": "terminal",
                          "session": {
                            "id": "demo-session-northlight-dev-r",
                            "shell": "/bin/zsh",
                            "workingDirectory": "/tmp/omux-sandbox/worktrees/northlight/src",
                            "environment": {}
                          }
                        },
                        "terminalState": {}
                      }
                    ],
                    "focusedPaneID": "demo-pane-northlight-dev-r"
                  }
                }
              ]
            }
          }
        },
        {
          "id": "demo-tab-northlight-git",
          "title": "git",
          "focusedPaneID": "demo-pane-northlight-git",
          "rootLayout": {
            "paneStack": {
              "id": "demo-stack-northlight-git",
              "panes": [
                {
                  "id": "demo-pane-northlight-git",
                  "title": "",
                  "content": {
                    "type": "terminal",
                    "session": {
                      "id": "demo-session-northlight-git",
                      "shell": "/bin/zsh",
                      "workingDirectory": "/tmp/omux-sandbox/worktrees/northlight",
                      "environment": {}
                    }
                  },
                  "terminalState": {}
                }
              ],
              "focusedPaneID": "demo-pane-northlight-git"
            }
          }
        }
      ],
      "focusedTabID": "demo-tab-northlight-dev",
      "floatingPaneModals": [],
      "focusedFloatingPaneModalID": null
    },
    {
      "id": "demo-ws-vaultpay",
      "generatedName": "vaultpay",
      "customName": "VaultPay",
      "rootPath": "/tmp/omux-sandbox/worktrees/vaultpay",
      "tabs": [
        {
          "id": "demo-tab-vaultpay-dev",
          "title": "dev",
          "focusedPaneID": "demo-pane-vaultpay-dev-l",
          "rootLayout": {
            "split": {
              "axis": "columns",
              "proportions": [0.5, 0.5],
              "children": [
                {
                  "paneStack": {
                    "id": "demo-stack-vaultpay-dev-l",
                    "panes": [
                      {
                        "id": "demo-pane-vaultpay-dev-l",
                        "title": "",
                        "content": {
                          "type": "terminal",
                          "session": {
                            "id": "demo-session-vaultpay-dev-l",
                            "shell": "/bin/zsh",
                            "workingDirectory": "/tmp/omux-sandbox/worktrees/vaultpay",
                            "environment": {}
                          }
                        },
                        "terminalState": {}
                      }
                    ],
                    "focusedPaneID": "demo-pane-vaultpay-dev-l"
                  }
                },
                {
                  "paneStack": {
                    "id": "demo-stack-vaultpay-dev-r",
                    "panes": [
                      {
                        "id": "demo-pane-vaultpay-dev-r",
                        "title": "",
                        "content": {
                          "type": "terminal",
                          "session": {
                            "id": "demo-session-vaultpay-dev-r",
                            "shell": "/bin/zsh",
                            "workingDirectory": "/tmp/omux-sandbox/worktrees/vaultpay/internal/payments",
                            "environment": {}
                          }
                        },
                        "terminalState": {}
                      }
                    ],
                    "focusedPaneID": "demo-pane-vaultpay-dev-r"
                  }
                }
              ]
            }
          }
        }
      ],
      "focusedTabID": "demo-tab-vaultpay-dev",
      "floatingPaneModals": [],
      "focusedFloatingPaneModalID": null
    },
    {
      "id": "demo-ws-fieldnotes",
      "generatedName": "fieldnotes",
      "customName": "Fieldnotes",
      "rootPath": "/tmp/omux-sandbox/worktrees/fieldnotes",
      "tabs": [
        {
          "id": "demo-tab-fieldnotes-dev",
          "title": "dev",
          "focusedPaneID": "demo-pane-fieldnotes-dev-l",
          "rootLayout": {
            "split": {
              "axis": "columns",
              "proportions": [0.5, 0.5],
              "children": [
                {
                  "paneStack": {
                    "id": "demo-stack-fieldnotes-dev-l",
                    "panes": [
                      {
                        "id": "demo-pane-fieldnotes-dev-l",
                        "title": "",
                        "content": {
                          "type": "terminal",
                          "session": {
                            "id": "demo-session-fieldnotes-dev-l",
                            "shell": "/bin/zsh",
                            "workingDirectory": "/tmp/omux-sandbox/worktrees/fieldnotes",
                            "environment": {}
                          }
                        },
                        "terminalState": {}
                      }
                    ],
                    "focusedPaneID": "demo-pane-fieldnotes-dev-l"
                  }
                },
                {
                  "paneStack": {
                    "id": "demo-stack-fieldnotes-dev-r",
                    "panes": [
                      {
                        "id": "demo-pane-fieldnotes-dev-r",
                        "title": "",
                        "content": {
                          "type": "terminal",
                          "session": {
                            "id": "demo-session-fieldnotes-dev-r",
                            "shell": "/bin/zsh",
                            "workingDirectory": "/tmp/omux-sandbox/worktrees/fieldnotes/fieldnotes",
                            "environment": {}
                          }
                        },
                        "terminalState": {}
                      }
                    ],
                    "focusedPaneID": "demo-pane-fieldnotes-dev-r"
                  }
                }
              ]
            }
          }
        }
      ],
      "focusedTabID": "demo-tab-fieldnotes-dev",
      "floatingPaneModals": [],
      "focusedFloatingPaneModalID": null
    }
  ],
  "activeWorkspaceID": "demo-ws-omux"
}
EOF

printf "[sandbox:demo] Done. Sandbox at %s\n" "$SANDBOX_DIR"
printf "[sandbox:demo]   OMUX_HOME=%s\n" "$SANDBOX_DIR"
printf "[sandbox:demo]   OMUX_APP_SUPPORT_DIR=%s\n" "$APP_SUPPORT_DIR"
printf "[sandbox:demo]   Workspaces: OpenMUX, Northlight, VaultPay, Fieldnotes\n"
