## MODIFIED Requirements

### Requirement: Markdown preview SHALL open as extension-owned preview content
The Markdown preview plugin SHALL render Markdown in extension-owned preview content that can be presented either as a docked pane tab or a floating modal rather than a terminal session.

#### Scenario: Preview opens beside editor
- **WHEN** a user requests Markdown preview with docked pane presentation from a focused terminal editor pane
- **THEN** OpenMUX creates an extension-owned preview pane adjacent to the source pane and associates it with the Markdown file

#### Scenario: Preview opens in modal
- **WHEN** a user requests Markdown preview with floating modal presentation
- **THEN** OpenMUX creates the preview as a floating modal while keeping the Markdown file association

#### Scenario: Existing preview can be reused
- **WHEN** a preview already exists for the same Markdown file in the workspace with the requested presentation
- **THEN** the plugin can update or focus the existing preview pane instead of always creating a duplicate

## ADDED Requirements

### Requirement: Markdown preview SHALL support configurable default presentation
The Markdown preview plugin SHALL support an OpenMUX-native configuration setting that selects whether previews open by default as a pane tab or a floating modal.

#### Scenario: Configured default opens as pane tab
- **WHEN** Markdown preview configuration sets the default presentation to pane tab
- **THEN** a preview request without an explicit presentation override opens as a docked pane tab

#### Scenario: Configured default opens as modal
- **WHEN** Markdown preview configuration sets the default presentation to modal
- **THEN** a preview request without an explicit presentation override opens as a floating modal
