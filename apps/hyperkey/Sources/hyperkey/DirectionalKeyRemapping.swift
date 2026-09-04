import CoreGraphics

/// Rewrites Hyper+Arrow to the matching Vim navigation key before the event
/// reaches macOS or AeroSpace. This keeps arrow navigation on the same reliable
/// path as the existing Hyper+H/J/K/L bindings.
enum DirectionalKeyRemapping {
    private static let keyCodes: [UInt16: UInt16] = [
        0x7B: 0x04, // Left Arrow -> H
        0x7D: 0x26, // Down Arrow -> J
        0x7E: 0x28, // Up Arrow -> K
        0x7C: 0x25, // Right Arrow -> L
    ]

    /// Both keyboard input paths run on the main run loop.
    nonisolated(unsafe) private static var heldArrowKeys: Set<UInt16> = []

    static func begin(keyCode: UInt16) -> UInt16? {
        guard let mappedKeyCode = keyCodes[keyCode] else { return nil }
        heldArrowKeys.insert(keyCode)
        return mappedKeyCode
    }

    static func end(keyCode: UInt16) -> UInt16? {
        guard heldArrowKeys.remove(keyCode) != nil else { return nil }
        return keyCodes[keyCode]
    }

    static func vimKeyFlags(from flags: CGEventFlags) -> CGEventFlags {
        let arrowOnlyFlags = CGEventFlags.maskNumericPad.rawValue
            | CGEventFlags.maskSecondaryFn.rawValue
        return CGEventFlags(rawValue: flags.rawValue & ~arrowOnlyFlags)
    }
}
