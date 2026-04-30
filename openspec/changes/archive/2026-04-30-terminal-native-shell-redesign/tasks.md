## 1. Shell composition

- [x] 1.1 Introduce a dedicated shell composition root that separates sidebar, top bar, workspace canvas, and terminal-hosted pane content.
- [x] 1.2 Replace the current scaffold-style workspace header layout with a terminal-native shell hierarchy that keeps terminal content visually dominant.
- [x] 1.3 Add persistent workspace and session navigation surfaces with visually secondary sidebar and top-bar presentation.

## 2. Pane chrome

- [x] 2.1 Replace generic pane-stack segmented controls with dedicated pane header and local tab chrome components.
- [x] 2.2 Implement slim pane focus cues, active-tab treatment, and pane-level actions that preserve terminal density.
- [x] 2.3 Keep pane chrome concerns in app-shell presentation code while leaving terminal hosting isolated behind the existing bridge boundary.

## 3. Theme system

- [x] 3.1 Define theme token models for shell backgrounds, text, borders, accents, selection states, and terminal palettes.
- [x] 3.2 Wire the shell to consume theme tokens coherently across sidebar, top bar, workspace canvas, and pane chrome.
- [x] 3.3 Add a bridge-safe path for applying terminal palette values without leaking shell theme concerns into libghostty-facing code.

## 4. Built-in presets and polish

- [x] 4.1 Ship an OpenMUX default theme that establishes the intended terminal-native look and feel.
- [x] 4.2 Add curated built-in presets for Catppuccin, Gruvbox, and Sonokai using the shared theme contract.
- [x] 4.3 Refine spacing, hierarchy, and navigation emphasis so shell chrome supports orientation without feeling IDE-like or dashboard-heavy.

## 5. Validation and documentation

- [x] 5.1 Add or update UI-focused tests that verify shell hierarchy, focus-state behavior, and pane-tab presentation without breaking existing workspace flows.
- [x] 5.2 Validate that the redesigned shell preserves terminal bridge boundaries and does not regress runtime-hosted pane behavior.
- [x] 5.3 Update roadmap and development-facing docs to reflect the shipped shell/theme model and any new customization entry points.
