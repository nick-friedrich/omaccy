import XCTest
@testable import hyperkey

final class ClipboardHistoryTests: XCTestCase {
    private func item(_ text: String, fromKeystroke: Bool = true, age: TimeInterval = 0) -> ClipboardItem {
        ClipboardItem(text: text, sourceBundleID: "com.mitchellh.ghostty",
                      copiedAt: Date().addingTimeInterval(-age), fromKeystroke: fromKeystroke)
    }

    // MARK: - What may be recorded

    func testRecordsAnOrdinaryCopy() {
        XCTAssertEqual(ClipboardCapture.decide(types: ["public.utf8-plain-text"],
                                               sourceBundleID: "com.mitchellh.ghostty",
                                               text: "git status"), .record)
    }

    func testRejectsEveryConcealedMarker() {
        // Bitwarden's desktop app sets ConcealedType; the others are the rest
        // of the nspasteboard.org convention.
        for marker in ClipboardCapture.concealedTypes {
            XCTAssertEqual(
                ClipboardCapture.decide(types: ["public.utf8-plain-text", marker],
                                        sourceBundleID: "com.bitwarden.desktop",
                                        text: "hunter2"),
                .reject(.marked(marker)), marker)
        }
    }

    func testRejectsDeniedSourceEvenWithoutAMarker() {
        XCTAssertEqual(
            ClipboardCapture.decide(types: ["public.utf8-plain-text"],
                                    sourceBundleID: "com.bitwarden.desktop",
                                    text: "hunter2"),
            .reject(.deniedSource("com.bitwarden.desktop")))
    }

    /// The case neither list catches: Bitwarden's Chrome extension sets no
    /// marker and the copy is attributed to Chrome, so it is recorded like any
    /// other text. Only the keystroke check and memory-only storage stand
    /// between it and the history, which is why this behavior is pinned here.
    func testAnExtensionCopyIsIndistinguishableFromAnOrdinaryOne() {
        let types = ["public.utf8-plain-text", "org.chromium.source-url"]
        XCTAssertEqual(ClipboardCapture.decide(types: types, sourceBundleID: "com.google.Chrome",
                                               text: "S3cret-Pass"), .record)
        XCTAssertFalse(ClipboardItem(text: "S3cret-Pass", sourceBundleID: "com.google.Chrome",
                                     fromKeystroke: false).isPersistable)
    }

    func testRejectsEmptyAndWhitespaceOnly() {
        for text in ["", "   ", "\n\t "] {
            XCTAssertEqual(ClipboardCapture.decide(types: [], sourceBundleID: nil, text: text), .reject(.empty))
        }
    }

    func testRejectsOversizedText() {
        let text = String(repeating: "a", count: 200)
        XCTAssertEqual(ClipboardCapture.decide(types: [], sourceBundleID: nil, text: text, maxBytes: 100),
                       .reject(.tooLarge))
        XCTAssertEqual(ClipboardCapture.decide(types: [], sourceBundleID: nil, text: text, maxBytes: 500), .record)
    }

    func testUnresolvedSourceIsNotStoredAsALabel() {
        XCTAssertNil(ClipboardCapture.source("com.apple.loginwindow"))
        XCTAssertNil(ClipboardCapture.source(nil))
        XCTAssertEqual(ClipboardCapture.source("com.google.Chrome"), "com.google.Chrome")
    }

    // MARK: - What is kept

    func testNewestFirstAndCappedAtTheLimit() {
        var items: [ClipboardItem] = []
        for text in ["one", "two", "three"] {
            items = ClipboardCapture.ingest(item(text), into: items, limit: 2)
        }
        XCTAssertEqual(items.map(\.text), ["three", "two"])
    }

    func testRecopyingPromotesInsteadOfDuplicating() {
        var items = ClipboardCapture.ingest(item("one"), into: [], limit: 10)
        items = ClipboardCapture.ingest(item("two"), into: items, limit: 10)
        items = ClipboardCapture.ingest(item("one"), into: items, limit: 10)
        XCTAssertEqual(items.map(\.text), ["one", "two"])
    }

    func testAZeroLimitKeepsNothing() {
        XCTAssertTrue(ClipboardCapture.ingest(item("one"), into: [], limit: 0).isEmpty)
    }

    func testProgrammaticCopiesExpireButKeyboardCopiesDoNot() {
        let items = [item("typed", fromKeystroke: true, age: 300),
                     item("fresh button copy", fromKeystroke: false, age: 10),
                     item("stale button copy", fromKeystroke: false, age: 300)]
        XCTAssertEqual(ClipboardCapture.pruned(items, volatileTTL: 90).map(\.text),
                       ["typed", "fresh button copy"])
    }

    func testOnlyKeystrokeCopiesReachDisk() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("omaccy-clipboard-\(UUID().uuidString)")
        setenv("OMACCY_CLIPBOARD_DIR", directory.path, 1)
        defer {
            unsetenv("OMACCY_CLIPBOARD_DIR")
            try? FileManager.default.removeItem(at: directory)
        }

        ClipboardStore.save([item("typed"), item("button copy", fromKeystroke: false)])
        XCTAssertEqual(ClipboardStore.load().map(\.text), ["typed"])

        let mode = try FileManager.default.attributesOfItem(atPath: ClipboardStore.fileURL.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.int16Value, 0o600)

        ClipboardStore.clear()
        XCTAssertTrue(ClipboardStore.load().isEmpty)
    }
}

/// Drives the real polling path -- timer, background read, record -- against a
/// private pasteboard, so it never touches the user's clipboard.
@MainActor
final class ClipboardMonitorTests: XCTestCase {
    private var monitor: ClipboardMonitor!
    private var pasteboard: NSPasteboard!

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard(name: NSPasteboard.Name("omaccy-test-\(UUID().uuidString)"))
        monitor = ClipboardMonitor(pasteboardName: pasteboard.name)
        monitor.apply(Configuration(escapeOnTap: false, bindings: [:]))
    }

    override func tearDown() {
        monitor.stop()
        pasteboard.releaseGlobally()
        super.tearDown()
    }

    /// Polls at 0.5s, and the read hops to a background queue and back, so the
    /// main run loop has to turn a few times before an entry lands.
    private func waitForItems(_ expected: Int, timeout: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(timeout)
        while monitor.count != expected && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertEqual(monitor.count, expected)
    }

    private func write(_ text: String, concealed: Bool = false) {
        pasteboard.clearContents()
        var types: [NSPasteboard.PasteboardType] = [.string]
        if concealed { types.append(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) }
        pasteboard.declareTypes(types, owner: nil)
        pasteboard.setString(text, forType: .string)
    }

    func testCapturesACopyEndToEnd() {
        write("git rebase -i")
        waitForItems(1)
        XCTAssertEqual(monitor.items.first?.text, "git rebase -i")
    }

    func testSkipsAConcealedCopy() {
        write("hunter2", concealed: true)
        // Nothing should ever land, so give the poll real time to prove it.
        RunLoop.main.run(until: Date().addingTimeInterval(2))
        XCTAssertEqual(monitor.count, 0)
    }

    func testDisablingDropsWhatWasAlreadyRecorded() {
        write("something copied")
        waitForItems(1)

        var off = Configuration(escapeOnTap: false, bindings: [:])
        off.clipboardHistory = false
        monitor.apply(off)
        XCTAssertEqual(monitor.count, 0)

        write("copied while off")
        RunLoop.main.run(until: Date().addingTimeInterval(2))
        XCTAssertEqual(monitor.count, 0)
    }
}

final class ClipboardHistoryPageTests: XCTestCase {
    private func item(_ text: String, source: String? = "com.google.Chrome",
                      age: TimeInterval = 0) -> ClipboardItem {
        ClipboardItem(text: text, sourceBundleID: source,
                      copiedAt: Date().addingTimeInterval(-age), fromKeystroke: true)
    }

    func testHistoryIsListedNewestFirstAsGiven() {
        let items = [item("newest"), item("older"), item("oldest")]
        XCTAssertEqual(MenuCatalog.clipboardHistoryEntries(matching: "", items: items).map(\.title),
                       ["newest", "older", "oldest"])
    }

    /// The whole entry is searched, not just the line shown on the row.
    func testSearchMatchesTextBelowTheFirstLine() {
        let items = [item("first line\nbudget: 4200\ntrailing"), item("unrelated")]
        let hits = MenuCatalog.clipboardHistoryEntries(matching: "budget", items: items)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.title, "first line")
        XCTAssertTrue(MenuCatalog.clipboardHistoryEntries(matching: "nothing here", items: items).isEmpty)
    }

    func testTitleUsesTheFirstNonBlankLineWithWhitespaceCollapsed() {
        XCTAssertEqual(MenuCatalog.clipboardTitle("\n\n    let x   =  1\nlet y = 2"), "let x = 1")
        XCTAssertEqual(MenuCatalog.clipboardTitle("\t spaced \t out "), "spaced out")
        XCTAssertEqual(MenuCatalog.clipboardTitle(""), "")
    }

    func testLongTitlesAreTruncated() {
        let title = MenuCatalog.clipboardTitle(String(repeating: "a", count: 200), limit: 10)
        XCTAssertEqual(title, String(repeating: "a", count: 10) + "…")
    }

    func testDetailDescribesShapeSourceAndAge() {
        XCTAssertEqual(MenuCatalog.clipboardDetail(item("one line", age: 0)),
                       "8 characters · Chrome · just now")
        XCTAssertEqual(MenuCatalog.clipboardDetail(item("a\nb\nc", age: 3 * 3600)),
                       "3 lines · 5 characters · Chrome · 3h ago")
        // An unattributed copy simply omits the source rather than inventing one.
        XCTAssertEqual(MenuCatalog.clipboardDetail(item("x", source: nil, age: 120)),
                       "1 character · 2m ago")
    }

    func testSourceNameFallsOutOfTheBundleIdentifier() {
        XCTAssertEqual(MenuCatalog.clipboardSourceName("com.mitchellh.ghostty"), "Ghostty")
        XCTAssertEqual(MenuCatalog.clipboardSourceName("com.google.Chrome"), "Chrome")
        XCTAssertNil(MenuCatalog.clipboardSourceName(nil))
        XCTAssertNil(MenuCatalog.clipboardSourceName(""))
    }

    func testAgeReadsInTheLargestUsefulUnit() {
        let now = Date()
        for (seconds, expected) in [(0.0, "just now"), (59.0, "just now"), (60.0, "1m ago"),
                                    (3599.0, "59m ago"), (7200.0, "2h ago"), (172_800.0, "2d ago")] {
            XCTAssertEqual(MenuCatalog.clipboardAge(from: now.addingTimeInterval(-seconds), to: now),
                           expected, "\(seconds)s")
        }
    }

    func testHomeOffersClipboardOnHyperVUnlessThatLetterIsBound() {
        let entry = MenuCatalog.categories().first { $0.destination == .clipboard }
        XCTAssertEqual(entry?.chord, "V")
        let bound = MenuCatalog.categories(boundKeys: ["v"]).first { $0.destination == .clipboard }
        XCTAssertNil(bound?.chord)
    }

    /// Recorded text must never leak into the search that spans every page.
    func testHistoryEntriesStayOffTheGlobalSearch() {
        let items = [item("a secret token")]
        for page in [MenuPage.home, .apps, .help, .system] {
            let results = MenuCatalog.results(query: "secret token", page: page, apps: [], help: [],
                                              clipboardItems: items)
            XCTAssertTrue(results.isEmpty, "\(page)")
        }
        XCTAssertEqual(MenuCatalog.results(query: "secret", page: .clipboard, apps: [], help: [],
                                           clipboardItems: items).count, 1)
    }
}
