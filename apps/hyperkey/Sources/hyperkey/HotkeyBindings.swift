import Foundation

/// Consumes configured Hyper chords and opens their application by bundle ID.
/// Access is confined to the main run loop used by both keyboard input paths.
enum HotkeyBindings {
    nonisolated(unsafe) private static var targets: [UInt16: String] = [:]
    nonisolated(unsafe) private static var heldKeys: Set<UInt16> = []

    static func configure(_ bindings: [String: String]) {
        targets.removeAll()
        heldKeys.removeAll()

        for (name, bundleIdentifier) in bindings {
            guard let keyCode = KeyNames.virtualKeyCode(for: name) else {
                fputs("omaccy-hyperkey: ignoring unknown binding key '\(name)'\n", stderr)
                continue
            }
            guard !bundleIdentifier.isEmpty else { continue }
            targets[keyCode] = bundleIdentifier
        }
    }

    /// Returns true when the event belongs to a configured chord and must not
    /// continue into the normal event stream.
    static func handle(keyCode: UInt16, keyDown: Bool) -> Bool {
        if keyDown {
            guard let bundleIdentifier = targets[keyCode] else { return false }
            if heldKeys.insert(keyCode).inserted {
                launch(bundleIdentifier: bundleIdentifier)
            }
            return true
        }

        return heldKeys.remove(keyCode) != nil
    }

    private static func launch(bundleIdentifier: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-b", bundleIdentifier]
        do {
            try process.run()
        } catch {
            fputs("omaccy-hyperkey: could not launch \(bundleIdentifier): \(error)\n", stderr)
        }
    }
}

private enum KeyNames {
    private static let codes: [String: UInt16] = [
        "a": 0x00, "b": 0x0B, "c": 0x08, "d": 0x02,
        "e": 0x0E, "f": 0x03, "g": 0x05, "h": 0x04,
        "i": 0x22, "j": 0x26, "k": 0x28, "l": 0x25,
        "m": 0x2E, "n": 0x2D, "o": 0x1F, "p": 0x23,
        "q": 0x0C, "r": 0x0F, "s": 0x01, "t": 0x11,
        "u": 0x20, "v": 0x09, "w": 0x0D, "x": 0x07,
        "y": 0x10, "z": 0x06,
        "0": 0x1D, "1": 0x12, "2": 0x13, "3": 0x14,
        "4": 0x15, "5": 0x17, "6": 0x16, "7": 0x1A,
        "8": 0x1C, "9": 0x19,
        "enter": 0x24, "return": 0x24, "space": 0x31,
        "tab": 0x30, "escape": 0x35, "backspace": 0x33,
        "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,
    ]

    static func virtualKeyCode(for name: String) -> UInt16? {
        codes[name.lowercased()]
    }
}
