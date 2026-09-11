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

    private static let theme = "catppuccin-latte"

    private static let cases: [(name: String, before: String, after: String)] = [
        ("replaces the name and keeps everything else",
         "onboarding = false\n[ui.toast]\ndelivery = \"system\"\n\n[theme]\nname = \"catppuccin\"\n"
            + "auto_switch = false\n\n[keys]\nprefix = \"ctrl+space\"\n",
         "onboarding = false\n[ui.toast]\ndelivery = \"system\"\n\n[theme]\nname = \"catppuccin-latte\"\n"
            + "auto_switch = false\n\n[keys]\nprefix = \"ctrl+space\"\n"),
        ("only the name under [theme], keeping its indent",
         "name = \"top\"\n[theme.custom]\nname = \"nested\"\n[theme]\n  name = \"old\"\n",
         "name = \"top\"\n[theme.custom]\nname = \"nested\"\n[theme]\n  name = \"catppuccin-latte\"\n"),
        ("adds a name to a table without one",
         "[theme]\nauto_switch = false\n",
         "[theme]\nname = \"catppuccin-latte\"\nauto_switch = false\n"),
        ("appends a table to a file without one",
         "[keys]\nprefix = \"ctrl+space\"",
         "[keys]\nprefix = \"ctrl+space\"\n\n[theme]\nname = \"catppuccin-latte\"\n"),
        ("fills an empty file",
         "",
         "[theme]\nname = \"catppuccin-latte\"\n"),
        ("keeps carriage returns",
         "[theme]\r\nname = \"nord\"\r\n",
         "[theme]\r\nname = \"catppuccin-latte\"\r\n"),
        ("reads a header with a comment",
         "[theme] # colors\nname = \"nord\"\n",
         "[theme] # colors\nname = \"catppuccin-latte\"\n"),
        ("leaves a config already on the theme alone",
         "[theme]\nname = \"catppuccin-latte\"\n",
         "[theme]\nname = \"catppuccin-latte\"\n")
    ]

    func testEveryCaseComesOutAsExpected() {
        for testCase in Self.cases {
            XCTAssertEqual(OmaccyAppearance.herdrConfig(testCase.before, settingTheme: Self.theme),
                           testCase.after, testCase.name)
        }
    }

    func testShellImplementationProducesTheSameBytes() throws {
        for testCase in Self.cases {
            XCTAssertEqual(try shellRewrite(testCase.before), testCase.after,
                           "scripts/lib/herdr-settings.sh: \(testCase.name)")
        }
    }

    private func shellRewrite(_ contents: String) throws -> String {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("omaccy-herdr-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let config = scratch.appendingPathComponent("config.toml")
        try contents.write(to: config, atomically: true, encoding: .utf8)

        let output = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", """
            set -euo pipefail
            source "$1"
            herdr_config_with_theme "$2" "$3"
            """, "bash", Self.library, config.path, Self.theme]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return String(decoding: data, as: UTF8.self)
    }
}
