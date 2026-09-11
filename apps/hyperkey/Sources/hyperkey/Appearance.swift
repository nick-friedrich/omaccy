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

    /// Whether VS Code and Cursor follow the theme too. Opt-in, since their
    /// settings files belong to the user rather than to Omaccy and keeping up
    /// can mean installing a marketplace extension. `scripts/theme.sh editors
    /// on` writes it.
    static var editorThemingEnabled: Bool {
        preference(named: "editor-theme") == "on"
    }

    /// Theme names with an installed theme file in the canonical config.
    static func availableThemes() -> [String] {
        let directory = stateDirectory + "/config/sketchybar/themes"
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return [] }
        return files.filter { $0.hasSuffix(".sh") }.map { String($0.dropLast(3)) }.sorted()
    }

    /// Themes whose brand capitalization the generic rule below would get
    /// wrong ("github-dark" would title-case into "Github Dark").
    private static let themeDisplayNames = ["github-dark": "GitHub Dark"]

    /// "tokyo-night" → "Tokyo Night"; custom theme names get the same treatment.
    static func displayName(forTheme name: String) -> String {
        if let known = themeDisplayNames[name] { return known }
        return name.split(whereSeparator: { $0 == "-" || $0 == "_" })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    @discardableResult
    static func applyTheme(_ name: String) -> Bool {
        guard availableThemes().contains(name) else { return false }
        writePreference(named: "theme", value: name)
        updateGhosttyTheme(to: name)
        reloadGhosttyIfRunning()
        updateMacOSAppearance(to: name)
        updateEditorThemes(to: name)
        updateHerdrTheme(to: name)
        reloadSketchybarIfRunning()
        return true
    }

    /// Whether macOS light/dark follows the theme. Opt-in: flipping the whole
    /// system's appearance is a large, visible side effect of picking a
    /// launcher palette, and it needs a one-time automation prompt.
    static var macOSAppearanceEnabled: Bool {
        preference(named: "appearance") == "on"
    }

    static func setMacOSAppearanceFollowing(_ enabled: Bool) {
        if enabled { recordOriginalAppearance() }
        writePreference(named: "appearance", value: enabled ? "on" : "off")
        guard enabled else { return }
        updateMacOSAppearance(to: currentThemeName)
    }

    /// The appearance is a macOS preference Omaccy takes over, so the value it
    /// found is kept the way scripts/lib/macos.sh keeps the ones it changes —
    /// uninstall puts it back. Mirrors `record_original_appearance`.
    private static func recordOriginalAppearance() {
        let path = stateDirectory + "/appearance.original"
        guard !FileManager.default.fileExists(atPath: path) else { return }
        let dark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        try? FileManager.default.createDirectory(atPath: stateDirectory, withIntermediateDirectories: true)
        try? (dark ? "dark" : "light").write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Writing AppleInterfaceStyle with `defaults` does not take effect live —
    /// running apps stay on the old appearance until they restart. System
    /// Events' appearance preferences is the supported route, and like the
    /// Ghostty reload it is ordinary Apple Events automation rather than UI
    /// scripting, so it needs no Accessibility permission. Mirrors
    /// `update_macos_appearance` in scripts/theme.sh.
    /// A theme file with no APPEARANCE gets no guess: defaulting to dark is
    /// how a light palette came to set macOS to Dark, when the installed copy
    /// of the theme predated the key. A wrong appearance is worse than none.
    private static func updateMacOSAppearance(to name: String) {
        guard macOSAppearanceEnabled, let appearance = OmaccyTheme.appearance(named: name) else { return }
        let dark = appearance != "light"
        DispatchQueue.global(qos: .utility).async {
            let script = "tell application \"System Events\" to tell appearance preferences "
                + "to set dark mode to \(dark)"
            _ = HotkeyBindings.run(URL(fileURLWithPath: "/usr/bin/osascript"),
                                   arguments: ["-e", script], timeout: 15)
        }
    }

    /// Records the opt-in and, when switching it on, brings the editors up to
    /// the current theme immediately rather than waiting for the next switch.
    static func setEditorTheming(_ enabled: Bool) {
        writePreference(named: "editor-theme", value: enabled ? "on" : "off")
        guard enabled else { return }
        updateEditorThemes(to: currentThemeName)
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

    /// herdr's config.toml is the user's own file — herdr writes it during
    /// its onboarding — so only `name` under `[theme]` is rewritten, the
    /// original is kept once in the backups, and a missing file stays
    /// missing. herdr rereads it on `herdr server reload-config`, which
    /// reaches the running session without disturbing the agents in it. The
    /// write goes to a link's target, so a config linked in from a dotfiles
    /// repository stays a link. Mirrors `update_herdr_theme` in
    /// scripts/theme.sh.
    private static func updateHerdrTheme(to name: String) {
        guard let herdrTheme = OmaccyTheme.herdrThemeName(named: name) else { return }
        let path = ((NSHomeDirectory() + "/.config/herdr/config.toml") as NSString).resolvingSymlinksInPath
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        let updated = herdrConfig(raw, settingTheme: herdrTheme,
                                  accent: OmaccyTheme.herdrAccent(named: name),
                                  panelBackground: OmaccyTheme.herdrPanelBackground(named: name))
        guard updated != raw else { return }
        let backup = stateDirectory + "/backups/herdr-config.toml"
        if !FileManager.default.fileExists(atPath: backup) {
            try? FileManager.default.createDirectory(atPath: stateDirectory + "/backups",
                                                     withIntermediateDirectories: true)
            try? raw.write(toFile: backup, atomically: true, encoding: .utf8)
        }
        guard (try? updated.write(toFile: path, atomically: true, encoding: .utf8)) != nil else { return }
        reloadHerdrIfRunning()
    }

    /// Talks to the running server over its socket, so with no server it
    /// fails fast rather than starting one.
    private static func reloadHerdrIfRunning() {
        let candidates = ["/opt/homebrew/bin/herdr", "/usr/local/bin/herdr"]
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return
        }
        DispatchQueue.global(qos: .utility).async {
            _ = HotkeyBindings.run(URL(fileURLWithPath: path), arguments: ["server", "reload-config"], timeout: 10)
        }
    }

    /// Sets `name` under `[theme]` and leaves every other line as it was: the
    /// name line replaced where the table has one, added under the header
    /// where it has none, and a `[theme]` table appended where the file has
    /// none. Always ends in a newline. Line-based for the same reason as
    /// `settings(_:settingTheme:)` — reserializing TOML would drop the user's
    /// comments — and implemented in awk too, in scripts/lib/herdr-settings.sh,
    /// which HerdrConfigTests holds to the same bytes.
    ///
    /// `accent` and `panelBackground` go under `[theme.custom]`; nil or empty
    /// means none. Each color line Omaccy writes is marked `# omaccy`, so
    /// those lines — and only those — are replaced or removed on the next
    /// switch. An unmarked accent or panel_bg is the user's own and wins:
    /// Omaccy adds none of its own beside it.
    static func herdrConfig(_ contents: String, settingTheme theme: String,
                            accent: String? = nil, panelBackground: String? = nil) -> String {
        var lines = contents.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        let nameEntry = "name = \"\(theme)\""
        // A value with a quote in it could only come from a misread theme file,
        // and would write broken TOML, so it counts as no color at all.
        func usable(_ color: String?) -> String? {
            guard let color, !color.isEmpty, !color.contains("\"") else { return nil }
            return color
        }
        let wanted: [(key: String, value: String?)] = [
            ("accent", usable(accent)),
            ("panel_bg", usable(panelBackground))
        ]
        func customEntry(_ key: String, _ value: String) -> String { "\(key) = \"\(value)\" # omaccy" }

        // Which table each line is in, and which colors the user set themselves.
        var table = ""
        var tables: [String] = []
        var themeHeader: Int?
        var customHeader: Int?
        var owned = Set<String>()
        for (index, line) in lines.enumerated() {
            let code = line.drop(while: isBlank)
            if code.hasPrefix("[") {
                table = herdrTable(code)
                tables.append("header")
                if table == "theme" && themeHeader == nil { themeHeader = index }
                if table == "theme.custom" && customHeader == nil { customHeader = index }
                continue
            }
            tables.append(table)
            if table == "theme.custom", let key = herdrCustomKey(code), !isOmaccyMarked(line) { owned.insert(key) }
        }

        var replaced = false
        var written = Set<String>()
        var dropped = Set<Int>()
        func needed(_ key: String) -> String? {
            guard let value = wanted.first(where: { $0.key == key })?.value,
                  !owned.contains(key), !written.contains(key) else { return nil }
            return value
        }
        for (index, line) in lines.enumerated() {
            let code = line.drop(while: isBlank)
            let indent = String(line.prefix(while: isBlank))
            if tables[index] == "theme" && !replaced && isHerdrNameAssignment(code) {
                lines[index] = indent + nameEntry + carriageReturn(of: line)
                replaced = true
            } else if tables[index] == "theme.custom", let key = herdrCustomKey(code), isOmaccyMarked(line) {
                if let value = needed(key) {
                    lines[index] = indent + customEntry(key, value) + carriageReturn(of: line)
                    written.insert(key)
                } else {
                    dropped.insert(index)
                }
            }
        }

        let missing = wanted.compactMap { item in needed(item.key).map { customEntry(item.key, $0) } }
        var output: [String] = []
        for (index, line) in lines.enumerated() where !dropped.contains(index) {
            output.append(line)
            if index == themeHeader && !replaced { output.append(nameEntry) }
            if index == customHeader { output.append(contentsOf: missing) }
        }
        if themeHeader == nil {
            if !lines.isEmpty { output.append("") }
            output.append(contentsOf: ["[theme]", nameEntry])
        }
        if customHeader == nil && !missing.isEmpty {
            output.append(contentsOf: ["", "[theme.custom]"] + missing)
        }
        return output.joined(separator: "\n") + "\n"
    }

    private static func isBlank(_ character: Character) -> Bool {
        character == " " || character == "\t"
    }

    /// "theme" for `[theme]` and "theme.custom" for `[theme.custom]`, each
    /// optionally padded and followed by a comment; "other" for any other
    /// header, `[theme.custom.dark]` included.
    private static func herdrTable(_ code: Substring) -> String {
        var rest = code.dropFirst().drop(while: isBlank)
        let name: String
        if rest.hasPrefix("theme.custom") {
            name = "theme.custom"
        } else if rest.hasPrefix("theme") {
            name = "theme"
        } else {
            return "other"
        }
        rest = rest.dropFirst(name.count).drop(while: isBlank)
        guard rest.hasPrefix("]") else { return "other" }
        rest = rest.dropFirst().drop(while: isBlank)
        if rest.hasPrefix("#") { return name }
        if rest.hasSuffix("\r") { rest = rest.dropLast() }
        return rest.isEmpty ? name : "other"
    }

    private static func isHerdrNameAssignment(_ code: Substring) -> Bool {
        guard code.hasPrefix("name") else { return false }
        return code.dropFirst("name".count).drop(while: isBlank).hasPrefix("=")
    }

    private static func herdrCustomKey(_ code: Substring) -> String? {
        for key in ["accent", "panel_bg"] where code.hasPrefix(key) {
            if code.dropFirst(key.count).drop(while: isBlank).hasPrefix("=") { return key }
        }
        return nil
    }

    private static func isOmaccyMarked(_ line: String) -> Bool {
        (line.hasSuffix("\r") ? String(line.dropLast()) : line).hasSuffix("# omaccy")
    }

    private struct Editor {
        let binary: String
        let name: String
        /// Its directory under ~/Library/Application Support.
        let supportDirectory: String
    }

    private static let editors = [
        Editor(binary: "code", name: "Visual Studio Code", supportDirectory: "Code"),
        Editor(binary: "cursor", name: "Cursor", supportDirectory: "Cursor")
    ]

    /// VS Code and Cursor watch their own settings.json and repaint the moment
    /// workbench.colorTheme changes, so unlike Ghostty they need no reload
    /// nudge at all. What they do need is the theme itself: every palette here
    /// but Solarized Dark lives in a marketplace extension, which is why this
    /// installs one when it is missing. That install is a network round-trip
    /// of its own, so the whole pass runs off the main thread — the palette
    /// stays responsive while an extension downloads. Mirrors
    /// `update_editor_themes` in scripts/theme.sh.
    private static func updateEditorThemes(to name: String) {
        guard editorThemingEnabled, let label = OmaccyTheme.vscodeThemeName(named: name) else { return }
        let extensionID = OmaccyTheme.vscodeExtensionID(named: name)
        DispatchQueue.global(qos: .utility).async {
            for editor in editors {
                guard let cli = commandLineTool(for: editor) else { continue }
                if let extensionID { installExtension(extensionID, using: cli) }
                applyColorTheme(label, to: editor)
            }
        }
    }

    /// The `code` / `cursor` launchers are on PATH only when the user ran the
    /// editor's "Install 'code' command in PATH" step; the copy inside the app
    /// bundle is always there.
    private static func commandLineTool(for editor: Editor) -> URL? {
        let candidates = [
            "/opt/homebrew/bin/\(editor.binary)",
            "/usr/local/bin/\(editor.binary)",
            "/Applications/\(editor.name).app/Contents/Resources/app/bin/\(editor.binary)"
        ]
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    /// Best effort: a failed install still leaves the color theme written, so
    /// the editor picks the palette up whenever the extension does arrive.
    private static func installExtension(_ identifier: String, using cli: URL) {
        guard let listed = HotkeyBindings.run(cli, arguments: ["--list-extensions"], timeout: 30) else { return }
        let installed = listed.output.components(separatedBy: .newlines).contains {
            $0.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(identifier) == .orderedSame
        }
        guard !installed else { return }
        _ = HotkeyBindings.run(cli, arguments: ["--install-extension", identifier, "--force"], timeout: 180)
    }

    private static func applyColorTheme(_ label: String, to editor: Editor) {
        let path = "\(NSHomeDirectory())/Library/Application Support/\(editor.supportDirectory)/User/settings.json"
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8),
              let updated = settings(raw, settingTheme: label), updated != raw else { return }
        backUpEditorSettings(at: path, for: editor)
        try? updated.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Keeps the untouched original once, the way the setup scripts preserve
    /// every file they displace.
    private static func backUpEditorSettings(at path: String, for editor: Editor) {
        let backup = "\(stateDirectory)/backups/\(editor.supportDirectory)-settings.json"
        guard !FileManager.default.fileExists(atPath: backup) else { return }
        try? FileManager.default.createDirectory(atPath: stateDirectory + "/backups",
                                                 withIntermediateDirectories: true)
        try? FileManager.default.copyItem(atPath: path, toPath: backup)
    }

    /// Rewrites — or inserts — the workbench.colorTheme entry and leaves every
    /// other line, comments and trailing commas included, exactly as it was.
    /// These files are JSONC, so parsing and reserializing would silently drop
    /// the user's comments; this stays line-based for the same reason
    /// `updateGhosttyTheme` does. Nil when the file's shape leaves nowhere safe
    /// to insert, which is left alone rather than guessed at.
    static func settings(_ contents: String, setting key: String, to value: String,
                         quoted: Bool = true) -> String? {
        var lines = contents.components(separatedBy: "\n")
        func entry(indent: String, comma: String, terminator: String) -> String {
            let quote = quoted ? "\"" : ""
            return "\(indent)\"\(key)\": \(quote)\(value)\(quote)\(comma)\(terminator)"
        }
        if let index = lines.firstIndex(where: { isAssignment($0, of: key) }) {
            let line = lines[index]
            let terminator = carriageReturn(of: line)
            let (code, comment) = splitTrailingComment(String(line.dropLast(terminator.count)))
            let comma = code.trimmingCharacters(in: .whitespaces).hasSuffix(",") ? "," : ""
            lines[index] = entry(indent: leadingWhitespace(of: line), comma: comma,
                                 terminator: (comment.isEmpty ? "" : " " + comment) + terminator)
            return lines.joined(separator: "\n")
        }
        // No entry yet, so it goes in first — which only works for the shape
        // the editors write themselves: "{" alone on the opening line.
        guard let open = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              lines[open].trimmingCharacters(in: .whitespacesAndNewlines) == "{" else { return nil }
        let rest = lines[(open + 1)...]
        let body = rest.joined().filter { !$0.isWhitespace }
        let comma = (body.isEmpty || body == "}") ? "" : ","
        let indent = rest.first { $0.contains { !$0.isWhitespace } }.map(leadingWhitespace) ?? ""
        lines.insert(entry(indent: indent.isEmpty ? "  " : indent, comma: comma,
                           terminator: carriageReturn(of: lines[open])), at: open + 1)
        return lines.joined(separator: "\n")
    }

    /// CRLF files leave a carriage return on the end of every line once the
    /// text is split on "\n", and it has to go back on the line this writes:
    /// `CharacterSet.whitespaces` does not cover it — that is `.newlines` —
    /// so a trailing comma hidden behind one reads as absent, which silently
    /// invalidates the JSON, and a line rewritten without it leaves a single
    /// odd terminator in an otherwise CRLF file. VS Code writes CRLF on
    /// plenty of machines. awk's `[[:space:]]` does include it, which is why
    /// scripts/theme.sh never had to say any of this.
    private static func carriageReturn(of line: String) -> String {
        line.hasSuffix("\r") ? "\r" : ""
    }

    /// Splits a line into its JSON and any comment trailing it, so the comma
    /// is read from the JSON alone. `"…": "Nord", // pinned` ends in the
    /// comment, and reading the comma off the whole line drops it and breaks
    /// the file — the same way a carriage return did. A `//` inside a string
    /// (a URL value) is not a comment, so this tracks quoting rather than
    /// searching for the characters. The comment is handed back to be kept.
    private static func splitTrailingComment(_ line: String) -> (code: String, comment: String) {
        var inString = false
        var escaped = false
        let characters = Array(line)
        for (index, character) in characters.enumerated() {
            if inString {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
                continue
            }
            if character == "\"" { inString = true; continue }
            guard character == "/", index + 1 < characters.count,
                  characters[index + 1] == "/" || characters[index + 1] == "*" else { continue }
            return (String(characters[..<index]), String(characters[index...]))
        }
        return (line, "")
    }

    private static func leadingWhitespace(of line: String) -> String {
        String(line.prefix { $0 == " " || $0 == "\t" })
    }

    private static func isAssignment(_ line: String, of key: String) -> Bool {
        let quoted = "\"\(key)\""
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(quoted) else { return false }
        return trimmed.dropFirst(quoted.count).drop(while: { $0 == " " || $0 == "\t" }).first == ":"
    }

    /// Whether the file sets `window.autoDetectColorScheme` to true. That
    /// setting makes both editors ignore workbench.colorTheme entirely and
    /// swap between the preferred light and dark themes with the OS appearance
    /// instead, so writing the theme without noticing it looks exactly like
    /// nothing happening — which is precisely how it looked in Cursor.
    static func settings(_ contents: String, followOSAppearance key: String = "window.autoDetectColorScheme") -> Bool {
        guard let line = contents.components(separatedBy: "\n").first(where: { isAssignment($0, of: key) })
        else { return false }
        let terminator = carriageReturn(of: line)
        let (code, _) = splitTrailingComment(String(line.dropLast(terminator.count)))
        guard let colon = code.firstIndex(of: ":") else { return false }
        return code[code.index(after: colon)...]
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: ",")) == "true"
    }

    /// Writes the theme, and pins off the OS-appearance detection that would
    /// otherwise make the editor ignore it. Omaccy drives the theme once its
    /// editor switch is on, and leaving the detection in place means the write
    /// lands in a setting nothing reads — which is exactly how Cursor came to
    /// sit on its own theme while its settings.json said otherwise.
    /// The `false` goes in even when the setting reads false already, because
    /// Cursor distinguishes a written value from an absent one: with no entry
    /// of its own it treats the theme as unclaimed and is free to adopt the
    /// system's polarity, which looks exactly like a theme that did not take.
    static func settings(_ contents: String, settingTheme label: String) -> String? {
        guard let written = settings(contents, setting: "workbench.colorTheme", to: label) else { return nil }
        return settings(written, setting: "window.autoDetectColorScheme", to: "false", quoted: false) ?? written
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
