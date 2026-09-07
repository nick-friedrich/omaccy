import XCTest
@testable import hyperkey

final class MenuTests: XCTestCase {
    func testGlobalSearchFromEveryPage() {
        let apps = [MenuEntry(title: "Ghostty", detail: "Hyper + T", bundleID: "ghostty")]
        let help = [MenuEntry(title: "Move window left", detail: "Hyper + Shift + H")]
        for page in [MenuPage.home, .apps, .help, .system] {
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
        XCTAssertEqual(MenuCatalog.results(query: "  ", page: .home, apps: apps, help: help).compactMap(\.destination), [.apps, .agents, .mail, .editors, .install, .omaccy, .help, .system, .settings])
        XCTAssertEqual(MenuCatalog.results(query: "", page: .apps, apps: apps, help: help).map(\.title), ["Finder"])
        XCTAssertEqual(MenuCatalog.results(query: "", page: .help, apps: apps, help: help).map(\.title), ["Focus left"])
        XCTAssertTrue(MenuCatalog.results(query: "missing", page: .home, apps: apps, help: help).isEmpty)
    }

    func testSystemBrowsingAndGlobalSearch() {
        let actions = MenuCatalog.results(query: "", page: .system, apps: [], help: [])
        XCTAssertEqual(actions.compactMap(\.systemAction), [.sleep, .restart, .shutDown])
        XCTAssertTrue(actions.allSatisfy { $0.bundleID == nil && $0.destination == nil })
        for page in [MenuPage.home, .apps, .help, .system] {
            for (query, expected) in [("sleep", SystemAction.sleep), ("restart", .restart), ("shutdown", .shutDown), ("shut down", .shutDown)] {
                let results = MenuCatalog.results(query: query, page: page, apps: [], help: [])
                XCTAssertEqual(results.compactMap(\.systemAction), [expected])
            }
        }
    }

    func testCollectionsListEveryChoiceAndMarkTheDefault() {
        for collection in AppCollection.allCases {
            let rows = MenuCatalog.results(query: "", page: collection.page, apps: [], help: [],
                                           defaultApps: [collection: collection.choices[1].id])
            XCTAssertEqual(rows.map(\.title), collection.choices.map(\.title))
            XCTAssertEqual(rows.filter(\.isDefaultChoice).map(\.title), [collection.choices[1].title])
            // Choices launch or install themselves; they never browse elsewhere.
            XCTAssertTrue(rows.allSatisfy { $0.destination == nil && $0.choice != nil })
        }
    }

    func testCollectionSearchMatchesTitleAndDescription() {
        let mail = MenuCatalog.results(query: "emzero", page: .mail, apps: [], help: [])
        XCTAssertEqual(mail.map(\.title), ["Emzero"])
        let editors = MenuCatalog.results(query: "jetbrains", page: .editors, apps: [], help: [])
        XCTAssertEqual(editors.map(\.title), ["IntelliJ IDEA"])
        XCTAssertTrue(MenuCatalog.results(query: "nothing here", page: .mail, apps: [], help: []).isEmpty)
    }

    func testCollectionChoicesInstallFromExactlyOneSource() {
        for choice in AppCollection.allCases.flatMap(\.choices) {
            XCTAssertTrue(choice.appName.hasSuffix(".app"), choice.id)
            switch choice.source {
            case .bundled:
                XCTAssertNil(choice.package, choice.id)
                XCTAssertNil(choice.appStoreURL, choice.id)
            case .homebrew:
                // A malformed token yields no command, which would strand the row.
                XCTAssertNotNil(choice.package?.actionCommand, choice.id)
                XCTAssertNil(choice.appStoreURL, choice.id)
            case .appStore:
                XCTAssertNil(choice.package, choice.id)
                XCTAssertNotNil(choice.appStoreURL, choice.id)
            }
        }
    }

    func testCollectionIdentitiesAndChordsAreDistinct() {
        let ids = AppCollection.allCases.flatMap { $0.choices.map(\.id) }
        XCTAssertEqual(Set(ids).count, ids.count)
        // Chords must resolve to a real key and never collide with each other
        // or with the agents chord, which is reserved the same way.
        var chords = ["a"]
        for collection in AppCollection.allCases {
            let chord = collection.chord.lowercased()
            XCTAssertNotNil(KeyNames.virtualKeyCode(for: chord), chord)
            XCTAssertFalse(chords.contains(chord), chord)
            chords.append(chord)
        }
    }

    func testPowerActionsRequireConfirmationBeforeQuittingApps() {
        XCTAssertFalse(SystemAction.sleep.requiresConfirmation)
        XCTAssertTrue(SystemAction.restart.requiresConfirmation)
        XCTAssertTrue(SystemAction.shutDown.requiresConfirmation)
        // Validate native event mappings without sending power events to this Mac.
        XCTAssertEqual(SystemAction.sleep.eventID, 0x736c6570)
        XCTAssertEqual(SystemAction.restart.eventID, 0x72657374)
        XCTAssertEqual(SystemAction.shutDown.eventID, 0x73687574)
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
        XCTAssertEqual(entries.count, 45)
        XCTAssertTrue(entries.contains { $0.title == "Shrink window" && $0.detail == "Hyper + u" })
        XCTAssertTrue(entries.contains { $0.title == "Grow window" && $0.detail == "Hyper + i" })
        XCTAssertTrue(entries.contains { $0.title == "Toggle Dock auto-hide" })
        XCTAssertTrue(entries.contains { $0.title == "Previous occupied workspace" })
    }
    func testOmaccyContainsItsOwnUpdater() {
        let actions = MenuCatalog.results(query: "", page: .omaccy, apps: [], help: [])
        XCTAssertEqual(actions.map(\.title), ["Update Omaccy"])
        XCTAssertTrue(actions[0].updatesOmaccy)
        XCTAssertFalse(actions[0].upgradesAll)
        XCTAssertTrue(MenuCatalog.results(query: "update", page: .omaccy, apps: [], help: []).first?.updatesOmaccy == true)
        XCTAssertTrue(MenuCatalog.results(query: "homebrew", page: .omaccy, apps: [], help: []).isEmpty)
        XCTAssertEqual(MenuCatalog.results(query: "update omaccy", page: .home, apps: [], help: []).first?.destination, .omaccy)
    }

    func testSettingsPageListsThemeAndFontCollections() {
        let entries = MenuCatalog.results(query: "", page: .settings, apps: [], help: [])
        XCTAssertEqual(entries.map(\.title), ["Theme", "Font"])
        XCTAssertEqual(entries.compactMap(\.destination), [.theme, .font])
        XCTAssertEqual(MenuCatalog.results(query: "font", page: .settings, apps: [], help: []).map(\.title), ["Font"])
        XCTAssertTrue(MenuCatalog.results(query: "nord", page: .settings, apps: [], help: []).isEmpty)
    }

    func testSettingsReachableFromHomeAndGlobalSearch() {
        XCTAssertTrue(MenuCatalog.categories.contains { $0.destination == .settings })
        XCTAssertEqual(MenuCatalog.results(query: "settings", page: .home, apps: [], help: []).compactMap(\.destination), [.settings])
        XCTAssertTrue(MenuCatalog.results(query: "theme", page: .home, apps: [], help: []).contains { $0.destination == .theme })
        XCTAssertTrue(MenuCatalog.results(query: "launcher font", page: .home, apps: [], help: []).contains { $0.destination == .font })
    }

    func testThemeEntriesMarkActiveAndMatchRawNames() {
        let themes = ["catppuccin", "tokyo-night", "rose-pine"]
        let entries = MenuCatalog.themeEntries(matching: "", themes: themes, active: "tokyo-night")
        XCTAssertEqual(entries.map(\.title), ["Catppuccin", "Tokyo Night", "Rose Pine"])
        XCTAssertEqual(entries.first { $0.theme == "tokyo-night" }?.detail, "Active")
        XCTAssertEqual(entries.first { $0.theme == "catppuccin" }?.detail, "Theme palette")
        XCTAssertEqual(MenuCatalog.themeEntries(matching: "tokyo-night", themes: themes, active: "tokyo-night").map(\.theme), ["tokyo-night"])
        XCTAssertEqual(MenuCatalog.themeEntries(matching: "active", themes: themes, active: "tokyo-night").map(\.theme), ["tokyo-night"])
        XCTAssertTrue(MenuCatalog.themeEntries(matching: "missing", themes: themes, active: "tokyo-night").isEmpty)
    }

    func testAgentEntriesMarkDefaultAndFilter() {
        let entries = MenuCatalog.agentEntries(matching: "", defaultToken: "codex")
        XCTAssertEqual(entries.map(\.agent), CodingAgent.allCases)
        XCTAssertEqual(entries.first { $0.agent == .codexCLI }?.isDefaultChoice, true)
        XCTAssertEqual(entries.first { $0.agent == .claudeCode }?.isDefaultChoice, false)
        XCTAssertEqual(MenuCatalog.agentEntries(matching: "claude code", defaultToken: nil).map(\.agent), [.claudeCode])
        XCTAssertEqual(MenuCatalog.agentEntries(matching: "chatgpt", defaultToken: nil).map(\.agent), [.chatGPTDesktop])
        XCTAssertTrue(MenuCatalog.agentEntries(matching: "missing-agent", defaultToken: nil).isEmpty)
    }

    func testFontEntriesMarkActiveAndFilter() {
        let entries = MenuCatalog.fontEntries(matching: "", active: "serif")
        XCTAssertEqual(entries.map(\.title), ["Inter", "JetBrains Mono", "Lora"])
        XCTAssertEqual(entries.first { $0.font == "serif" }?.detail, "Active")
        XCTAssertEqual(MenuCatalog.fontEntries(matching: "jetbrains", active: "serif").map(\.font), ["jetbrains-mono"])
        XCTAssertEqual(MenuCatalog.fontEntries(matching: "active", active: "serif").map(\.font), ["serif"])
    }
}
