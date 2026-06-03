import AppKit
import OmuxConfig
import OmuxCore
import QuartzCore

// MARK: - SidebarSplitView

/// A VSCode-style vertical split container for sidebar panels.
/// Panels are separated by draggable 4pt handles. The first panel is pinned to
/// the top, the last to the bottom. Collapsed panels shrink to `collapsedHeight`.
/// Expanded panels share remaining space proportionally; proportions are persisted.
/// Panels can be reordered by dragging their header row.
@MainActor
final class SidebarSplitView: NSView {

    static let separatorThickness: CGFloat = 4

    struct Panel {
        let view: NSView
        let collapsedHeight: CGFloat
        var isCollapsed: Bool
        var proportion: CGFloat
        var defaultsKey: String
        let panelID: String
        let headerView: CollapsibleSectionHeaderView?

        init(
            view: NSView,
            collapsedHeight: CGFloat,
            isCollapsed: Bool,
            proportion: CGFloat,
            defaultsKey: String,
            panelID: String,
            headerView: CollapsibleSectionHeaderView? = nil
        ) {
            self.view = view
            self.collapsedHeight = collapsedHeight
            self.isCollapsed = isCollapsed
            self.proportion = proportion
            self.defaultsKey = defaultsKey
            self.panelID = panelID
            self.headerView = headerView
        }

        var collapsedDefaultsKey: String {
            guard let dotRange = defaultsKey.range(of: ".", options: .backwards) else {
                return "\(panelID).collapsed"
            }
            return "\(defaultsKey[..<dotRange.lowerBound]).\(panelID)Collapsed"
        }
    }

    private var panels: [Panel] = []
    private var separators: [SidebarSeparatorView] = []
    private var theme: WorkspaceShellTheme = .defaultTheme

    // MARK: Widget reorder drag state
    private struct WidgetDragState {
        let sourcePanelIndex: Int
        let sourcePanelMinY: CGFloat   // stable Y captured at drag start, before any drop zone shifts
        var targetInsertionIndex: Int?
        weak var ghostView: NSView?
        let ghostHeight: CGFloat
        let dragOffset: NSPoint        // cursor offset from ghost origin at drag start
    }
    private var widgetDragState: WidgetDragState?
    private let dropZoneView = WidgetDropZoneView()

    /// Coordinator callbacks — set by `SidebarDragCoordinator` to intercept cross-sidebar drag.
    var onCoordinatorDragBegan: ((_ splitView: SidebarSplitView, _ panelIndex: Int, _ ghost: NSView, _ ghostHeight: CGFloat, _ dragOffset: NSPoint) -> Void)?
    var onCoordinatorDragMoved: ((_ splitView: SidebarSplitView, _ windowY: CGFloat, _ windowX: CGFloat) -> Void)?
    var onCoordinatorDragEnded: ((_ splitView: SidebarSplitView) -> Void)?
    var onPanelOrderChanged: (() -> Void)?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        dropZoneView.isHidden = true
        addSubview(dropZoneView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: Setup

    func setPanels(_ newPanels: [Panel]) {
        for sep in separators { sep.removeFromSuperview() }
        for p in panels { p.view.removeFromSuperview() }
        separators = []
        panels = newPanels

        for panel in panels {
            panel.view.translatesAutoresizingMaskIntoConstraints = true
            panel.view.autoresizingMask = []
            addSubview(panel.view)
        }

        // Bring drop zone to front so it renders above panel views.
        dropZoneView.removeFromSuperview()
        addSubview(dropZoneView)

        rebuildSeparators()
        rewireHeaderDragCallbacks()
        rebalanceProportions()
        needsLayout = true
    }

    private func rewireHeaderDragCallbacks() {
        for (i, panel) in panels.enumerated() {
            guard let header = panel.headerView else { continue }
            let idx = i
            header.onDragBegan = { [weak self] mouseDownPoint in
                self?.beginWidgetDrag(panelIndex: idx, mouseDownPoint: mouseDownPoint)
            }
            header.onDragMoved = { [weak self] windowPoint in
                self?.updateWidgetDrag(windowY: windowPoint.y, windowX: windowPoint.x)
            }
            header.onDragEnded = { [weak self] in
                self?.endWidgetDrag()
            }
        }
    }

    private func rebuildSeparators() {
        for sep in separators { sep.removeFromSuperview() }
        separators = []
        guard panels.count > 1 else {
            dropZoneView.removeFromSuperview()
            addSubview(dropZoneView)
            return
        }
        for i in 0 ..< (panels.count - 1) {
            let sep = SidebarSeparatorView()
            let idx = i
            sep.onDrag = { [weak self] delta in
                self?.handleDrag(separatorIndex: idx, delta: delta)
            }
            sep.apply(theme: theme)
            addSubview(sep)
            separators.append(sep)
        }
        // Keep drop zone on top.
        dropZoneView.removeFromSuperview()
        addSubview(dropZoneView)
    }

    func applyTheme(_ t: WorkspaceShellTheme) {
        theme = t
        for sep in separators { sep.apply(theme: t) }
        dropZoneView.apply(theme: t)
    }

    // MARK: Collapse

    func setCollapsed(_ collapsed: Bool, panelID: String) {
        guard let i = panels.firstIndex(where: { $0.panelID == panelID }) else { return }
        panels[i].isCollapsed = collapsed
        UserDefaults.standard.set(collapsed, forKey: panels[i].collapsedDefaultsKey)
        rebalanceProportions()
        needsLayout = true
    }

    var panelIDs: [String] { panels.map(\.panelID) }
    var currentPanels: [Panel] { panels }

    // MARK: Layout

    override func layout() {
        super.layout()
        applyFrames()
    }

    private func applyFrames() {
        let total = bounds.height
        let width = bounds.width
        let separatorSpace = CGFloat(separators.count) * Self.separatorThickness
        let collapsedSpace = panels.filter(\.isCollapsed).reduce(0) { $0 + $1.collapsedHeight }

        // Determine active insertion index and drop zone height from either
        // an internal widget drag or an external (cross-sidebar) drag.
        let activeInsertionIdx: Int?
        let activeDropZoneHeight: CGFloat
        if let dragState = widgetDragState, let idx = dragState.targetInsertionIndex {
            activeInsertionIdx = idx
            activeDropZoneHeight = dragState.ghostHeight
        } else if let extState = externalDragState, let idx = extState.targetInsertionIndex {
            activeInsertionIdx = idx
            activeDropZoneHeight = extState.ghostHeight
        } else {
            activeInsertionIdx = nil
            activeDropZoneHeight = 0
        }

        guard let insertionIdx = activeInsertionIdx else {
            // No active drag — normal layout, drop zone hidden.
            dropZoneView.isHidden = true
            let flexibleSpace = max(0, total - separatorSpace - collapsedSpace)
            var y: CGFloat = 0
            for (i, panel) in panels.enumerated() {
                let h: CGFloat = panel.isCollapsed ? panel.collapsedHeight : (flexibleSpace * panel.proportion).rounded()
                panel.view.frame = NSRect(x: 0, y: y, width: width, height: h)
                y += h
                if i < separators.count {
                    separators[i].frame = NSRect(x: 0, y: y, width: width, height: Self.separatorThickness)
                    y += Self.separatorThickness
                }
            }
            return
        }

        // Active drag: insert the drop zone into the flow at insertionIdx,
        // pushing real panels aside so the highlight occupies real space.
        let dropZoneHeight = activeDropZoneHeight
        let flexibleSpace = max(0, total - separatorSpace - collapsedSpace - dropZoneHeight)

        var y: CGFloat = 0
        for (i, panel) in panels.enumerated() {
            if i == insertionIdx {
                dropZoneView.frame = NSRect(x: 0, y: y, width: width, height: dropZoneHeight)
                dropZoneView.isHidden = false
                y += dropZoneHeight
            }
            let h: CGFloat = panel.isCollapsed ? panel.collapsedHeight : (flexibleSpace * panel.proportion).rounded()
            panel.view.frame = NSRect(x: 0, y: y, width: width, height: h)
            y += h
            if i < separators.count {
                separators[i].frame = NSRect(x: 0, y: y, width: width, height: Self.separatorThickness)
                y += Self.separatorThickness
            }
        }
        // Insertion after last panel.
        if insertionIdx >= panels.count {
            dropZoneView.frame = NSRect(x: 0, y: y, width: width, height: dropZoneHeight)
            dropZoneView.isHidden = false
        }
    }

    // MARK: Resize drag

    private func handleDrag(separatorIndex: Int, delta: CGFloat) {
        let aboveIdx = separatorIndex
        let belowIdx = separatorIndex + 1
        guard aboveIdx < panels.count, belowIdx < panels.count else { return }
        var above = panels[aboveIdx]
        var below = panels[belowIdx]
        guard !above.isCollapsed, !below.isCollapsed else { return }

        let separatorSpace = CGFloat(separators.count) * Self.separatorThickness
        let collapsedSpace = panels.filter(\.isCollapsed).reduce(0) { $0 + $1.collapsedHeight }
        let flexibleSpace = max(1, bounds.height - separatorSpace - collapsedSpace)

        let proportionDelta = delta / flexibleSpace
        let minProportion = 28 / flexibleSpace
        let newAbove = (above.proportion + proportionDelta).clamped(to: minProportion ... (above.proportion + below.proportion - minProportion))
        let newBelow = above.proportion + below.proportion - newAbove

        above.proportion = newAbove
        below.proportion = newBelow
        panels[aboveIdx] = above
        panels[belowIdx] = below

        persistProportions()
        needsLayout = true
    }

    // MARK: Widget reorder drag

    private func beginWidgetDrag(panelIndex: Int, mouseDownPoint: NSPoint) {
        let sourceView = panels[panelIndex].headerView ?? panels[panelIndex].view
        let ghost = makeWidgetDragGhost(for: sourceView)
        let ghostHeight = sourceView.bounds.height

        // Compute the offset from the ghost's origin (in contentView coords) to the
        // mousedown point (in window coords), so the ghost stays pinned under the
        // exact spot the user clicked rather than recentering on the cursor.
        var dragOffset = NSPoint.zero
        if let ghost, let contentView = ghost.superview {
            let mouseInContent = contentView.convert(mouseDownPoint, from: nil)
            dragOffset = NSPoint(
                x: mouseInContent.x - ghost.frame.origin.x,
                y: mouseInContent.y - ghost.frame.origin.y
            )
        }

        widgetDragState = WidgetDragState(
            sourcePanelIndex: panelIndex,
            sourcePanelMinY: panels[panelIndex].view.frame.minY,
            targetInsertionIndex: nil,
            ghostView: ghost,
            ghostHeight: ghostHeight,
            dragOffset: dragOffset
        )
        if let ghost {
            onCoordinatorDragBegan?(self, panelIndex, ghost, ghostHeight, dragOffset)
        }
        updateDropZone()
    }

    private func updateWidgetDrag(windowY: CGFloat, windowX: CGFloat) {
        // Always forward to the coordinator — it needs move events even after
        // abortInternalDrag has cleared widgetDragState (i.e. during cross-sidebar drag).
        onCoordinatorDragMoved?(self, windowY, windowX)

        guard var dragState = widgetDragState else { return }
        let localY = convert(NSPoint(x: 0, y: windowY), from: nil).y
        dragState.targetInsertionIndex = insertionIndex(for: localY, excluding: dragState.sourcePanelIndex)
        widgetDragState = dragState
        updateWidgetDragGhost(dragState.ghostView, windowY: windowY, windowX: windowX, dragOffset: dragState.dragOffset)
        updateDropZone()
    }

    /// Abort the internal drag without committing a reorder. Used by the coordinator
    /// when it takes over cross-sidebar routing. The ghost is intentionally NOT removed
    /// here — the coordinator still holds the strong reference and will remove it on drop.
    func abortInternalDrag() {
        widgetDragState = nil
        needsLayout = true
    }

    private func endWidgetDrag() {
        onCoordinatorDragEnded?(self)
        defer {
            widgetDragState?.ghostView?.removeFromSuperview()
            widgetDragState = nil
            needsLayout = true
        }
        guard let dragState = widgetDragState, var dst = dragState.targetInsertionIndex else { return }
        let src = dragState.sourcePanelIndex
        var reordered = panels
        let moved = reordered.remove(at: src)
        if dst > src { dst -= 1 }
        reordered.insert(moved, at: dst)
        panels = reordered
        rebuildSeparators()
        rewireHeaderDragCallbacks()
        equalizeProportions()
        needsLayout = true
        onPanelOrderChanged?()
    }

    // MARK: Cross-sidebar drag API

    /// Called by `SidebarDragCoordinator` when a drag enters this split view.
    /// Pass `excludedPanelID` when the dragged panel still lives here (source sidebar re-entry)
    /// so its own adjacent slots are suppressed.
    func beginExternalDrag(ghost: NSView, panel: Panel, ghostHeight: CGFloat, excludedPanelID: String? = nil) {
        externalDragState = ExternalDragState(
            panel: panel,
            ghostView: ghost,
            ghostHeight: ghostHeight,
            targetInsertionIndex: nil,
            excludedPanelID: excludedPanelID
        )
    }

    /// Updates the drop-zone position as the ghost moves (windowY is in window coordinates).
    func updateExternalDrag(windowY: CGFloat) {
        guard var state = externalDragState else { return }
        let localY = convert(NSPoint(x: 0, y: windowY), from: nil).y
        state.targetInsertionIndex = externalInsertionIndex(for: localY)
        externalDragState = state
        needsLayout = true
    }

    /// Commits the cross-sidebar drop. Removes the panel from the source split view
    /// and inserts it here. Returns the migrated panel (with updated defaultsKey) or nil.
    @discardableResult
    func acceptExternalDrop(sidebarNamespace: String) -> Panel? {
        defer {
            externalDragState = nil
            needsLayout = true
        }
        guard let state = externalDragState else { return nil }
        var panel = state.panel
        // Re-key proportion and collapsed defaults into the target sidebar namespace.
        panel.defaultsKey = "\(sidebarNamespace).\(panel.panelID)Proportion"
        UserDefaults.standard.set(panel.isCollapsed, forKey: panel.collapsedDefaultsKey)
        let insertionIdx = state.targetInsertionIndex ?? panels.count
        panels.insert(panel, at: min(insertionIdx, panels.count))
        rebuildSeparators()
        rewireHeaderDragCallbacks()
        equalizeProportions()
        needsLayout = true
        return panel
    }

    /// Cancels an in-progress external drag without committing any insertion.
    func cancelExternalDrag() {
        externalDragState = nil
        needsLayout = true
    }

    /// Commits the cross-sidebar drop using the real `panel` (which has a real view).
    /// The external drag state must already be active and contain the computed insertion index.
    func finishExternalDropWithPanel(_ panel: Panel, sidebarNamespace: String) {
        defer {
            externalDragState = nil
            needsLayout = true
        }
        let insertionIdx = externalDragState?.targetInsertionIndex ?? panels.count
        var newPanel = panel
        newPanel.defaultsKey = "\(sidebarNamespace).\(panel.panelID)Proportion"
        UserDefaults.standard.set(newPanel.isCollapsed, forKey: newPanel.collapsedDefaultsKey)
        newPanel.view.translatesAutoresizingMaskIntoConstraints = true
        newPanel.view.autoresizingMask = []
        addSubview(newPanel.view)
        // Bring drop zone to front.
        dropZoneView.removeFromSuperview()
        addSubview(dropZoneView)
        panels.insert(newPanel, at: min(insertionIdx, panels.count))
        rebuildSeparators()
        rewireHeaderDragCallbacks()
        equalizeProportions()
        needsLayout = true
    }

    /// Removes the panel with the given panelID and returns it. Used by the coordinator
    /// before transferring the panel to the target split view.
    func extractPanel(panelID: String) -> Panel? {
        guard let idx = panels.firstIndex(where: { $0.panelID == panelID }) else { return nil }
        let panel = panels.remove(at: idx)
        panel.view.removeFromSuperview()
        rebuildSeparators()
        rewireHeaderDragCallbacks()
        equalizeProportions()
        needsLayout = true
        return panel
    }

    // MARK: External drag layout support

    private struct ExternalDragState {
        var panel: Panel
        weak var ghostView: NSView?
        let ghostHeight: CGFloat
        var targetInsertionIndex: Int?
        var excludedPanelID: String?   // when set, slots adjacent to this panel are suppressed
    }
    private var externalDragState: ExternalDragState?

    private func externalInsertionIndex(for localY: CGFloat) -> Int? {
        guard !panels.isEmpty else { return 0 }

        // If a panel is excluded (e.g. dragging back to source sidebar where the panel
        // still lives), suppress the slots immediately above and below it.
        let excludedIndex: Int?
        if let id = externalDragState?.excludedPanelID {
            excludedIndex = panels.firstIndex(where: { $0.panelID == id })
        } else {
            excludedIndex = nil
        }

        func isValidSlot(_ slot: Int) -> Bool {
            guard let ex = excludedIndex else { return true }
            return slot != ex && slot != ex + 1
        }

        // Check slot 0: above or within the top threshold of the first panel.
        let firstMinY = panels[0].view.frame.minY
        if localY <= firstMinY + 34 && isValidSlot(0) { return 0 }

        // Check between-panel slots.
        for slot in 1 ..< panels.count {
            let above = panels[slot - 1].view.frame.maxY
            let below = panels[slot].view.frame.minY
            let mid = (above + below) / 2
            let upperThreshold = panels[slot - 1].view.frame.maxY - 34
            let lowerThreshold = panels[slot].view.frame.minY + 34
            if localY >= upperThreshold && localY <= lowerThreshold {
                let candidate = localY <= mid ? slot - 1 : slot
                return isValidSlot(candidate) ? candidate : nil
            }
        }

        // Check slot after last panel.
        let lastMaxY = panels[panels.count - 1].view.frame.maxY
        if localY >= lastMaxY - 34 && isValidSlot(panels.count) { return panels.count }

        return nil
    }

    private func makeWidgetDragGhost(for panelView: NSView) -> NSView? {
        guard let contentView = window?.contentView else { return nil }
        let size = panelView.bounds.size
        guard size.width > 0, size.height > 0 else { return nil }

        let snapshot = NSImage(size: size, flipped: false) { [weak panelView] _ in
            guard let layer = panelView?.layer else { return false }
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            layer.render(in: ctx)
            return true
        }

        let ghost = NSImageView(image: snapshot)
        ghost.wantsLayer = true
        ghost.layer?.opacity = 0.82
        ghost.layer?.cornerRadius = 3
        ghost.layer?.shadowOpacity = 0.28
        ghost.layer?.shadowRadius = 10
        ghost.layer?.shadowColor = NSColor.black.cgColor
        ghost.layer?.shadowOffset = CGSize(width: 0, height: -3)

        ghost.frame = panelView.convert(panelView.bounds, to: nil)
        contentView.addSubview(ghost, positioned: .above, relativeTo: nil)
        return ghost
    }

    private func updateWidgetDragGhost(_ ghost: NSView?, windowY: CGFloat, windowX: CGFloat, dragOffset: NSPoint) {
        guard let ghost, let contentView = ghost.superview else { return }
        let local = contentView.convert(NSPoint(x: windowX, y: windowY), from: nil)
        ghost.frame.origin.x = local.x - dragOffset.x
        ghost.frame.origin.y = local.y - dragOffset.y
    }

    /// Returns the insertion index (0 = before panel 0, n = after last panel)
    /// only when the cursor is within the activation zone of a valid slot.
    /// Each slot activates when the cursor is in the outer quarter of an adjacent panel.
    /// Returns nil when the cursor is in the middle of a panel (no active drop zone).
    private func insertionIndex(for localY: CGFloat, excluding src: Int) -> Int? {
        let validSlots = Set((0 ... panels.count).filter { $0 != src && $0 != src + 1 })
        guard !validSlots.isEmpty else { return nil }

        // Activate the slot when the cursor gets within one header-height of the
        // panel boundary, so the drop zone appears as the dragged widget approaches
        // the other panel — not immediately on drag start.
        let proximityThreshold: CGFloat = 34   // one collapsed header height

        if src + 2 <= panels.count {
            var candidateSlot: Int?
            for slot in (src + 2) ... panels.count where validSlots.contains(slot) {
                let previous = panels[slot - 1]
                let previousHeight = previous.isCollapsed ? previous.collapsedHeight : previous.view.frame.height
                let boundary = previous.view.frame.minY + previousHeight
                if localY > boundary - proximityThreshold {
                    candidateSlot = slot
                }
            }
            if let candidateSlot {
                return candidateSlot
            }
        }

        if src > 0 {
            var candidateSlot: Int?
            for slot in stride(from: src - 1, through: 0, by: -1) where validSlots.contains(slot) {
                let boundary = panels[slot].view.frame.minY
                if localY < boundary + proximityThreshold {
                    candidateSlot = slot
                }
            }
            if let candidateSlot {
                return candidateSlot
            }
        }
        return nil
    }

    private func updateDropZone() {
        needsLayout = true
    }

    // MARK: Proportion management

    /// Normalizes proportions so expanded panels fill exactly 1.0 total, preserving relative ratios.
    private func rebalanceProportions() {
        let expandedIndices = panels.indices.filter { !panels[$0].isCollapsed }
        guard !expandedIndices.isEmpty else { return }
        let currentSum = expandedIndices.reduce(0.0) { $0 + panels[$1].proportion }
        if currentSum < 0.001 {
            let share = 1.0 / CGFloat(expandedIndices.count)
            for i in expandedIndices { panels[i].proportion = share }
        } else {
            for i in expandedIndices { panels[i].proportion /= currentSum }
        }
        persistProportions()
    }

    /// Gives each expanded panel an equal proportion. Used after a reorder so that
    /// swapped proportions don't cause unexpected size changes.
    private func equalizeProportions() {
        let expandedIndices = panels.indices.filter { !panels[$0].isCollapsed }
        guard !expandedIndices.isEmpty else { return }
        let share = 1.0 / CGFloat(expandedIndices.count)
        for i in expandedIndices { panels[i].proportion = share }
        persistProportions()
    }

    private func persistProportions() {
        for panel in panels {
            UserDefaults.standard.set(Double(panel.proportion), forKey: panel.defaultsKey)
            UserDefaults.standard.set(panel.isCollapsed, forKey: panel.collapsedDefaultsKey)
        }
    }
}


// MARK: - SidebarDragCoordinator

/// Coordinates cross-sidebar widget drag between the left (`leftSplit`) and right (`rightSplit`)
/// `SidebarSplitView` instances. The coordinator intercepts drag callbacks from both split views
/// and routes cross-boundary drags to the other split view.
@MainActor
final class SidebarDragCoordinator {

    private struct CrossSidebarDragState {
        let sourceSplit: SidebarSplitView
        let sourceNamespace: String
        let panelID: String
        weak var ghost: NSView?
        let ghostHeight: CGFloat
        let dragOffset: NSPoint
        var crossSidebarActive: Bool = false
        var currentTargetSplit: SidebarSplitView?
    }

    private weak var leftSplit: SidebarSplitView?
    private weak var rightSplit: SidebarSplitView?
    private weak var leftSidebarView: NSView?
    private weak var rightSidebarView: NSView?
    private var crossDragState: CrossSidebarDragState?

    // Called after cross-sidebar drop to let the shell re-persist panel order.
    var onPanelOrderChanged: (() -> Void)?

    init(
        leftSplit: SidebarSplitView,
        rightSplit: SidebarSplitView,
        leftSidebarView: NSView,
        rightSidebarView: NSView
    ) {
        self.leftSplit = leftSplit
        self.rightSplit = rightSplit
        self.leftSidebarView = leftSidebarView
        self.rightSidebarView = rightSidebarView
        wireCallbacks()
    }

    private func wireCallbacks() {
        guard let leftSplit, let rightSplit else { return }

        leftSplit.onCoordinatorDragBegan = { [weak self] split, panelIndex, ghost, ghostHeight, dragOffset in
            self?.handleDragBegan(split: split, panelIndex: panelIndex, ghost: ghost, ghostHeight: ghostHeight, dragOffset: dragOffset)
        }
        leftSplit.onCoordinatorDragMoved = { [weak self] split, windowY, windowX in
            self?.handleDragMoved(split: split, windowY: windowY, windowX: windowX)
        }
        leftSplit.onCoordinatorDragEnded = { [weak self] split in
            self?.handleDragEnded(split: split)
        }

        rightSplit.onCoordinatorDragBegan = { [weak self] split, panelIndex, ghost, ghostHeight, dragOffset in
            self?.handleDragBegan(split: split, panelIndex: panelIndex, ghost: ghost, ghostHeight: ghostHeight, dragOffset: dragOffset)
        }
        rightSplit.onCoordinatorDragMoved = { [weak self] split, windowY, windowX in
            self?.handleDragMoved(split: split, windowY: windowY, windowX: windowX)
        }
        rightSplit.onCoordinatorDragEnded = { [weak self] split in
            self?.handleDragEnded(split: split)
        }
    }

    private func handleDragBegan(split: SidebarSplitView, panelIndex: Int, ghost: NSView, ghostHeight: CGFloat, dragOffset: NSPoint) {
        let sourceNamespace = (split === leftSplit) ? "omux.leftSidebar" : "omux.rightSidebar"
        let panelID = split.panelIDs[panelIndex]
        crossDragState = CrossSidebarDragState(
            sourceSplit: split,
            sourceNamespace: sourceNamespace,
            panelID: panelID,
            ghost: ghost,
            ghostHeight: ghostHeight,
            dragOffset: dragOffset,
            currentTargetSplit: nil
        )
    }

    private func handleDragMoved(split: SidebarSplitView, windowY: CGFloat, windowX: CGFloat) {
        guard var state = crossDragState else { return }

        let targetSplit = sidebarSplit(at: windowX)

        if let targetSplit, targetSplit !== state.sourceSplit {
            // Cursor is inside the opposite sidebar.
            if !state.crossSidebarActive {
                // First cross: abort the source's internal drag and enter cross-sidebar mode.
                state.sourceSplit.abortInternalDrag()
                state.crossSidebarActive = true
            }
            if state.currentTargetSplit !== targetSplit {
                state.currentTargetSplit?.cancelExternalDrag()
                targetSplit.beginExternalDrag(
                    ghost: NSView(), // placeholder; ghost managed by coordinator
                    panel: SidebarSplitView.Panel(
                        view: NSView(),
                        collapsedHeight: 34,
                        isCollapsed: false,
                        proportion: 0,
                        defaultsKey: "",
                        panelID: state.panelID
                    ),
                    ghostHeight: state.ghostHeight
                )
                state.currentTargetSplit = targetSplit
            }
            state.currentTargetSplit?.updateExternalDrag(windowY: windowY)
        } else if state.crossSidebarActive {
            if targetSplit === state.sourceSplit {
                // Cursor moved back into source sidebar — show drop zones there.
                if state.currentTargetSplit !== state.sourceSplit {
                    state.currentTargetSplit?.cancelExternalDrag()
                    state.sourceSplit.beginExternalDrag(
                        ghost: NSView(),
                        panel: SidebarSplitView.Panel(
                            view: NSView(),
                            collapsedHeight: 34,
                            isCollapsed: false,
                            proportion: 0,
                            defaultsKey: "",
                            panelID: state.panelID
                        ),
                        ghostHeight: state.ghostHeight,
                        excludedPanelID: state.panelID   // panel still lives here; suppress its own slots
                    )
                    state.currentTargetSplit = state.sourceSplit
                }
                state.currentTargetSplit?.updateExternalDrag(windowY: windowY)
            } else {
                // Cursor is in the dead zone between sidebars — cancel any active drop zone.
                state.currentTargetSplit?.cancelExternalDrag()
                state.currentTargetSplit = nil
            }
        }

        // Move the ghost to follow the cursor. Once crossSidebarActive the source split's
        // updateWidgetDragGhost is no longer running (abortInternalDrag cleared it), so the
        // coordinator owns ghost movement. We update here — after crossSidebarActive may have
        // just been set — so the ghost moves on the very first crossing frame too.
        if state.crossSidebarActive, let ghost = state.ghost, let contentView = ghost.superview {
            let local = contentView.convert(NSPoint(x: windowX, y: windowY), from: nil)
            ghost.frame.origin.x = local.x - state.dragOffset.x
            ghost.frame.origin.y = local.y - state.dragOffset.y
        }

        crossDragState = state
    }

    private func handleDragEnded(split: SidebarSplitView) {
        guard let state = crossDragState else { return }
        crossDragState = nil

        // Always clean up the ghost regardless of where the drop lands.
        defer { state.ghost?.removeFromSuperview() }

        guard state.crossSidebarActive else {
            // Never left the source sidebar — normal same-sidebar reorder handled by the split view.
            return
        }

        guard let targetSplit = state.currentTargetSplit else {
            // Released in the dead zone between sidebars. Panel is still in the source,
            // cancel any lingering external drag state and bail.
            state.sourceSplit.cancelExternalDrag()
            return
        }

        // Extract the real panel from the source split view (still there, abortInternalDrag
        // only cleared widgetDragState, it didn't remove the panel).
        guard var panel = state.sourceSplit.extractPanel(panelID: state.panelID) else {
            targetSplit.cancelExternalDrag()
            return
        }

        let targetNamespace = (targetSplit === leftSplit) ? "omux.leftSidebar" : "omux.rightSidebar"
        panel.defaultsKey = "\(targetNamespace).\(panel.panelID)Proportion"
        UserDefaults.standard.set(panel.isCollapsed, forKey: panel.collapsedDefaultsKey)

        targetSplit.finishExternalDropWithPanel(panel, sidebarNamespace: targetNamespace)
        onPanelOrderChanged?()
    }

    /// Returns the split view whose sidebar view contains `windowX`, or nil.
    private func sidebarSplit(at windowX: CGFloat) -> SidebarSplitView? {
        if let leftView = leftSidebarView {
            let rect = leftView.convert(leftView.bounds, to: nil)
            if rect.contains(NSPoint(x: windowX, y: rect.midY)) { return leftSplit }
        }
        if let rightView = rightSidebarView {
            let rect = rightView.convert(rightView.bounds, to: nil)
            if rect.contains(NSPoint(x: windowX, y: rect.midY)) { return rightSplit }
        }
        return nil
    }
}


// MARK: - SidebarSeparatorView

@MainActor
private final class SidebarSeparatorView: NSView {
    var onDrag: ((CGFloat) -> Void)?
    private let line = NSView()
    private var dragOrigin: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = true
        autoresizingMask = []
        wantsLayer = true

        line.translatesAutoresizingMaskIntoConstraints = false
        line.wantsLayer = true
        addSubview(line)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: leadingAnchor),
            line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.centerYAnchor.constraint(equalTo: centerYAnchor),
            line.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func apply(theme: WorkspaceShellTheme) {
        line.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        dragOrigin = event.locationInWindow.y
    }

    override func mouseDragged(with event: NSEvent) {
        // locationInWindow.y increases upward in screen space.
        // Dragging down → y decreases → delta negative → above panel shrinks.
        // We want drag-down to grow the above panel, so negate.
        let delta = -(event.locationInWindow.y - dragOrigin)
        dragOrigin = event.locationInWindow.y
        onDrag?(delta)
    }
}

// MARK: - WidgetDropZoneView

/// A horizontal highlight band rendered in `SidebarSplitView` during a widget
/// reorder drag. It sits between panels to show where the dragged widget will land.
@MainActor
private final class WidgetDropZoneView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 2
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var mouseDownCanMoveWindow: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func apply(theme: WorkspaceShellTheme) {
        layer?.backgroundColor = theme.shell.selection.withAlphaComponent(0.35).cgColor
        layer?.borderColor = theme.shell.selection.withAlphaComponent(0.8).cgColor
        layer?.borderWidth = 1.5
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private extension Double {
    /// Returns nil if the value is zero (for UserDefaults default-value detection).
    var nonZero: Double? { self == 0 ? nil : self }
}
