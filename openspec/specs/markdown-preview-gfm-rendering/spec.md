# markdown-preview-gfm-rendering Specification

## Purpose
TBD - created by archiving change add-gfm-markdown-rendering. Update Purpose after archive.
## Requirements
### Requirement: Markdown preview SHALL render GitHub Flavored Markdown
The Markdown preview plugin SHALL render local Markdown with GitHub Flavored Markdown-compatible parsing for common README content.

#### Scenario: GFM table renders as table HTML
- **WHEN** a Markdown file contains a pipe table with a delimiter row
- **THEN** the preview HTML contains table, header, row, and cell elements representing that table

#### Scenario: GFM task list renders checked state
- **WHEN** a Markdown file contains task list items using `- [ ]` and `- [x]`
- **THEN** the preview HTML represents them as task list items with visible checkbox state

#### Scenario: GFM strikethrough and autolinks render
- **WHEN** a Markdown file contains `~~deleted~~` text and a bare `https://` URL
- **THEN** the preview HTML renders strikethrough markup and an anchor for the autolink

### Requirement: Markdown preview SHALL render README HTML blocks
The Markdown preview plugin SHALL preserve common raw HTML used in README files while keeping script-oriented content constrained.

#### Scenario: Raw README layout HTML renders
- **WHEN** a Markdown file contains raw HTML such as `<p align="center">` or `<img src="...">`
- **THEN** the preview HTML preserves that HTML so the WebKit preview can render it

#### Scenario: Local image paths resolve from source file
- **WHEN** a Markdown file references an image with a relative local path
- **THEN** the preview HTML resolves the image source relative to the Markdown file so the host can load the local image

#### Scenario: Script-oriented HTML is constrained
- **WHEN** a Markdown file contains script blocks or script-oriented inline attributes
- **THEN** the preview HTML removes or neutralizes that script-oriented content before it reaches the extension pane host

### Requirement: Markdown preview SHALL keep existing plugin contracts
The Markdown preview plugin SHALL keep the existing CLI, configuration, watch, and extension-pane update contracts while changing renderer fidelity.

#### Scenario: Existing preview command still creates HTML extension pane
- **WHEN** a user runs `omux markdown-preview <file>` with the plugin enabled
- **THEN** the command creates or updates an extension pane with HTML content for the rendered file

#### Scenario: Hot reload still updates rendered GFM
- **WHEN** the watched Markdown file changes
- **THEN** the plugin re-renders the file with the GFM renderer and updates the same preview pane

### Requirement: Markdown preview GFM rendering SHALL stay plugin-owned
The system SHALL keep Markdown parsing and rendering dependencies isolated to the Markdown preview plugin and SHALL NOT route Markdown rendering through the terminal bridge or core workspace model.

#### Scenario: Terminal bridge is unaffected
- **WHEN** GFM rendering is added to Markdown preview
- **THEN** terminal panes, libghostty surfaces, and terminal keyboard input behavior remain unchanged

