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
}
