# OpenMUX Roadmap

This roadmap is a practical overview of what OpenMUX has already landed and what is still ahead.

It is intentionally directional rather than date-driven.

## Status overview

| Status | Step | What it means |
| --- | --- | --- |
| ✅ Done | Foundation and app shell | Swift package workspace, native macOS app entrypoint, module boundaries, and baseline app structure are in place. |
| ✅ Done | Control plane and CLI | `omux` and the local JSON-RPC control plane exist and share the same live workspace actions. |
| ✅ Done | Hook foundation | External hook execution seams exist for automation and future plugin workflows. |
| ✅ Done | Workspace tabs and split panes | The shell supports top-level workspace tabs plus split-right and split-down layouts. |
| ✅ Done | Pane-local tab stacks | Each split region can host its own local pane tabs instead of behaving like a single terminal only. |
| ✅ Done | Interactive session model | Panes own persistent shell sessions and accept direct keyboard input, paste, resize, and command injection. |
| ✅ Done | Ghostty bridge boundary | `libghostty` / `CGhostty` stays isolated inside `OmuxTerminalBridge`. |
| ✅ Done | Vendored Ghostty runtime path | Ghostty is vendored, pinned, buildable locally, and runtime-hosted pane surfaces are wired through the bridge. |
| ✅ Done | Runtime fallback path | When the vendored runtime is unavailable, OpenMUX still falls back to the internal PTY-backed host. |
| ✅ Done | Native developer workflow | `make setup`, `make dev`, `make build`, `make test`, `make verify`, and `make smoke` provide a stable native workflow. |
| ✅ Done | CI baseline and app smoke coverage | CI now runs normal build/test checks and a dedicated runtime-enabled launch smoke test. |
| ⏳ Next | Visual shell redesign | Redesign the shell so the app feels intentional and polished, with a stronger sidebar, pane chrome, spacing system, and overall hierarchy. |
| ⏳ Next | Theme system and built-in presets | Add a first-class theming model for both terminal colors and shell chrome, with curated built-in themes such as Catppuccin, Sonokai, and Gruvbox. |
| ⏳ Next | Runtime transcript and snapshot quality | Improve runtime-backed pane snapshots so they expose richer transcript state instead of the current minimal placeholder snapshot. |
| ⏳ Next | Pane stack polish | Add reordering, drag/drop, and better local pane-tab ergonomics inside split regions. |
| ⏳ Next | Layout persistence and restore | Save and restore workspaces, splits, pane stacks, and sessions in a predictable way. |
| ⏳ Next | Notifications and workflow automation | Build on the control plane and hooks with more useful notifications, triggers, and event-driven workflows. |
| ⏳ Next | Plugin model expansion | Move from hook-only seams toward a stronger external plugin/process model built on the same control surface. |
| ⏳ Next | Terminal fidelity and TUI robustness | Improve ANSI/control-sequence handling and runtime behavior for heavier full-screen terminal applications. |
| ⏳ Later | Release and packaging flow | Add a more complete distribution story for shipping OpenMUX as a polished macOS app. |

## Near-term focus

| Priority | Area | Planned work |
| --- | --- | --- |
| High | Visual shell redesign | Establish the overall look of OpenMUX with a stronger dark shell, improved spacing, clearer visual hierarchy, better pane chrome, and a more polished sidebar/workspace experience. |
| High | Theme system | Build a theme token system that controls both terminal palette and app chrome so OpenMUX can ship cohesive built-in themes instead of only raw terminal colors. |
| High | Built-in theme presets | Ship familiar, high-quality defaults such as Catppuccin, Gruvbox, Sonokai, and similar curated presets that make the app look good immediately. |
| High | Runtime-hosted terminal experience | Improve transcript access, reduce remaining runtime rough edges, and keep the Ghostty-backed path stable under real use. |
| High | Workspace usability | Refine pane-tab interactions, focus behavior, restore flows, and sidebar/session navigation so the shell feels more complete day to day. |
| High | Automation platform | Keep growing the `omux` + JSON-RPC + hooks surface so external tools and AI workflows can build on OpenMUX cleanly. |
| Medium | Theme customization | Add user overrides and eventually import/export support once the built-in theme model is stable. |
| Medium | Plugin architecture | Define the next layer above hooks for longer-running extensions and richer tool integrations. |
| Medium | Interaction polish | Improve hover states, focus cues, transitions, empty states, notifications, and other details that make the UI feel deliberate without bloating the core model. |

## Current shape of the product

Today, OpenMUX is best understood as:

1. a native AppKit-first macOS shell
2. a terminal workspace with tabs, splits, and pane-local tab stacks
3. a narrow Ghostty-backed terminal bridge with a safe fallback path
4. a local-first automation surface through `omux`, JSON-RPC, and hooks

The next big shift is not just deeper terminal/runtime work, but turning that foundation into a shell that feels visually coherent, themeable, and pleasant to live in every day.

## Guiding rule for future steps

OpenMUX should keep moving toward a terminal workspace that is:

- native
- reliable
- open to automation
- extensible without forking
- built on strong terminal foundations without leaking those details into product logic
