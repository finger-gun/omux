# workspace-state-write-coalescing Delta Specification

## ADDED Requirements

### Requirement: Presentation-state refresh callbacks SHALL be coalesced within a runloop turn
When multiple window or application presentation-state notifications (`NSWindow.didBecomeKeyNotification`, `NSWindow.didResignKeyNotification`, `NSWindow.didChangeOcclusionStateNotification`, `NSApplication.didBecomeActiveNotification`, `NSApplication.didResignActiveNotification`) fire within the same `CFRunLoop` turn, the resulting `refreshTerminalPresentation` calls SHALL be coalesced into at most one execution per turn.

#### Scenario: Three simultaneous presentation changes produce one refresh
- **WHEN** the app becomes active, the window becomes key, and the window occlusion state changes all within the same runloop turn
- **THEN** at most one `refreshTerminalPresentation` call is made, with the final presentation state derived from all three events

#### Scenario: Sequential runloop turns each fire independently
- **WHEN** the window becomes key in turn N and later becomes occluded in turn N+1 with no other events between them
- **THEN** two `refreshTerminalPresentation` calls are made, one per turn, since the presentation state genuinely changed between turns
