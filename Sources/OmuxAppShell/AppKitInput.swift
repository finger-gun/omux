import AppKit
import OmuxCore

public struct AppKitKeyEventNormalizer {
    private let normalizer: any KeyEventNormalizing

    public init(normalizer: any KeyEventNormalizing = DefaultKeyEventNormalizer()) {
        self.normalizer = normalizer
    }

    public func normalize(_ event: NSEvent) -> NormalizedKeyEvent {
        normalizer.normalize(
            RawKeyInput(
                keyCode: event.keyCode,
                characters: event.characters ?? "",
                charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
                modifiers: KeyModifiers(event.modifierFlags),
                phase: event.type == .keyUp ? .keyUp : .keyDown,
                isRepeat: event.isARepeat,
                isComposing: event.characters?.isEmpty ?? true
            )
        )
    }
}

private extension KeyModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var result: KeyModifiers = []
        if flags.contains(.shift) { result.insert(.leftShift) }
        if flags.contains(.control) { result.insert(.leftControl) }
        if flags.contains(.option) { result.insert(.leftOption) }
        if flags.contains(.command) { result.insert(.leftCommand) }
        if flags.contains(.function) { result.insert(.function) }
        if flags.contains(.capsLock) { result.insert(.capsLock) }
        self = result
    }
}
