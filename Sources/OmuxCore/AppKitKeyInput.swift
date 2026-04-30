#if canImport(AppKit)
import AppKit

public extension KeyModifiers {
    init(appKitEvent event: NSEvent) {
        self = Self.appKitModifierFlags(
            event.modifierFlags,
            keyCode: event.keyCode,
            eventType: event.type
        )
    }

    static func appKitModifierFlags(
        _ flags: NSEvent.ModifierFlags,
        keyCode: UInt16? = nil,
        eventType: NSEvent.EventType? = nil
    ) -> KeyModifiers {
        let rawFlags = flags.rawValue
        var result: KeyModifiers = []

        if flags.contains(.shift) {
            result.insert(rawFlags & UInt(NX_DEVICERSHIFTKEYMASK) != 0 ? .rightShift : .leftShift)
        }
        if flags.contains(.control) {
            result.insert(rawFlags & UInt(NX_DEVICERCTLKEYMASK) != 0 ? .rightControl : .leftControl)
        }
        if flags.contains(.option) {
            result.insert(rawFlags & UInt(NX_DEVICERALTKEYMASK) != 0 ? .rightOption : .leftOption)
        }
        if flags.contains(.command) {
            result.insert(rawFlags & UInt(NX_DEVICERCMDKEYMASK) != 0 ? .rightCommand : .leftCommand)
        }
        if flags.contains(.function) {
            result.insert(.function)
        }
        if flags.contains(.capsLock) {
            result.insert(.capsLock)
        }

        guard let eventType, eventType == .flagsChanged, let keyCode else {
            return result
        }

        let keyPhase = KeyEventPhase.appKitPhase(
            for: eventType,
            keyCode: keyCode,
            modifierFlags: flags
        )
        guard keyPhase == .keyUp else {
            return result
        }

        switch keyCode {
        case 0x38:
            result.insert(.leftShift)
        case 0x3C:
            result.insert(.rightShift)
        case 0x3B:
            result.insert(.leftControl)
        case 0x3E:
            result.insert(.rightControl)
        case 0x3A:
            result.insert(.leftOption)
        case 0x3D:
            result.insert(.rightOption)
        case 0x37:
            result.insert(.leftCommand)
        case 0x36:
            result.insert(.rightCommand)
        case 0x39:
            result.insert(.capsLock)
        case 0x3F:
            result.insert(.function)
        default:
            break
        }

        return result
    }
}

public extension KeyEventPhase {
    static func appKitPhase(for event: NSEvent) -> KeyEventPhase {
        appKitPhase(for: event.type, keyCode: event.keyCode, modifierFlags: event.modifierFlags)
    }

    static func appKitPhase(
        for eventType: NSEvent.EventType,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags
    ) -> KeyEventPhase {
        switch eventType {
        case .keyUp:
            return .keyUp
        case .flagsChanged:
            let rawFlags = modifierFlags.rawValue
            let sidePressed: Bool
            switch keyCode {
            case 0x3C:
                sidePressed = rawFlags & UInt(NX_DEVICERSHIFTKEYMASK) != 0
            case 0x3E:
                sidePressed = rawFlags & UInt(NX_DEVICERCTLKEYMASK) != 0
            case 0x3D:
                sidePressed = rawFlags & UInt(NX_DEVICERALTKEYMASK) != 0
            case 0x36:
                sidePressed = rawFlags & UInt(NX_DEVICERCMDKEYMASK) != 0
            case 0x38:
                sidePressed = modifierFlags.contains(.shift) && rawFlags & UInt(NX_DEVICERSHIFTKEYMASK) == 0
            case 0x3B:
                sidePressed = modifierFlags.contains(.control) && rawFlags & UInt(NX_DEVICERCTLKEYMASK) == 0
            case 0x3A:
                sidePressed = modifierFlags.contains(.option) && rawFlags & UInt(NX_DEVICERALTKEYMASK) == 0
            case 0x37:
                sidePressed = modifierFlags.contains(.command) && rawFlags & UInt(NX_DEVICERCMDKEYMASK) == 0
            case 0x39:
                sidePressed = modifierFlags.contains(.capsLock)
            case 0x3F:
                sidePressed = modifierFlags.contains(.function)
            default:
                sidePressed = true
            }
            return sidePressed ? .keyDown : .keyUp
        default:
            return .keyDown
        }
    }
}
#endif
