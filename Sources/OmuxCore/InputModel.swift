import Foundation

public struct KeyModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public static let leftShift = KeyModifiers(rawValue: 1 << 0)
    public static let rightShift = KeyModifiers(rawValue: 1 << 1)
    public static let leftControl = KeyModifiers(rawValue: 1 << 2)
    public static let rightControl = KeyModifiers(rawValue: 1 << 3)
    public static let leftOption = KeyModifiers(rawValue: 1 << 4)
    public static let rightOption = KeyModifiers(rawValue: 1 << 5)
    public static let leftCommand = KeyModifiers(rawValue: 1 << 6)
    public static let rightCommand = KeyModifiers(rawValue: 1 << 7)
    public static let function = KeyModifiers(rawValue: 1 << 8)
    public static let capsLock = KeyModifiers(rawValue: 1 << 9)
}

extension KeyModifiers: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(UInt16.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum KeyEventPhase: String, Codable, Sendable {
    case keyDown
    case keyUp
}

public struct RawKeyInput: Equatable, Codable, Sendable {
    public var keyCode: UInt16?
    public var characters: String
    public var charactersIgnoringModifiers: String
    public var modifiers: KeyModifiers
    public var phase: KeyEventPhase
    public var isRepeat: Bool
    public var isComposing: Bool

    public init(
        keyCode: UInt16? = nil,
        characters: String,
        charactersIgnoringModifiers: String,
        modifiers: KeyModifiers = [],
        phase: KeyEventPhase = .keyDown,
        isRepeat: Bool = false,
        isComposing: Bool = false
    ) {
        self.keyCode = keyCode
        self.characters = characters
        self.charactersIgnoringModifiers = charactersIgnoringModifiers
        self.modifiers = modifiers
        self.phase = phase
        self.isRepeat = isRepeat
        self.isComposing = isComposing
    }
}

public enum NormalizedInputRoute: String, Codable, Sendable {
    case terminal
    case shortcut
    case composition
}

public struct NormalizedKeyEvent: Equatable, Codable, Sendable {
    public var keyCode: UInt16?
    public var key: String
    public var text: String?
    public var modifiers: KeyModifiers
    public var phase: KeyEventPhase
    public var isRepeat: Bool
    public var route: NormalizedInputRoute

    public init(
        keyCode: UInt16?,
        key: String,
        text: String?,
        modifiers: KeyModifiers,
        phase: KeyEventPhase,
        isRepeat: Bool,
        route: NormalizedInputRoute
    ) {
        self.keyCode = keyCode
        self.key = key
        self.text = text
        self.modifiers = modifiers
        self.phase = phase
        self.isRepeat = isRepeat
        self.route = route
    }
}

public protocol KeyEventNormalizing {
    func normalize(_ raw: RawKeyInput) -> NormalizedKeyEvent
}

public struct DefaultKeyEventNormalizer: KeyEventNormalizing, Sendable {
    public init() {}

    public func normalize(_ raw: RawKeyInput) -> NormalizedKeyEvent {
        let key = raw.charactersIgnoringModifiers.isEmpty
            ? raw.characters
            : raw.charactersIgnoringModifiers

        let text: String?
        if raw.characters.isEmpty || raw.isComposing {
            text = nil
        } else {
            text = raw.characters
        }

        let route: NormalizedInputRoute
        if raw.isComposing {
            route = .composition
        } else if OpenMUXShortcutClassifier.isOpenMUXShortcut(raw) {
            route = .shortcut
        } else {
            route = .terminal
        }

        return NormalizedKeyEvent(
            keyCode: raw.keyCode,
            key: key,
            text: text,
            modifiers: raw.modifiers,
            phase: raw.phase,
            isRepeat: raw.isRepeat,
            route: route
        )
    }
}

public struct OpenMUXShortcutClassifier: Sendable {
    public init() {}

    public static func isOpenMUXShortcut(_ raw: RawKeyInput) -> Bool {
        guard raw.modifiers.containsCommand,
              raw.modifiers.containsOptionOrControl == false
        else {
            return false
        }

        let key = (raw.charactersIgnoringModifiers.isEmpty ? raw.characters : raw.charactersIgnoringModifiers)
            .lowercased()

        switch key {
        case "d":
            return raw.modifiers.containsOnlyCommandOrShift
        case "b", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
            return raw.modifiers.containsOnlyCommand
        default:
            return false
        }
    }
}

public extension KeyModifiers {
    var containsCommand: Bool {
        intersection([.leftCommand, .rightCommand]).isEmpty == false
    }

    var containsOptionOrControl: Bool {
        intersection([.leftOption, .rightOption, .leftControl, .rightControl]).isEmpty == false
    }

    var containsOnlyCommand: Bool {
        containsCommand && subtracting([.leftCommand, .rightCommand, .capsLock]).isEmpty
    }

    var containsOnlyCommandOrShift: Bool {
        containsCommand && subtracting([.leftCommand, .rightCommand, .leftShift, .rightShift, .capsLock]).isEmpty
    }
}

public protocol NormalizedKeyEventConsumer {
    func handle(_ event: NormalizedKeyEvent)
}

public struct NormalizedInputPipeline {
    private let normalizer: any KeyEventNormalizing

    public init(normalizer: any KeyEventNormalizing = DefaultKeyEventNormalizer()) {
        self.normalizer = normalizer
    }

    @discardableResult
    public func process(
        _ raw: RawKeyInput,
        consumer: any NormalizedKeyEventConsumer
    ) -> NormalizedKeyEvent {
        let event = normalizer.normalize(raw)
        consumer.handle(event)
        return event
    }
}
