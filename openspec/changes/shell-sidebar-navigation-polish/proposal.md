## Why

The shell now has enough terminal-dispatch context to show richer, developer-relevant navigation state, but the current workspace and pane labels still reflect early scaffolding rather than a polished terminal-first workflow. This change uses that new context to make workspaces easier to scan, rename, and manage without adding background services, browser-like chrome, or leaking terminal-engine details across module boundaries.

## Goals

- Replace path-derived default workspace names with stable generated names such as `Workspace 1`, `Workspace 2`, and support returning to that generated name after a custom rename.
- Add contextual management actions for workspace rows and pane-tab surfaces so common rename and close flows do not depend on top-level menus.
- Turn the sidebar into a better navigation surface by showing subtle terminal metadata for the terminals inside each workspace, including branch/repository and path context derived from terminal state.
- Remove redundant path presentation in pane chrome so terminal identity is clearer and the shell does not repeat the same information in competing locations.
- Keep the design terminal-first, AppKit-native, performant, and behind OpenMUX-owned models rather than pushing VCS logic into the `libghostty` bridge.

## Non-goals

- Adding browser-heavy sidebars, web views, or vendor-specific source control integrations.
- Introducing a daemon or long-lived background service for VCS indexing.
- Mirroring every internal layout node in the sidebar if a simpler terminal-oriented navigation model works better.
- Changing keyboard dispatch behavior or terminal input semantics beyond ensuring new menus do not interfere with existing shortcuts.

## What Changes

- Change default workspace naming from root-path-derived names to generated `Workspace N` labels, while preserving optional user-provided custom names and allowing a reset back to generated defaults.
- Add context menus to workspace rows with actions for rename, remove custom name, close, close others, close above, and close below.
- Add similar context menus to pane-tab surfaces for rename and close-oriented actions that match their local ordering semantics.
- Expand sidebar presentation so each workspace can show subtle terminal metadata rows for the terminals it contains, including git branch or repository context and working-directory path where available.
- Remove the persistent duplicate cwd/path row from pane chrome when it only repeats identity information already represented by the pane tab title or sidebar metadata, while keeping space for transient terminal status such as progress or exit state.
- Keep VCS detection and sidebar metadata generation in OpenMUX-owned shell/app models and services, with no new `libghostty` bridge responsibilities and no plugin API breakage.

## Capabilities

### New Capabilities
- `workspace-label-management`: Generated workspace names, optional custom workspace names, and reset-to-default behavior.
- `shell-context-menus`: Contextual rename and close actions for workspace rows and pane-tab surfaces.
- `sidebar-terminal-metadata`: Sidebar terminal metadata rows showing terminal-oriented repo/branch/path context within each workspace.
- `pane-chrome-identity`: Pane chrome rules that separate identity labels from transient status text to avoid redundant path presentation.

### Modified Capabilities

None.

## Impact

- Affected code will primarily live in `OmuxCore` workspace models, `OmuxAppShell` sidebar and pane chrome views, and supporting shell-side services that derive git metadata from workspace or pane paths.
- The `libghostty` bridge boundary remains unchanged; terminal dispatch continues to provide cwd/title events, while repo and branch resolution stays in OpenMUX-owned code.
- New behavior must preserve keyboard correctness, especially around context menu invocation and focus behavior on international keyboard layouts.
- Existing control-plane and hook surfaces may need additive metadata if sidebar-derived terminal information should become observable, but this change does not require a breaking RPC or plugin contract change.
