## 1. PaneCardView in-place mutation

- [x] 1.1 ~~Add `previousConfiguredHeaderView`/`previousConfiguredPaneView` stored properties~~ — not needed: `reconcileArrangedSubviews` compares against the live `container.arrangedSubviews` by identity, so no cached references are required
- [x] 1.2 Replace `container.arrangedSubviews.forEach { removeArrangedSubview; removeFromSuperview }` in `configure` with targeted in-place mutation: remove only views whose identity changed, update statusText in-place, add new views only when identity differs
- [x] 1.3 Ensure status label `stringValue` and `isHidden` are updated in-place regardless of view identity changes
- [x] 1.4 Verify `PaneStackView.update` still correctly passes the new header/renderer to `configure` after its own identity checks at lines 575-607

## 2. Key-window guard

- [x] 2.1 Add `lastRefreshedWorkspaceID: WorkspaceID?` stored property to `WorkspaceShellViewController`
- [x] 2.2 In `refreshTerminalPresentation(for:restoreFocusIfPossible:)`, store `workspace.id` as `lastRefreshedWorkspaceID` after successful refresh
- [x] 2.3 In `windowDidBecomeKey(_:)`, add a guard at the top: if `windowIsKey == true` AND `workspace.id == lastRefreshedWorkspaceID`, return immediately
- [x] 2.4 Apply the same guard to `windowDidResignKey`, `windowPresentationStateDidChange`, and `applicationPresentationStateDidChange` where appropriate — skip refresh when previous key state is already non-key

## 3. `update(workspace:)` short-circuit — DROPPED (unsafe & redundant)

> Removed during implementation. `update(workspace:)` is the single render entry
> point that also rebuilds the workspace sidebar, and the sidebar reflects state
> that is independent of the active workspace value: the workspace *list order*
> (`controller.allWorkspaces()` / `moveWorkspace`), per-workspace *collapse* flags
> (`collapsedWorkspaceIDs`, `isWorkspacesSectionCollapsed`), and *pane-metadata row
> overrides*. Short-circuiting on the active workspace (either `id`+`focusedTabID`
> as originally specified, or full value equality) drops these legitimate sidebar
> re-renders and regresses existing behavior (`testWorkspaceWindowReflectsReorderedWorkspaceSidebarOrder`,
> `testWorkspaceSidebarCollapseHidesPaneRowsUntilWorkspaceFocus`,
> `testWorkspaceWindowAppliesPaneMetadataRowOverridesInSidebar`).
>
> The hang is already resolved without this short-circuit: Task 1 removes the
> constraint-teardown storm at its root, Task 2's key-window guard prevents the
> redundant `refreshTerminalPresentation` that triggered the hang, and Task 4
> coalesces rapid presentation callbacks.

- [x] 3.1 ~~In `update(workspace:)`, short-circuit on unchanged workspace~~ — DROPPED: unsafe for the sidebar (see note above), redundant with Tasks 1/2/4
- [x] 3.2 ~~When short-circuiting, still reconcile surface visibility~~ — DROPPED with 3.1
- [x] 3.3 ~~Add `#if DEBUG` log when short-circuit fires~~ — DROPPED with 3.1

## 4. Runloop coalescing of presentation-state callbacks

- [x] 4.1 Add a `pendingPresentationRefresh: Bool` flag and a coalesced `refreshTerminalPresentation(for: Workspace, restoreFocusIfPossible: Bool)` method that sets the flag and defers execution
- [x] 4.2 Use `DispatchQueue.main.async` with a no-delay block to flush the deferred refresh at the end of the current runloop turn; guard against re-entry with the pending flag
- [x] 4.3 Wire `windowDidBecomeKey`, `windowDidResignKey`, `windowPresentationStateDidChange`, and `applicationPresentationStateDidChange` to use the coalesced method instead of calling `refreshTerminalPresentation` directly
- [x] 4.4 Ensure `windowDidBecomeKey` still sets `windowIsKey = true` immediately (synchronously) even when coalescing the refresh, so `currentTerminalSurfacePresentationState()` returns correct state

## 5. Regression tests

> The literal per-unit tests below were adapted during implementation. `PaneCardView.configure`
> is `fileprivate` and its `container` is `private`, so it cannot be exercised directly from the
> test module; and `PaneStackView.update` always creates a fresh `PaneHeaderView`, so the pane
> header identity always changes through the render path. Tests therefore drive the real render
> path (`WorkspaceWindowController.update`) and assert on observable view identity. Task 3's
> short-circuit was dropped (see section 3), so its dedicated tests (5.6, 5.7) are obsolete.

- [x] 5.1 Covered by existing `testWorkspaceWindowPresentationNotificationsRefreshRuntimeFocusAndResponder` (updated for coalescing) + Task 2 key-window guard
- [x] 5.2 Covered by existing multi-workspace refresh tests + Task 2 guard (guard keys on `lastRefreshedWorkspaceID`, so a new workspace still refreshes)
- [x] 5.3 `testNonStructuralUpdatePreservesTerminalRendererView` — non-structural update reuses the terminal renderer view in place instead of tearing it down
- [x] 5.4 Adapted: header is always recreated by `PaneStackView.update`; renderer reuse is covered by 5.3/5.5. `configure` is fileprivate so direct header-swap assertion is not reachable.
- [x] 5.5 `testNonStructuralUpdatePreservesTerminalRendererView` — renderer view identity preserved (and remains attached to the same container) across a non-structural update
- [x] 5.6 ~~short-circuit rebuild-once test~~ — obsolete (Task 3 dropped)
- [x] 5.7 ~~short-circuit still-reconciles-visibility test~~ — obsolete (Task 3 dropped)
- [x] 5.8 `testKeyWindowRefreshIsCoalescedToRunloopTurn` — multiple presentation notifications in one runloop turn coalesce; refresh is deferred (not applied synchronously) and yields a single `[true]` focus update after draining
- [x] 5.9 Covered by existing `testWorkspaceWindowPresentationNotificationsRefreshRuntimeFocusAndResponder` (drains the runloop between coalesced turns)

## 6. Verification

- [x] 6.1 `swift test --filter OmuxAppShellTests` — 283 tests, 0 failures (1 pre-existing skip)
- [x] 6.2 `swift build` — no new compiler warnings in `PaneViews.swift` / `WorkspaceShellViewController.swift`
- [ ] 6.3 Manual smoke test: launch OpenMUX, create multiple panes and splits, click away and back to window, verify no delay or beachball
- [ ] 6.4 Manual smoke test: test with extension panes (WKWebView), verify web content survives key-window transitions without reload
- [ ] 6.5 Verify keyboard focus is correctly restored when window becomes key after the guard/short-circuit changes
