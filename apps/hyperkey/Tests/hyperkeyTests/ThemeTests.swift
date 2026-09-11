import XCTest
@testable import hyperkey

final class ThemeTests: XCTestCase {
    private func writeThemeFile(_ contents: String) throws -> String {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("omaccy-themes-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("test.sh")
        try contents.write(to: file, atomically: true, encoding: .utf8)
        return file.path
    }

    func testParsesThemePaletteWithComments() throws {
        let path = try writeThemeFile("""
        # Nord-ish test palette.
        BAR_BG=0xff2e3440      # nord0
        ACCENT=0x8088c0d0
        """)
        let colors = OmaccyTheme.palette(fromFile: path)
        XCTAssertEqual(colors.count, 2)
        XCTAssertEqual(colors["BAR_BG"]?.alphaComponent ?? -1, 1, accuracy: 0.001)
        XCTAssertEqual(colors["BAR_BG"]?.redComponent ?? -1, 0x2e / 255.0, accuracy: 0.001)
        XCTAssertEqual(colors["BAR_BG"]?.greenComponent ?? -1, 0x34 / 255.0, accuracy: 0.001)
        XCTAssertEqual(colors["BAR_BG"]?.blueComponent ?? -1, 0x40 / 255.0, accuracy: 0.001)
        XCTAssertEqual(colors["ACCENT"]?.alphaComponent ?? -1, 0x80 / 255.0, accuracy: 0.001)
    }

    func testIgnoresMalformedPaletteLines() throws {
        let path = try writeThemeFile("""
        TEXT=0xffcdd6f4
        BROKEN=nope
        SHORT=0xff12
        =
        TEXT=0xff000000
        """)
        let colors = OmaccyTheme.palette(fromFile: path)
        XCTAssertEqual(colors.count, 1, "later assignments should win; malformed lines are dropped")
        XCTAssertEqual(colors["TEXT"]?.redComponent ?? -1, 0, accuracy: 0.001)
    }

    func testMissingPaletteFileIsEmpty() {
        XCTAssertTrue(OmaccyTheme.palette(fromFile: "/nonexistent/theme.sh").isEmpty)
    }

    func testFontSwitcherKeysMapToFamilyNames() {
        XCTAssertEqual(OmaccyTheme.fontFamilies["inter"], "Inter")
        XCTAssertEqual(OmaccyTheme.fontFamilies["jetbrains-mono"], "JetBrains Mono")
        XCTAssertEqual(OmaccyTheme.fontFamilies["serif"], "Lora")
        XCTAssertNil(OmaccyTheme.fontFamilies["comic-sans"])
        XCTAssertEqual(OmaccyTheme.fontKeys, ["inter", "jetbrains-mono", "serif"])
    }

    func testGhosttyThemeNameParsesQuotedAssignment() throws {
        let path = try writeThemeFile("""
        # Nord.
        BAR_BG=0xff2e3440

        # Ghostty ships this palette as a built-in theme name.
        GHOSTTY_THEME="Nord"
        """)
        XCTAssertEqual(OmaccyTheme.ghosttyThemeName(fromFile: path), "Nord")
    }

    func testHerdrThemeNameParsesFromThemeFile() throws {
        let path = try writeThemeFile("""
        GHOSTTY_THEME="Everforest Dark Hard"
        HERDR_THEME="terminal"
        """)
        XCTAssertEqual(OmaccyTheme.herdrThemeName(fromFile: path), "terminal")
        XCTAssertNil(OmaccyTheme.herdrThemeName(fromFile: try writeThemeFile("BAR_BG=0xff2e3440\n")))
    }

    /// A `#` inside quotes is part of the value, not a comment: reading
    /// `"#83c092"` as a lone quote once wrote broken colors into herdr's
    /// config. A comment after the value is still dropped.
    func testQuotedHashIsPartOfTheValue() throws {
        let path = try writeThemeFile("""
        HERDR_ACCENT="#83c092"   # Omaccy's aqua
        HERDR_PANEL_BG="#1e2326"
        APPEARANCE="dark" # the palette's nature
        """)
        XCTAssertEqual(OmaccyTheme.herdrAccent(fromFile: path), "#83c092")
        XCTAssertEqual(OmaccyTheme.herdrPanelBackground(fromFile: path), "#1e2326")
        XCTAssertEqual(OmaccyTheme.appearance(fromFile: path), "dark")
    }

    func testGhosttyThemeNameMissingWhenAbsent() throws {
        let path = try writeThemeFile("BAR_BG=0xff2e3440\n")
        XCTAssertNil(OmaccyTheme.ghosttyThemeName(fromFile: path))
    }

    func testThemeDisplayNames() {
        XCTAssertEqual(OmaccyAppearance.displayName(forTheme: "catppuccin"), "Catppuccin")
        XCTAssertEqual(OmaccyAppearance.displayName(forTheme: "tokyo-night"), "Tokyo Night")
        XCTAssertEqual(OmaccyAppearance.displayName(forTheme: "gruvbox_dark"), "Gruvbox Dark")
        XCTAssertEqual(OmaccyAppearance.displayName(forTheme: "github-dark"), "GitHub Dark")
        XCTAssertEqual(OmaccyAppearance.displayName(forTheme: "my-custom-theme"), "My Custom Theme")
    }

    func testEditorMappingParsesFromThemeFile() throws {
        let path = try writeThemeFile("""
        BAR_BG=0xff1f1f28
        GHOSTTY_THEME="Kanagawa Wave"
        VSCODE_EXTENSION="metaphore.kanagawa-vscode-color-theme"
        VSCODE_THEME="Kanagawa Wave"
        """)
        XCTAssertEqual(OmaccyTheme.vscodeThemeName(fromFile: path), "Kanagawa Wave")
        XCTAssertEqual(OmaccyTheme.vscodeExtensionID(fromFile: path), "metaphore.kanagawa-vscode-color-theme")
    }

    /// An empty VSCODE_EXTENSION means the label is built into VS Code, so
    /// nothing should be installed for it.
    func testEmptyEditorExtensionReadsAsAbsent() throws {
        let path = try writeThemeFile("""
        VSCODE_EXTENSION=""
        VSCODE_THEME="Solarized Dark"
        """)
        XCTAssertEqual(OmaccyTheme.vscodeThemeName(fromFile: path), "Solarized Dark")
        XCTAssertNil(OmaccyTheme.vscodeExtensionID(fromFile: path))
    }

    func testEditorSettingsReplacesExistingColorThemeAndKeepsComments() {
        let settings = """
        {
          "editor.fontSize": 13, // my size
          "workbench.colorTheme": "Default Dark+",
          "editor.tabSize": 2
        }

        """
        XCTAssertEqual(OmaccyAppearance.settings(settings, setting: "workbench.colorTheme", to: "Kanagawa Wave"), """
        {
          "editor.fontSize": 13, // my size
          "workbench.colorTheme": "Kanagawa Wave",
          "editor.tabSize": 2
        }

        """)
    }

    /// The last entry carries no trailing comma, and must not gain one.
    func testEditorSettingsKeepsMissingTrailingComma() {
        let settings = """
        {
          "editor.tabSize": 2,
          "workbench.colorTheme": "Nord"
        }
        """
        XCTAssertEqual(OmaccyAppearance.settings(settings, setting: "workbench.colorTheme", to: "Catppuccin Latte"), """
        {
          "editor.tabSize": 2,
          "workbench.colorTheme": "Catppuccin Latte"
        }
        """)
    }

    func testEditorSettingsInsertsColorThemeMatchingIndentation() {
        let settings = """
        {
            "window.autoDetectColorScheme": true
        }
        """
        XCTAssertEqual(OmaccyAppearance.settings(settings, setting: "workbench.colorTheme", to: "GitHub Dark Default"), """
        {
            "workbench.colorTheme": "GitHub Dark Default",
            "window.autoDetectColorScheme": true
        }
        """)
    }

    func testEditorSettingsInsertsIntoEmptyObjectWithoutComma() {
        XCTAssertEqual(OmaccyAppearance.settings("{\n}\n", setting: "workbench.colorTheme", to: "Solarized Dark"),
                       "{\n  \"workbench.colorTheme\": \"Solarized Dark\"\n}\n")
    }

    /// The shape that actually broke a real settings.json: VS Code writes CRLF
    /// on plenty of machines, and the carriage return left behind by splitting
    /// on "\n" hid the trailing comma from `CharacterSet.whitespaces`, which
    /// does not cover it. Dropping that comma invalidates the JSON outright.
    func testEditorSettingsKeepsTrailingCommaBehindACarriageReturn() {
        let settings = "{\r\n  \"editor.fontSize\": 13,\r\n"
            + "  \"workbench.colorTheme\": \"Bearded Theme Monokai Reversed\",\r\n"
            + "  \"editor.tabSize\": 2\r\n}\r\n"
        XCTAssertEqual(OmaccyAppearance.settings(settings, setting: "workbench.colorTheme", to: "Catppuccin Mocha"),
                       "{\r\n  \"editor.fontSize\": 13,\r\n"
                       + "  \"workbench.colorTheme\": \"Catppuccin Mocha\",\r\n"
                       + "  \"editor.tabSize\": 2\r\n}\r\n")
    }

    /// An inserted line has to match the file's terminator too, or it becomes
    /// the one odd line out in an otherwise CRLF file.
    func testEditorSettingsInsertsCarriageReturnIntoCRLFFile() {
        XCTAssertEqual(OmaccyAppearance.settings("{\r\n  \"editor.tabSize\": 2\r\n}\r\n",
                                                 setting: "workbench.colorTheme", to: "Nord"),
                       "{\r\n  \"workbench.colorTheme\": \"Nord\",\r\n  \"editor.tabSize\": 2\r\n}\r\n")
    }

    /// `window.autoDetectColorScheme` makes both editors ignore
    /// workbench.colorTheme and swap between the preferred light and dark
    /// themes with the OS appearance instead — which is why Cursor kept
    /// rendering its own theme while its settings.json said otherwise.
    func testDetectsFollowOSAppearance() {
        XCTAssertTrue(OmaccyAppearance.settings("""
        {
            "workbench.colorTheme": "Catppuccin Frappé",
            "window.autoDetectColorScheme": true,
            "git.autofetch": true
        }
        """, followOSAppearance: "window.autoDetectColorScheme"))
        XCTAssertFalse(OmaccyAppearance.settings("""
        {
          "window.autoDetectColorScheme": false
        }
        """, followOSAppearance: "window.autoDetectColorScheme"))
        XCTAssertFalse(OmaccyAppearance.settings("{\n  \"editor.tabSize\": 2\n}\n",
                                                 followOSAppearance: "window.autoDetectColorScheme"))
        // A trailing comment must not hide the value, as it hid the comma.
        XCTAssertTrue(OmaccyAppearance.settings("{\n  \"window.autoDetectColorScheme\": true, // follow macOS\n}\n",
                                                followOSAppearance: "window.autoDetectColorScheme"))
    }

    /// Cursor's shape: the detection goes off, unquoted, and the theme lands.
    func testWritingAThemeTurnsOffOSAppearanceDetection() {
        let out = OmaccyAppearance.settings("""
        {
            "workbench.colorTheme": "Cursor Dark",
            "window.autoDetectColorScheme": true,
            "git.autofetch": true
        }
        """, settingTheme: "Gruvbox Dark Hard")
        XCTAssertEqual(out, """
        {
            "workbench.colorTheme": "Gruvbox Dark Hard",
            "window.autoDetectColorScheme": false,
            "git.autofetch": true
        }
        """)
    }

    /// A file that never mentioned the detection gets it written anyway: an
    /// absent value is not the same as a false one to Cursor, which reads the
    /// silence as permission to follow the system's light/dark instead.
    /// Everything else in the file is still left alone.
    func testWritingAThemePinsDetectionOffEvenWhenItIsAbsent() {
        let out = OmaccyAppearance.settings("{\n  \"editor.tabSize\": 2\n}\n", settingTheme: "Nord")
        XCTAssertEqual(out, "{\n  \"window.autoDetectColorScheme\": false,\n"
                       + "  \"workbench.colorTheme\": \"Nord\",\n  \"editor.tabSize\": 2\n}\n")
    }

    func testThemeAppearanceParsesFromThemeFile() throws {
        let path = try writeThemeFile("APPEARANCE=\"light\"\nVSCODE_THEME=\"Catppuccin Latte\"")
        XCTAssertEqual(OmaccyTheme.appearance(fromFile: path), "light")
    }

    /// A hand-packed object has nowhere safe to insert, so it is left alone.
    func testEditorSettingsRefusesUnfamiliarShape() {
        XCTAssertNil(OmaccyAppearance.settings("{ \"editor.tabSize\": 2 }", setting: "workbench.colorTheme", to: "Nord"))
    }
}
