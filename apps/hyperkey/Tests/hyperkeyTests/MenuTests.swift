import XCTest
@testable import hyperkey

final class MenuTests: XCTestCase {
    func testGlobalSearchFromEveryPage() {
        let apps = [MenuEntry(title: "Ghostty", detail: "Hyper + T", bundleID: "ghostty")]
        let help = [MenuEntry(title: "Move window left", detail: "Hyper + Shift + H")]
        for page in [MenuPage.home, .apps, .help] {
            XCTAssertEqual(MenuCatalog.results(query: "window shift", page: page, apps: apps, help: help).map(\.title), ["Move window left"])
            XCTAssertEqual(MenuCatalog.results(query: "ghost", page: page, apps: apps, help: help).map(\.title), ["Ghostty"])
        }
    }

    func testGlobalResultsMergeAppAndItsShortcut() {
        let apps = [MenuEntry(title: "Finder", detail: "Hyper + F", bundleID: "finder")]
        let help = [MenuEntry(title: "Open Finder", detail: "Hyper + F", bundleID: "finder")]
        let results = MenuCatalog.results(query: "finder", page: .home, apps: apps, help: help)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.detail, "Hyper + F")
        XCTAssertEqual(MenuCatalog.results(query: "open finder", page: .home, apps: apps, help: help).count, 1)
    }

    func testCategoryBrowsingAndEmptySearch() {
        let apps = [MenuEntry(title: "Finder", detail: "Application")]
        let help = [MenuEntry(title: "Focus left", detail: "Hyper + H")]
        XCTAssertEqual(MenuCatalog.results(query: "  ", page: .home, apps: apps, help: help).compactMap(\.destination), [.apps, .help])
        XCTAssertEqual(MenuCatalog.results(query: "", page: .apps, apps: apps, help: help).map(\.title), ["Finder"])
        XCTAssertEqual(MenuCatalog.results(query: "", page: .help, apps: apps, help: help).map(\.title), ["Focus left"])
        XCTAssertTrue(MenuCatalog.results(query: "missing", page: .home, apps: apps, help: help).isEmpty)
    }

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
