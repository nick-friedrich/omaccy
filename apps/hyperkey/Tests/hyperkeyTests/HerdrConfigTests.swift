import XCTest
@testable import hyperkey

/// herdr's theme rewrite exists twice, like the editor settings one: in Swift
/// for the launcher, and in awk (scripts/lib/herdr-settings.sh) for
/// scripts/theme.sh. Every case states the exact result, and the shell half
/// has to produce the very same bytes.
final class HerdrConfigTests: XCTestCase {
    private static let library = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // hyperkeyTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // hyperkey
        .deletingLastPathComponent()  // apps
        .deletingLastPathComponent()  // repository root
        .appendingPathComponent("scripts/lib/herdr-settings.sh").path

    private struct Case {
        let name: String
        let theme: String
        var accent: String?
        var panel: String?
        let before: String
        let after: String

        init(_ name: String, theme: String = "catppuccin-latte", accent: String? = nil, panel: String? = nil,
             before: String, after: String) {
            self.name = name
            self.theme = theme
            self.accent = accent
            self.panel = panel
            self.before = before
            self.after = after
        }
    }

    private static let terminalConfig = "[theme]\nname = \"terminal\"\n\n[theme.custom]\n"
        + "accent = \"#83c092\" # omaccy\npanel_bg = \"#272e33\" # omaccy\n"

    private static let cases: [Case] = [
        Case("replaces the name and keeps everything else",
             before: "onboarding = false\n[ui.toast]\ndelivery = \"system\"\n\n[theme]\nname = \"catppuccin\"\n"
                + "auto_switch = false\n\n[keys]\nprefix = \"ctrl+space\"\n",
             after: "onboarding = false\n[ui.toast]\ndelivery = \"system\"\n\n[theme]\nname = \"catppuccin-latte\"\n"
                + "auto_switch = false\n\n[keys]\nprefix = \"ctrl+space\"\n"),
        Case("only the name under [theme], keeping its indent",
             before: "name = \"top\"\n[theme.custom]\nname = \"nested\"\n[theme]\n  name = \"old\"\n",
             after: "name = \"top\"\n[theme.custom]\nname = \"nested\"\n[theme]\n  name = \"catppuccin-latte\"\n"),
        Case("adds a name to a table without one",
             before: "[theme]\nauto_switch = false\n",
             after: "[theme]\nname = \"catppuccin-latte\"\nauto_switch = false\n"),
        Case("appends a table to a file without one",
             before: "[keys]\nprefix = \"ctrl+space\"",
             after: "[keys]\nprefix = \"ctrl+space\"\n\n[theme]\nname = \"catppuccin-latte\"\n"),
        Case("fills an empty file",
             before: "",
             after: "[theme]\nname = \"catppuccin-latte\"\n"),
        Case("keeps carriage returns",
             before: "[theme]\r\nname = \"nord\"\r\n",
             after: "[theme]\r\nname = \"catppuccin-latte\"\r\n"),
        Case("reads a header with a comment",
             before: "[theme] # colors\nname = \"nord\"\n",
             after: "[theme] # colors\nname = \"catppuccin-latte\"\n"),
        Case("leaves a config already on the theme alone",
             before: "[theme]\nname = \"catppuccin-latte\"\n",
             after: "[theme]\nname = \"catppuccin-latte\"\n"),
        Case("appends marked colors for a palette on the terminal theme",
             theme: "terminal", accent: "#83c092", panel: "#272e33",
             before: "[theme]\nname = \"catppuccin\"\n",
             after: terminalConfig),
        Case("writing the same palette again changes nothing",
             theme: "terminal", accent: "#83c092", panel: "#272e33",
             before: terminalConfig,
             after: terminalConfig),
        Case("switching to a built-in theme removes only Omaccy's colors",
             theme: "catppuccin",
             before: "[theme]\nname = \"terminal\"\n\n[theme.custom]\naccent = \"#83c092\" # omaccy\n"
                + "sidebar_bg = \"#111111\"\npanel_bg = \"#272e33\" # omaccy\n",
             after: "[theme]\nname = \"catppuccin\"\n\n[theme.custom]\nsidebar_bg = \"#111111\"\n"),
        Case("replaces Omaccy's colors in place and adds the missing one under the header",
             theme: "terminal", accent: "#2f81f7", panel: "#0d1117",
             before: "[theme]\nname = \"terminal\"\n[theme.custom]\naccent = \"#83c092\" # omaccy\n",
             after: "[theme]\nname = \"terminal\"\n[theme.custom]\npanel_bg = \"#0d1117\" # omaccy\n"
                + "accent = \"#2f81f7\" # omaccy\n"),
        Case("a color the user set wins over Omaccy's",
             theme: "terminal", accent: "#83c092", panel: "#272e33",
             before: "[theme.custom]\npanel_bg = \"reset\"\npanel_bg = \"#000000\" # omaccy\n[theme]\nname = \"nord\"\n",
             after: "[theme.custom]\naccent = \"#83c092\" # omaccy\npanel_bg = \"reset\"\n[theme]\nname = \"terminal\"\n"),
        Case("leaves the light and dark tables alone",
             theme: "catppuccin",
             before: "[theme]\nname = \"terminal\"\n[theme.custom.dark]\naccent = \"#83c092\" # omaccy\n",
             after: "[theme]\nname = \"catppuccin\"\n[theme.custom.dark]\naccent = \"#83c092\" # omaccy\n"),
        Case("keeps carriage returns on colors too",
             theme: "terminal", accent: "#2f81f7",
             before: "[theme]\r\nname = \"terminal\"\r\n[theme.custom]\r\naccent = \"#83c092\" # omaccy\r\n",
             after: "[theme]\r\nname = \"terminal\"\r\n[theme.custom]\r\naccent = \"#2f81f7\" # omaccy\r\n")
    ]

    func testEveryCaseComesOutAsExpected() {
        for testCase in Self.cases {
            XCTAssertEqual(OmaccyAppearance.herdrConfig(testCase.before, settingTheme: testCase.theme,
                                                        accent: testCase.accent, panelBackground: testCase.panel),
                           testCase.after, testCase.name)
        }
    }

    func testShellImplementationProducesTheSameBytes() throws {
        for testCase in Self.cases {
            XCTAssertEqual(try shellRewrite(testCase), testCase.after,
                           "scripts/lib/herdr-settings.sh: \(testCase.name)")
        }
    }

    private func shellRewrite(_ testCase: Case) throws -> String {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("omaccy-herdr-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let config = scratch.appendingPathComponent("config.toml")
        try testCase.before.write(to: config, atomically: true, encoding: .utf8)

        let output = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", """
            set -euo pipefail
            source "$1"
            herdr_config_with_theme "$2" "$3" "$4" "$5"
            """, "bash", Self.library, config.path, testCase.theme, testCase.accent ?? "", testCase.panel ?? ""]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return String(decoding: data, as: UTF8.self)
    }
}
