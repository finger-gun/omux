# floating-pane-modals Specification

## Purpose
TBD - created by archiving change add-floating-pane-modals. Update Purpose after archive.

## Requirements
### Requirement: Floating pane modals SHALL be shell-owned pane presentations
The system SHALL provide a shell-owned floating modal presentation that can host OpenMUX pane content above the workspace canvas without routing that presentation through `OmuxTerminalBridge` or plugin-owned windowing code.

#### Scenario: Plugin pane opens in floating modal
- **WHEN** OpenMUX receives an extension-pane create request with modal presentation
- **THEN** the shell creates a floating modal container for that pane content inside the workspace window

#### Scenario: Terminal bridge stays presentation-agnostic
- **WHEN** a pane is shown in a floating modal
- **THEN** the modal container is created by shell-owned view logic and SHALL NOT introduce libghostty-specific modal APIs into workspace or plugin contracts

### Requirement: Floating pane modals SHALL preserve pane identity across presentation changes
The system SHALL preserve the pane ID, plugin ownership, source metadata, and host continuity of pane content when that pane moves between docked workspace presentation and floating modal presentation.

#### Scenario: Docked extension pane moves to modal
- **WHEN** an existing extension pane is moved from a docked pane stack into a floating modal
- **THEN** the same pane ID remains associated with the pane after the move

#### Scenario: Floating pane returns to docked layout
- **WHEN** a pane currently shown in a floating modal is docked back into a workspace pane stack
- **THEN** OpenMUX restores that same pane into the target stack instead of closing it and creating a replacement pane

### Requirement: Floating pane modals SHALL manage focus and dismissal explicitly
The system SHALL manage floating modal focus, dismissal, and focus restoration through explicit shell-side responder handling so modal interactions do not leak text input to terminal panes behind the modal.

#### Scenario: Modal focus isolates terminal input
- **WHEN** a floating modal is focused and the user types text, uses IME composition, or enters dead-key sequences
- **THEN** the modal host handles that input and SHALL NOT send the text to a background terminal pane

#### Scenario: Dismissing modal restores prior focus
- **WHEN** a user dismisses a floating modal that was opened above a focused workspace pane
- **THEN** OpenMUX restores focus to the prior eligible pane without changing terminal keyboard semantics
