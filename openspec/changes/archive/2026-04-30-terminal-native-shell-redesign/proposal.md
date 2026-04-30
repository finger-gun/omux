## Why

OpenMUX has the core terminal workspace foundations in place, but the current shell still reads like a functional scaffold rather than a product people want to live in all day. The next change should turn that foundation into a cohesive, terminal-native shell that feels polished, open, and empowering without drifting toward an IDE-like experience where the terminal becomes just another panel.

Now is the right time because the shell architecture already exists, the roadmap has elevated UI/UX and theming to near-term priorities, and the manifesto is explicit that the terminal is the product. If OpenMUX hardens the wrong visual model now, later polish work will stack on top of a shell that feels too generic, too boxed-in, or too opinionated.

## Goals

- Redesign the workspace shell so it feels intentional, calm, and terminal-first instead of default-AppKit scaffolding.
- Preserve the sense of freedom and composability expected from terminal tools rather than making the app feel like a closed IDE shell.
- Introduce a theme system that styles both shell chrome and terminal palettes as one coherent product theme.
- Ship strong built-in theme presets such as Catppuccin, Gruvbox, and Sonokai so OpenMUX looks good immediately.
- Improve visual hierarchy around navigation, pane focus, pane headers, spacing, and workspace context without weakening terminal density or performance.
- Keep the redesign compatible with the existing AppKit-first shell, the narrow libghostty bridge boundary, and future automation/hooks work.

## Non-goals

- Rebuilding OpenMUX as a browser-heavy or webview-first application.
- Turning the product into a VS Code-style IDE shell with terminal panels subordinate to editor/application chrome.
- Expanding the core into a monolithic dashboard with workflow-specific UI that constrains how users work.
- Changing terminal engine architecture, broadening the libghostty bridge boundary, or coupling shell styling to runtime internals.
- Adding arbitrary theme import/export or advanced customization before the built-in theme model is stable.
- Implementing the redesign in this change proposal; this change defines the contract and implementation plan only.

## What Changes

- Define a terminal-native shell model for the macOS workspace UI, including sidebar, top bar, canvas layout, and visual hierarchy rules that keep the terminal as the dominant surface.
- Define navigation and shell chrome requirements so workspace/session switching supports orientation and flow without overwhelming the main terminal canvas.
- Define pane chrome requirements for pane headers, local tab strips, focus states, and related controls so panes feel deliberate without feeling boxed in.
- Define a token-driven theme system that covers shell backgrounds, borders, text, accents, selection states, and terminal palettes together.
- Define built-in product theme expectations for curated presets, including Catppuccin, Gruvbox, and Sonokai, with a strong OpenMUX default theme.
- Define explicit UX guardrails so the redesign remains terminal-native, lightweight, script-friendly, and performance-conscious.
- Preserve clean boundaries between shell presentation, workspace state, and the libghostty-backed terminal bridge.

## Capabilities

### New Capabilities
- `terminal-native-shell`: Defines the overall shell composition, hierarchy, and terminal-first UX principles for the redesigned macOS workspace.
- `workspace-navigation`: Defines sidebar and top-bar behavior for navigating workspaces and sessions without making shell chrome dominate the experience.
- `pane-chrome`: Defines pane headers, local pane-tab presentation, focus cues, and pane-level actions for a more intentional workspace canvas.
- `theme-system`: Defines token-based theming for shell chrome and terminal palettes, including cohesive built-in theme presets.

### Modified Capabilities

None.

## Impact

- Affects the AppKit shell layer in `OmuxAppShell`, especially workspace window composition, pane stack presentation, and shell-level styling.
- Introduces a product-facing theme contract that will influence shell rendering, terminal color configuration, and future settings/customization work.
- Constrains future UI work to terminal-native design rules that support openness, hackability, and performance instead of IDE-style enclosure.
- Requires clear separation between shell chrome and terminal hosting so the libghostty bridge remains narrow and implementation details do not leak upward.
- Shapes later implementation changes for built-in themes, workspace navigation polish, pane interaction refinement, and visual consistency across the product.
