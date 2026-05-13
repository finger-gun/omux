## ADDED Requirements

### Requirement: Extension panes SHALL support explicit presentation targets
The system SHALL allow extension-pane creation and update contracts to declare a shell presentation target of either docked pane presentation or floating modal presentation.

#### Scenario: Control plane creates modal presentation
- **WHEN** a caller creates an extension pane with a floating modal presentation target
- **THEN** OpenMUX creates the extension-owned pane in a floating modal instead of inserting it into the split tree

#### Scenario: Control plane keeps docked presentation explicit
- **WHEN** a caller creates an extension pane with docked pane presentation
- **THEN** OpenMUX uses the existing pane-stack and split-layout flow for that pane

### Requirement: Extension pane hosts SHALL preserve continuity across docked and modal presentation
The system SHALL preserve shell-owned extension pane host continuity for a stable pane identity during non-structural updates and presentation moves between docked and floating modal states.

#### Scenario: Modal update keeps same extension host continuity
- **WHEN** an extension pane remains the same pane identity while its content updates in a floating modal
- **THEN** OpenMUX preserves the host continuity for that pane instead of replacing it because the pane is modal

#### Scenario: Dock or undock preserves plugin action ownership
- **WHEN** an extension pane moves between a docked stack and a floating modal
- **THEN** the pane continues to validate plugin actions against the same owning plugin and pane identity
