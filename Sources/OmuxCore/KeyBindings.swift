import Foundation

public enum OpenMUXKeyBindingAction: String, CaseIterable, Sendable {
    case workspaceCreate = "workspace.create"
    case workspaceClose = "workspace.close"
    case workspacePrevious = "workspace.previous"
    case workspaceMoveUp = "workspace.move-up"
    case workspaceMoveDown = "workspace.move-down"
    case workspaceFocus1 = "workspace.focus-1"
    case workspaceFocus2 = "workspace.focus-2"
    case workspaceFocus3 = "workspace.focus-3"
    case workspaceFocus4 = "workspace.focus-4"
    case workspaceFocus5 = "workspace.focus-5"
    case workspaceFocus6 = "workspace.focus-6"
    case workspaceFocus7 = "workspace.focus-7"
    case workspaceFocus8 = "workspace.focus-8"
    case workspaceFocus9 = "workspace.focus-9"
    case sidebarToggle = "sidebar.toggle"
    case paneSplitRight = "pane.split-right"
    case paneSplitDown = "pane.split-down"
    case paneRemove = "pane.remove"
    case paneNext = "pane.next"
    case panePrevious = "pane.previous"
    case paneTabCreate = "pane-tab.create"
    case paneTabClose = "pane-tab.close"
    case paneTabNext = "pane-tab.next"
    case paneTabPrevious = "pane-tab.previous"
}

public struct OpenMUXKeyChord: Hashable, Sendable {
    public enum ParseError: Error, Equatable, Sendable {
        case empty
        case missingModifier
        case unknownModifier(String)
        case duplicateModifier(String)
        case unsupportedOptionModifier
        case unsupportedKey(String)
    }

    public let key: String
    public let modifiers: KeyModifiers

    public init(key: String, modifiers: KeyModifiers) {
        self.key = key
        self.modifiers = modifiers
    }

    public init(parsing rawValue: String) throws {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
        guard normalized.isEmpty == false else {
            throw ParseError.empty
        }

        let parts = normalized.split(separator: "+").map(String.init)
        guard let rawKey = parts.last, rawKey.isEmpty == false else {
            throw ParseError.unsupportedKey("")
        }

        var modifiers: KeyModifiers = []
        var seen = Set<String>()
        for token in parts.dropLast() {
            let canonical: String
            let modifier: KeyModifiers
            switch token {
            case "cmd", "command":
                canonical = "cmd"
                modifier = .leftCommand
            case "ctrl", "control":
                canonical = "ctrl"
                modifier = .leftControl
            case "shift":
                canonical = "shift"
                modifier = .leftShift
            case "option", "alt":
                throw ParseError.unsupportedOptionModifier
            default:
                throw ParseError.unknownModifier(token)
            }
            guard seen.insert(canonical).inserted else {
                throw ParseError.duplicateModifier(canonical)
            }
            modifiers.insert(modifier)
        }

        guard modifiers.isEmpty == false else {
            throw ParseError.missingModifier
        }

        guard let key = Self.canonicalKey(rawKey) else {
            throw ParseError.unsupportedKey(rawKey)
        }

        self.key = key
        self.modifiers = modifiers
    }

    public var description: String {
        var parts: [String] = []
        if modifiers.containsCommand {
            parts.append("cmd")
        }
        if modifiers.containsControl {
            parts.append("ctrl")
        }
        if modifiers.containsShift {
            parts.append("shift")
        }
        parts.append(key)
        return parts.joined(separator: "+")
    }

    public func matches(_ raw: RawKeyInput) -> Bool {
        guard raw.isComposing == false else {
            return false
        }
        guard Self.key(for: raw) == key else {
            return false
        }
        return raw.modifiers.matchesChordModifiers(modifiers)
    }

    private static func canonicalKey(_ rawKey: String) -> String? {
        if rawKey.count == 1, let scalar = rawKey.unicodeScalars.first {
            if CharacterSet.lowercaseLetters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) {
                return rawKey
            }
        }

        switch rawKey {
        case "tab", "backspace", "up", "down":
            return rawKey
        default:
            return nil
        }
    }

    private static func key(for raw: RawKeyInput) -> String {
        switch raw.keyCode {
        case 51:
            return "backspace"
        case 125:
            return "down"
        case 126:
            return "up"
        default:
            break
        }

        let value = (raw.charactersIgnoringModifiers.isEmpty ? raw.characters : raw.charactersIgnoringModifiers)
            .lowercased()
        switch value {
        case "\t":
            return "tab"
        case "\u{7F}", "\u{8}":
            return "backspace"
        default:
            return value
        }
    }
}

public struct OpenMUXKeyBindingOverride: Equatable, Sendable {
    public let chord: OpenMUXKeyChord
    public let action: OpenMUXKeyBindingAction?

    public init(chord: OpenMUXKeyChord, action: OpenMUXKeyBindingAction?) {
        self.chord = chord
        self.action = action
    }
}

public struct OpenMUXKeyBindingRegistry: Equatable, Sendable {
    public static let defaultBindingPairs: [(OpenMUXKeyChord, OpenMUXKeyBindingAction)] = [
        (try! OpenMUXKeyChord(parsing: "cmd+n"), .workspaceCreate),
        (try! OpenMUXKeyChord(parsing: "cmd+shift+n"), .workspaceClose),
        (try! OpenMUXKeyChord(parsing: "cmd+0"), .workspacePrevious),
        (try! OpenMUXKeyChord(parsing: "cmd+ctrl+up"), .workspaceMoveUp),
        (try! OpenMUXKeyChord(parsing: "cmd+ctrl+down"), .workspaceMoveDown),
        (try! OpenMUXKeyChord(parsing: "cmd+1"), .workspaceFocus1),
        (try! OpenMUXKeyChord(parsing: "cmd+2"), .workspaceFocus2),
        (try! OpenMUXKeyChord(parsing: "cmd+3"), .workspaceFocus3),
        (try! OpenMUXKeyChord(parsing: "cmd+4"), .workspaceFocus4),
        (try! OpenMUXKeyChord(parsing: "cmd+5"), .workspaceFocus5),
        (try! OpenMUXKeyChord(parsing: "cmd+6"), .workspaceFocus6),
        (try! OpenMUXKeyChord(parsing: "cmd+7"), .workspaceFocus7),
        (try! OpenMUXKeyChord(parsing: "cmd+8"), .workspaceFocus8),
        (try! OpenMUXKeyChord(parsing: "cmd+9"), .workspaceFocus9),
        (try! OpenMUXKeyChord(parsing: "cmd+b"), .sidebarToggle),
        (try! OpenMUXKeyChord(parsing: "cmd+d"), .paneSplitRight),
        (try! OpenMUXKeyChord(parsing: "cmd+shift+d"), .paneSplitDown),
        (try! OpenMUXKeyChord(parsing: "cmd+shift+w"), .paneRemove),
        (try! OpenMUXKeyChord(parsing: "ctrl+shift+tab"), .paneNext),
        (try! OpenMUXKeyChord(parsing: "cmd+t"), .paneTabCreate),
        (try! OpenMUXKeyChord(parsing: "cmd+w"), .paneTabClose),
        (try! OpenMUXKeyChord(parsing: "ctrl+tab"), .paneTabNext),
    ]

    public static let defaults = OpenMUXKeyBindingRegistry(bindings: Dictionary(uniqueKeysWithValues: defaultBindingPairs))

    private let bindings: [OpenMUXKeyChord: OpenMUXKeyBindingAction]

    public init(bindings: [OpenMUXKeyChord: OpenMUXKeyBindingAction]) {
        self.bindings = bindings
    }

    public static func effective(overrides: [OpenMUXKeyBindingOverride]) -> OpenMUXKeyBindingRegistry {
        var bindings = Dictionary(uniqueKeysWithValues: defaultBindingPairs)
        for override in overrides {
            if let action = override.action {
                bindings[override.chord] = action
            } else {
                bindings.removeValue(forKey: override.chord)
            }
        }
        return OpenMUXKeyBindingRegistry(bindings: bindings)
    }

    public func action(for raw: RawKeyInput) -> OpenMUXKeyBindingAction? {
        for (chord, action) in bindings where chord.matches(raw) {
            return action
        }
        return nil
    }

    public func contains(_ raw: RawKeyInput) -> Bool {
        action(for: raw) != nil
    }

    public func chord(for action: OpenMUXKeyBindingAction) -> OpenMUXKeyChord? {
        bindings
            .filter { $0.value == action }
            .map(\.key)
            .sorted { $0.description < $1.description }
            .first
    }

    public var sortedBindings: [(OpenMUXKeyChord, OpenMUXKeyBindingAction)] {
        bindings.sorted { lhs, rhs in
            lhs.key.description < rhs.key.description
        }
    }
}

private extension KeyModifiers {
    var containsShift: Bool {
        intersection([.leftShift, .rightShift]).isEmpty == false
    }

    var containsControl: Bool {
        intersection([.leftControl, .rightControl]).isEmpty == false
    }

    func matchesChordModifiers(_ expected: KeyModifiers) -> Bool {
        let expectedCommand = expected.containsCommand
        let expectedControl = expected.containsControl
        let expectedShift = expected.containsShift

        return containsCommand == expectedCommand
            && containsControl == expectedControl
            && containsShift == expectedShift
            && intersection([.leftOption, .rightOption, .function]).isEmpty
            && subtracting([
                .leftCommand, .rightCommand,
                .leftControl, .rightControl,
                .leftShift, .rightShift,
                .capsLock,
            ]).isEmpty
    }
}
