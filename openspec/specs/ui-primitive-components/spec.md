# ui-primitive-components Specification

## Purpose
Specifies the extracted UI primitive components within `OmuxAppShell` — count badges and collapsible section headers — their visibility, file placement, and behavioral contracts.

## Requirements

### Requirement: `CountBadgeView` SHALL be declared in its own file with internal visibility
The count badge view SHALL be extracted from `WorkspaceWindowController.swift` into `Sources/OmuxAppShell/CountBadgeView.swift` and declared `internal`, making it accessible to any code within the `OmuxAppShell` module including unit tests.

#### Scenario: Badge is accessible within the module
- **WHEN** a test target in `OmuxAppShellTests` instantiates `CountBadgeView`
- **THEN** the type is visible and can be initialized without accessing `WorkspaceWindowController.swift` internals

#### Scenario: Badge renders a count with the correct colors
- **WHEN** `render(count:badgeColor:numberColor:)` is called with a positive integer
- **THEN** the badge displays the count using the provided badge background color and number foreground color

#### Scenario: Badge is hidden when count is zero
- **WHEN** `render(count:badgeColor:numberColor:)` is called with a count of zero
- **THEN** the badge view is hidden

### Requirement: `CollapsibleSectionHeaderView` SHALL be declared in its own file with internal visibility
The collapsible section header view SHALL be extracted from `WorkspaceWindowController.swift` into `Sources/OmuxAppShell/CollapsibleSectionHeaderView.swift` and declared `internal`.

#### Scenario: Header is accessible within the module
- **WHEN** a test target in `OmuxAppShellTests` instantiates `CollapsibleSectionHeaderView`
- **THEN** the type is visible and can be initialized without accessing `WorkspaceWindowController.swift` internals

#### Scenario: Header renders title, chevron, and optional badge
- **WHEN** the header is rendered with a title and a non-zero count
- **THEN** the chevron, title label, and `CountBadgeView` are all visible and laid out in order

#### Scenario: Header renders without badge when count is zero
- **WHEN** the header is rendered with a count of zero
- **THEN** the `CountBadgeView` is hidden and only the chevron and title label are visible

#### Scenario: Header chevron reflects collapsed state
- **WHEN** the header is set to collapsed state
- **THEN** the chevron rotates to indicate the section is collapsed

#### Scenario: Header chevron reflects expanded state
- **WHEN** the header is set to expanded state
- **THEN** the chevron rotates to indicate the section is expanded

### Requirement: Extracted UI primitives SHALL not change observable behavior
Extraction of `CountBadgeView` and `CollapsibleSectionHeaderView` into separate files SHALL produce no change in rendered output, layout, theming, or user-observable behavior.

#### Scenario: Sidebar widgets render identically after extraction
- **WHEN** the workspace shell renders sidebar widgets after the extraction refactor
- **THEN** widget headers, badges, chevrons, and section rows are visually and behaviorally identical to the pre-extraction state
