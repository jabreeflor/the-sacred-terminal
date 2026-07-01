import AppKit
import GhosttyKit

extension NSEvent {
    /// Build a libghostty key event. Callers set `text` and `composing` when needed.
    func ghosttyKeyEvent(
        _ action: ghostty_input_action_e,
        translationMods: NSEvent.ModifierFlags? = nil
    ) -> ghostty_input_key_s {
        var key = ghostty_input_key_s()
        key.action = action
        key.keycode = UInt32(keyCode)
        key.text = nil
        key.composing = false
        key.mods = GhosttyInput.mods(from: modifierFlags)
        key.consumed_mods = GhosttyInput.mods(
            from: (translationMods ?? modifierFlags).subtracting([.control, .command])
        )
        key.unshifted_codepoint = 0
        if type == .keyDown || type == .keyUp,
           let chars = characters(byApplyingModifiers: []),
           let codepoint = chars.unicodeScalars.first {
            key.unshifted_codepoint = codepoint.value
        }
        return key
    }

    /// Text payload for a key event, omitting control chars and macOS function-key PUAs.
    var ghosttyCharacters: String? {
        guard let chars = characters else { return nil }
        if chars.count == 1, let scalar = chars.unicodeScalars.first {
            if scalar.value < 0x20 {
                return self.characters(byApplyingModifiers: modifierFlags.subtracting(.control))
            }
            if scalar.value >= 0xF700 && scalar.value <= 0xF8FF { return nil }
        }
        return chars
    }
}

extension GhosttyInput {
    static func translatedModifierFlags(for event: NSEvent, surface: GhosttySurface) -> NSEvent.ModifierFlags {
        let translated = surface.translateKeyMods(mods(from: event.modifierFlags))
        let translatedFlags = eventModifierFlags(from: translated)
        var result = event.modifierFlags
        for flag in [NSEvent.ModifierFlags.shift, .control, .option, .command] {
            if translatedFlags.contains(flag) { result.insert(flag) }
            else { result.remove(flag) }
        }
        return result
    }

    private static func eventModifierFlags(from mods: ghostty_input_mods_e) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        let raw = mods.rawValue
        if raw & GHOSTTY_MODS_SHIFT.rawValue != 0 { flags.insert(.shift) }
        if raw & GHOSTTY_MODS_CTRL.rawValue != 0 { flags.insert(.control) }
        if raw & GHOSTTY_MODS_ALT.rawValue != 0 { flags.insert(.option) }
        if raw & GHOSTTY_MODS_SUPER.rawValue != 0 { flags.insert(.command) }
        return flags
    }
}
