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
        XCTAssertEqual(MenuCatalog.results(query: "  ", page: .home, apps: apps, help: help).compactMap(\.destination), [.apps, .agents, .mail, .editors, .clipboard, .install, .help, .system, .settings])
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

    func testCollectionChordsAppearInTheMenuUntilABindingClaimsTheLetter() {
        let home = MenuCatalog.results(query: "", page: .home, apps: [], help: [])
        XCTAssertEqual(home.first { $0.destination == .mail }?.chord, "E")
        XCTAssertEqual(home.first { $0.destination == .editors }?.chord, "C")
        XCTAssertEqual(home.first { $0.destination == .agents }?.chord, "A")

        // A binding on the same letter wins, so the chord stops being advertised.
        let claimed = MenuCatalog.results(query: "", page: .home, apps: [], help: [],
                                          boundKeys: ["c", "a"])
        XCTAssertEqual(claimed.first { $0.destination == .mail }?.chord, "E")
        XCTAssertNil(claimed.first { $0.destination == .editors }?.chord)
        XCTAssertNil(claimed.first { $0.destination == .agents }?.chord)
    }

    func testOnlyTheDefaultChoiceCarriesTheLaunchChord() {
        let rows = MenuCatalog.results(query: "", page: .mail, apps: [], help: [],
                                       defaultApps: [.mail: "emzero"], boundKeys: [])
        XCTAssertTrue(rows.allSatisfy { $0.chord == "E" })
        XCTAssertEqual(rows.filter(\.isDefaultChoice).map(\.title), ["Emzero"])
        let claimed = MenuCatalog.results(query: "", page: .mail, apps: [], help: [],
                                          defaultApps: [.mail: "emzero"], boundKeys: ["e"])
        XCTAssertTrue(claimed.allSatisfy { $0.chord == nil })
    }

    func testChordsRenderWithTheHyperGlyph() {
        XCTAssertEqual(MenuShortcut.hyper("E"), "✦ E")
        XCTAssertEqual(MenuShortcut.symbolic("Hyper + Shift + E"), "✦ ⇧ E")
        XCTAssertEqual(MenuShortcut.symbolic("Hyper + Space"), "✦ Space")
        // Text that names no chord is left exactly as written.
        XCTAssertEqual(MenuShortcut.symbolic("Tap Caps Lock"), "Tap Caps Lock")
        // The written form stays in the row's own text, so search still matches.
        let rows = MenuCatalog.results(query: "hyper", page: .help, apps: [],
                                       help: [MenuEntry(title: "Focus left", detail: "Hyper + H")])
        XCTAssertEqual(rows.map(\.detail), ["Hyper + H"])
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
        // A flag between the command and the workspace used to land in the title.
        XCTAssertTrue(entries.contains {
            $0.title == "Move window to workspace 7" && $0.detail == "Hyper + Shift + 7"
        })
        XCTAssertFalse(entries.contains { $0.title.contains("--") })
    }
    /// omaccy:// links name a page by their host, which is how the menu bar's
    /// Apple menu opens Settings. Any other scheme is ignored rather than
    /// falling back to Help the way an unknown preview name does.
    func testLinksOpenThePageTheyName() throws {
        let settings = try XCTUnwrap(URL(string: "omaccy://settings"))
        XCTAssertEqual(SuperMenuController.Section.linked(by: settings)?.page, .settings)
        let system = try XCTUnwrap(URL(string: "omaccy://System"))
        XCTAssertEqual(SuperMenuController.Section.linked(by: system)?.page, .system)
        let web = try XCTUnwrap(URL(string: "https://settings"))
        XCTAssertNil(SuperMenuController.Section.linked(by: web))
        XCTAssertEqual(SuperMenuController.Section.named("settings").page, .settings)
    }

    func testSettingsUpdaterRunsWithoutAFurtherPage() {
        let actions = MenuCatalog.results(query: "update", page: .settings, apps: [], help: [])
        XCTAssertEqual(actions.map(\.title), ["Update Omaccy"])
        XCTAssertTrue(actions[0].updatesOmaccy)
        XCTAssertFalse(actions[0].upgradesAll)
        // Nothing to browse into: the row is the action, not a doorway.
        XCTAssertNil(actions[0].destination)
        // A search from Home reaches the same row and fires it in place.
        let fromHome = MenuCatalog.results(query: "update omaccy", page: .home, apps: [], help: []).first
        XCTAssertTrue(fromHome?.updatesOmaccy == true)
        XCTAssertNil(fromHome?.destination)
    }

    func testUpdaterRowNamesTheRunningVersion() {
        let updater = MenuCatalog.results(query: "", page: .settings, apps: [], help: [])
            .first { $0.updatesOmaccy }
        XCTAssertTrue(updater?.detail.contains(Constants.version) == true)
        // The version is searchable too, so "0.4.0" finds what is running.
        XCTAssertTrue(MenuCatalog.results(query: Constants.version, page: .settings, apps: [], help: [])
            .contains { $0.updatesOmaccy })
    }

    func testSettingsPageListsThemeAndFontCollections() {
        let entries = MenuCatalog.results(query: "", page: .settings, apps: [], help: [])
        XCTAssertEqual(entries.map(\.title), ["Theme", "Font", "Clipboard", "Update Omaccy"])
        XCTAssertEqual(entries.compactMap(\.destination), [.theme, .font, .clipboardSettings])
        // The updater lives here now rather than on Home, but a search from
        // Home still reaches it, since global search spans Settings too.
        XCTAssertFalse(MenuCatalog.categories().contains { $0.updatesOmaccy })
        XCTAssertEqual(MenuCatalog.results(query: "font", page: .settings, apps: [], help: []).map(\.title), ["Font"])
        XCTAssertTrue(MenuCatalog.results(query: "nord", page: .settings, apps: [], help: []).isEmpty)
    }

    func testClipboardSettingsRowsReadTheirCurrentState() {
        let on = ClipboardSettingsState(enabled: true, persist: false, count: 3)
        let rows = MenuCatalog.results(query: "", page: .clipboardSettings, apps: [], help: [], clipboard: on)
        XCTAssertEqual(rows.compactMap(\.clipboardSetting), [.enabled, .persist, .clear])
        XCTAssertEqual(rows.map(\.isOn), [true, false, false])
        XCTAssertTrue(rows[0].detail.hasPrefix("On"))
        XCTAssertTrue(rows[1].detail.hasPrefix("Off"))
        XCTAssertEqual(rows[2].detail, "3 entries recorded")

        let off = ClipboardSettingsState(enabled: false, persist: true, count: 1)
        let flipped = MenuCatalog.results(query: "", page: .clipboardSettings, apps: [], help: [], clipboard: off)
        XCTAssertEqual(flipped.map(\.isOn), [false, true, false])
        XCTAssertEqual(flipped[2].detail, "1 entry recorded")
    }

    func testClipboardSettingsAreSearchableWithinTheirPage() {
        let state = ClipboardSettingsState()
        XCTAssertEqual(MenuCatalog.results(query: "disk", page: .clipboardSettings, apps: [], help: [],
                                           clipboard: state).map(\.title), ["Keep history on disk"])
        XCTAssertTrue(MenuCatalog.results(query: "nord", page: .clipboardSettings, apps: [], help: [],
                                          clipboard: state).isEmpty)
    }

    /// Both clipboard pages are findable from anywhere, but only as pages: no
    /// individual control, and no recorded entry, is ever a global result.
    func testOnlyClipboardPagesReachTheGlobalSearch() {
        for page in [MenuPage.home, .apps, .help, .system] {
            let results = MenuCatalog.results(query: "clipboard", page: page, apps: [], help: [])
            XCTAssertEqual(results.compactMap(\.destination), [.clipboard, .clipboardSettings])
            XCTAssertTrue(results.allSatisfy { $0.clipboardSetting == nil && $0.clip == nil })
        }
    }

    func testSettingsReachableFromHomeAndGlobalSearch() {
        XCTAssertTrue(MenuCatalog.categories().contains { $0.destination == .settings })
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

    /// The Theme page opens with the switches for where a theme reaches, ahead
    /// of the palettes themselves.
    func testThemePageLeadsWithTheReachSwitches() {
        let page = MenuCatalog.results(query: "", page: .theme, apps: [], help: [])
        XCTAssertEqual(page.first?.togglesEditorTheming, true)
        XCTAssertEqual(page.dropFirst().first?.togglesMacOSAppearance, true)
        let off = MenuCatalog.themeReachEntries(matching: "", editors: false, appearance: false)
        XCTAssertEqual(off.count, 2)
        XCTAssertTrue(off.allSatisfy { !$0.isOn })
        XCTAssertTrue(off.allSatisfy { $0.detail.hasPrefix("Off · ") })
        XCTAssertTrue(MenuCatalog.themeReachEntries(matching: "", editors: true, appearance: true)
            .allSatisfy(\.isOn))
    }

    /// They answer to what they affect by name, not just to the word "theme".
    func testReachSwitchesAreSearchableByWhatTheyAffect() {
        func one(_ query: String) -> MenuEntry? {
            let hits = MenuCatalog.themeReachEntries(matching: query, editors: false, appearance: false)
            return hits.count == 1 ? hits[0] : nil
        }
        XCTAssertEqual(one("cursor")?.togglesEditorTheming, true)
        XCTAssertEqual(one("vs code")?.togglesEditorTheming, true)
        XCTAssertEqual(one("macos")?.togglesMacOSAppearance, true)
        XCTAssertEqual(one("light")?.togglesMacOSAppearance, true)
        XCTAssertTrue(MenuCatalog.themeReachEntries(matching: "gruvbox", editors: false, appearance: false).isEmpty)
    }

    /// ⌘1–9 picks a row directly; every other digit chord stays out of the way.
    func testCommandDigitPicksARow() {
        func event(_ characters: String, _ flags: NSEvent.ModifierFlags, keyCode: UInt16 = 18) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                             windowNumber: 0, context: nil, characters: characters,
                             charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
        }
        XCTAssertEqual(SuperMenuController.numberedRow(in: event("1", .command)), 0)
        XCTAssertEqual(SuperMenuController.numberedRow(in: event("9", .command)), 8)
        // Caps lock and the numeric keypad ride along; the chord still counts.
        XCTAssertEqual(SuperMenuController.numberedRow(in: event("4", [.command, .capsLock])), 3)
        XCTAssertEqual(SuperMenuController.numberedRow(in: event("4", [.command, .numericPad, .function])), 3)
        // No ⌘, a bare digit typed into the search field.
        XCTAssertNil(SuperMenuController.numberedRow(in: event("1", [])))
        // ⇧ turns the digit into a symbol, so ⌘⇧3 never reads as row 3.
        XCTAssertNil(SuperMenuController.numberedRow(in: event("#", [.command, .shift])))
        // Other modifiers belong to whatever else claims them.
        XCTAssertNil(SuperMenuController.numberedRow(in: event("1", [.command, .option])))
        XCTAssertNil(SuperMenuController.numberedRow(in: event("1", [.command, .control])))
        // 0 is not a row: rows are numbered from 1.
        XCTAssertNil(SuperMenuController.numberedRow(in: event("0", .command)))
        XCTAssertNil(SuperMenuController.numberedRow(in: event("a", .command)))
    }

    func testAgentEntriesMarkDefaultAndFilter() {
        let entries = MenuCatalog.agentEntries(matching: "", defaultToken: "codex")
        XCTAssertEqual(entries.map(\.agent), CodingAgent.allCases)
        // Desktop apps lead the list; the terminal agents follow.
        XCTAssertEqual(entries.compactMap { $0.agent?.kind }, [.desktop, .desktop, .desktop, .terminal, .terminal, .terminal])
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

/// `reloadData` drops the selection, which broke every ⌘ chord in the palette:
/// pressing ⌘ repaints the rows with their ⌘1–9 markers, and the repaint left
/// no selected row for ⌘↵ (open on Homebrew, set a picker default) or ⌘⌫ to
/// act on. The repaint has to put the selection back.
// Every line here drives NSTableView, which is main-actor isolated. Swift
// 6.3 lets a nonisolated test reach it; the Xcode the release workflow runs
// does not, and the whole class failed to compile there while passing
// locally. Isolating the class is how ClipboardHistoryTests answers the same
// mismatch.
@MainActor
final class TableReloadTests: XCTestCase {
    private final class Source: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var count: Int
        init(count: Int) { self.count = count }
        func numberOfRows(in tableView: NSTableView) -> Int { count }
        func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
            NSTextField(labelWithString: "row \(row)")
        }
    }

    /// `dataSource` and `delegate` are weak, so the source is parked on the
    /// test case to keep the table answering for the length of the test.
    private var sources: [Source] = []

    private func makeTable(rows: Int) -> (NSTableView, Source) {
        let source = Source(count: rows)
        sources.append(source)
        let table = NSTableView()
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("column")))
        table.dataSource = source
        table.delegate = source
        table.reloadData()
        return (table, source)
    }

    // The async override inherits the class's isolation; the synchronous one
    // is nonisolated and cannot reach `sources`. It does not call super for
    // the reason ClipboardMonitorTests gives: XCTestCase's implementation is
    // empty, and handing a main actor-isolated, non-Sendable fixture to a
    // nonisolated superclass method is an error under strict concurrency.
    override func tearDown() async throws {
        sources.removeAll()
    }

    /// The behaviour the fix exists for: plain `reloadData` really does deselect.
    func testReloadDataClearsSelection() {
        let (table, _) = makeTable(rows: 12)
        table.selectRowIndexes(IndexSet(integer: 4), byExtendingSelection: false)
        XCTAssertEqual(table.selectedRow, 4)
        table.reloadData()
        XCTAssertEqual(table.selectedRow, -1)
    }

    func testReloadPreservingSelectionKeepsTheSelectedRow() {
        let (table, _) = makeTable(rows: 12)
        table.selectRowIndexes(IndexSet(integer: 4), byExtendingSelection: false)
        table.reloadPreservingSelection()
        XCTAssertEqual(table.selectedRow, 4)
    }

    func testReloadPreservingSelectionOnAnEmptyOrUnselectedTable() {
        let (empty, _) = makeTable(rows: 0)
        empty.reloadPreservingSelection()
        XCTAssertEqual(empty.selectedRow, -1)

        let (table, _) = makeTable(rows: 5)
        table.reloadPreservingSelection()
        XCTAssertEqual(table.selectedRow, -1)
    }

    /// A selection past the end of a shrunken table is dropped, not restored.
    func testReloadPreservingSelectionDropsAnOutOfRangeSelection() {
        let (table, source) = makeTable(rows: 12)
        table.selectRowIndexes(IndexSet(integer: 11), byExtendingSelection: false)
        source.count = 3
        table.reloadPreservingSelection()
        XCTAssertEqual(table.selectedRow, -1)
    }
}
