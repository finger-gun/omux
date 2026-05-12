# OpenMUX Roadmap

This roadmap is directional rather than date-driven. It describes the current product shape and the main areas that still need work.

## Status overview

| Status | Area | Current state |
| --- | --- | --- |
| Done | Foundation and app shell | Swift package workspace, native macOS app entrypoint, AppKit shell, module boundaries, and baseline app structure are in place. |
| Done | Terminal runtime boundary | The pinned Ghostty runtime is vendored and isolated behind `OmuxTerminalBridge`. Runtime-backed pane views are the normal path. |
| Done | Workspace model | Workspaces, top-level tabs, split panes, pane-local tab stacks, focus routing, and persistent shell sessions are available. |
| Done | CLI and control plane | `omux` and the local JSON-RPC control plane share live workspace actions. |
| Done | Configuration and themes | OpenMUX owns `~/.omux/config.toml`, token-based themes, built-in presets, user theme overrides, and generated Ghostty config output. |
| Done | Hooks and events | External hooks, hook registries, terminal runtime events, and `omux events` provide local automation seams. |
| Done | Plugins and extension panes | User plugin commands, plugin registries, bundled plugin registration, extension panes, menu contributions, plugin toggling, and terminal text activation exist. |
| Done | Developer workflow | `make setup`, `make app`, `make build`, `make test`, `make verify`, and `make smoke` provide a stable local workflow. |
| In progress | Runtime transcript and snapshot quality | Improve runtime-backed pane snapshots and transcript fidelity for automation and restore flows. |
| In progress | Pane stack polish | Improve reordering, drag/drop, close behavior, and local pane-tab ergonomics. |
| In progress | Layout restore polish | Continue improving workspace, split, pane-stack, and session restore behavior. |
| In progress | Terminal fidelity and TUI robustness | Keep tightening ANSI/control-sequence behavior, input correctness, and full-screen TUI workflows. |
| In progress | Plugin capabilities | Grow the external plugin/process model while keeping the core small and terminal-first. |
| Later | Distribution polish | Move from early unsigned/ad-hoc release artifacts toward a more complete signed and notarized macOS distribution flow. |

## Near-term focus

| Priority | Area | Planned work |
| --- | --- | --- |
| High | Terminal fidelity | Improve transcript access, runtime snapshots, keyboard correctness, and robustness under heavy terminal applications. |
| High | Workspace usability | Refine pane-tab interactions, focus behavior, restore flows, sidebar context, and split ergonomics. |
| High | Automation contracts | Keep `omux`, JSON-RPC, hooks, terminal events, and plugin extension points predictable and documented. |
| Medium | Plugins | Expand bundled plugin examples and make external plugin authoring easier without embedding runtimes into the core. |
| Medium | Theme and config UX | Improve discovery, validation messages, contrast checks, and editing workflows on top of the token model and Settings UI. |
| Medium | Release UX | Improve app packaging, install/update confidence, and user-facing release notes. |

## Product shape

Today, OpenMUX is best understood as:

1. A native AppKit-first macOS shell with a terminal-native sidebar and keyboard-first workspace navigation.
2. A terminal workspace with tabs, splits, pane-local tab stacks, persistent sessions, themes, and bounded scrollback restore.
3. A narrow Ghostty-backed terminal bridge that hides terminal-engine details from app, CLI, hook, and plugin code.
4. A local-first automation platform through `omux`, JSON-RPC, hooks, events, plugins, and extension panes.

## Guiding rule

OpenMUX should keep moving toward a terminal workspace that is native, reliable, open to automation, extensible without forking, and built on strong terminal foundations without leaking those details into product logic.
