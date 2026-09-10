import XCTest
@testable import hyperkey

/// The workbench.colorTheme rewrite is implemented twice — here in Swift for
/// the launcher, and in awk for scripts/theme.sh — because the launcher ships
/// as a signed bundle that cannot reach the checkout those scripts live in.
/// Two implementations of one fiddly rule drift, and when they drifted over a
/// carriage return the Swift half wrote an invalid settings.json. So neither
/// half is trusted alone: every fixture goes through both, and their output
/// has to match byte for byte.
final class EditorSettingsParityTests: XCTestCase {
    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // hyperkeyTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // hyperkey
        .deletingLastPathComponent()  // apps
        .deletingLastPathComponent()  // repository root

    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/editor-settings")

    /// Runs the shell implementation over a copy of the fixture. Nil when it
    /// refuses the file's shape, which is its half of the Swift nil.
    private func shellRewrite(_ contents: String, label: String) throws -> String? {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("omaccy-parity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let settings = scratch.appendingPathComponent("settings.json")
        try contents.write(to: settings, atomically: true, encoding: .utf8)

        let library = Self.repositoryRoot.appendingPathComponent("scripts/lib/editor-settings.sh").path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", """
            set -euo pipefail
            source "$1"
            write_editor_theme "$2" "$3"
            """, "bash", library, settings.path, label]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return try String(contentsOf: settings, encoding: .utf8)
    }

    func testBothImplementationsAgreeOnEveryFixture() throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: Self.fixtures.path)
            .filter { $0.hasSuffix(".json") }.sorted()
        XCTAssertFalse(files.isEmpty, "no fixtures found at \(Self.fixtures.path)")
        for file in files {
            let contents = try String(contentsOf: Self.fixtures.appendingPathComponent(file), encoding: .utf8)
            let label = "Catppuccin Mocha"
            let swift = OmaccyAppearance.settings(contents, settingTheme: label)
            let shell = try shellRewrite(contents, label: label)
            XCTAssertEqual(swift, shell, "Swift and scripts/lib/editor-settings.sh disagree on \(file)")
        }
    }

    /// Parity alone would be satisfied by both halves being wrong together, so
    /// every fixture the two accept also has to come out as parseable JSON
    /// carrying the theme that was asked for.
    func testEveryRewrittenFixtureStaysValidJSON() throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: Self.fixtures.path)
            .filter { $0.hasSuffix(".json") }.sorted()
        for file in files {
            let contents = try String(contentsOf: Self.fixtures.appendingPathComponent(file), encoding: .utf8)
            guard let rewritten = OmaccyAppearance.settings(contents, settingTheme: "Catppuccin Mocha") else {
                continue  // A refused shape is left alone on purpose.
            }
            let object = try XCTUnwrap(JSONSerialization.jsonObject(
                with: Data(Self.strippingComments(rewritten).utf8)) as? [String: Any],
                "\(file) did not survive the rewrite as JSON")
            XCTAssertEqual(object["workbench.colorTheme"] as? String, "Catppuccin Mocha", file)
        }
    }

    /// JSONSerialization has no JSONC mode, so the fixtures' comments come out
    /// before parsing — quote-aware, so a "//" inside a value is left alone.
    private static func strippingComments(_ contents: String) -> String {
        var output = ""
        var inString = false
        var escaped = false
        var index = contents.startIndex
        while index < contents.endIndex {
            let character = contents[index]
            if inString {
                output.append(character)
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
                index = contents.index(after: index)
                continue
            }
            if character == "\"" {
                inString = true
                output.append(character)
                index = contents.index(after: index)
                continue
            }
            if character == "/", contents.index(after: index) < contents.endIndex,
               contents[contents.index(after: index)] == "/" {
                while index < contents.endIndex, contents[index] != "\n" {
                    index = contents.index(after: index)
                }
                continue
            }
            output.append(character)
            index = contents.index(after: index)
        }
        return output
    }
}
