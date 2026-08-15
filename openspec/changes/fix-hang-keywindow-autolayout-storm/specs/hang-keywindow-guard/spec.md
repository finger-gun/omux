# hang-keywindow-guard Specification

## Purpose
Prevent redundant full workspace refresh when the OpenMUX window receives a key-window notification but nothing material changed since the last refresh.

## ADDED Requirements

### Requirement: Window DID become key SHALL skip refresh when workspace is unchanged
The shell SHALL NOT trigger a full `refreshTerminalPresentation` when `windowDidBecomeKey` fires and the window was already key with the same active workspace and presentation state as the previous refresh.

#### Scenario: Redundant key-window notification is suppressed
- **WHEN** `NSWindow.didBecomeKeyNotification` fires and `windowIsKey` is already `true` AND the active workspace ID matches the workspace ID used in the most recent `refreshTerminalPresentation` call
- **THEN** the shell returns immediately without calling `refreshTerminalPresentation`, `ensureVisibleTerminalSurfaces`, or `update(workspace:)`

#### Scenario: First key-window transition proceeds normally
- **WHEN** `NSWindow.didBecomeKeyNotification` fires and `windowIsKey` is `false`
- **THEN** the shell sets `windowIsKey = true` and calls `refreshTerminalPresentation` for the active workspace

#### Scenario: Key-window with new workspace proceeds normally
- **WHEN** `NSWindow.didBecomeKeyNotification` fires and `windowIsKey` is already `true` BUT the active workspace ID differs from the workspace ID last refreshed
- **THEN** the shell calls `refreshTerminalPresentation` for the active workspace

### Requirement: Multiple presentation-state changes in one runloop turn SHALL coalesce
When multiple window or application presentation-state notifications fire within the same runloop turn (e.g., window becomes key AND app becomes active simultaneously), the shell SHALL coalesce them into at most one `refreshTerminalPresentation` call per runloop turn.

#### Scenario: Simultaneous key-window and app-active notifications coalesce
- **WHEN** `windowDidBecomeKey` and `applicationDidBecomeActive` fire in the same runloop turn
- **THEN** at most one `refreshTerminalPresentation` is executed, using the final combined presentation state at the end of the turn

#### Scenario: Sequential notifications across different runloop turns each fire
- **WHEN** `windowDidBecomeKey` fires in one runloop turn and `applicationDidResignActive` fires in a later runloop turn
- **THEN** each notification triggers its own `refreshTerminalPresentation` call since the presentation state genuinely changed between turns
