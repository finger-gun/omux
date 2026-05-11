# markdown-preview-plugin Specification

## Purpose
TBD - created by archiving change add-markdown-preview-plugin. Update Purpose after archive.
## Requirements
### Requirement: Markdown preview plugin SHALL be optional
The Markdown preview capability SHALL be enabled only when the Markdown preview plugin is available and enabled by configuration or documented built-in defaults.

#### Scenario: Disabled plugin refuses preview
- **WHEN** a user invokes Markdown preview while the plugin is disabled
- **THEN** OpenMUX reports an explicit disabled-plugin error and does not create a misleading terminal pane

#### Scenario: Enabled plugin can start preview
- **WHEN** the plugin is enabled and a user requests preview for a readable Markdown file
- **THEN** the plugin can open or update an extension pane for that file

### Requirement: Markdown preview SHALL open as an extension pane
The Markdown preview plugin SHALL render Markdown in an extension pane rather than a terminal session.

#### Scenario: Preview opens beside editor
- **WHEN** a user requests Markdown preview with split placement from a focused terminal editor pane
- **THEN** OpenMUX creates an extension pane adjacent to the source pane and associates it with the Markdown file

#### Scenario: Existing preview can be reused
- **WHEN** a preview already exists for the same Markdown file in the workspace
- **THEN** the plugin can update or focus the existing preview pane instead of always creating a duplicate

### Requirement: Markdown preview SHALL render local Markdown files
The Markdown preview plugin SHALL read a local Markdown file and render a preview representation suitable for a GitHub-style documentation workflow.

#### Scenario: Readable Markdown renders
- **WHEN** the user previews a readable `.md` or `.markdown` file
- **THEN** the preview pane displays rendered headings, paragraphs, links, code blocks, lists, tables when supported, and images when local paths are readable

#### Scenario: Missing file reports error
- **WHEN** the user requests preview for a missing or unreadable Markdown file
- **THEN** the plugin reports an explicit error and does not create a success-shaped preview

### Requirement: Markdown preview SHALL hot-reload on file changes
The Markdown preview plugin SHALL watch the source Markdown file and update the associated extension pane after the file changes.

#### Scenario: Save updates preview
- **WHEN** the user saves changes to the Markdown file from Helix or another editor
- **THEN** the preview pane refreshes to show the new rendered content without requiring manual pane recreation

#### Scenario: Rapid saves are coalesced
- **WHEN** multiple file changes arrive in quick succession
- **THEN** the plugin avoids flooding OpenMUX with redundant preview updates and renders the latest file contents

### Requirement: Markdown preview SHALL constrain unsafe content
The Markdown preview plugin SHALL sanitize or disable unsafe rendered content so local preview does not become an arbitrary script execution surface.

#### Scenario: Script content is not executed
- **WHEN** Markdown input contains inline HTML with script content
- **THEN** the preview does not execute that script

#### Scenario: External links leave the pane
- **WHEN** a user activates an external link in rendered Markdown
- **THEN** the host opens the link externally rather than turning the preview pane into a browser navigation surface

### Requirement: Markdown preview SHALL respect OpenMUX visual context
The Markdown preview plugin SHALL provide a readable default style that works with OpenMUX dark and light themes.

#### Scenario: Theme-aware preview
- **WHEN** the active OpenMUX theme changes between dark and light presentation
- **THEN** the Markdown preview remains readable without requiring the user to edit the Markdown file

### Requirement: Markdown preview SHALL use public extension-pane APIs
The Markdown preview plugin SHALL create and update preview panes through public OpenMUX control-plane or CLI operations rather than private in-process state.

#### Scenario: Plugin updates through control plane
- **WHEN** the Markdown file changes
- **THEN** the plugin sends a public extension-pane update request identifying the target pane and replacement content

