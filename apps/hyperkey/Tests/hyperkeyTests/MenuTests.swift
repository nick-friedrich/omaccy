import XCTest
@testable import hyperkey

final class MenuTests: XCTestCase {
    func testBindingsRespectSectionsAndDeduplicateArrowAliases() {
        let entries = SuperMenuController.parseWindowShortcuts("""
        start-at-login = true
        [mode.main.binding]
        cmd-ctrl-alt-h = 'focus left'
        cmd-ctrl-alt-left = 'focus left'
        cmd-ctrl-alt-shift-7 = 'move-node-to-workspace 7'
        [gaps]
        outer.top = 8
        [mode.resize.binding]
        h = 'resize width -50'
        """)
        XCTAssertEqual(entries.count, 4)
        XCTAssertEqual(entries.filter { $0.detail == "Hyper + ←" }.count, 1)
        XCTAssertTrue(entries.contains { $0.title == "Move window to workspace 7" })
        XCTAssertTrue(entries.contains { $0.detail == "h (resize mode)" })
        XCTAssertFalse(entries.contains { $0.detail.contains("outer") })
    }

    func testShippedWindowBindingsAreAllRepresented() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let contents = try String(contentsOf: root.appendingPathComponent("config/aerospace/aerospace.toml"), encoding: .utf8)
        let entries = SuperMenuController.parseWindowShortcuts(contents)
        XCTAssertEqual(entries.count, 43)
        XCTAssertTrue(entries.contains { $0.title == "Toggle Dock auto-hide" })
        XCTAssertTrue(entries.contains { $0.title == "Previous occupied workspace" })
    }
}
