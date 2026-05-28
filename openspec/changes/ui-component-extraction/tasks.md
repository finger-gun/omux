## 1. Extract `CountBadgeView`

- [x] 1.1 Create `Sources/OmuxAppShell/CountBadgeView.swift` and move the `CountBadgeView` class definition into it, removing `private` so it is `internal`
- [x] 1.2 Remove the `CountBadgeView` definition from `WorkspaceWindowController.swift`
- [x] 1.3 Build and confirm no compilation errors before proceeding

## 2. Extract `CollapsibleSectionHeaderView`

- [x] 2.1 Create `Sources/OmuxAppShell/CollapsibleSectionHeaderView.swift` and move the `CollapsibleSectionHeaderView` class definition into it, removing `private` so it is `internal`
- [x] 2.2 Remove the `CollapsibleSectionHeaderView` definition from `WorkspaceWindowController.swift`
- [x] 2.3 Build and verify no compilation errors; smoke-test that sidebar widget headers render correctly

## 3. Introduce `SidebarContainerView` base class

- [x] 3.1 Create `Sources/OmuxAppShell/SidebarContainerView.swift` with a concrete `SidebarContainerView: NSView` base class owning the shared width constraint, toggle/collapse infrastructure, and `apply(theme:)` hook
- [x] 3.2 Update `WorkspaceSidebarView` to inherit from `SidebarContainerView` and remove its now-redundant width constraint and toggle logic
- [x] 3.3 Build and verify no compilation errors; smoke-test the left sidebar toggles and renders correctly
- [x] 3.4 Update `WorkspaceVaultSidebarView` to inherit from `SidebarContainerView` and remove its now-redundant width constraint and toggle logic
- [x] 3.5 Build and verify no compilation errors; smoke-test the right sidebar toggles and renders correctly

## 4. Verify behavioral parity

- [ ] 4.1 Launch the app and confirm both sidebars toggle, resize via drag, and apply themes identically to pre-refactor behavior
- [ ] 4.2 Confirm all sidebar widget headers display titles, chevrons, and count badges correctly
- [ ] 4.3 Confirm collapsible sections expand and collapse as expected
- [ ] 4.4 Confirm no regressions in sidebar drag-resize coordination between left and right sidebars

## 5. Update specs and documentation

- [x] 5.1 Sync the delta spec for `workspace-window-shell-boundaries` by running `openspec sync --change ui-component-extraction` (or equivalent) to merge changes into `openspec/specs/`
- [x] 5.2 Review `docs/open-by-design.md` and confirm no hook, CLI, or control-plane coverage table entries are affected; update if needed

## 6. Extract shared UI utilities

- [x] 6.1 Create `Sources/OmuxAppShell/DraggableEventRelayView.swift` — merged `FloatingPaneModalHeaderView` and `FloatingPaneModalResizeHandleView` (identical drag-relay views) into one class
- [x] 6.2 Create `Sources/OmuxAppShell/NSScrollView+Sidebar.swift` — `configureSidebarScrollView()` + `makeSidebarScrollView()` replacing 3 verbatim scroll-view setup blocks
- [x] 6.3 Create `Sources/OmuxAppShell/NSViewController+ConfirmationAlert.swift` — `presentConfirmation(...)` helper replacing 5 `NSAlert` patterns
- [x] 6.4 Extract `togglePanelCollapsed(panelID:isCollapsed:)` private helper in `WorkspaceWindowController`, replacing 3 identical methods
- [x] 6.5 Extract `toggleSidebarPanel(panelID:isCollapsed:)` private helper replacing `toggleAgentSessionsPanel` and `toggleWorktreesPanel`
- [x] 6.6 Create `Sources/OmuxAppShell/NSView+TrackingArea.swift` — `replaceTrackingArea(_:options:)` extension
- [x] 6.7 Apply `replaceTrackingArea` to `TitleBarButton.updateTrackingAreas()`
- [x] 6.8 Add `private var hoverTrackingArea: NSTrackingArea?` to `ChromePillButton` and apply `replaceTrackingArea`
- [x] 6.9 Apply `replaceTrackingArea` to `WorktreeRowButton.updateTrackingAreas()`
- [x] 6.10 Create `Sources/OmuxAppShell/ThemedCardView.swift` — base class for `WorkspaceRestoreBannerView` and `AgentSessionPathMismatchModalView`; both views now inherit from it
- [x] 6.11 Create `Sources/OmuxAppShell/NSTextField+Label.swift` — `NSTextField.label(fontSize:weight:maxLines:)` factory extension
- [x] 6.12 Build clean after all above changes
