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
                modifiers: KeyModifiers(appKitEvent: event),
                phase: .appKitPhase(for: event),
                isRepeat: event.isARepeat,
                isComposing: event.type == .keyDown && (event.characters?.isEmpty ?? true)
            )
        )
    }
}
