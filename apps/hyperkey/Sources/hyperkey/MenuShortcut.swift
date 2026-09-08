import Carbon
import CoreGraphics

/// Translate with the active layout and physical Shift only, before adding Hyper.
/// This lets ? work on both US (Shift+/) and German (Shift+ß) keyboards.
enum MenuShortcut {
    /// Hyper drawn the way keyboard launchers draw it, so a chord reads as a
    /// glyph instead of a sentence.
    static let hyperSymbol = "✦"

    static func hyper(_ key: String) -> String { "\(hyperSymbol) \(key)" }

    /// Rewrites a written chord ("Hyper + Shift + H") for display only. The
    /// written form stays in the entry's own text, so searching for "hyper" or
    /// "shift" still matches what the row says it does.
    static func symbolic(_ chord: String) -> String {
        chord.replacingOccurrences(of: "Hyper + ", with: "\(hyperSymbol) ")
            .replacingOccurrences(of: "Shift + ", with: "⇧ ")
    }

    static func isQuestionMark(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return false
        }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
        let layout = UnsafeRawPointer(CFDataGetBytePtr(data))!
            .assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKey: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let modifiers = flags.contains(.maskShift) ? UInt32(shiftKey >> 8) : 0
        let result = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDown), modifiers,
                                    UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                    &deadKey, characters.count, &length, &characters)
        return result == noErr && length == 1 && characters[0] == 63
    }
}
