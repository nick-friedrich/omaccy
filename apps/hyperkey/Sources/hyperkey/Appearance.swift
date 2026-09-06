import AppKit

/// Applies the appearance choices behind the Settings pages. Writing the
/// theme/font preferences mirrors scripts/theme.sh and scripts/font.sh: the
/// same ~/.omaccy/theme and ~/.omaccy/font files feed SketchyBar and this
/// launcher. Ghostty's own font stays JetBrains Mono regardless of the font
/// choice here (Inter and Lora aren't monospace); its theme still follows
/// the theme choice.
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
        updateGhosttyTheme(to: name)
        reloadGhosttyIfRunning()
        reloadSketchybarIfRunning()
        return true
    }

    @discardableResult
    static func applyFont(_ key: String) -> Bool {
        guard OmaccyTheme.fontFamilies[key] != nil else { return false }
        writePreference(named: "font", value: key)
        reloadSketchybarIfRunning()
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

    /// Replaces Ghostty's theme line in the canonical config with the theme's
    /// GHOSTTY_THEME match. A theme file without a GHOSTTY_THEME assignment
    /// (e.g. a custom theme) leaves Ghostty's existing theme alone.
    private static func updateGhosttyTheme(to name: String) {
        guard let ghosttyTheme = OmaccyTheme.ghosttyThemeName(named: name) else { return }
        let path = stateDirectory + "/config/ghostty/config.ghostty"
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        var lines = raw.components(separatedBy: .newlines).filter { !isThemeAssignment($0) }
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        lines.append("theme = \(ghosttyTheme)")
        try? lines.joined(separator: "\n").appending("\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    private static func isThemeAssignment(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("theme") else { return false }
        guard let next = trimmed.dropFirst("theme".count).first else { return false }
        return next == "=" || next == " " || next == "\t"
    }

    /// SketchyBar's own `--reload` re-sources its config (and therefore the
    /// new theme/font) in place over its existing IPC socket: no launchd
    /// stop/start, no bar flicker, and it lands in well under a second. That
    /// replaces the old `brew services restart sketchybar`, which tore the
    /// whole process down and back up for every single theme/font change.
    /// If sketchybar isn't running, the reload call fails fast and is
    /// ignored — no need to check first.
    static func reloadSketchybarIfRunning() {
        DispatchQueue.global(qos: .utility).async {
            guard let sketchybar = ["/opt/homebrew/bin/sketchybar", "/usr/local/bin/sketchybar"].first(where: {
                FileManager.default.isExecutableFile(atPath: $0)
            }), let sketchybarURL = URL(string: "file://" + sketchybar) else { return }
            _ = HotkeyBindings.run(sketchybarURL, arguments: ["--reload"], timeout: 5)
        }
    }

    /// Ghostty does not watch its config file for changes on macOS, and its
    /// only CLI-level reload command (`+new-window`) is GTK-only. Its bundled
    /// scripting dictionary (Ghostty.sdef) exposes "perform action" as a
    /// native AppleScript command though, so this needs no Accessibility
    /// permission (unlike System Events UI scripting) — just the ordinary
    /// Apple Events automation already implied by launching Ghostty at all.
    /// Checking for a running instance first matters here: unlike sketchybar's
    /// CLI, `tell application "Ghostty"` launches it if it isn't running.
    static func reloadGhosttyIfRunning() {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.mitchellh.ghostty").isEmpty else { return }
        DispatchQueue.global(qos: .utility).async {
            let script = """
            tell application "Ghostty" to try
                perform action "reload_config" on terminal 1 of window 1
            end try
            """
            _ = HotkeyBindings.run(URL(fileURLWithPath: "/usr/bin/osascript"), arguments: ["-e", script], timeout: 5)
        }
    }
}
