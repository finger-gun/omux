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
