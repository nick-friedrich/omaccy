import AppKit

/// Applies the appearance choices behind the Settings pages. Writing the
/// theme/font preferences mirrors scripts/theme.sh and scripts/font.sh: the
/// same ~/.omaccy/theme and ~/.omaccy/font files feed SketchyBar, Ghostty, and
/// this launcher.
enum OmaccyAppearance {
    static var stateDirectory: String { NSHomeDirectory() + "/.omaccy" }

    static var currentThemeName: String {
        preference(named: "theme") ?? "catppuccin"
    }

    static var currentFontKey: String {
        preference(named: "font") ?? "inter"
    }

    /// Theme names with an installed theme file in the canonical config.
    static func availableThemes() -> [String] {
        let directory = stateDirectory + "/config/sketchybar/themes"
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return [] }
        return files.filter { $0.hasSuffix(".sh") }.map { String($0.dropLast(3)) }.sorted()
    }

    /// "tokyo-night" → "Tokyo Night"; custom theme names get the same treatment.
    static func displayName(forTheme name: String) -> String {
        name.split(whereSeparator: { $0 == "-" || $0 == "_" })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    @discardableResult
    static func applyTheme(_ name: String) -> Bool {
        guard availableThemes().contains(name) else { return false }
        writePreference(named: "theme", value: name)
        restartSketchybarIfRunning()
        return true
    }

    @discardableResult
    static func applyFont(_ key: String) -> Bool {
        guard let family = OmaccyTheme.fontFamilies[key] else { return false }
        writePreference(named: "font", value: key)
        updateGhosttyFontFamily(to: family)
        restartSketchybarIfRunning()
        return true
    }

    private static func preference(named name: String) -> String? {
        guard let raw = try? String(contentsOfFile: "\(stateDirectory)/\(name)", encoding: .utf8) else { return nil }
        let firstLine = raw.components(separatedBy: .newlines).first ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func writePreference(named name: String, value: String) {
        try? FileManager.default.createDirectory(atPath: stateDirectory, withIntermediateDirectories: true)
        try? value.write(toFile: "\(stateDirectory)/\(name)", atomically: true, encoding: .utf8)
    }

    /// Replaces Ghostty's font-family line in the canonical config. A missing
    /// config means Omaccy is not installed; the preference still applies to
    /// the bar and launcher.
    private static func updateGhosttyFontFamily(to family: String) {
        let path = stateDirectory + "/config/ghostty/config.ghostty"
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        var lines = raw.components(separatedBy: .newlines).filter { !isFontFamilyAssignment($0) }
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        lines.append("font-family = \(family)")
        try? lines.joined(separator: "\n").appending("\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    private static func isFontFamilyAssignment(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("font-family") else { return false }
        guard let next = trimmed.dropFirst("font-family".count).first else { return false }
        return next == "=" || next == " " || next == "\t"
    }

    /// SketchyBar reads its palette at startup, so a running service restarts
    /// off the UI thread. No-op without Homebrew or a stopped service.
    static func restartSketchybarIfRunning() {
        DispatchQueue.global(qos: .utility).async {
            guard let brew = HomebrewInventory.executable, let brewURL = URL(string: "file://" + brew) else { return }
            guard let listing = HotkeyBindings.run(brewURL, arguments: ["services", "list"], timeout: 15),
                  listing.status == 0 else { return }
            let running = listing.output.split(separator: "\n").contains { line in
                let columns = line.split(separator: " ", omittingEmptySubsequences: true)
                return columns.count >= 2 && columns[0] == "sketchybar" && columns[1] == "started"
            }
            guard running else { return }
            _ = HotkeyBindings.run(brewURL, arguments: ["services", "restart", "sketchybar"], timeout: 60)
        }
    }
}
