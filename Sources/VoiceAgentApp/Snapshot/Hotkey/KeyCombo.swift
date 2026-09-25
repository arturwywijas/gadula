// Pochodzi ze snapshotu vlr-code/dictly (MIT).
import AppKit
import Carbon.HIToolbox
import VoiceAgentCore

// Dane, wybór i migracja są w rdzeniu; tutaj tylko interpretacja klawiszy macOS.
typealias KeyCombo = UstawienieSkrotu

extension KeyCombo {
    static func combo(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> KeyCombo {
        KeyCombo(
            kind: .keyCombo,
            solo: nil,
            keyCode: keyCode,
            modifierFlags: modifiers.intersection(.deviceIndependentFlagsMask).rawValue
        )
    }

    var displayName: String {
        switch kind {
        case .modifierOnly:
            return solo?.displayName ?? "-"
        case .keyCombo:
            return Self.string(forKeyCode: keyCode ?? 0,
                               modifiers: NSEvent.ModifierFlags(rawValue: modifierFlags))
        }
    }

    func isPressed(flags: NSEvent.ModifierFlags) -> Bool {
        guard let solo else { return false }
        return solo.isPressed(flags: flags)
    }

    nonisolated static func string(forKeyCode keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option)  { s += "⌥" }
        if modifiers.contains(.shift)   { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        s += keyName(for: keyCode)
        return s
    }

    nonisolated private static func keyName(for keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Escape: return "Esc"
        case kVK_Tab: return "Tab"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Home: return "Home"
        case kVK_End: return "End"
        case kVK_PageUp: return "Page Up"
        case kVK_PageDown: return "Page Down"
        case kVK_Help: return "Help"
        case kVK_F1: return "F1"; case kVK_F2: return "F2"; case kVK_F3: return "F3"
        case kVK_F4: return "F4"; case kVK_F5: return "F5"; case kVK_F6: return "F6"
        case kVK_F7: return "F7"; case kVK_F8: return "F8"; case kVK_F9: return "F9"
        case kVK_F10: return "F10"; case kVK_F11: return "F11"; case kVK_F12: return "F12"
        case kVK_F13: return "F13"; case kVK_F14: return "F14"; case kVK_F15: return "F15"
        case kVK_F16: return "F16"; case kVK_F17: return "F17"; case kVK_F18: return "F18"
        case kVK_F19: return "F19"; case kVK_F20: return "F20"
        default:
            if let layout = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
               let ptr = TISGetInputSourceProperty(layout, kTISPropertyUnicodeKeyLayoutData) {
                let data = unsafeBitCast(ptr, to: CFData.self) as Data
                return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> String in
                    let layoutPtr = raw.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self)
                    var deadKeys: UInt32 = 0
                    var length = 0
                    var chars = [UniChar](repeating: 0, count: 4)
                    let err = UCKeyTranslate(
                        layoutPtr,
                        keyCode,
                        UInt16(kUCKeyActionDisplay),
                        0,
                        UInt32(LMGetKbdType()),
                        UInt32(kUCKeyTranslateNoDeadKeysBit),
                        &deadKeys,
                        chars.count,
                        &length,
                        &chars
                    )
                    if err == noErr, length > 0 {
                        return String(utf16CodeUnits: chars, count: length).uppercased()
                    }
                    return "Key\(keyCode)"
                }
            }
            return "Key\(keyCode)"
        }
    }
}

extension KeyCombo.SoloModifier {
    func isPressed(flags: NSEvent.ModifierFlags) -> Bool {
        let raw = flags.rawValue
        switch self {
        case .fn:           return flags.contains(.function)
        case .leftControl:  return raw & 0x00000001 != 0
        case .rightShift:   return raw & 0x00000004 != 0
        case .rightCommand: return raw & 0x00000010 != 0
        case .leftOption:   return raw & 0x00000020 != 0
        case .rightOption:  return raw & 0x00000040 != 0
        case .rightControl: return raw & 0x00002000 != 0
        }
    }
}

extension KeyCombo.SoloModifier {
        var displayName: String {
            switch self {
            case .fn: return "Fn"
            case .rightOption: return "Right ⌥"
            case .leftOption: return "Left ⌥"
            case .rightControl: return "Right ⌃"
            case .leftControl: return "Left ⌃"
            case .rightCommand: return "Right ⌘"
            case .rightShift: return "Right ⇧"
            }
        }

}
