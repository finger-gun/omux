import Foundation

public struct SessionDescriptor: Equatable, Codable, Sendable {
    public let id: SessionID
    public var shell: String
    public var workingDirectory: String
    public var environment: [String: String]

    public init(
        id: SessionID = SessionID(),
        shell: String,
        workingDirectory: String,
        environment: [String: String] = [:]
    ) {
        self.id = id
        self.shell = shell
        self.workingDirectory = workingDirectory
        self.environment = environment
    }
}

public struct Pane: Equatable, Codable, Sendable {
    public let id: PaneID
    public var title: String
    public var session: SessionDescriptor
    public var terminalState: PaneTerminalState

    public init(
        id: PaneID = PaneID(),
        title: String,
        session: SessionDescriptor,
        terminalState: PaneTerminalState = PaneTerminalState()
    ) {
        self.id = id
        self.title = title
        self.session = session
        self.terminalState = terminalState
    }
}

public enum PaneProgressState: String, Codable, Sendable {
    case active
    case error
    case indeterminate
    case paused
}

public struct PaneProgress: Equatable, Codable, Sendable {
    public var state: PaneProgressState
    public var value: Int?

    public init(state: PaneProgressState, value: Int? = nil) {
        self.state = state
        self.value = value
    }
}

public struct PaneExitStatus: Equatable, Codable, Sendable {
    public var exitCode: Int
    public var elapsedMilliseconds: UInt64

    public init(exitCode: Int, elapsedMilliseconds: UInt64) {
        self.exitCode = exitCode
        self.elapsedMilliseconds = elapsedMilliseconds
    }
}

public struct PaneScrollbackSnapshot: Equatable, Codable, Sendable {
    public static let defaultMaxBytes = 1_048_576
    public static let defaultMaxLines = 4_000

    public var text: String
    public var truncated: Bool
    public var storageIdentifier: String?

    public init(text: String, truncated: Bool = false, storageIdentifier: String? = nil) {
        self.text = text
        self.truncated = truncated
        self.storageIdentifier = storageIdentifier
    }

    public static func bounded(
        text: String,
        maxBytes: Int = defaultMaxBytes,
        maxLines: Int = defaultMaxLines
    ) -> PaneScrollbackSnapshot? {
        let sanitizedText = text.trimmingCharacters(in: .newlines)
        guard sanitizedText.isEmpty == false else {
            return nil
        }

        var boundedText = sanitizedText
        var truncated = false

        if maxLines > 0 {
            let lines = boundedText.split(separator: "\n", omittingEmptySubsequences: false)
            if lines.count > maxLines {
                boundedText = lines.suffix(maxLines).joined(separator: "\n")
                truncated = true
            }
        }

        if maxBytes > 0 {
            let utf8 = Array(boundedText.utf8)
            if utf8.count > maxBytes {
                let suffix = utf8.suffix(maxBytes)
                boundedText = String(decoding: suffix, as: UTF8.self)
                truncated = true
            }
        }

        let finalText = boundedText.trimmingCharacters(in: .newlines)
        guard finalText.isEmpty == false else {
            return nil
        }

        return PaneScrollbackSnapshot(text: finalText, truncated: truncated)
    }

    public static func combined(
        _ first: PaneScrollbackSnapshot?,
        _ second: PaneScrollbackSnapshot?,
        maxBytes: Int = defaultMaxBytes,
        maxLines: Int = defaultMaxLines
    ) -> PaneScrollbackSnapshot? {
        let parts = combinedParts(first?.text, second?.text)
        guard parts.isEmpty == false else {
            return nil
        }

        guard var snapshot = bounded(
            text: parts.joined(separator: "\n"),
            maxBytes: maxBytes,
            maxLines: maxLines
        ) else {
            return nil
        }
        snapshot.truncated = snapshot.truncated || first?.truncated == true || second?.truncated == true
        return snapshot
    }

    private static func combinedParts(_ first: String?, _ second: String?) -> [String] {
        let firstText = first?.trimmingCharacters(in: .newlines) ?? ""
        let secondText = second?.trimmingCharacters(in: .newlines) ?? ""
        guard firstText.isEmpty == false else {
            return secondText.isEmpty ? [] : [secondText]
        }
        guard secondText.isEmpty == false else {
            return [firstText]
        }

        let firstLines = firstText.split(separator: "\n", omittingEmptySubsequences: false)
        let secondLines = secondText.split(separator: "\n", omittingEmptySubsequences: false)
        let overlap = overlappingLineCount(firstLines: firstLines, secondLines: secondLines)
        let remainingSecond = secondLines.dropFirst(overlap).joined(separator: "\n")
        return remainingSecond.isEmpty ? [firstText] : [firstText, remainingSecond]
    }

    private static func overlappingLineCount(
        firstLines: [String.SubSequence],
        secondLines: [String.SubSequence]
    ) -> Int {
        let maxOverlap = min(firstLines.count, secondLines.count)
        guard maxOverlap > 0 else {
            return 0
        }

        for count in stride(from: maxOverlap, through: 1, by: -1) {
            if Array(firstLines.suffix(count)) == Array(secondLines.prefix(count)) {
                return count
            }
        }
        return 0
    }
}

public struct PaneTerminalState: Equatable, Codable, Sendable {
    public var reportedTitle: String?
    public var reportedWorkingDirectory: String?
    public var progress: PaneProgress?
    public var lastExit: PaneExitStatus?
    public var rendererHealthy: Bool?
    public var restoredScrollback: PaneScrollbackSnapshot?

    public init(
        reportedTitle: String? = nil,
        reportedWorkingDirectory: String? = nil,
        progress: PaneProgress? = nil,
        lastExit: PaneExitStatus? = nil,
        rendererHealthy: Bool? = nil,
        restoredScrollback: PaneScrollbackSnapshot? = nil
    ) {
        self.reportedTitle = reportedTitle
        self.reportedWorkingDirectory = reportedWorkingDirectory
        self.progress = progress
        self.lastExit = lastExit
        self.rendererHealthy = rendererHealthy
        self.restoredScrollback = restoredScrollback
    }

    public var statusSummary: String? {
        var parts: [String] = []
        if let progress {
            switch progress.state {
            case .active:
                if let value = progress.value {
                    parts.append("Progress \(value)%")
                } else {
                    parts.append("Progress")
                }
            case .error:
                parts.append("Progress error")
            case .indeterminate:
                parts.append("Progress indeterminate")
            case .paused:
                parts.append("Progress paused")
            }
        }
        if let lastExit {
            parts.append("Exited \(lastExit.exitCode)")
        }
        if rendererHealthy == false {
            parts.append("Renderer unhealthy")
        }

        guard parts.isEmpty == false else {
            return nil
        }
        return parts.joined(separator: " · ")
    }
}

public struct PaneStack: Equatable, Codable, Sendable {
    public let id: PaneStackID
    public var panes: [Pane]
    public var focusedPaneID: PaneID

    public init(
        id: PaneStackID = PaneStackID(),
        panes: [Pane],
        focusedPaneID: PaneID
    ) {
        self.id = id
        self.panes = panes
        self.focusedPaneID = focusedPaneID
    }

    public var focusedPane: Pane? {
        panes.first(where: { $0.id == focusedPaneID })
    }

    public func nextPaneID(after paneID: PaneID? = nil) -> PaneID? {
        adjacentPaneID(from: paneID ?? focusedPaneID, offset: 1)
    }

    public func previousPaneID(before paneID: PaneID? = nil) -> PaneID? {
        adjacentPaneID(from: paneID ?? focusedPaneID, offset: -1)
    }

    @discardableResult
    public mutating func focusPane(_ paneID: PaneID) -> Bool {
        guard panes.contains(where: { $0.id == paneID }) else {
            return false
        }

        focusedPaneID = paneID
        return true
    }

    public mutating func appendPane(_ pane: Pane, focus: Bool = true) {
        panes.append(pane)
        if focus {
            focusedPaneID = pane.id
        }
    }

    public mutating func closePane(id paneID: PaneID) -> Pane? {
        guard panes.count > 1,
              let index = panes.firstIndex(where: { $0.id == paneID })
        else {
            return nil
        }

        let removedPane = panes.remove(at: index)
        if focusedPaneID == removedPane.id {
            let nextIndex = min(index, panes.count - 1)
            focusedPaneID = panes[nextIndex].id
        }
        return removedPane
    }

    private func adjacentPaneID(from paneID: PaneID, offset: Int) -> PaneID? {
        guard panes.count > 1,
              let index = panes.firstIndex(where: { $0.id == paneID })
        else {
            return nil
        }

        let nextIndex = (index + offset + panes.count) % panes.count
        return panes[nextIndex].id
    }
}

public enum PaneSplitAxis: String, Codable, Sendable {
    case columns
    case rows
}

public enum PaneSplitResizeDirection: String, Codable, Sendable {
    case up
    case down
    case left
    case right

    public var axis: PaneSplitAxis {
        switch self {
        case .up, .down:
            return .rows
        case .left, .right:
            return .columns
        }
    }

    var proportionDelta: Double {
        switch self {
        case .up, .left:
            return -0.05
        case .down, .right:
            return 0.05
        }
    }
}

public indirect enum TabLayoutNode: Equatable, Codable, Sendable {
    private struct PaneDetachResult {
        let pane: Pane
        let collapseNode: Bool
    }

    private enum CodingKeys: String, CodingKey {
        case paneStack
        case split
    }

    private enum SplitCodingKeys: String, CodingKey {
        case axis
        case children
        case proportions
    }

    case paneStack(PaneStack)
    case split(axis: PaneSplitAxis, proportions: [Double], children: [TabLayoutNode])

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.paneStack) {
            self = .paneStack(try container.decode(PaneStack.self, forKey: .paneStack))
            return
        }

        if container.contains(.split) {
            let splitContainer = try container.nestedContainer(keyedBy: SplitCodingKeys.self, forKey: .split)
            let axis = try splitContainer.decode(PaneSplitAxis.self, forKey: .axis)
            let children = try splitContainer.decode([TabLayoutNode].self, forKey: .children)
            let proportions = try splitContainer.decodeIfPresent([Double].self, forKey: .proportions) ?? []
            self = Self.makeSplit(axis: axis, proportions: proportions, children: children)
            return
        }

        throw DecodingError.dataCorrupted(
            .init(codingPath: decoder.codingPath, debugDescription: "Unsupported TabLayoutNode encoding")
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .paneStack(let paneStack):
            try container.encode(paneStack, forKey: .paneStack)
        case .split(let axis, let proportions, let children):
            var splitContainer = container.nestedContainer(keyedBy: SplitCodingKeys.self, forKey: .split)
            try splitContainer.encode(axis, forKey: .axis)
            try splitContainer.encode(children, forKey: .children)
            try splitContainer.encode(proportions, forKey: .proportions)
        }
    }

    public var panes: [Pane] {
        switch self {
        case .paneStack(let paneStack):
            return paneStack.panes
        case .split(_, _, let children):
            return children.flatMap(\.panes)
        }
    }

    public var visiblePaneIDs: [PaneID] {
        switch self {
        case .paneStack(let paneStack):
            return paneStack.panes.contains(where: { $0.id == paneStack.focusedPaneID })
                ? [paneStack.focusedPaneID]
                : []
        case .split(_, _, let children):
            return children.flatMap(\.visiblePaneIDs)
        }
    }

    public var paneStacks: [PaneStack] {
        switch self {
        case .paneStack(let paneStack):
            return [paneStack]
        case .split(_, _, let children):
            return children.flatMap(\.paneStacks)
        }
    }

    public var representativePaneID: PaneID? {
        switch self {
        case .paneStack(let paneStack):
            return paneStack.panes.first?.id
        case .split(_, _, let children):
            return children.first?.representativePaneID
        }
    }

    public var hasSplits: Bool {
        switch self {
        case .paneStack:
            return false
        case .split:
            return true
        }
    }

    public func pane(id: PaneID) -> Pane? {
        switch self {
        case .paneStack(let paneStack):
            return paneStack.panes.first(where: { $0.id == id })
        case .split(_, _, let children):
            for child in children {
                if let pane = child.pane(id: id) {
                    return pane
                }
            }
            return nil
        }
    }

    public func paneStack(id: PaneStackID) -> PaneStack? {
        switch self {
        case .paneStack(let paneStack):
            return paneStack.id == id ? paneStack : nil
        case .split(_, _, let children):
            for child in children {
                if let paneStack = child.paneStack(id: id) {
                    return paneStack
                }
            }
            return nil
        }
    }

    public func paneStack(containingPaneID paneID: PaneID) -> PaneStack? {
        switch self {
        case .paneStack(let paneStack):
            return paneStack.panes.contains(where: { $0.id == paneID }) ? paneStack : nil
        case .split(_, _, let children):
            for child in children {
                if let paneStack = child.paneStack(containingPaneID: paneID) {
                    return paneStack
                }
            }
            return nil
        }
    }

    public func containsPane(id: PaneID) -> Bool {
        pane(id: id) != nil
    }

    public func canResizeSplit(containingPaneID paneID: PaneID, direction: PaneSplitResizeDirection) -> Bool {
        switch self {
        case .paneStack:
            return false

        case .split(let axis, _, let children):
            for child in children where child.containsPane(id: paneID) {
                if child.canResizeSplit(containingPaneID: paneID, direction: direction) {
                    return true
                }
            }

            guard axis == direction.axis,
                  children.count > 1,
                  let childIndex = children.firstIndex(where: { $0.containsPane(id: paneID) })
            else {
                return false
            }

            return Self.dividerIndex(forChildAt: childIndex, direction: direction, childCount: children.count) != nil
        }
    }

    @discardableResult
    public mutating func updatePane(
        _ paneID: PaneID,
        transform: (inout Pane) -> Void
    ) -> Bool {
        switch self {
        case .paneStack(var paneStack):
            guard let index = paneStack.panes.firstIndex(where: { $0.id == paneID }) else {
                return false
            }
            transform(&paneStack.panes[index])
            self = .paneStack(paneStack)
            return true
        case .split(let axis, let proportions, var children):
            for index in children.indices {
                if children[index].updatePane(paneID, transform: transform) {
                    self = Self.makeSplit(axis: axis, proportions: proportions, children: children)
                    return true
                }
            }
            return false
        }
    }

    @discardableResult
    public mutating func equalizeSplits() -> Bool {
        switch self {
        case .paneStack:
            return false

        case .split(let axis, let proportions, var children):
            var changed = false
            for index in children.indices {
                changed = children[index].equalizeSplits() || changed
            }

            let equalizedProportions = Self.normalizedSplitProportions([], childCount: children.count)
            changed = changed || proportions != equalizedProportions
            self = Self.makeSplit(axis: axis, proportions: equalizedProportions, children: children)
            return changed
        }
    }

    @discardableResult
    public mutating func resizeSplit(
        containingPaneID paneID: PaneID,
        direction: PaneSplitResizeDirection
    ) -> Bool {
        switch self {
        case .paneStack:
            return false

        case .split(let axis, let proportions, var children):
            for index in children.indices where children[index].containsPane(id: paneID) {
                if children[index].resizeSplit(containingPaneID: paneID, direction: direction) {
                    self = Self.makeSplit(axis: axis, proportions: proportions, children: children)
                    return true
                }
            }

            guard axis == direction.axis,
                  children.count > 1,
                  let childIndex = children.firstIndex(where: { $0.containsPane(id: paneID) }),
                  let dividerIndex = Self.dividerIndex(
                      forChildAt: childIndex,
                      direction: direction,
                      childCount: children.count
                  )
            else {
                return false
            }

            let currentProportions = Self.normalizedSplitProportions(proportions, childCount: children.count)
            guard let updatedProportions = Self.proportions(
                currentProportions,
                movingDividerAt: dividerIndex,
                by: direction.proportionDelta
            ) else {
                return false
            }

            self = Self.makeSplit(axis: axis, proportions: updatedProportions, children: children)
            return true
        }
    }

    public func containsSession(id: SessionID) -> Bool {
        panes.contains(where: { $0.session.id == id })
    }

    @discardableResult
    public mutating func focusPane(_ paneID: PaneID) -> Bool {
        switch self {
        case .paneStack(var paneStack):
            guard paneStack.focusPane(paneID) else {
                return false
            }

            self = .paneStack(paneStack)
            return true

        case .split(let axis, let proportions, var children):
            for index in children.indices {
                if children[index].focusPane(paneID) {
                    self = Self.makeSplit(axis: axis, proportions: proportions, children: children)
                    return true
                }
            }
            return false
        }
    }

    @discardableResult
    public mutating func createPane(
        inStack stackID: PaneStackID,
        pane: Pane,
        focus: Bool = true
    ) -> Bool {
        switch self {
        case .paneStack(var paneStack):
            guard paneStack.id == stackID else {
                return false
            }

            paneStack.appendPane(pane, focus: focus)
            self = .paneStack(paneStack)
            return true

        case .split(let axis, let proportions, var children):
            for index in children.indices {
                if children[index].createPane(inStack: stackID, pane: pane, focus: focus) {
                    self = Self.makeSplit(axis: axis, proportions: proportions, children: children)
                    return true
                }
            }
            return false
        }
    }

    public mutating func closePane(
        inStack stackID: PaneStackID,
        paneID: PaneID
    ) -> Pane? {
        switch self {
        case .paneStack(var paneStack):
            guard paneStack.id == stackID,
                  let removedPane = paneStack.closePane(id: paneID)
            else {
                return nil
            }

            self = .paneStack(paneStack)
            return removedPane

        case .split(let axis, let proportions, var children):
            for index in children.indices {
                if let removedPane = children[index].closePane(inStack: stackID, paneID: paneID) {
                    self = Self.makeSplit(axis: axis, proportions: proportions, children: children)
                    return removedPane
                }
            }
            return nil
        }
    }

    public mutating func detachPane(id paneID: PaneID) -> Pane? {
        detachPaneResult(id: paneID)?.pane
    }

    @discardableResult
    public mutating func updateSplitProportions(
        _ proportions: [Double],
        forChildPaneIDs childPaneIDs: [PaneID]
    ) -> Bool {
        switch self {
        case .paneStack:
            return false

        case .split(let axis, let currentProportions, var children):
            let normalizedProportions = Self.normalizedSplitProportions(proportions, childCount: children.count)
            if childPaneIDs.count == children.count,
               zip(children, childPaneIDs).allSatisfy({ child, paneID in child.containsPane(id: paneID) }) {
                guard normalizedProportions != currentProportions else {
                    return false
                }
                self = Self.makeSplit(axis: axis, proportions: normalizedProportions, children: children)
                return true
            }

            for index in children.indices {
                if children[index].updateSplitProportions(proportions, forChildPaneIDs: childPaneIDs) {
                    self = Self.makeSplit(axis: axis, proportions: currentProportions, children: children)
                    return true
                }
            }
            return false
        }
    }

    @discardableResult
    public mutating func split(
        stackID: PaneStackID,
        axis: PaneSplitAxis,
        adding paneStack: PaneStack
    ) -> Bool {
        switch self {
        case .paneStack(let existingPaneStack):
            guard existingPaneStack.id == stackID else {
                return false
            }

            self = Self.makeSplit(
                axis: axis,
                proportions: [],
                children: [.paneStack(existingPaneStack), .paneStack(paneStack)]
            )
            return true

        case .split(let existingAxis, let proportions, var children):
            for index in children.indices {
                if children[index].split(stackID: stackID, axis: axis, adding: paneStack) {
                    self = Self.makeSplit(axis: existingAxis, proportions: proportions, children: children)
                    return true
                }
            }
            return false
        }
    }

    private mutating func detachPaneResult(id paneID: PaneID) -> PaneDetachResult? {
        switch self {
        case .paneStack(var paneStack):
            guard let index = paneStack.panes.firstIndex(where: { $0.id == paneID }) else {
                return nil
            }

            let removedPane = paneStack.panes.remove(at: index)
            if paneStack.panes.isEmpty {
                return PaneDetachResult(pane: removedPane, collapseNode: true)
            }

            if paneStack.focusedPaneID == removedPane.id {
                paneStack.focusedPaneID = paneStack.panes[min(index, paneStack.panes.count - 1)].id
            }

            self = .paneStack(paneStack)
            return PaneDetachResult(pane: removedPane, collapseNode: false)

        case .split(let axis, let proportions, var children):
            for index in children.indices {
                if let result = children[index].detachPaneResult(id: paneID) {
                    var updatedProportions = proportions
                    if result.collapseNode {
                        children.remove(at: index)
                        if updatedProportions.indices.contains(index) {
                            updatedProportions.remove(at: index)
                        }
                    }

                    if children.isEmpty {
                        return PaneDetachResult(pane: result.pane, collapseNode: true)
                    }

                    self = children.count == 1
                        ? children[0]
                        : Self.makeSplit(axis: axis, proportions: updatedProportions, children: children)
                    return PaneDetachResult(pane: result.pane, collapseNode: false)
                }
            }

            return nil
        }
    }

    private static func makeSplit(
        axis: PaneSplitAxis,
        proportions: [Double],
        children: [TabLayoutNode]
    ) -> TabLayoutNode {
        .split(
            axis: axis,
            proportions: normalizedSplitProportions(proportions, childCount: children.count),
            children: children
        )
    }

    private static func dividerIndex(
        forChildAt childIndex: Int,
        direction: PaneSplitResizeDirection,
        childCount: Int
    ) -> Int? {
        guard childCount > 1 else {
            return nil
        }

        switch direction {
        case .up, .left:
            if childIndex > 0 {
                return childIndex - 1
            }
            return childIndex < childCount - 1 ? childIndex : nil

        case .down, .right:
            if childIndex < childCount - 1 {
                return childIndex
            }
            return childIndex > 0 ? childIndex - 1 : nil
        }
    }

    private static func proportions(
        _ proportions: [Double],
        movingDividerAt dividerIndex: Int,
        by requestedDelta: Double
    ) -> [Double]? {
        let trailingIndex = dividerIndex + 1
        guard proportions.indices.contains(dividerIndex),
              proportions.indices.contains(trailingIndex)
        else {
            return nil
        }

        let minimumProportion = 0.05
        let lowerDelta = minimumProportion - proportions[dividerIndex]
        let upperDelta = proportions[trailingIndex] - minimumProportion
        let delta = min(max(requestedDelta, lowerDelta), upperDelta)
        guard abs(delta) > 0.000001 else {
            return nil
        }

        var updatedProportions = proportions
        updatedProportions[dividerIndex] += delta
        updatedProportions[trailingIndex] -= delta
        return normalizedSplitProportions(updatedProportions, childCount: updatedProportions.count)
    }

    private static func normalizedSplitProportions(_ proportions: [Double], childCount: Int) -> [Double] {
        guard childCount > 0 else {
            return []
        }

        if childCount == 1 {
            return [1]
        }

        guard proportions.count == childCount,
              proportions.allSatisfy({ $0.isFinite && $0 > 0 })
        else {
            return Array(repeating: 1.0 / Double(childCount), count: childCount)
        }

        let total = proportions.reduce(0, +)
        guard total.isFinite, total > 0 else {
            return Array(repeating: 1.0 / Double(childCount), count: childCount)
        }

        return proportions.map { $0 / total }
    }
}

public struct Tab: Equatable, Codable, Sendable {
    public let id: TabID
    public var title: String
    public var rootLayout: TabLayoutNode
    public var focusedPaneID: PaneID

    public init(
        id: TabID = TabID(),
        title: String,
        panes: [Pane],
        focusedPaneID: PaneID
    ) {
        self.id = id
        self.title = title
        self.rootLayout = Self.makeInitialLayout(from: panes)
        self.focusedPaneID = focusedPaneID
    }

    public init(
        id: TabID = TabID(),
        title: String,
        rootLayout: TabLayoutNode,
        focusedPaneID: PaneID
    ) {
        self.id = id
        self.title = title
        self.rootLayout = rootLayout
        self.focusedPaneID = focusedPaneID
    }

    @discardableResult
    public mutating func focusPane(_ paneID: PaneID) -> Bool {
        guard rootLayout.focusPane(paneID) else {
            return false
        }

        focusedPaneID = paneID
        return true
    }

    public var panes: [Pane] {
        rootLayout.panes
    }

    public var visiblePaneIDs: [PaneID] {
        rootLayout.visiblePaneIDs
    }

    public var paneStacks: [PaneStack] {
        rootLayout.paneStacks
    }

    public var hasSplits: Bool {
        rootLayout.hasSplits
    }

    public var focusedPane: Pane? {
        rootLayout.pane(id: focusedPaneID)
    }

    public var focusedPaneStack: PaneStack? {
        rootLayout.paneStack(containingPaneID: focusedPaneID)
    }

    public func nextPaneTabID() -> PaneID? {
        focusedPaneStack?.nextPaneID(after: focusedPaneID)
    }

    public func previousPaneTabID() -> PaneID? {
        focusedPaneStack?.previousPaneID(before: focusedPaneID)
    }

    public func nextVisiblePaneID() -> PaneID? {
        adjacentVisiblePaneID(offset: 1)
    }

    public func previousVisiblePaneID() -> PaneID? {
        adjacentVisiblePaneID(offset: -1)
    }

    public func canResizeFocusedSplit(_ direction: PaneSplitResizeDirection) -> Bool {
        rootLayout.canResizeSplit(containingPaneID: focusedPaneID, direction: direction)
    }

    @discardableResult
    public mutating func createPaneInFocusedStack(_ pane: Pane, focus: Bool = true) -> Bool {
        guard let stackID = focusedPaneStack?.id,
              rootLayout.createPane(inStack: stackID, pane: pane, focus: focus)
        else {
            return false
        }

        if focus {
            focusedPaneID = pane.id
        }
        return true
    }

    @discardableResult
    public mutating func focusNextPaneTab() -> Bool {
        guard let paneID = nextPaneTabID() else {
            return false
        }
        return focusPane(paneID)
    }

    @discardableResult
    public mutating func focusPreviousPaneTab() -> Bool {
        guard let paneID = previousPaneTabID() else {
            return false
        }
        return focusPane(paneID)
    }

    @discardableResult
    public mutating func focusNextVisiblePane() -> Bool {
        guard let paneID = nextVisiblePaneID() else {
            return false
        }
        return focusPane(paneID)
    }

    @discardableResult
    public mutating func focusPreviousVisiblePane() -> Bool {
        guard let paneID = previousVisiblePaneID() else {
            return false
        }
        return focusPane(paneID)
    }

    @discardableResult
    public mutating func createPane(
        inStack stackID: PaneStackID,
        pane: Pane,
        focus: Bool = true
    ) -> Bool {
        guard rootLayout.createPane(inStack: stackID, pane: pane, focus: focus) else {
            return false
        }

        if focus {
            focusedPaneID = pane.id
        }
        return true
    }

    public mutating func closeFocusedPane() -> Pane? {
        closePane(focusedPaneID)
    }

    public mutating func closePane(_ paneID: PaneID) -> Pane? {
        guard let stackID = rootLayout.paneStack(containingPaneID: paneID)?.id,
              let removedPane = rootLayout.closePane(inStack: stackID, paneID: paneID)
        else {
            return nil
        }

        if let updatedStack = rootLayout.paneStack(id: stackID) {
            focusedPaneID = updatedStack.focusedPaneID
        }
        return removedPane
    }

    public mutating func removePane(_ paneID: PaneID) -> Pane? {
        guard let removedPane = rootLayout.detachPane(id: paneID),
              let nextFocusedPaneID = rootLayout.panes.first?.id
        else {
            return nil
        }

        focusedPaneID = nextFocusedPaneID
        return removedPane
    }

    @discardableResult
    public mutating func splitFocusedPane(_ pane: Pane, axis: PaneSplitAxis, focus: Bool = true) -> Bool {
        guard let focusedStackID = focusedPaneStack?.id else {
            return false
        }

        let newStack = PaneStack(panes: [pane], focusedPaneID: pane.id)
        guard rootLayout.split(stackID: focusedStackID, axis: axis, adding: newStack) else {
            return false
        }

        if focus {
            focusedPaneID = pane.id
        }
        return true
    }

    @discardableResult
    public mutating func updateSplitProportions(
        _ proportions: [Double],
        forChildPaneIDs childPaneIDs: [PaneID]
    ) -> Bool {
        rootLayout.updateSplitProportions(proportions, forChildPaneIDs: childPaneIDs)
    }

    @discardableResult
    public mutating func equalizeSplits() -> Bool {
        rootLayout.equalizeSplits()
    }

    @discardableResult
    public mutating func resizeFocusedSplit(_ direction: PaneSplitResizeDirection) -> Bool {
        rootLayout.resizeSplit(containingPaneID: focusedPaneID, direction: direction)
    }

    private static func makeInitialLayout(from panes: [Pane]) -> TabLayoutNode {
        guard let firstPane = panes.first else {
            return .split(axis: .columns, proportions: [], children: [])
        }

        return panes.dropFirst().reduce(.paneStack(PaneStack(panes: [firstPane], focusedPaneID: firstPane.id))) {
            partialResult, pane in
            .split(
                axis: .columns,
                proportions: [0.5, 0.5],
                children: [
                    partialResult,
                    .paneStack(PaneStack(panes: [pane], focusedPaneID: pane.id)),
                ]
            )
        }
    }

    private func adjacentVisiblePaneID(offset: Int) -> PaneID? {
        let paneIDs = visiblePaneIDs
        guard paneIDs.count > 1,
              let index = paneIDs.firstIndex(of: focusedPaneID)
        else {
            return nil
        }

        let nextIndex = (index + offset + paneIDs.count) % paneIDs.count
        return paneIDs[nextIndex]
    }
}

public struct Workspace: Equatable, Codable, Sendable {
    public let id: WorkspaceID
    public var generatedName: String
    public var customName: String?
    public var rootPath: String
    public var tabs: [Tab]
    public var focusedTabID: TabID

    public init(
        id: WorkspaceID = WorkspaceID(),
        generatedName: String,
        customName: String? = nil,
        rootPath: String,
        tabs: [Tab],
        focusedTabID: TabID
    ) {
        self.id = id
        self.generatedName = generatedName
        self.customName = customName
        self.rootPath = rootPath
        self.tabs = tabs
        self.focusedTabID = focusedTabID
    }

    public init(
        id: WorkspaceID = WorkspaceID(),
        name: String,
        rootPath: String,
        tabs: [Tab],
        focusedTabID: TabID
    ) {
        self.init(
            id: id,
            generatedName: name,
            customName: nil,
            rootPath: rootPath,
            tabs: tabs,
            focusedTabID: focusedTabID
        )
    }

    public var name: String {
        customName ?? generatedName
    }

    public var hasCustomName: Bool {
        customName != nil
    }

    public var focusedTab: Tab? {
        tabs.first(where: { $0.id == focusedTabID })
    }

    public var focusedPane: Pane? {
        focusedTab?.focusedPane
    }

    public var focusedPaneStack: PaneStack? {
        focusedTab?.focusedPaneStack
    }

    public var hasFocusedTabSplits: Bool {
        focusedTab?.hasSplits ?? false
    }

    public func canResizeFocusedSplit(_ direction: PaneSplitResizeDirection) -> Bool {
        focusedTab?.canResizeFocusedSplit(direction) ?? false
    }

    @discardableResult
    public mutating func focus(sessionID: SessionID) -> Bool {
        for tabIndex in tabs.indices {
            if let pane = tabs[tabIndex].panes.first(where: { $0.session.id == sessionID }) {
                focusedTabID = tabs[tabIndex].id
                return tabs[tabIndex].focusPane(pane.id)
            }
        }

        return false
    }

    @discardableResult
    public mutating func focus(tabID: TabID) -> Bool {
        guard tabs.contains(where: { $0.id == tabID }) else {
            return false
        }

        focusedTabID = tabID
        return true
    }

    @discardableResult
    public mutating func focus(paneID: PaneID) -> Bool {
        for tabIndex in tabs.indices {
            if tabs[tabIndex].panes.contains(where: { $0.id == paneID }) {
                focusedTabID = tabs[tabIndex].id
                return tabs[tabIndex].focusPane(paneID)
            }
        }

        return false
    }

    @discardableResult
    public mutating func focusNextPaneTab() -> Bool {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == focusedTabID }) else {
            return false
        }

        return tabs[tabIndex].focusNextPaneTab()
    }

    @discardableResult
    public mutating func focusPreviousPaneTab() -> Bool {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == focusedTabID }) else {
            return false
        }

        return tabs[tabIndex].focusPreviousPaneTab()
    }

    @discardableResult
    public mutating func focusNextPane() -> Bool {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == focusedTabID }) else {
            return false
        }

        return tabs[tabIndex].focusNextVisiblePane()
    }

    @discardableResult
    public mutating func focusPreviousPane() -> Bool {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == focusedTabID }) else {
            return false
        }

        return tabs[tabIndex].focusPreviousVisiblePane()
    }

    public mutating func appendTab(_ tab: Tab, focus: Bool = true) {
        tabs.append(tab)
        if focus {
            focusedTabID = tab.id
        }
    }

    public mutating func closeTab(_ tabID: TabID) -> Tab? {
        guard tabs.count > 1,
              let index = tabs.firstIndex(where: { $0.id == tabID })
        else {
            return nil
        }

        let removedTab = tabs.remove(at: index)
        if focusedTabID == removedTab.id {
            focusedTabID = tabs[min(index, tabs.count - 1)].id
        }
        return removedTab
    }

    @discardableResult
    public mutating func createPaneInFocusedStack(_ pane: Pane) -> Bool {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == focusedTabID }) else {
            return false
        }

        return tabs[tabIndex].createPaneInFocusedStack(pane)
    }

    @discardableResult
    public mutating func createPane(
        inStack stackID: PaneStackID,
        pane: Pane
    ) -> Bool {
        for tabIndex in tabs.indices {
            guard tabs[tabIndex].rootLayout.paneStack(id: stackID) != nil else {
                continue
            }

            focusedTabID = tabs[tabIndex].id
            return tabs[tabIndex].createPane(inStack: stackID, pane: pane)
        }

        return false
    }

    public mutating func closeFocusedPane() -> Pane? {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == focusedTabID }) else {
            return nil
        }

        return tabs[tabIndex].closeFocusedPane()
    }

    public mutating func closePane(_ paneID: PaneID) -> Pane? {
        for tabIndex in tabs.indices {
            if tabs[tabIndex].panes.contains(where: { $0.id == paneID }) {
                focusedTabID = tabs[tabIndex].id
                return tabs[tabIndex].closePane(paneID)
            }
        }

        return nil
    }

    @discardableResult
    public mutating func updatePane(
        _ paneID: PaneID,
        transform: (inout Pane) -> Void
    ) -> Bool {
        for tabIndex in tabs.indices {
            if tabs[tabIndex].rootLayout.updatePane(paneID, transform: transform) {
                return true
            }
        }
        return false
    }

    @discardableResult
    public mutating func appendPaneToFocusedTab(_ pane: Pane, axis: PaneSplitAxis? = nil) -> Bool {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == focusedTabID }) else {
            return false
        }

        return tabs[tabIndex].splitFocusedPane(pane, axis: axis ?? .columns)
    }

    @discardableResult
    public mutating func updateSplitProportions(
        _ proportions: [Double],
        forChildPaneIDs childPaneIDs: [PaneID]
    ) -> Bool {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == focusedTabID }) else {
            return false
        }

        return tabs[tabIndex].updateSplitProportions(proportions, forChildPaneIDs: childPaneIDs)
    }

    @discardableResult
    public mutating func equalizeSplitsInFocusedTab() -> Bool {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == focusedTabID }) else {
            return false
        }

        return tabs[tabIndex].equalizeSplits()
    }

    @discardableResult
    public mutating func resizeFocusedSplit(_ direction: PaneSplitResizeDirection) -> Bool {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == focusedTabID }) else {
            return false
        }

        return tabs[tabIndex].resizeFocusedSplit(direction)
    }
}

public struct WorkspaceSummary: Equatable, Codable, Sendable {
    public let id: WorkspaceID
    public let name: String
    public let generatedName: String
    public let customName: String?
    public let hasCustomName: Bool
    public let rootPath: String
    public let tabCount: Int
    public let paneCount: Int

    public init(workspace: Workspace) {
        self.id = workspace.id
        self.name = workspace.name
        self.generatedName = workspace.generatedName
        self.customName = workspace.customName
        self.hasCustomName = workspace.hasCustomName
        self.rootPath = workspace.rootPath
        self.tabCount = workspace.tabs.count
        self.paneCount = workspace.tabs.reduce(into: 0) { $0 += $1.panes.count }
    }
}

public enum NotificationSeverity: String, Codable, Sendable {
    case info
    case warning
    case error
}

public struct NotificationRequest: Equatable, Codable, Sendable {
    public var title: String
    public var body: String
    public var severity: NotificationSeverity

    public init(title: String, body: String, severity: NotificationSeverity = .info) {
        self.title = title
        self.body = body
        self.severity = severity
    }
}
