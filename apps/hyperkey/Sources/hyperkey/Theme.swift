import AppKit

/// Omaccy's shared look for the launcher palette. Colors come from the active
/// SketchyBar theme file (scripts/theme.sh stores the choice in
/// ~/.omaccy/theme) so the bar and the palette always match; the font comes
/// from scripts/font.sh. Everything falls back to Catppuccin Mocha and the
/// system font when a preference or theme file is missing.
struct OmaccyTheme {
    let name: String
    let background: NSColor
    let border: NSColor
    let accent: NSColor
    let text: NSColor
    let muted: NSColor
    let fontFamily: String?

    /// Font switcher keys (scripts/font.sh) mapped to their family names.
    static let fontFamilies = [
        "inter": "Inter",
        "jetbrains-mono": "JetBrains Mono",
        "serif": "Lora"
    ]

    /// Stable ordering for the font settings list.
    static let fontKeys = ["inter", "jetbrains-mono", "serif"]

    /// The theme's accent color for row previews; nil when the theme file or
    /// its ACCENT assignment is missing.
    static func accentColor(named name: String) -> NSColor? {
        palette(from: "\(NSHomeDirectory())/.omaccy/config/sketchybar/themes/\(name).sh")["ACCENT"]
    }

    var identity: String { name + "/" + (fontFamily ?? "system") }

    static func load() -> OmaccyTheme {
        let stateDirectory = NSHomeDirectory() + "/.omaccy"
        let name = preference(from: stateDirectory + "/theme") ?? "catppuccin"
        var colors = palette(from: "\(stateDirectory)/config/sketchybar/themes/\(name).sh")
        if colors.isEmpty {
            colors = palette(from: "\(stateDirectory)/config/sketchybar/themes/catppuccin.sh")
        }
        let fontKey = preference(from: stateDirectory + "/font") ?? "inter"
        return OmaccyTheme(
            name: name,
            background: colors["BAR_BG"] ?? color(0x11111b),
            border: colors["BORDER"] ?? color(0x45475a),
            accent: colors["ACCENT"] ?? color(0x89b4fa),
            text: colors["TEXT"] ?? color(0xcdd6f4),
            muted: colors["MUTED"] ?? color(0x7f849c),
            fontFamily: fontFamilies[fontKey]
        )
    }

    private static func preference(from path: String) -> String? {
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let firstLine = raw.components(separatedBy: .newlines).first ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Reads KEY=0xAARRGGBB palette assignments, ignoring comments. Returns an
    /// empty dictionary when the file is missing or malformed.
    static func palette(fromFile path: String) -> [String: NSColor] {
        palette(from: path)
    }

    private static func palette(from path: String) -> [String: NSColor] {
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { return [:] }
        var colors: [String: NSColor] = [:]
        for rawLine in raw.components(separatedBy: .newlines) {
            let withoutComment = rawLine.split(separator: "#", maxSplits: 1,
                                               omittingEmptySubsequences: false).first.map(String.init) ?? rawLine
            let parts = withoutComment.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            var value = parts[1].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("0x") { value.removeFirst(2) }
            guard value.count == 8, let hex = UInt32(value, radix: 16) else { continue }
            colors[parts[0].trimmingCharacters(in: .whitespaces)] = NSColor(
                calibratedRed: CGFloat((hex >> 16) & 0xff) / 255,
                green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255,
                alpha: CGFloat((hex >> 24) & 0xff) / 255
            )
        }
        return colors
    }

    private static func color(_ rgb: UInt32) -> NSColor {
        NSColor(calibratedRed: CGFloat((rgb >> 16) & 0xff) / 255,
                green: CGFloat((rgb >> 8) & 0xff) / 255,
                blue: CGFloat(rgb & 0xff) / 255,
                alpha: 1)
    }
}
