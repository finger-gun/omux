## ADDED Requirements

### Requirement: Workspace rendering SHALL derive terminal surface visibility from shell state
The app shell SHALL derive the user-visible set of terminal panes from OpenMUX workspace, tab, pane-stack, floating modal, and window state during render reconciliation.

#### Scenario: Active workspace visible panes are visible
- **WHEN** a terminal pane is in the active workspace's visible tab or visible floating modal and the containing window is visible
- **THEN** the reconciled shell marks that pane's hosted terminal surface as user-visible

#### Scenario: Inactive workspace panes are hidden
- **WHEN** a terminal pane belongs to a workspace that is not the active workspace
- **THEN** the reconciled shell marks that pane's hosted terminal surface as not user-visible while leaving the pane and session in the workspace model

#### Scenario: Inactive pane-stack tabs are hidden
- **WHEN** a terminal pane is a non-focused pane tab inside a pane stack
- **THEN** the reconciled shell marks that pane's hosted terminal surface as not user-visible while preserving the pane tab state

#### Scenario: Window occlusion hides surfaces
- **WHEN** the containing OpenMUX window is minimized, hidden, or fully occluded
- **THEN** the reconciled shell marks hosted terminal surfaces in that window as not user-visible

### Requirement: Visibility reconciliation SHALL preserve stable pane hosts
Visibility updates SHALL reuse existing identity-stable pane hosts and SHALL NOT rebuild unrelated workspace subtrees merely to update terminal presentation visibility.

#### Scenario: Visibility-only update reuses terminal host
- **WHEN** a workspace switch changes which terminal panes are user-visible but pane identities and layout topology remain stable
- **THEN** OpenMUX updates hosted surface visibility without recreating unaffected terminal sessions or pane host views

#### Scenario: Reappearing pane keeps host continuity
- **WHEN** a terminal pane becomes visible again after being hidden by workspace or tab navigation
- **THEN** the same pane identity remains associated with its existing terminal session and host state

### Requirement: Visibility reconciliation SHALL stay bridge-safe
Workspace rendering SHALL express terminal surface visibility through OpenMUX pane identifiers and bridge APIs, not through terminal-engine layout or renderer types.

#### Scenario: Shell does not import terminal-engine occlusion details
- **WHEN** the shell reconciles visible and hidden terminal panes
- **THEN** it does not import or expose libghostty-specific occlusion, renderer, display-link, or surface types outside `OmuxTerminalBridge`
