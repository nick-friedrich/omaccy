import XCTest
@testable import hyperkey

/// The Zed theme rewrite is implemented twice — here in Swift for the
/// launcher, and in awk for scripts/theme.sh — because the launcher ships as a
/// signed bundle that cannot reach the checkout those scripts live in. Two
/// implementations of one fiddly rule drift, and when the VS Code pair drifted
/// over a carriage return the Swift half wrote an invalid settings.json. So
/// neither half is trusted alone: every fixture goes through both, and their
/// output has to match byte for byte.
final class ZedSettingsParityTests: XCTestCase {
    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // hyperkeyTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // hyperkey
        .deletingLastPathComponent()  // apps
        .deletingLastPathComponent()  // repository root

    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/zed-settings")

    private static let theme = "Tokyo Night"
    private static let extensionID = "tokyo-night"

    /// Runs the shell implementation over a copy of the fixture. Nil when it
    /// refuses the file's shape, which is its half of the Swift nil.
    private func shellRewrite(_ contents: String, theme: String, extensionID: String) throws -> String? {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("omaccy-zed-parity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let settings = scratch.appendingPathComponent("settings.json")
        try contents.write(to: settings, atomically: true, encoding: .utf8)

        let library = Self.repositoryRoot.appendingPathComponent("scripts/lib/zed-settings.sh").path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", """
            set -euo pipefail
            source "$1"
            write_zed_settings "$2" "$3" "$4"
            """, "bash", library, settings.path, theme, extensionID]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return try String(contentsOf: settings, encoding: .utf8)
    }

    private func fixtureNames() throws -> [String] {
        let files = try FileManager.default.contentsOfDirectory(atPath: Self.fixtures.path)
            .filter { $0.hasSuffix(".json") }.sorted()
        XCTAssertFalse(files.isEmpty, "no fixtures found at \(Self.fixtures.path)")
        return files
    }

    private func fixture(_ name: String) throws -> String {
        try String(contentsOf: Self.fixtures.appendingPathComponent(name), encoding: .utf8)
    }

    func testBothImplementationsAgreeOnEveryFixture() throws {
        for file in try fixtureNames() {
            let contents = try fixture(file)
            let swift = OmaccyZedSettings.settings(contents, theme: Self.theme,
                                                   extensionID: Self.extensionID)
            let shell = try shellRewrite(contents, theme: Self.theme, extensionID: Self.extensionID)
            XCTAssertEqual(swift, shell, "Swift and scripts/lib/zed-settings.sh disagree on \(file)")
        }
    }

    /// A palette Zed has built in names no extension, and neither half may
    /// invent one.
    func testBothImplementationsAgreeWithNoExtension() throws {
        for file in try fixtureNames() {
            let contents = try fixture(file)
            let swift = OmaccyZedSettings.settings(contents, theme: "One Dark", extensionID: nil)
            let shell = try shellRewrite(contents, theme: "One Dark", extensionID: "")
            XCTAssertEqual(swift, shell, "Swift and scripts/lib/zed-settings.sh disagree on \(file)")
            XCTAssertEqual(swift?.contains("auto_install_extensions"),
                           contents.contains("auto_install_extensions"),
                           "\(file) gained or lost auto_install_extensions with no extension to install")
        }
    }

    /// Parity alone would be satisfied by both halves being wrong together, so
    /// every fixture the two accept also has to come out as parseable JSON
    /// carrying the theme that was asked for — and, where an extension was
    /// requested, an `auto_install_extensions` that still names whatever it
    /// named before.
    func testEveryRewrittenFixtureStaysValidJSON() throws {
        for file in try fixtureNames() {
            let contents = try fixture(file)
            guard let rewritten = OmaccyZedSettings.settings(contents, theme: Self.theme,
                                                             extensionID: Self.extensionID) else {
                continue  // A refused shape is left alone on purpose.
            }
            let object = try XCTUnwrap(JSONSerialization.jsonObject(
                with: Data(Self.strippingJSONC(rewritten).utf8)) as? [String: Any],
                "\(file) did not survive the rewrite as JSON")
            XCTAssertEqual(object["theme"] as? String, Self.theme, file)

            guard let extensions = object["auto_install_extensions"] as? [String: Any] else { continue }
            // Zed installs the theme's extension at its next launch, unless
            // someone already said what they wanted for it.
            let before = try XCTUnwrap(JSONSerialization.jsonObject(
                with: Data(Self.strippingJSONC(contents).utf8)) as? [String: Any])
            let existing = (before["auto_install_extensions"] as? [String: Any]) ?? [:]
            if let claimed = existing[Self.extensionID] as? Bool {
                XCTAssertEqual(extensions[Self.extensionID] as? Bool, claimed,
                               "\(file) overwrote an entry that was already spoken for")
            } else {
                XCTAssertEqual(extensions[Self.extensionID] as? Bool, true, file)
            }
            for (key, value) in existing where key != Self.extensionID {
                XCTAssertEqual(extensions[key] as? Bool, value as? Bool,
                               "\(file) lost the existing \(key) entry")
            }
        }
    }

    /// JSONSerialization has no JSONC mode, so the fixtures' comments and
    /// trailing commas — which Zed writes into a settings.json itself — come
    /// out before parsing. Quote-aware, so a "//" inside a value is left
    /// alone.
    private static func strippingJSONC(_ contents: String) -> String {
        var output = ""
        var inString = false
        var escaped = false
        let characters = Array(contents)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if inString {
                output.append(character)
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
                index += 1
                continue
            }
            if character == "\"" {
                inString = true
                output.append(character)
                index += 1
                continue
            }
            if character == "/", index + 1 < characters.count {
                if characters[index + 1] == "/" {
                    while index < characters.count, characters[index] != "\n" { index += 1 }
                    continue
                }
                if characters[index + 1] == "*" {
                    index += 2
                    while index + 1 < characters.count,
                          !(characters[index] == "*" && characters[index + 1] == "/") { index += 1 }
                    index += 2
                    continue
                }
            }
            if character == "," {
                // A comma is trailing when the next thing that is not
                // whitespace or a comment closes the object it sits in.
                var lookahead = index + 1
                while lookahead < characters.count {
                    let next = characters[lookahead]
                    if next == " " || next == "\t" || next == "\r" || next == "\n" {
                        lookahead += 1
                    } else if next == "/", lookahead + 1 < characters.count, characters[lookahead + 1] == "/" {
                        while lookahead < characters.count, characters[lookahead] != "\n" { lookahead += 1 }
                    } else {
                        break
                    }
                }
                if lookahead < characters.count, characters[lookahead] == "}" || characters[lookahead] == "]" {
                    index += 1
                    continue
                }
            }
            output.append(character)
            index += 1
        }
        return output
    }

    /// Rewriting twice has to land where rewriting once did: a second theme
    /// switch must not stack up a second entry or drift the formatting.
    func testRewriteIsStable() throws {
        for file in try fixtureNames() {
            let contents = try fixture(file)
            guard let once = OmaccyZedSettings.settings(contents, theme: Self.theme,
                                                        extensionID: Self.extensionID) else { continue }
            let twice = OmaccyZedSettings.settings(once, theme: Self.theme, extensionID: Self.extensionID)
            XCTAssertEqual(twice, once, "rewriting \(file) a second time changed it again")
        }
    }
}
