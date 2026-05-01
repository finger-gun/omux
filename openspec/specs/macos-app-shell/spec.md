# macos-app-shell Specification

## Purpose
TBD - created by archiving change macos-foundation. Update Purpose after archive.

## Requirements

### Requirement: Native app shell owns workspace structure
The system SHALL provide a native macOS application shell that owns OpenMUX workspaces, windows, tabs, pane stacks, local pane tabs, and focus relationships independently of the terminal engine, even when each visible pane region hosts a real libghostty-backed terminal surface.

#### Scenario: Workspace structure is modeled in app-level terms
- **WHEN** a developer creates or manipulates workspace structure
- **THEN** the system represents that structure using OpenMUX-native concepts rather than raw terminal-engine objects

### Requirement: Terminal hosting uses AppKit-first integration
The system SHALL host terminal surfaces within an AppKit-first application shell, with SwiftUI limited to non-terminal chrome where it does not control terminal interaction semantics, and with real pane surfaces embedded as native AppKit-hosted views.

#### Scenario: Terminal surfaces stay in native view ownership
- **WHEN** a terminal pane is displayed in the desktop application
- **THEN** the terminal surface is hosted within an AppKit-owned interaction model that preserves native focus, menus, event routing, and accessibility expectations

### Requirement: App shell responsibilities remain separate from terminal rendering
The system SHALL keep shell responsibilities such as window lifecycle, pane layout, pane-stack chrome, focus management, notifications, and workspace orchestration separate from terminal rendering and PTY behavior, even when the shell hosts real libghostty-backed surfaces.

#### Scenario: Shell concerns do not require terminal-engine knowledge
- **WHEN** shell-level logic handles layout or focus behavior
- **THEN** that logic operates without requiring direct knowledge of terminal-engine internals

### Requirement: The native shell SHALL minimize non-terminal chrome
The native macOS shell SHALL prioritize pane space over decorative chrome by removing low-value persistent header UI and reducing nested card-like container treatment around terminal content. Pane-local headers MAY remain where needed for pane-tab navigation and pane context.

#### Scenario: Shell does not reserve a top header row
- **WHEN** a workspace window is shown
- **THEN** the main content region does not include the current persistent top header bar and that vertical space is available to pane content

#### Scenario: Pane content is not wrapped in stacked cards
- **WHEN** a terminal pane stack is rendered
- **THEN** the shell avoids multiple nested rounded bordered containers around the pane and keeps the pane header as the primary remaining pane-local chrome

### Requirement: The native shell SHALL support a collapsible workspace column
The native macOS shell SHALL allow the workspace navigation column to be shown or hidden at runtime without changing workspace model data, SHALL persist that visibility state across app restarts as OpenMUX-owned UI state, and SHALL expand the pane content area when the column is hidden.

#### Scenario: Hiding the workspace column expands pane space
- **WHEN** the user triggers the workspace-column toggle while a workspace window is focused
- **THEN** the workspace column collapses and the main pane region expands to use the reclaimed width

#### Scenario: Showing the workspace column restores navigation UI
- **WHEN** the user triggers the workspace-column toggle again
- **THEN** the workspace column becomes visible again without recreating the workspace model

#### Scenario: Sidebar visibility survives restart
- **WHEN** the user closes OpenMUX after hiding or showing the workspace column and later launches OpenMUX again
- **THEN** the workspace column visibility matches the last remembered OpenMUX UI state

### Requirement: The native shell SHALL visually integrate the titlebar with the shell
The native macOS shell SHALL use AppKit window configuration so the titlebar/background region visually blends with the shell instead of appearing as a separate contrasting strip above the workspace content.

#### Scenario: Window chrome reads as one shell surface
- **WHEN** a workspace window is displayed with the current theme
- **THEN** the titlebar region visually matches or blends with the shell background rather than presenting a separate default macOS band

### Requirement: Transparent titlebar preserves native double-click zoom
Workspace windows SHALL preserve native macOS double-click titlebar zoom/maximize behavior while using the transparent full-size-content titlebar appearance.

#### Scenario: Titlebar double-click requests window zoom
- **WHEN** the user double-clicks the workspace window titlebar or unified titlebar background region
- **THEN** OpenMUX invokes the native window zoom behavior for that window

#### Scenario: Titlebar appearance remains integrated
- **WHEN** a workspace window is displayed
- **THEN** the titlebar region remains visually integrated with the shell background

### Requirement: The native shell surfaces terminal action outcomes without surrendering shell ownership
The native macOS shell SHALL consume supported terminal action events and apply the resulting user-visible behavior through OpenMUX-owned shell state, pane chrome, and native host integrations rather than delegating shell ownership to the terminal engine.

#### Scenario: Pane title updates stay shell-owned
- **WHEN** OpenMUX receives a supported title-change terminal event for a pane
- **THEN** the native shell updates the corresponding pane or tab label through OpenMUX-owned shell state rather than letting the terminal engine own shell chrome directly

#### Scenario: Native host side effects stay shell-owned
- **WHEN** OpenMUX receives a supported terminal event requesting URL opening, a desktop notification, or bell behavior
- **THEN** the native shell performs the host-side behavior through macOS-native integrations while preserving OpenMUX ownership of workspace and pane structure

### Requirement: The native shell surfaces pane status from supported terminal events
The native macOS shell SHALL surface pane-local status for supported terminal events including progress, child-exited state, and renderer health so the user can understand terminal state from OpenMUX chrome.

#### Scenario: Pane shows terminal progress state
- **WHEN** OpenMUX receives a supported progress-report terminal event for a pane
- **THEN** the shell updates pane-owned status or chrome for that pane without requiring Ghostty-owned app UI

#### Scenario: Pane shows session-ended or unhealthy state
- **WHEN** OpenMUX receives a supported child-exited or renderer-health terminal event for a pane
- **THEN** the shell updates pane-owned status to reflect the ended or unhealthy session state
