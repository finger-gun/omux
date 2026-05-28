import AppKit
import OmuxConfig
import OmuxControlPlane
import OmuxCore
import OmuxTerminalBridge
import OmuxVault
import QuartzCore

final class WorkspaceCanvasView: NSView {
    private var currentContentView: NSView?
    private var rootSplitPreview: PaneSplitPreviewView?

    var currentLayoutView: NSView? {
        currentContentView
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        setAccessibilityRole(.group)
        setAccessibilityElement(true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func apply(theme: WorkspaceShellTheme) {
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderWidth = 0
    }

    func render(layoutView: NSView?, theme: WorkspaceShellTheme) {
        apply(theme: theme)
        currentContentView?.removeFromSuperview()
        currentContentView = nil

        guard let layoutView else {
            return
        }

        layoutView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(layoutView)
        currentContentView = layoutView
        NSLayoutConstraint.activate([
            layoutView.topAnchor.constraint(equalTo: topAnchor, constant: ShellLayoutMetrics.canvasPadding),
            layoutView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ShellLayoutMetrics.canvasPadding),
            layoutView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -ShellLayoutMetrics.canvasPadding),
            layoutView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -ShellLayoutMetrics.canvasPadding),
        ])
    }

    func setRootSplitPreview(_ direction: PaneSplitDropDirection, theme: WorkspaceShellTheme) {
        if rootSplitPreview == nil {
            let preview = PaneSplitPreviewView()
            addSubview(preview, positioned: NSWindow.OrderingMode.above, relativeTo: nil)
            rootSplitPreview = preview
        }
        rootSplitPreview?.update(direction: direction, theme: theme, in: bounds)
    }

    func clearRootSplitPreview() {
        rootSplitPreview?.removeFromSuperview()
        rootSplitPreview = nil
    }
}

@MainActor
final class SplitLayoutView: NSView {
    private struct DragState {
        let dividerIndex: Int
        let initialLocation: CGFloat
        let initialLengths: [CGFloat]
    }

    private let axis: PaneSplitAxis
    private var childPaneIDs: [PaneID]
    private let onResize: ([PaneID], [Double]) -> Void
    private var desiredProportions: [Double]
    private var dividerRects: [NSRect] = []
    private var dividerHitRects: [NSRect] = []
    private var dragState: DragState?

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    init(
        axis: PaneSplitAxis,
        proportions: [Double],
        childPaneIDs: [PaneID],
        onResize: @escaping ([PaneID], [Double]) -> Void
    ) {
        self.axis = axis
        self.childPaneIDs = childPaneIDs
        self.onResize = onResize
        self.desiredProportions = Self.normalizedProportions(proportions, count: childPaneIDs.count)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .vertical)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        applyLayout()
    }

    var childLayoutViews: [NSView] {
        subviews
    }

    func canReconcile(axis: PaneSplitAxis, childCount: Int) -> Bool {
        self.axis == axis && subviews.count == childCount
    }

    func updateLayout(proportions: [Double], childPaneIDs: [PaneID]) {
        self.childPaneIDs = childPaneIDs
        desiredProportions = Self.normalizedProportions(proportions, count: childPaneIDs.count)
        needsLayout = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.black.withAlphaComponent(0.35).setFill()
        for rect in dividerRects where dirtyRect.intersects(rect) {
            rect.fill()
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        let cursor: NSCursor = axis == .columns ? .resizeLeftRight : .resizeUpDown
        dividerHitRects.forEach { addCursorRect($0, cursor: cursor) }
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        guard let dividerIndex = dividerHitRects.firstIndex(where: { $0.contains(location) }) else {
            return
        }

        dragState = DragState(
            dividerIndex: dividerIndex,
            initialLocation: primaryCoordinate(of: location),
            initialLengths: currentLengths()
        )
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragState else {
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        let delta = primaryCoordinate(of: location) - dragState.initialLocation
        let leadingIndex = dragState.dividerIndex
        let trailingIndex = leadingIndex + 1
        guard dragState.initialLengths.indices.contains(leadingIndex),
              dragState.initialLengths.indices.contains(trailingIndex)
        else {
            return
        }

        let minimumLeading = minimumPrimaryExtent(ofSubviewAt: leadingIndex)
        let minimumTrailing = minimumPrimaryExtent(ofSubviewAt: trailingIndex)
        let minimumDelta = minimumLeading - dragState.initialLengths[leadingIndex]
        let maximumDelta = dragState.initialLengths[trailingIndex] - minimumTrailing
        let clampedDelta = min(max(delta, minimumDelta), maximumDelta)

        var updatedLengths = dragState.initialLengths
        updatedLengths[leadingIndex] += clampedDelta
        updatedLengths[trailingIndex] -= clampedDelta

        desiredProportions = normalizedProportions(for: updatedLengths)
        needsLayout = true
    }

    override func mouseUp(with event: NSEvent) {
        guard dragState != nil else {
            return
        }

        dragState = nil
        guard childPaneIDs.count == subviews.count, subviews.count > 1 else {
            return
        }
        onResize(childPaneIDs, desiredProportions)
    }

    private func applyLayout() {
        guard subviews.isEmpty == false else {
            dividerRects = []
            dividerHitRects = []
            return
        }

        let spacing = ShellLayoutMetrics.splitSpacing
        let hitArea = ShellLayoutMetrics.splitHitArea
        let hitPad = (hitArea - spacing) / 2
        let availableLength = max(primaryLength(of: bounds.size) - spacing * CGFloat(max(subviews.count - 1, 0)), 0)
        let lengths = resolvedLengths(totalLength: availableLength)

        var cursor: CGFloat = 0
        dividerRects = []
        dividerHitRects = []

        for (index, subview) in subviews.enumerated() {
            let length = lengths[index]
            let frame: NSRect
            if axis == .columns {
                frame = NSRect(x: cursor, y: 0, width: length, height: bounds.height)
            } else {
                frame = NSRect(x: 0, y: cursor, width: bounds.width, height: length)
            }
            subview.frame = frame
            cursor += length

            if index < subviews.count - 1 {
                let dividerRect: NSRect
                let hitRect: NSRect
                if axis == .columns {
                    dividerRect = NSRect(x: cursor, y: 0, width: spacing, height: bounds.height)
                    hitRect = NSRect(x: cursor - hitPad, y: 0, width: hitArea, height: bounds.height)
                } else {
                    dividerRect = NSRect(x: 0, y: cursor, width: bounds.width, height: spacing)
                    hitRect = NSRect(x: 0, y: cursor - hitPad, width: bounds.width, height: hitArea)
                }
                dividerRects.append(dividerRect)
                dividerHitRects.append(hitRect)
                cursor += spacing
            }
        }

        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    private func currentLengths() -> [CGFloat] {
        subviews.map { primaryLength(of: $0.frame.size) }
    }

    private func resolvedLengths(totalLength: CGFloat) -> [CGFloat] {
        guard subviews.isEmpty == false else {
            return []
        }

        if totalLength <= 0 {
            return Array(repeating: 0, count: subviews.count)
        }

        let minimums = subviews.indices.map(minimumPrimaryExtent(ofSubviewAt:))
        let minimumTotal = minimums.reduce(0, +)
        guard minimumTotal < totalLength else {
            return Array(repeating: totalLength / CGFloat(subviews.count), count: subviews.count)
        }

        let normalized = Self.normalizedProportions(desiredProportions, count: subviews.count)
        var lengths = normalized.map { CGFloat($0) * totalLength }
        var remainingIndices = Set(lengths.indices)
        var remainingLength = totalLength

        while true {
            let undersized = remainingIndices.filter { lengths[$0] < minimums[$0] }
            guard undersized.isEmpty == false else {
                break
            }

            for index in undersized {
                lengths[index] = minimums[index]
                remainingIndices.remove(index)
                remainingLength -= minimums[index]
            }

            guard remainingIndices.isEmpty == false else {
                break
            }

            let remainingWeight = remainingIndices.reduce(CGFloat(0)) { partialResult, index in
                partialResult + CGFloat(normalized[index])
            }

            for index in remainingIndices {
                let weight = remainingWeight > 0 ? CGFloat(normalized[index]) / remainingWeight : 1 / CGFloat(remainingIndices.count)
                lengths[index] = remainingLength * weight
            }
        }

        let correction = totalLength - lengths.reduce(0, +)
        if let lastIndex = lengths.indices.last {
            lengths[lastIndex] += correction
        }

        return lengths
    }

    private func minimumPrimaryExtent(ofSubviewAt index: Int) -> CGFloat {
        guard subviews.indices.contains(index) else {
            return 0
        }

        let fittingSize = subviews[index].fittingSize
        return max(primaryLength(of: fittingSize), 120)
    }

    private func primaryLength(of size: CGSize) -> CGFloat {
        axis == .columns ? size.width : size.height
    }

    private func primaryCoordinate(of point: CGPoint) -> CGFloat {
        axis == .columns ? point.x : point.y
    }

    private func normalizedProportions(for lengths: [CGFloat]) -> [Double] {
        let total = lengths.reduce(0, +)
        guard total > 0 else {
            return Self.normalizedProportions([], count: lengths.count)
        }
        return lengths.map { Double($0 / total) }
    }

    private static func normalizedProportions(_ proportions: [Double], count: Int) -> [Double] {
        guard count > 0 else {
            return []
        }

        guard proportions.count == count,
              proportions.allSatisfy({ $0.isFinite && $0 > 0 })
        else {
            return Array(repeating: 1.0 / Double(count), count: count)
        }

        let total = proportions.reduce(0, +)
        guard total > 0 else {
            return Array(repeating: 1.0 / Double(count), count: count)
        }
        return proportions.map { $0 / total }
    }
}
