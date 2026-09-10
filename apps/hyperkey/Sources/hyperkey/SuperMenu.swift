import AppKit

struct MenuEntry: Sendable {
    let title: String
    let detail: String
    var bundleID: String? = nil
    var destination: MenuPage? = nil
    var systemAction: SystemAction? = nil
    var package: HomebrewPackage? = nil
    var upgradesAll = false
    var updatesOmaccy = false
    var theme: String? = nil
    var font: String? = nil
    var agent: CodingAgent? = nil
    var collection: AppCollection? = nil
    var choice: AppChoice? = nil
    /// Marks the agent or app this collection launches from its own chord.
    var isDefaultChoice = false
    /// The Hyper letter this collection answers to, absent when a `[bindings]`
    /// entry has taken that letter back.
    var chord: String? = nil
    var clip: ClipboardItem? = nil
    var clipboardSetting: ClipboardSetting? = nil
    /// The Theme page's switch for whether VS Code and Cursor follow along.
    var togglesEditorTheming = false
    /// The Theme page's switch for whether macOS light/dark follows along.
    var togglesMacOSAppearance = false
    /// Current state of a two-state setting row.
    var isOn = false
}

/// The clipboard-history controls on the Settings page.
enum ClipboardSetting: String, Sendable, CaseIterable {
    case enabled, persist, clear
}

/// What those controls currently read as.
struct ClipboardSettingsState: Sendable, Equatable {
    var enabled = true
    var persist = false
    var count = 0
}

enum MenuPage: String, Sendable {
    case home = "Home", apps = "Apps", help = "Help", install = "Install"
    case system = "System", agents = "Agents"
    case mail = "Mail", editors = "Editors"
    case settings = "Settings", theme = "Theme", font = "Font"
    case clipboardSettings = "Clipboard"
    case clipboard = "Clipboard History"
}

enum MenuCatalog {
    /// `boundKeys` are the letters claimed by `[bindings]`; a collection whose
    /// letter is claimed no longer advertises a chord it does not answer to.
    static func categories(boundKeys: Set<String> = []) -> [MenuEntry] { [
        MenuEntry(title: "Apps", detail: "Find and open an application", destination: .apps),
        MenuEntry(title: "Agents", detail: "Launch a coding agent in a terminal or its own app", destination: .agents,
                  chord: chord("A", boundKeys)),
        MenuEntry(title: "Mail", detail: AppCollection.mail.summary, destination: .mail, collection: .mail,
                  chord: chord(AppCollection.mail.chord, boundKeys)),
        MenuEntry(title: "Editors", detail: AppCollection.editors.summary, destination: .editors, collection: .editors,
                  chord: chord(AppCollection.editors.chord, boundKeys)),
        MenuEntry(title: "Clipboard", detail: "Paste something you copied earlier", destination: .clipboard,
                  chord: chord("V", boundKeys)),
        MenuEntry(title: "Install", detail: "Search Homebrew apps and command-line tools", destination: .install),
        MenuEntry(title: "Help", detail: "Explore your keyboard shortcuts", destination: .help),
        MenuEntry(title: "System", detail: "Sleep, restart, or shut down your Mac", destination: .system),
        MenuEntry(title: "Settings", detail: "Pick the theme and font for the bar and launcher", destination: .settings),
    ] }

    static func chord(_ letter: String, _ boundKeys: Set<String>) -> String? {
        boundKeys.contains(letter.lowercased()) ? nil : letter
    }

    static let settings = [
        MenuEntry(title: "Theme", detail: "Color palettes for SketchyBar and this launcher", destination: .theme),
        MenuEntry(title: "Font", detail: "UI font for SketchyBar and this launcher", destination: .font),
        MenuEntry(title: "Clipboard", detail: "Turn clipboard history on or off and choose how it is kept",
                  destination: .clipboardSettings),
        updateEntry,
    ]

    /// Settings runs the updater directly: the page it used to open held this
    /// one row, so the extra hop only restated the row the user just picked.
    /// The detail names the running version, which is where the question
    /// "should I update?" is actually asked. It no longer names Ghostty --
    /// the row now sits in global search, where "ghost" must find the app and
    /// not the updater; the action hint carries that terminal instead.
    static var updateEntry: MenuEntry {
        MenuEntry(title: "Update Omaccy",
                  detail: "Version \(Constants.version) · Pull the latest code, then rerun setup",
                  updatesOmaccy: true)
    }

    /// Rows for the clipboard controls. Each carries its own current state, so
    /// the page reads as a set of switches rather than a list of commands.
    static func clipboardEntries(matching query: String, state: ClipboardSettingsState) -> [MenuEntry] {
        matching(query, in: [
            MenuEntry(title: "Clipboard history",
                      detail: state.enabled ? "On · Recording what you copy" : "Off · Nothing is recorded",
                      clipboardSetting: .enabled, isOn: state.enabled),
            MenuEntry(title: "Keep history on disk",
                      detail: state.persist
                          ? "On · Kept in ~/.omaccy/clipboard, survives a restart"
                          : "Off · Memory only, cleared when Omaccy restarts",
                      clipboardSetting: .persist, isOn: state.persist),
            MenuEntry(title: "Clear clipboard history",
                      detail: state.count == 1 ? "1 entry recorded" : "\(state.count) entries recorded",
                      clipboardSetting: .clear),
        ], searchText: { "\($0.title) \($0.detail)" })
    }

    /// Head the Theme page: a theme is a choice, but where it lands is a set
    /// of switches, and the questions are only worth asking together. State is
    /// injected by the tests the way `themeEntries` takes its own.
    static func themeReachEntries(matching query: String, editors: Bool? = nil,
                                  appearance: Bool? = nil) -> [MenuEntry] {
        let editorsOn = editors ?? OmaccyAppearance.editorThemingEnabled
        let appearanceOn = appearance ?? OmaccyAppearance.macOSAppearanceEnabled
        return matching(query, in: [
            MenuEntry(title: "Follow in VS Code and Cursor",
                      detail: editorsOn
                          ? "On · Both switch with the theme, installing its extension when needed"
                          : "Off · Both keep whatever theme they are on",
                      togglesEditorTheming: true, isOn: editorsOn),
            MenuEntry(title: "Follow in macOS light and dark",
                      detail: appearanceOn
                          ? "On · macOS switches appearance to match the palette"
                          : "Off · macOS keeps whatever appearance you set",
                      togglesMacOSAppearance: true, isOn: appearanceOn)
        ], searchText: { "\($0.title) \($0.detail)" })
    }

    static let system = SystemAction.allCases.map {
        MenuEntry(title: $0.title, detail: $0.detail, systemAction: $0)
    }

    static func results(query: String, page: MenuPage, apps: [MenuEntry], help: [MenuEntry],
                        defaultAgent: String? = nil,
                        defaultApps: [AppCollection: String] = [:],
                        boundKeys: Set<String> = [],
                        clipboard: ClipboardSettingsState = ClipboardSettingsState(),
                        clipboardItems: [ClipboardItem] = []) -> [MenuEntry] {
        if page == .install { return [] }
        if page == .settings {
            return matching(query, in: settings) { "\($0.title) \($0.detail)" }
        }
        if page == .clipboardSettings { return clipboardEntries(matching: query, state: clipboard) }
        if page == .clipboard { return clipboardHistoryEntries(matching: query, items: clipboardItems) }
        if page == .theme { return themeReachEntries(matching: query) + themeEntries(matching: query) }
        if page == .font { return fontEntries(matching: query) }
        if page == .agents {
            return agentEntries(matching: query, defaultToken: defaultAgent, chord: chord("A", boundKeys))
        }
        if let collection = AppCollection.allCases.first(where: { $0.page == page }) {
            return choiceEntries(matching: query, in: collection, defaultToken: defaultApps[collection],
                                 chord: chord(collection.chord, boundKeys))
        }
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        if words.isEmpty {
            switch page {
            case .home: return categories(boundKeys: boundKeys)
            case .apps: return apps
            case .help: return help
            case .system: return system
            case .install, .settings, .theme, .font, .agents, .mail, .editors,
                 .clipboardSettings, .clipboard: return []
            }
        }
        // Search always spans the whole menu, even while browsing a category.
        var seenApps = Set<String>()
        var searchable: [MenuEntry] = categories(boundKeys: boundKeys)
        searchable += settings
        searchable += apps
        searchable += help
        searchable += system
        return searchable.filter { entry in
            words.allSatisfy { (entry.title + " " + entry.detail).localizedCaseInsensitiveContains($0) }
        }.filter { entry in
            guard let id = entry.bundleID else { return true }
            return seenApps.insert(id).inserted
        }
    }

    static func themeEntries(matching query: String, themes: [String]? = nil, active: String? = nil) -> [MenuEntry] {
        let names = themes ?? OmaccyAppearance.availableThemes()
        let current = active ?? OmaccyAppearance.currentThemeName
        return matching(query, in: names.map { name in
            MenuEntry(title: OmaccyAppearance.displayName(forTheme: name),
                      detail: name == current ? "Active" : "Theme palette", theme: name)
        }, searchText: { "\($0.title) \($0.theme ?? "") \($0.detail)" })
    }

    static func fontEntries(matching query: String, active: String? = nil) -> [MenuEntry] {
        let current = active ?? OmaccyAppearance.currentFontKey
        return matching(query, in: OmaccyTheme.fontKeys.map { key in
            MenuEntry(title: OmaccyTheme.fontFamilies[key] ?? key,
                      detail: key == current ? "Active" : "UI font", font: key)
        }, searchText: { "\($0.title) \($0.font ?? "") \($0.detail)" })
    }

    static func agentEntries(matching query: String, defaultToken: String?, chord: String? = nil) -> [MenuEntry] {
        matching(query, in: CodingAgent.allCases.map { agent in
            MenuEntry(title: agent.title,
                      detail: "\(agent.detail) · \(agent.isInstalled ? "Installed" : "Installs via Homebrew")",
                      bundleID: agent.bundleID,
                      agent: agent,
                      isDefaultChoice: agent.rawValue == defaultToken,
                      chord: chord)
        }, searchText: { "\($0.title) \($0.detail)" })
    }

    /// Rows for a picker collection: every choice, installed or not, so an app
    /// can be set as the default and installed from the same place.
    static func choiceEntries(matching query: String, in collection: AppCollection,
                              defaultToken: String?, chord: String? = nil) -> [MenuEntry] {
        matching(query, in: collection.choices.map { choice in
            let status = choice.isInstalled ? "Installed" : (choice.installLabel ?? "Included with macOS")
            return MenuEntry(title: choice.title,
                             detail: "\(collection.itemLabel) · \(choice.summary) · \(status)",
                             collection: collection,
                             choice: choice,
                             isDefaultChoice: choice.id == defaultToken,
                             chord: chord)
        }, searchText: { "\($0.title) \($0.detail)" })
    }

    /// Recorded copies, newest first. Unlike every other page, the query runs
    /// against the whole entry text rather than the visible row, since finding
    /// a line buried in something copied earlier is the point of the page.
    static func clipboardHistoryEntries(matching query: String, items: [ClipboardItem],
                                        now: Date = Date()) -> [MenuEntry] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return items.filter { item in
            words.allSatisfy { item.text.localizedCaseInsensitiveContains($0) }
        }.map { item in
            MenuEntry(title: clipboardTitle(item.text), detail: clipboardDetail(item, now: now), clip: item)
        }
    }

    /// The first non-blank line, with runs of whitespace collapsed so that
    /// indented code or wrapped prose still reads as one line.
    static func clipboardTitle(_ text: String, limit: Int = 120) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let collapsed = line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard collapsed.count > limit else { return collapsed }
        return collapsed.prefix(limit).trimmingCharacters(in: .whitespaces) + "…"
    }

    static func clipboardDetail(_ item: ClipboardItem, now: Date = Date()) -> String {
        var parts: [String] = []
        let lines = item.text.components(separatedBy: .newlines).count
        if lines > 1 { parts.append("\(lines) lines") }
        parts.append(item.text.count == 1 ? "1 character" : "\(item.text.count) characters")
        if let name = clipboardSourceName(item.sourceBundleID) { parts.append(name) }
        parts.append(clipboardAge(from: item.copiedAt, to: now))
        return parts.joined(separator: " · ")
    }

    /// The last component of a bundle identifier reads as the app's name far
    /// more often than not, and costs no disk lookup per row.
    static func clipboardSourceName(_ bundleID: String?) -> String? {
        guard let last = bundleID?.split(separator: ".").last, !last.isEmpty else { return nil }
        return last.prefix(1).uppercased() + last.dropFirst()
    }

    static func clipboardAge(from date: Date, to now: Date) -> String {
        let seconds = max(now.timeIntervalSince(date), 0)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h ago" }
        return "\(Int(seconds / 86_400))d ago"
    }

    private static func matching(_ query: String, in entries: [MenuEntry], searchText: (MenuEntry) -> String) -> [MenuEntry] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return entries }
        return entries.filter { entry in
            words.allSatisfy { searchText(entry).localizedCaseInsensitiveContains($0) }
        }
    }
}

@MainActor
private enum PaletteStyle {
    static var theme = OmaccyTheme.load()
    static var accent: NSColor { theme.accent }
    static var muted: NSColor { theme.muted }
    static var text: NSColor { theme.text }

    static func reload() { theme = OmaccyTheme.load() }

    static func font(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        guard let family = theme.fontFamily, let font = NSFont(name: family, size: size) else {
            return .systemFont(ofSize: size, weight: weight)
        }
        return font
    }

    static func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font(size: size, weight: weight)
        label.textColor = Self.text
        label.lineBreakMode = .byTruncatingTail
        return label
    }
}

private final class PaletteRow: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        PaletteStyle.accent.withAlphaComponent(0.10).setFill()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 2), xRadius: 10, yRadius: 10)
        path.fill()
        PaletteStyle.accent.withAlphaComponent(0.22).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
}

private final class PalettePanel: NSPanel {
    var onDismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onDismiss?() }
}

@MainActor
final class SuperMenuController: NSObject, NSWindowDelegate, NSTextFieldDelegate,
                                 NSTableViewDataSource, NSTableViewDelegate {
    enum Section { case apps, help, agents, clipboard, collection(AppCollection)

        /// Resolves a preview page name; anything unrecognized opens Help,
        /// the section previews have always started on.
        static func named(_ name: String?) -> Section {
            switch name?.lowercased() {
            case "home", "apps": return .apps
            case "agents": return .agents
            case "clipboard": return .clipboard
            default:
                if let collection = AppCollection.allCases.first(where: { $0.rawValue == name?.lowercased() }) {
                    return .collection(collection)
                }
                return .help
            }
        }

        var page: MenuPage {
            switch self {
            case .apps: return .home
            case .help: return .help
            case .agents: return .agents
            case .clipboard: return .clipboard
            case let .collection(collection): return collection.page
            }
        }
    }
    static let shared = SuperMenuController()
    private var panel: PalettePanel!
    private let search = NSTextField()
    private let table = NSTableView()
    private let location = PaletteStyle.label("BROWSE", size: 10, weight: .semibold)
    private let count = PaletteStyle.label("", size: 10)
    private let actionHint = PaletteStyle.label("", size: 11)
    private let emptyState = PaletteStyle.label("No matches. Try an app, shortcut, or system action.", size: 14)
    private var page: MenuPage = .home
    /// The row each page was left on when the user descended out of it, so
    /// going back lands on the collection they just came from rather than
    /// snapping to the top of the list. Cleared whenever the palette is opened
    /// afresh, so a new invocation always starts at the first row.
    private var selectionMemory: [MenuPage: MenuEntry] = [:]
    /// Whether ⌘ is held right now, which turns the first nine rows' markers
    /// into the digits that fire them. Tracked rather than polled so the
    /// numbers appear on the press and leave again on the release.
    private var commandHeld = false
    private var openingSection: Section = .apps
    private var keyMonitor: Any?
    private var builtFor: String?
    private var previewGeneration = 0
    private var apps: [MenuEntry] = []
    private var help: [MenuEntry] = []
    private var rows: [MenuEntry] = []
    private var installedApps: [String: MenuEntry] = [:]
    private var defaultAgentToken: String?
    private var defaultAppTokens: [AppCollection: String] = [:]
    private var boundKeys: Set<String> = []
    private var clipboardState = ClipboardSettingsState()
    private var indexing = false
    private var packages: [HomebrewPackage] = []
    private var installedPackages: [HomebrewPackage] = []
    private var loadingInventory = false
    private var inventoryReady = false
    private var inventoryError = false
    private var loadingPackages = false
    private var packageError = false
    private var catalogLoadedAt: Date?
    private var previousApp: NSRunningApplication?

    /// Mirrors `height=34` in config/sketchybar/sketchybarrc. SketchyBar floats
    /// above `visibleFrame` rather than reserving space in it -- the native menu
    /// bar is hidden, so that frame reaches the top of the screen -- which means
    /// the palette has to keep clear of the bar itself.
    private static let barHeight: CGFloat = 34
    private static let screenMargin: CGFloat = 12
    /// Tall enough for a comfortable page, short enough not to take over the
    /// screen. Longer lists scroll rather than growing without bound.
    private static let maxHeight: CGFloat = 700

    /// The region the panel may occupy: the visible frame, less the bar and a
    /// margin on each edge.
    private func allowedFrame(on screen: NSScreen?) -> NSRect {
        guard let visible = screen?.visibleFrame else { return .zero }
        return NSRect(x: visible.minX + Self.screenMargin,
                      y: visible.minY + Self.screenMargin,
                      width: visible.width - Self.screenMargin * 2,
                      height: visible.height - Self.barHeight - Self.screenMargin * 2)
    }

    /// Moves a frame back inside `allowed` without resizing it; the height is
    /// already constrained to fit by the time this runs.
    private func clamped(_ frame: NSRect, within allowed: NSRect) -> NSRect {
        guard !allowed.isEmpty else { return frame }
        var frame = frame
        if frame.maxY > allowed.maxY { frame.origin.y = allowed.maxY - frame.height }
        if frame.minY < allowed.minY { frame.origin.y = allowed.minY }
        return frame
    }

    func toggle(section: Section) {
        // Rebuild the palette when the theme or font changed since it was built.
        PaletteStyle.reload()
        if panel != nil, builtFor != PaletteStyle.theme.identity, let frame = teardownPanelForRebuild() {
            build()
            panel.setFrameOrigin(frame.origin)
        }
        if panel == nil { build() }
        if panel.isVisible && openingSection.page == section.page { dismiss(); return }
        if !panel.isVisible { previousApp = NSWorkspace.shared.frontmostApplication }
        openingSection = section
        page = section.page
        selectionMemory.removeAll()
        // The palette leaves by several paths — dismissed, ordered out to launch
        // an app, or simply losing key status — and the ⌘ release then lands in
        // whatever came forward instead of here. Clearing on the way in is the
        // one place that covers all of them.
        commandHeld = false
        search.stringValue = ""
        reloadCatalog()
        filter()
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let allowed = allowedFrame(on: screen)
        if !allowed.isEmpty {
            let origin = NSPoint(x: allowed.midX - panel.frame.width / 2,
                                 y: allowed.midY - panel.frame.height / 2 + allowed.height * 0.10)
            panel.setFrame(clamped(NSRect(origin: origin, size: panel.frame.size), within: allowed),
                           display: false)
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(search)
    }

    private func build() {
        if NSApp.mainMenu == nil {
            let menu = NSMenu()
            menu.addItem(NSMenuItem())
            let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: "Edit")
            for (title, action, key) in [
                ("Cut", #selector(NSText.cut(_:)), "x"),
                ("Copy", #selector(NSText.copy(_:)), "c"),
                ("Paste", #selector(NSText.paste(_:)), "v"),
                ("Select All", #selector(NSText.selectAll(_:)), "a")
            ] { submenu.addItem(NSMenuItem(title: title, action: action, keyEquivalent: key)) }
            edit.submenu = submenu
            menu.addItem(edit)
            NSApp.mainMenu = menu
        }
        panel = PalettePanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 500),
                             styleMask: [.borderless], backing: .buffered, defer: false)
        panel.onDismiss = { [weak self] in self?.back() }
        panel.title = "Omaccy"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        let background = NSView()
        background.wantsLayer = true
        background.layer?.backgroundColor = PaletteStyle.theme.background.withAlphaComponent(0.98).cgColor
        background.layer?.cornerRadius = 18
        background.layer?.borderWidth = 1
        background.layer?.borderColor = PaletteStyle.theme.border.cgColor
        panel.contentView = background

        let brand = PaletteStyle.label("O M A C C Y", size: 10, weight: .bold)
        brand.textColor = PaletteStyle.accent
        let subtitle = PaletteStyle.label("Your keyboard. Your workspace.", size: 11)
        subtitle.textColor = PaletteStyle.muted
        search.placeholderAttributedString = NSAttributedString(string: "Search anything…", attributes: [
            .foregroundColor: PaletteStyle.muted,
            .font: PaletteStyle.font(size: 23, weight: .regular)
        ])
        search.font = PaletteStyle.font(size: 23)
        search.textColor = PaletteStyle.text
        search.isBordered = false
        search.drawsBackground = false
        search.focusRingType = .none
        search.delegate = self
        search.setAccessibilityLabel("Search all apps, shortcuts, and system actions")
        let magnifier = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)!)
        magnifier.contentTintColor = PaletteStyle.muted
        location.textColor = PaletteStyle.muted
        count.textColor = PaletteStyle.muted
        actionHint.textColor = PaletteStyle.accent
        emptyState.textColor = PaletteStyle.muted
        emptyState.isHidden = true

        table.headerView = nil
        table.rowHeight = 62
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.backgroundColor = .clear
        table.focusRingType = .none
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("entry")))
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.action = #selector(activateClickedRow)
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let line = NSBox(); line.boxType = .separator
        let bottomLine = NSBox(); bottomLine.boxType = .separator
        let navigation = PaletteStyle.label("↑ ↓  Navigate     ⇥  Next     esc  Back", size: 11)
        navigation.textColor = PaletteStyle.muted
        for view in [brand, subtitle, search, magnifier, location, count, scroll, line, bottomLine, navigation, actionHint, emptyState] {
            view.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(view)
        }
        NSLayoutConstraint.activate([
            brand.topAnchor.constraint(equalTo: background.topAnchor, constant: 23),
            brand.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 26),
            subtitle.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -26),
            subtitle.centerYAnchor.constraint(equalTo: brand.centerYAnchor),
            magnifier.leadingAnchor.constraint(equalTo: brand.leadingAnchor),
            magnifier.topAnchor.constraint(equalTo: brand.bottomAnchor, constant: 26),
            magnifier.widthAnchor.constraint(equalToConstant: 22), magnifier.heightAnchor.constraint(equalToConstant: 28),
            search.leadingAnchor.constraint(equalTo: magnifier.trailingAnchor, constant: 14),
            search.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -26),
            search.centerYAnchor.constraint(equalTo: magnifier.centerYAnchor), search.heightAnchor.constraint(equalToConstant: 34),
            line.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 21),
            line.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 1),
            line.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -1),
            location.topAnchor.constraint(equalTo: line.bottomAnchor, constant: 17),
            location.leadingAnchor.constraint(equalTo: brand.leadingAnchor),
            count.centerYAnchor.constraint(equalTo: location.centerYAnchor),
            count.trailingAnchor.constraint(equalTo: subtitle.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: location.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: bottomLine.topAnchor, constant: -10),
            bottomLine.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -47),
            bottomLine.leadingAnchor.constraint(equalTo: line.leadingAnchor), bottomLine.trailingAnchor.constraint(equalTo: line.trailingAnchor),
            navigation.leadingAnchor.constraint(equalTo: brand.leadingAnchor),
            navigation.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -17),
            actionHint.trailingAnchor.constraint(equalTo: subtitle.trailingAnchor),
            actionHint.centerYAnchor.constraint(equalTo: navigation.centerYAnchor),
            emptyState.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyState.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
        ])
        // Keep typing in search after navigation or a mouse selection. All actions
        // are available without moving focus through native controls.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            // ⌘ alone is never ours to swallow — other shortcuts still need it —
            // so this only repaints the markers and passes the event along.
            if event.type == .flagsChanged {
                self.setCommandHeld(event.modifierFlags.contains(.command))
                return event
            }
            if let row = Self.numberedRow(in: event) { self.activate(numberedRow: row); return nil }
            switch event.keyCode {
            case 125: self.select(delta: 1)
            case 126: self.select(delta: -1)
            case 48: self.select(delta: event.modifierFlags.contains(.shift) ? -1 : 1)
            case 36, 76: self.performReturn(commandHeld: event.modifierFlags.contains(.command))
            case 53: self.back()
            case 51 where self.page == .clipboard && event.modifierFlags.contains(.command):
                self.deleteClipboardSelection()
            case 51 where self.search.stringValue.isEmpty && self.page != .home: self.back()
            default:
                if self.panel.firstResponder === self.table { self.panel.makeFirstResponder(self.search) }
                return event
            }
            return nil
        }
        builtFor = PaletteStyle.theme.identity
    }

    /// Repaints the row markers as ⌘ goes down or up, so only the right-hand
    /// column moves. `reloadData` drops the selection, which has to be put
    /// back: without that, merely pressing ⌘ deselected the row, and every
    /// chord the markers advertise -- ⌘↵ to open a package on Homebrew, ⌘↵ to
    /// set a picker default, ⌘⌫ to delete a clip -- found no row to act on.
    private func setCommandHeld(_ held: Bool) {
        guard commandHeld != held else { return }
        commandHeld = held
        table.reloadPreservingSelection()
    }

    private func dismiss() {
        panel.orderOut(nil)
        if let previousApp, previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp.activate(options: [])
        }
    }

    private func teardownPanelForRebuild() -> NSRect? {
        guard let panel else { return nil }
        let frame = panel.frame
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
        keyMonitor = nil
        panel.delegate = nil
        panel.orderOut(nil)
        self.panel = nil
        return frame
    }

    /// Rebuilds the open palette after an appearance change, preserving its
    /// position, page, and search query so rows re-render with the new look.
    private func refreshAppearance() {
        PaletteStyle.reload()
        guard builtFor != PaletteStyle.theme.identity, let frame = teardownPanelForRebuild() else { return }
        let query = search.stringValue
        build()
        // Restore the exact prior frame, not just its origin: build() always
        // starts a fresh panel at a fixed default height, and filter() below
        // only nudges the height by the delta from whatever height it finds
        // on the panel right now. Seeding just the origin left the height at
        // that fixed default, so every in-place rebuild (i.e. every theme
        // pick while the palette stays open) quietly walked the window's top
        // edge down by the gap between the default and the real height.
        panel.setFrame(frame, display: false)
        search.stringValue = query
        filter()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(search)
    }

    private func back() {
        if !search.stringValue.isEmpty { search.stringValue = ""; filter() }
        else if page != .home { page = .home; filter(restoring: selectionMemory.removeValue(forKey: .home)) }
        else { dismiss() }
        if panel.isVisible { panel.makeFirstResponder(search) }
    }

    func windowDidResignKey(_ notification: Notification) { panel.orderOut(nil) }
    func controlTextDidChange(_ notification: Notification) { filter() }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { PaletteRow() }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard rows.indices.contains(table.selectedRow) else { actionHint.stringValue = ""; return }
        let entry = rows[table.selectedRow]
        if entry.updatesOmaccy {
            actionHint.stringValue = "↵  Open updater in Ghostty…"
        } else if entry.upgradesAll {
            actionHint.stringValue = !inventoryReady
                ? (inventoryError ? "Reopen Install to retry" : "Checking installed packages…")
                : HomebrewUpgrade.availableCount(installedPackages) > 0 ? "↵  Confirm upgrade all…" : "No updates available"
        } else if let package = entry.package {
            let openHint = package.homebrewURL != nil ? "  ·  ⌘↵  Open on Homebrew" : ""
            actionHint.stringValue = !inventoryReady
                ? (inventoryError ? "Reopen Install to retry" : "Checking installed packages…")
                : (package.actionTitle.map { "↵  " + $0 + "…" } ?? (package.pinned ? "Pinned in Homebrew" : "Installed")) + openHint
        } else if let agent = entry.agent {
            let installed = agent.kind == .terminal ? agent.isInstalled && CodingAgent.herdrInstalled : agent.isInstalled
            actionHint.stringValue = installed
                ? (entry.isDefaultChoice ? "↵  Launch  ·  Default" : "↵  Launch  ·  ⌘↵  Set default")
                : "↵  Install \(agent.title)…"
        } else if entry.clip != nil {
            actionHint.stringValue = "↵  Paste  ·  ⌘↵  Copy  ·  ⌘⌫  Delete"
        } else if let setting = entry.clipboardSetting {
            actionHint.stringValue = setting == .clear
                ? (entry.detail.hasPrefix("0 ") ? "Nothing recorded" : "↵  Clear now")
                : entry.isOn ? "↵  Turn off" : "↵  Turn on"
        } else if entry.togglesEditorTheming || entry.togglesMacOSAppearance {
            actionHint.stringValue = entry.isOn ? "↵  Turn off" : "↵  Turn on"
        } else if let choice = entry.choice {
            actionHint.stringValue = choice.isInstalled
                ? (entry.isDefaultChoice ? "↵  Launch  ·  Default" : "↵  Launch  ·  ⌘↵  Set default")
                : choice.appStoreURL != nil ? "↵  Open in the Mac App Store  ·  ⌘↵  Set default"
                : "↵  Install \(choice.title)…  ·  ⌘↵  Set default"
        } else {
            actionHint.stringValue = entry.destination != nil ? "↵  Browse" : entry.bundleID != nil ? "↵  Open app" : entry.theme != nil ? "↵  Apply theme" : entry.font != nil ? "↵  Apply font" : entry.systemAction != nil ? "↵  " + (entry.systemAction == .sleep ? "Sleep" : "Confirm…") : "Shortcut reference"
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = rows[row]
        let cell = NSView()
        let title = PaletteStyle.label(entry.title, size: 14, weight: .medium)
        if let fontKey = entry.font, let family = OmaccyTheme.fontFamilies[fontKey],
           let preview = NSFont(name: family, size: 14) {
            title.font = preview
        }
        let isApp = entry.bundleID != nil
        let describesItself = entry.updatesOmaccy || entry.upgradesAll || entry.package != nil
            || entry.destination != nil || entry.systemAction != nil || entry.theme != nil || entry.font != nil
            || entry.agent != nil || entry.choice != nil || entry.clipboardSetting != nil || entry.clip != nil
            || entry.togglesEditorTheming || entry.togglesMacOSAppearance
        let detail = PaletteStyle.label(describesItself && !entry.detail.hasPrefix("Hyper") ? entry.detail : isApp ? "Application" : "Keyboard shortcut", size: 11)
        detail.textColor = PaletteStyle.muted
        let icon: NSView
        if let themeName = entry.theme {
            // Theme rows preview the actual palette (background + accent/text/
            // muted dots) instead of a generic tinted icon.
            icon = Self.themeSwatch(for: themeName)
        } else {
            let image: NSImage
            if let id = entry.bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                image = NSWorkspace.shared.icon(forFile: url.path)
            } else {
                image = NSImage(systemSymbolName: Self.symbol(for: entry), accessibilityDescription: nil)!
            }
            let imageView = NSImageView(image: image)
            imageView.contentTintColor = PaletteStyle.accent
            imageView.imageScaling = .scaleProportionallyUpOrDown
            icon = imageView
        }
        // While ⌘ is held the first nine rows advertise the digit that fires
        // them, in place of their usual chevron, ✓, or shortcut.
        let numbered = commandHeld && row < 9
        let keys = PaletteStyle.label(numbered ? "⌘\(row + 1)" : Self.keyHint(for: entry, isApp: isApp),
                                      size: 11, weight: .medium)
        keys.textColor = numbered || entry.destination != nil || entry.package?.outdated == true
            || entry.theme != nil || entry.font != nil ? PaletteStyle.accent : PaletteStyle.muted
        keys.alignment = .right
        keys.setContentCompressionResistancePriority(.required, for: .horizontal)
        // Its own label so the chord stays muted next to an accented chevron.
        let chord = PaletteStyle.label(numbered ? "" : Self.chordHint(for: entry), size: 11, weight: .medium)
        chord.textColor = PaletteStyle.muted
        chord.alignment = .right
        chord.setContentCompressionResistancePriority(.required, for: .horizontal)
        for view in [icon, title, detail, chord, keys] { view.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(view) }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 30), icon.heightAnchor.constraint(equalToConstant: 30),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 14),
            title.topAnchor.constraint(equalTo: cell.topAnchor, constant: 12),
            detail.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            keys.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -18),
            keys.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            keys.widthAnchor.constraint(lessThanOrEqualToConstant: 230),
            chord.trailingAnchor.constraint(equalTo: keys.leadingAnchor, constant: -12),
            chord.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: chord.leadingAnchor, constant: -16),
            detail.trailingAnchor.constraint(lessThanOrEqualTo: chord.leadingAnchor, constant: -16),
        ])
        return cell
    }

    /// A 30x30 preview of a theme's palette: its bar background as a rounded
    /// swatch, bordered, with small dots for accent/text/muted so a row shows
    /// what the theme actually looks like rather than a single tint color.
    private static func themeSwatch(for name: String) -> NSView {
        let size: CGFloat = 30
        let container = NSView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        container.wantsLayer = true
        let colors = OmaccyTheme.palette(named: name)
        container.layer?.backgroundColor = (colors["BAR_BG"] ?? PaletteStyle.theme.background).cgColor
        container.layer?.borderColor = (colors["BORDER"] ?? PaletteStyle.theme.border).cgColor
        container.layer?.borderWidth = 1
        container.layer?.cornerRadius = 7

        let dotColors = [
            colors["ACCENT"] ?? PaletteStyle.theme.accent,
            colors["TEXT"] ?? PaletteStyle.theme.text,
            colors["MUTED"] ?? PaletteStyle.theme.muted,
        ]
        let dotSize: CGFloat = 6
        let spacing: CGFloat = 3
        var x = (size - (dotSize * CGFloat(dotColors.count) + spacing * CGFloat(dotColors.count - 1))) / 2
        let y = (size - dotSize) / 2
        for color in dotColors {
            let dot = CALayer()
            dot.frame = CGRect(x: x, y: y, width: dotSize, height: dotSize)
            dot.backgroundColor = color.cgColor
            dot.cornerRadius = dotSize / 2
            container.layer?.addSublayer(dot)
            x += dotSize + spacing
        }
        return container
    }

    private static func symbol(for entry: MenuEntry) -> String {
        if let setting = entry.clipboardSetting {
            switch setting {
            case .enabled: return "doc.on.clipboard"
            case .persist: return "internaldrive"
            case .clear: return "trash"
            }
        }
        if entry.destination == .clipboardSettings || entry.destination == .clipboard
            || entry.clip != nil { return "doc.on.clipboard" }
        if let agent = entry.agent { return agent.symbol }
        if let collection = entry.collection { return collection.symbol }
        if let action = entry.systemAction { return action.symbol }
        if entry.togglesEditorTheming { return "chevron.left.forwardslash.chevron.right" }
        if entry.togglesMacOSAppearance { return "circle.lefthalf.filled" }
        if entry.theme != nil || entry.destination == .theme { return "paintpalette" }
        if entry.font != nil || entry.destination == .font { return "textformat" }
        if entry.destination == .settings { return "gearshape" }
        if entry.updatesOmaccy || entry.upgradesAll || entry.package != nil || entry.destination == .install {
            return "arrow.down.circle"
        }
        switch entry.destination {
        case .system: return "power"
        case .apps: return "square.grid.2x2"
        case .help: return "keyboard"
        default: return "command"
        }
    }

    private static func keyHint(for entry: MenuEntry, isApp: Bool) -> String {
        if let status = entry.package?.status { return status }
        if entry.theme != nil || entry.font != nil { return entry.detail == "Active" ? "✓" : "" }
        if let setting = entry.clipboardSetting { return setting == .clear ? "" : entry.isOn ? "✓" : "" }
        if entry.togglesEditorTheming || entry.togglesMacOSAppearance { return entry.isOn ? "✓" : "" }
        if entry.clip != nil { return "" }
        if entry.agent != nil || entry.choice != nil { return entry.isDefaultChoice ? "✓" : "" }
        if entry.detail.hasPrefix("Hyper") { return MenuShortcut.symbolic(entry.detail) }
        if entry.destination != nil { return "›" }
        let isShortcut = !isApp && entry.systemAction == nil && entry.package == nil
            && !entry.upgradesAll && !entry.updatesOmaccy
        return isShortcut ? MenuShortcut.symbolic(entry.detail) : ""
    }

    /// The collection chord, shown muted beside the row's own marker so a
    /// browsable row keeps its chevron. Rows inside a collection carry the
    /// chord too, but only the chosen default is actually launched by it.
    private static func chordHint(for entry: MenuEntry) -> String {
        guard let chord = entry.chord else { return "" }
        if entry.agent != nil || entry.choice != nil {
            return entry.isDefaultChoice ? MenuShortcut.hyper(chord) : ""
        }
        return MenuShortcut.hyper(chord)
    }

    private func select(delta: Int) {
        guard !rows.isEmpty else { return }
        let row = (max(table.selectedRow, 0) + delta + rows.count) % rows.count
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
        previewAppearance(for: rows[row])
    }

    /// Live-previews a theme/font as arrow-key browsing passes over it —
    /// clicking a row already applies immediately via activate(row:), so
    /// this makes keyboard navigation match. Debounced so holding the
    /// arrow key down (or arrowing straight through the list) doesn't
    /// rebuild the palette and reload SketchyBar on every repeat tick;
    /// only the row the user actually settles on gets applied.
    private func previewAppearance(for entry: MenuEntry) {
        let apply: () -> Void
        if let themeName = entry.theme, themeName != OmaccyAppearance.currentThemeName {
            apply = { self.applyTheme(named: themeName) }
        } else if let fontKey = entry.font, fontKey != OmaccyAppearance.currentFontKey {
            apply = { self.applyFont(named: fontKey) }
        } else {
            return
        }
        previewGeneration += 1
        let generation = previewGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self, self.previewGeneration == generation else { return }
            apply()
        }
    }

    @objc private func activateClickedRow() {
        if isPickerPage, NSApp.currentEvent?.modifierFlags.contains(.command) == true {
            table.selectRowIndexes(IndexSet(integer: table.clickedRow), byExtendingSelection: false)
            setDefaultChoice()
            return
        }
        if page == .install, NSApp.currentEvent?.modifierFlags.contains(.command) == true {
            table.selectRowIndexes(IndexSet(integer: table.clickedRow), byExtendingSelection: false)
            openSelectedPackageOnHomebrew()
            return
        }
        activate(row: table.clickedRow)
    }

    private func activateSelection() {
        activate(row: table.selectedRow)
    }

    private func openSelectedPackageOnHomebrew() {
        guard rows.indices.contains(table.selectedRow), let package = rows[table.selectedRow].package,
              let url = package.homebrewURL else { return }
        NSWorkspace.shared.open(url)
    }

    private func activate(row: Int) {
        guard rows.indices.contains(row) else { return }
        let entry = rows[row]
        if let destination = entry.destination {
            selectionMemory[page] = entry
            page = destination
            if destination == .install { loadPackages() }
            search.stringValue = ""
            filter()
            panel.makeFirstResponder(search)
        } else if let bundleID = entry.bundleID {
            panel.orderOut(nil)
            HotkeyBindings.focusOrLaunch(bundleIdentifier: bundleID)
        } else if let themeName = entry.theme {
            previewGeneration += 1
            applyTheme(named: themeName)
        } else if let fontKey = entry.font {
            previewGeneration += 1
            applyFont(named: fontKey)
        } else if entry.updatesOmaccy {
            updateOmaccy()
        } else if entry.upgradesAll {
            upgradeAll()
        } else if let package = entry.package {
            install(package)
        } else if let agent = entry.agent {
            activateAgent(agent)
        } else if let choice = entry.choice {
            activateChoice(choice)
        } else if let clip = entry.clip {
            useClipboardItem(clip, paste: true)
        } else if let setting = entry.clipboardSetting {
            toggleClipboard(setting)
        } else if entry.togglesEditorTheming {
            toggleEditorTheming()
        } else if entry.togglesMacOSAppearance {
            toggleMacOSAppearance()
        } else if let action = entry.systemAction {
            performSystemAction(action)
        }
    }

    /// What Return does on the current page. Shared with the ⌘1–9 shortcuts so
    /// a numbered pick lands on exactly the action the row's hint advertises.
    private func performReturn(commandHeld: Bool) {
        if page == .clipboard {
            activateClipboardSelection(paste: !commandHeld)
        } else if isPickerPage, commandHeld {
            setDefaultChoice()
        } else if page == .install, commandHeld {
            openSelectedPackageOnHomebrew()
        } else {
            activateSelection()
        }
    }

    /// The row a ⌘1–9 press points at, zero-based. Matched on the character
    /// rather than the key code, so the digit printed on the key is the one
    /// that works on non-US layouts and the numeric keypad comes along free.
    /// ⇧ turns a digit into a symbol, so ⌘⇧3 and friends never reach here.
    nonisolated static func numberedRow(in event: NSEvent) -> Int? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.subtracting([.command, .numericPad, .function, .capsLock]) == [],
              flags.contains(.command),
              let digit = event.charactersIgnoringModifiers.flatMap({ Int($0) }),
              (1...9).contains(digit) else { return nil }
        return digit - 1
    }

    /// Jumps to a row by number and fires it. ⌘ is only there to spell the
    /// chord, so this never means the ⌘Return variant of the row's action.
    private func activate(numberedRow row: Int) {
        guard rows.indices.contains(row) else { return }
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
        performReturn(commandHeld: false)
    }

    private func activateClipboardSelection(paste: Bool) {
        guard rows.indices.contains(table.selectedRow), let clip = rows[table.selectedRow].clip else { return }
        useClipboardItem(clip, paste: paste)
    }

    /// Puts the entry back on the pasteboard and, unless the user asked only to
    /// copy it, pastes it into whatever they were using. Dismissing first hands
    /// focus back to that app; the keystroke is worthless until it has it.
    private func useClipboardItem(_ item: ClipboardItem, paste: Bool) {
        ClipboardMonitor.shared.put(item)
        dismiss()
        guard paste else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { ClipboardPaste.send() }
    }

    private func deleteClipboardSelection() {
        guard rows.indices.contains(table.selectedRow), let clip = rows[table.selectedRow].clip else { return }
        ClipboardMonitor.shared.remove(clip.id)
        filter(preservingSelection: true)
    }

    /// Applies a clipboard control and re-renders the page in place, so the
    /// row the user just pressed shows its new state without leaving Settings.
    private func toggleClipboard(_ setting: ClipboardSetting) {
        var config = Configuration.load()
        switch setting {
        case .enabled: config.clipboardHistory.toggle()
        case .persist: config.clipboardPersist.toggle()
        case .clear: ClipboardMonitor.shared.clear()
        }
        if setting != .clear {
            config.save()
            ClipboardMonitor.shared.apply(config)
        }
        reloadCatalog(refreshApps: false)
        filter(preservingSelection: true)
    }

    /// Flips the opt-in and, when turning it on, pushes the theme at the
    /// editors straight away — so the switch has the same visible effect as
    /// picking a theme does. Mirrors `set_editor_theming` in scripts/theme.sh.
    private func toggleEditorTheming() {
        OmaccyAppearance.setEditorTheming(!OmaccyAppearance.editorThemingEnabled)
        filter(preservingSelection: true)
        restoreSelection { $0.togglesEditorTheming }
    }

    /// Same shape as the editor switch: turning it on brings macOS up to the
    /// current palette straight away rather than waiting for the next pick.
    private func toggleMacOSAppearance() {
        OmaccyAppearance.setMacOSAppearanceFollowing(!OmaccyAppearance.macOSAppearanceEnabled)
        filter(preservingSelection: true)
        restoreSelection { $0.togglesMacOSAppearance }
    }

    private func applyTheme(named themeName: String) {
        applyAppearance {
            guard OmaccyAppearance.applyTheme(themeName) else { return false }
            return true
        } onSettled: {
            self.restoreSelection { $0.theme == themeName }
        }
    }

    private func applyFont(named fontKey: String) {
        applyAppearance {
            OmaccyAppearance.applyFont(fontKey)
        } onSettled: {
            self.restoreSelection { $0.font == fontKey }
        }
    }

    /// Applies a theme/font choice and rebuilds the palette in place so the
    /// new look and active markers appear without closing the panel. The
    /// settle hook runs after the rebuild and reselects the applied entry.
    private func applyAppearance(apply: () -> Bool, onSettled: @escaping () -> Void) {
        guard apply() else { return }
        refreshAppearance()
        onSettled()
        tableViewSelectionDidChange(Notification(name: NSTableView.selectionDidChangeNotification))
    }

    private func restoreSelection(matching predicate: (MenuEntry) -> Bool) {
        guard let index = rows.firstIndex(where: predicate) else { return }
        table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        table.scrollRowToVisible(index)
    }

    private func loadPackages() {
        if !loadingInventory {
            loadingInventory = true
            inventoryReady = false
            inventoryError = false
            Task { @MainActor in
                do {
                    installedPackages = try await Task.detached { try HomebrewInventory.load() }.value
                    inventoryReady = true
                } catch { inventoryError = true }
                loadingInventory = false
                if page == .install { filter(preservingSelection: true) }
            }
        }
        guard page == .install, !loadingPackages, catalogLoadedAt.map({ Date().timeIntervalSince($0) > 3600 }) ?? true else { return }
        loadingPackages = true
        packageError = false
        Task { @MainActor in
            do {
                packages = try await HomebrewCatalog.load()
                catalogLoadedAt = Date()
            } catch { packageError = true }
            loadingPackages = false
            if page == .install { filter(preservingSelection: true) }
        }
    }

    private func install(_ package: HomebrewPackage) {
        guard inventoryReady, let command = package.actionCommand, let actionTitle = package.actionTitle else { return }
        panel.orderOut(nil)
        let alert = NSAlert()
        guard let brew = HomebrewInventory.executable else {
            alert.messageText = "Homebrew is required"
            alert.informativeText = "Install Homebrew from brew.sh, then try again."
            alert.runModal()
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(search)
            return
        }
        alert.messageText = "\(actionTitle) \(package.name)?"
        alert.informativeText = "Ghostty will run:\n\n\(command)\n\nHomebrew may install dependencies or ask for your password. Packages you install here remain yours when Omaccy is uninstalled."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: actionTitle)
        guard alert.runModal() == .alertSecondButtonReturn else {
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(search)
            return
        }
        guard let arguments = package.ghosttyArguments(brew: brew) else { return }
        launchPackageCommand(arguments: arguments)
    }

    private func updateOmaccy() {
        panel.orderOut(nil)
        guard let checkout = OmaccyUpdate.checkout(),
              let arguments = OmaccyUpdate.ghosttyArguments(checkout: checkout) else {
            showPackageLaunchError("The Omaccy checkout is missing or has moved. Run scripts/update.sh from its new location to restore this menu action.")
            return
        }
        // update.sh explains the setup changes and asks for confirmation in
        // Ghostty. Its independent process survives the app restarting itself.
        launchPackageCommand(arguments: arguments)
    }

    private func upgradeAll() {
        let available = HomebrewUpgrade.availableCount(installedPackages)
        guard inventoryReady, available > 0, let brew = HomebrewInventory.executable,
              let arguments = HomebrewUpgrade.allArguments(brew: brew) else { return }
        panel.orderOut(nil)
        let alert = NSAlert()
        alert.messageText = "Upgrade all Homebrew packages?"
        alert.informativeText = "Homebrew currently reports \(available) unpinned package\(available == 1 ? "" : "s") with updates.\n\nGhostty will run: brew upgrade\n\nThis upgrades eligible formulae and apps, including dependencies. Homebrew may refresh its metadata and find additional updates. Pinned packages stay pinned. Progress and any errors will appear in Ghostty."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Upgrade all")
        guard alert.runModal() == .alertSecondButtonReturn else {
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(search)
            return
        }
        launchPackageCommand(arguments: arguments)
    }

    /// Launches the agent configured as `default_agent`, or opens the Agents
    /// collection to pick one if none is set. Works even before the palette
    /// has ever been opened, since Hyper+A can be the very first press.
    func launchDefaultAgent() {
        guard let token = Configuration.load().defaultAgent, let agent = CodingAgent(rawValue: token) else {
            toggle(section: .agents)
            return
        }
        activateAgent(agent)
    }

    /// Launches the app configured for `collection`, or opens the collection
    /// to pick one when none is set or the configured app is gone. Like
    /// `launchDefaultAgent`, this works before the palette has ever opened,
    /// since the chord can be the very first press.
    func launchDefaultApp(in collection: AppCollection) {
        guard let token = Configuration.load()[collection],
              let choice = collection.choice(id: token), choice.isInstalled else {
            toggle(section: .collection(collection))
            return
        }
        activateChoice(choice)
    }

    /// Installed apps launch like any other binding, so they follow their
    /// window across AeroSpace workspaces. Missing ones offer their install
    /// route instead of failing silently.
    private func activateChoice(_ choice: AppChoice) {
        guard let bundleID = choice.bundleID else {
            confirmAndInstallChoice(choice)
            return
        }
        panel?.orderOut(nil)
        HotkeyBindings.focusOrLaunch(bundleIdentifier: bundleID)
    }

    /// Mirrors `confirmAndInstallDesktopAgent`, including its skipped
    /// `inventoryReady` gate: a chord press has no reason to have loaded the
    /// Install page's Homebrew inventory, and a choice's installed state comes
    /// from a synchronous lookup on disk. App Store apps have no command to
    /// confirm — opening their store page is the whole action.
    private func confirmAndInstallChoice(_ choice: AppChoice) {
        panel?.orderOut(nil)
        if let storeURL = choice.appStoreURL {
            NSWorkspace.shared.open(storeURL)
            return
        }
        guard choice.package != nil else {
            // Bundled apps have no install route; one missing from disk is a
            // removed or relocated system app, not something to install.
            showRestoringPanel(title: "\(choice.title) is not installed",
                               message: "\(choice.appName) was not found in Applications.")
            return
        }
        guard let brew = HomebrewInventory.executable else {
            showRestoringPanel(title: "Homebrew is required",
                               message: "Install Homebrew from brew.sh, then try again.")
            return
        }
        guard let package = choice.package, let command = package.actionCommand,
              let arguments = package.ghosttyArguments(brew: brew) else { return }
        let alert = NSAlert()
        alert.messageText = "Install \(choice.title)?"
        alert.informativeText = "Ghostty will run:\n\n\(command)\n\nHomebrew may install dependencies or ask for your password. Reopen \(pageTitleForChoice(choice)) and press Return again once it finishes."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Install")
        guard alert.runModal() == .alertSecondButtonReturn else {
            panel?.makeKeyAndOrderFront(nil)
            panel?.makeFirstResponder(search)
            return
        }
        launchPackageCommand(arguments: arguments)
    }

    private func pageTitleForChoice(_ choice: AppChoice) -> String {
        AppCollection.allCases.first { $0.choices.contains(choice) }?.title ?? "the collection"
    }

    /// An alert that hands focus back to the palette, the pattern every
    /// blocked action here already follows.
    private func showRestoringPanel(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
        panel?.makeKeyAndOrderFront(nil)
        panel?.makeFirstResponder(search)
    }

    private func activateAgent(_ agent: CodingAgent) {
        switch agent.kind {
        case .desktop:
            if agent.isInstalled {
                panel?.orderOut(nil)
                HotkeyBindings.focusOrLaunch(bundleIdentifier: agent.bundleID!)
            } else {
                confirmAndInstallDesktopAgent(agent)
            }
        case .terminal:
            guard let binary = agent.binaryName else { return }
            guard agent.isInstalled, CodingAgent.herdrInstalled else {
                confirmAndInstallTerminalAgent(agent)
                return
            }
            panel?.orderOut(nil)
            // herdr's own CLI can block briefly, so do all of this off the main
            // thread — same rule HotkeyBindings.focusOrLaunch follows for its
            // AeroSpace calls. Provisioning (creating a workspace, starting the
            // agent) is headless and needs no terminal, so it happens here
            // whether or not the agent was already running — only the final
            // reveal decides whether a Ghostty window is even needed.
            DispatchQueue.global(qos: .userInitiated).async {
                let workspaceID = HerdrBridge.runningWorkspaceID(for: binary) ?? HerdrBridge.provisionWorkspace(binary: binary)
                if let workspaceID { HerdrBridge.focusWorkspace(workspaceID) }
                Self.revealAgentWorkspace()
            }
        }
    }

    /// Switches to the dedicated AeroSpace workspace and opens Ghostty there
    /// only if nothing is already showing it — so reattaching to an agent
    /// that's already visible never spawns a redundant window.
    nonisolated private static func revealAgentWorkspace() {
        guard let aerospace = HotkeyBindings.aeroSpaceExecutableURL() else { return }
        _ = HotkeyBindings.run(aerospace, arguments: ["workspace", "agent"])
        guard !HotkeyBindings.ghosttyWindowExists(inWorkspace: "agent") else { return }
        DispatchQueue.main.async {
            SuperMenuController.shared.launchPackageCommand(arguments: [
                "--wait-after-command=true", "--quit-after-last-window-closed=true",
                "-e", "/bin/bash", "-c",
                "export PATH=/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$PATH; exec herdr",
            ])
        }
    }

    /// Mirrors `install(_:)`'s confirm-then-run-in-Ghostty flow, but skips its
    /// `inventoryReady` gate: that flag only becomes true once the Install
    /// page's async Homebrew inventory has loaded, which a fresh Hyper+A or
    /// Hyper+Shift+A press has no reason to have triggered yet. Agent install
    /// status already comes from a synchronous bundle-identifier lookup.
    private func confirmAndInstallDesktopAgent(_ agent: CodingAgent) {
        panel?.orderOut(nil)
        guard let brew = HomebrewInventory.executable else {
            let alert = NSAlert()
            alert.messageText = "Homebrew is required"
            alert.informativeText = "Install Homebrew from brew.sh, then try again."
            alert.runModal()
            panel?.makeKeyAndOrderFront(nil)
            panel?.makeFirstResponder(search)
            return
        }
        let package = HomebrewPackage(token: agent.brewToken, name: agent.title, description: agent.detail, kind: .cask)
        guard let command = package.actionCommand else { return }
        let alert = NSAlert()
        alert.messageText = "Install \(agent.title)?"
        alert.informativeText = "Ghostty will run:\n\n\(command)\n\nHomebrew may install dependencies or ask for your password. Reopen Agents and press Return again once it finishes."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Install")
        guard alert.runModal() == .alertSecondButtonReturn else {
            panel?.makeKeyAndOrderFront(nil)
            panel?.makeFirstResponder(search)
            return
        }
        guard let arguments = package.ghosttyArguments(brew: brew) else { return }
        launchPackageCommand(arguments: arguments)
    }

    private func confirmAndInstallTerminalAgent(_ agent: CodingAgent) {
        panel?.orderOut(nil)
        guard HomebrewInventory.executable != nil else {
            let alert = NSAlert()
            alert.messageText = "Homebrew is required"
            alert.informativeText = "Install Homebrew from brew.sh, then try again."
            alert.runModal()
            panel?.makeKeyAndOrderFront(nil)
            panel?.makeFirstResponder(search)
            return
        }
        var steps: [String] = []
        if !CodingAgent.herdrInstalled { steps.append("brew install herdr") }
        if !agent.isInstalled { steps.append("brew install \(agent.brewKind == .cask ? "--cask " : "")\(agent.brewToken)") }
        steps.append("start \(agent.title) in a herdr session")
        let alert = NSAlert()
        alert.messageText = "Launch \(agent.title)?"
        alert.informativeText = "A new Ghostty window in its own AeroSpace workspace will:\n\n\(steps.joined(separator: "\n"))\n\nHomebrew may install dependencies or ask for your password."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Install & Launch")
        guard alert.runModal() == .alertSecondButtonReturn else {
            panel?.makeKeyAndOrderFront(nil)
            panel?.makeFirstResponder(search)
            return
        }
        launchTerminalAgent(agent)
    }

    /// Only reached via `confirmAndInstallTerminalAgent`, after the user has
    /// confirmed something needs installing — so unlike the ordinary
    /// already-installed launch path (`activateAgent`, which provisions
    /// headlessly and reuses an existing Ghostty window when one already
    /// shows the agent workspace), this always opens a fresh Ghostty window:
    /// the user was told a new window would show install progress and any
    /// password prompt, so it should actually appear even if another agent's
    /// window is already open elsewhere in the AeroSpace workspace.
    ///
    /// Verified live against herdr 0.8.2: a per-launch `herdr server --session
    /// <name> &` backgrounded under Ghostty's own pty dies with the window
    /// (SIGHUP), which is why this targets herdr's shared *default* session —
    /// the one `brew services start herdr` (a real launchd daemon, exactly
    /// like this repo already runs SketchyBar as) keeps alive independently of
    /// any terminal window — with one labeled workspace per agent kind rather
    /// than a session per kind that would need its own service supervision.
    private func launchTerminalAgent(_ agent: CodingAgent) {
        guard let brew = HomebrewInventory.executable, let binary = agent.binaryName else {
            showPackageLaunchError("Homebrew is required. Install it from brew.sh, then try again.")
            return
        }
        let prefix = String(brew.dropLast("/bin/brew".count))
        let installFlag = agent.brewKind == .cask ? "--cask " : ""
        let script = """
        export PATH=\(prefix)/bin:\(prefix)/sbin:$PATH
        command -v herdr >/dev/null 2>&1 || brew install herdr
        command -v \(binary) >/dev/null 2>&1 || brew install \(installFlag)\(agent.brewToken)
        brew services start herdr >/dev/null 2>&1
        created=$(herdr workspace create --label \(binary) --cwd "$HOME" 2>/dev/null)
        ws=$(printf '%s' "$created" | grep -o '"workspace_id":"[^"]*"' | head -1 | cut -d'"' -f4)
        pane=$(printf '%s' "$created" | grep -o '"pane_id":"[^"]*"' | head -1 | cut -d'"' -f4)
        for _ in $(seq 1 12); do
          herdr agent start \(binary) --kind \(binary) --pane "$pane" >/dev/null 2>&1 && break
          sleep 0.2
        done
        herdr workspace focus "$ws" >/dev/null 2>&1
        exec herdr
        """
        let arguments = ["--wait-after-command=true", "--quit-after-last-window-closed=true",
                          "-e", "/bin/bash", "-c", script]
        // Switch workspace off the main thread, like HotkeyBindings.focusOrLaunch does for
        // its own AeroSpace calls, then hand off to the main actor via DispatchQueue (not
        // Task/MainActor.run) so this doesn't need to capture non-Sendable `self`.
        DispatchQueue.global(qos: .userInitiated).async {
            if let aerospace = HotkeyBindings.aeroSpaceExecutableURL() {
                _ = HotkeyBindings.run(aerospace, arguments: ["workspace", "agent"])
            }
            DispatchQueue.main.async {
                SuperMenuController.shared.launchPackageCommand(arguments: arguments)
            }
        }
    }

    /// Spells out the chord that opens the current picker collection, so the
    /// shortcut is visible from inside the collection it belongs to. Empty when
    /// a `[bindings]` entry has claimed that letter, since the chord no longer
    /// opens anything.
    private var pickerChordHint: String {
        let chord: String?
        if page == .agents {
            chord = MenuCatalog.chord("A", boundKeys)
        } else if let collection = AppCollection.allCases.first(where: { $0.page == page }) {
            chord = MenuCatalog.chord(collection.chord, boundKeys)
        } else {
            return ""
        }
        guard let chord else { return "" }
        return "  ·  " + MenuShortcut.symbolic("Hyper + Shift + \(chord)")
    }

    private var isPickerPage: Bool {
        page == .agents || AppCollection.allCases.contains { $0.page == page }
    }

    /// ⌘Return on any picker page records the selected entry as the app that
    /// collection's own Hyper chord launches directly.
    private func setDefaultChoice() {
        guard rows.indices.contains(table.selectedRow) else { return }
        let entry = rows[table.selectedRow]
        var config = Configuration.load()
        if let agent = entry.agent {
            config.defaultAgent = agent.rawValue
            defaultAgentToken = agent.rawValue
        } else if let collection = entry.collection, let choice = entry.choice {
            config[collection] = choice.id
            defaultAppTokens[collection] = choice.id
        } else {
            return
        }
        config.save()
        filter(preservingSelection: true)
    }

    private func launchPackageCommand(arguments: [String]) {
        guard let ghostty = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.mitchellh.ghostty") else {
            showPackageLaunchError("Ghostty could not be found. Install Ghostty, then try again.")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = arguments
        NSWorkspace.shared.openApplication(at: ghostty, configuration: configuration) { _, error in
            if let error {
                let message = error.localizedDescription
                Task { @MainActor [weak self] in self?.showPackageLaunchError(message) }
            }
        }
    }

    private func showPackageLaunchError(_ message: String) {
        let failure = NSAlert()
        failure.messageText = "Couldn’t open the installer in Ghostty"
        failure.informativeText = message
        failure.runModal()
        panel?.makeKeyAndOrderFront(nil)
        panel?.makeFirstResponder(search)
    }

    private func performSystemAction(_ action: SystemAction) {
        // Hide the palette so its Return/Escape monitor cannot intercept alerts.
        panel.orderOut(nil)
        if action.requiresConfirmation {
            let alert = NSAlert()
            alert.messageText = "\(action.title) your Mac?"
            alert.informativeText = "Your open applications will be asked to quit. Save your work before continuing."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: action.title)
            guard alert.runModal() == .alertSecondButtonReturn else {
                panel.makeKeyAndOrderFront(nil)
                panel.makeFirstResponder(search)
                return
            }
        }
        do {
            try action.perform()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn’t \(action.title.lowercased()) your Mac"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(search)
        }
    }

    private func filter(preservingSelection: Bool = false, restoring: MenuEntry? = nil) {
        let selected = restoring ?? (preservingSelection && rows.indices.contains(table.selectedRow) ? rows[table.selectedRow] : nil)
        rows = page == .install
            ? HomebrewCatalog.search(search.stringValue, packages: HomebrewInventory.merge(catalog: packages, installed: installedPackages)).map {
                MenuEntry(title: $0.name, detail: $0.detail, package: $0)
            }
            : MenuCatalog.results(query: search.stringValue, page: page, apps: apps, help: help,
                                  defaultAgent: defaultAgentToken, defaultApps: defaultAppTokens,
                                  boundKeys: boundKeys, clipboard: clipboardState,
                                  clipboardItems: ClipboardMonitor.shared.items)
        let upgradeQuery = search.stringValue.lowercased().split(whereSeparator: \.isWhitespace)
        if page == .install && inventoryReady && upgradeQuery.allSatisfy({ "upgrade all update packages".contains($0) }) {
            let available = HomebrewUpgrade.availableCount(installedPackages)
            rows.insert(MenuEntry(title: "Upgrade all", detail: available > 0
                ? "\(available) packages with updates · Opens Ghostty"
                : "No updates available · Pinned packages are excluded", upgradesAll: true), at: 0)
        }
        search.placeholderString = page == .install ? "Search Homebrew…" : "Search anything…"
        search.setAccessibilityLabel(page == .install ? "Search Homebrew packages" : "Search all apps, shortcuts, and system actions")
        emptyState.stringValue = page == .install
            ? (loadingInventory ? "Checking installed packages…" : inventoryError ? "Couldn’t read Homebrew. Reopen Install to retry." : loadingPackages ? "Loading Homebrew catalog…" : packageError ? "Couldn’t load Homebrew. Go back and reopen Install to retry."
                : search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No Homebrew packages installed. Search to install one." : "No Homebrew packages match your search.")
            : page == .clipboard
            ? (!clipboardState.enabled
                ? "Clipboard history is off. Turn it on in Settings → Clipboard."
                : search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Nothing copied yet." : "Nothing copied matches your search.")
            : page == .theme && OmaccyAppearance.availableThemes().isEmpty
            ? "No themes installed. Run scripts/update.sh to install them."
            : "No matches. Try an app, shortcut, or system action."
        table.reloadData()
        if !rows.isEmpty {
            let index = selected.flatMap { selected in rows.firstIndex { selected.package != nil ? $0.package?.id == selected.package?.id : $0.title == selected.title && $0.detail == selected.detail } } ?? 0
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            table.scrollRowToVisible(index)
        }
        let searching = !search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        location.stringValue = page == .install ? (inventoryError ? "HOMEBREW · INVENTORY UNAVAILABLE — REOPEN TO RETRY" : loadingInventory ? "HOMEBREW · CHECKING INSTALLED PACKAGES…" : packageError ? "HOMEBREW · CATALOG UNAVAILABLE — INSTALLED ONLY" : searching ? "OMACCY  /  INSTALL · HOMEBREW" : "HOMEBREW · INSTALLED PACKAGES") : searching ? "SEARCH RESULTS · ALL" : page == .home ? "BROWSE" : "OMACCY  /  \(page.rawValue.uppercased())" + pickerChordHint
        let noun = searching ? "result" : page == .home ? "collection" : "item"
        count.stringValue = "\(page == .install && searching && rows.count == 100 ? "100+" : String(rows.count)) \(noun)\(rows.count == 1 ? "" : "s")"
        emptyState.isHidden = !rows.isEmpty
        tableViewSelectionDidChange(Notification(name: NSTableView.selectionDidChangeNotification))
        // Home stays compact; long collections and results get room to breathe.
        // A row is 62pt plus 2pt of intercell spacing and the chrome around the
        // table measures 220pt, so a short page still fits its rows exactly.
        // Beyond `maxHeight` -- or beyond what fits clear of SketchyBar on this
        // display -- the list scrolls instead of growing.
        let allowed = allowedFrame(on: panel.screen ?? NSScreen.main)
        let wanted: CGFloat = rows.count <= 3
            ? 250 + CGFloat(max(rows.count, 2)) * 64
            : 220 + CGFloat(rows.count) * 64
        let ceiling = allowed.isEmpty ? Self.maxHeight : min(Self.maxHeight, allowed.height)
        let height = min(wanted, ceiling)
        var frame = panel.frame
        // Grow downward from a fixed top edge, then pull the whole panel back
        // inside the allowed region if that pushed it past an edge.
        frame.origin.y += frame.height - height
        frame.size.height = height
        panel.setFrame(clamped(frame, within: allowed), display: true)
    }
    private func reloadCatalog(refreshApps: Bool = true) {
        let config = Configuration.load()
        defaultAgentToken = config.defaultAgent
        defaultAppTokens = AppCollection.allCases.reduce(into: [:]) { tokens, collection in
            tokens[collection] = config[collection]
        }
        boundKeys = Set(config.bindings.keys.map { $0.lowercased() })
        clipboardState = ClipboardSettingsState(enabled: config.clipboardHistory,
                                                persist: config.clipboardPersist,
                                                count: ClipboardMonitor.shared.count)
        var byID: [String: MenuEntry] = [:]
        if refreshApps && !indexing {
            indexing = true
            Task { @MainActor in
                installedApps = await Task.detached { Self.discoverApps() }.value
                indexing = false
                reloadCatalog(refreshApps: false)
                filter(preservingSelection: true)
            }
        }
        byID = installedApps
        help = [MenuEntry(title: "Open shortcut help", detail: "Hyper + ?", destination: .help),
                MenuEntry(title: "Open app launcher", detail: "Hyper + Space", destination: .home)]
        if !boundKeys.contains("a") {
            help.append(MenuEntry(title: "Launch default agent", detail: "Hyper + A", destination: .agents))
            help.append(MenuEntry(title: "Open Agents", detail: "Hyper + Shift + A", destination: .agents))
        }
        for collection in AppCollection.allCases where !boundKeys.contains(collection.chord.lowercased()) {
            help.append(MenuEntry(title: "Launch default \(collection.itemLabel.lowercased())",
                                  detail: "Hyper + \(collection.chord)", destination: collection.page))
            help.append(MenuEntry(title: "Open \(collection.title)",
                                  detail: "Hyper + Shift + \(collection.chord)", destination: collection.page))
        }
        if !boundKeys.contains("v") {
            help.append(MenuEntry(title: "Open clipboard history", detail: "Hyper + V", destination: .clipboard))
        }
        for (key, id) in config.bindings.sorted(by: { $0.key < $1.key }) {
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
            let name = url.map { FileManager.default.displayName(atPath: $0.path)
                .replacingOccurrences(of: ".app", with: "") } ?? id
            byID[id] = MenuEntry(title: name, detail: "Hyper + \(key.uppercased())", bundleID: id)
            help.append(MenuEntry(title: "Open \(name)", detail: "Hyper + \(key.uppercased())", bundleID: id))
        }
        apps = byID.values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        if config.escapeOnTap { help.append(MenuEntry(title: "Send Escape", detail: "Tap Caps Lock")) }
        help.append(contentsOf: windowShortcuts())
    }

    nonisolated private static func discoverApps() -> [String: MenuEntry] {
        var byID: [String: MenuEntry] = [:]
        let roots = ["/Applications", "/System/Applications", "/System/Library/CoreServices/Applications",
                     NSHomeDirectory() + "/Applications"]
        for root in roots {
            guard let files = FileManager.default.enumerator(at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in files where url.pathExtension == "app" {
                guard let id = Bundle(url: url)?.bundleIdentifier else { continue }
                byID[id] = MenuEntry(title: FileManager.default.displayName(atPath: url.path)
                    .replacingOccurrences(of: ".app", with: ""), detail: id, bundleID: id)
            }
        }
        return byID
    }

    private func windowShortcuts() -> [MenuEntry] {
        let paths = [NSHomeDirectory() + "/.aerospace.toml",
                     NSHomeDirectory() + "/.config/aerospace/aerospace.toml"]
        guard let contents = paths.compactMap({ try? String(contentsOfFile: $0, encoding: .utf8) }).first else {
            return [MenuEntry(title: "Window shortcuts unavailable", detail: "No AeroSpace configuration found")]
        }
        return Self.parseWindowShortcuts(contents)
    }

    nonisolated static func parseWindowShortcuts(_ contents: String) -> [MenuEntry] {
        var mode: String?
        var entries: [MenuEntry] = []
        for raw in contents.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                mode = line.hasPrefix("[mode.") && line.hasSuffix(".binding]")
                    ? String(line.dropFirst(6).dropLast(9)) : nil
                continue
            }
            guard let mode, !line.hasPrefix("#") else { continue }
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            let command = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            var chord = key.replacingOccurrences(of: "cmd-ctrl-alt-", with: "Hyper + ")
                .replacingOccurrences(of: "shift-", with: "Shift + ")
            for (name, symbol) in [("left", "←"), ("down", "↓"), ("up", "↑"), ("right", "→")] {
                if chord.hasSuffix("+ " + name) { chord = String(chord.dropLast(name.count)) + symbol }
            }
            if mode != "main" { chord += " (\(mode) mode)" }
            let title: String
            if command.contains("menu-toggle.sh") { title = "Toggle native menu bar" }
            else if command.contains("dock-toggle.sh") { title = "Toggle Dock auto-hide" }
            else if command.contains("--stdin next") { title = "Next occupied workspace" }
            else if command.contains("--stdin prev") { title = "Previous occupied workspace" }
            else if command.hasPrefix("move-node-to-workspace ") {
                title = "Move window to workspace " + command.dropFirst(23)
            } else if command.hasPrefix("workspace ") { title = "Switch to " + command }
            else if command.hasPrefix("focus ") { title = "Focus window " + command.dropFirst(6) }
            else if command.hasPrefix("move ") { title = "Move window " + command.dropFirst(5) }
            else if command == "resize smart -50" { title = "Shrink window" }
            else if command == "resize smart +50" { title = "Grow window" }
            else if command == "layout tiles horizontal vertical" { title = "Cycle tiled layout" }
            else if command == "layout accordion horizontal vertical" { title = "Cycle accordion layout" }
            else if command == "layout floating tiling" { title = "Toggle floating window" }
            else { title = command }
            entries.append(MenuEntry(title: title, detail: chord))
        }
        // The engine also maps arrow keys to H/J/K/L before AeroSpace sees them.
        for (key, arrow) in [("h", "←"), ("j", "↓"), ("k", "↑"), ("l", "→")] {
            for entry in entries where entry.detail == "Hyper + \(key)" || entry.detail == "Hyper + Shift + \(key)" {
                let chord = String(entry.detail.dropLast()) + arrow
                entries.append(MenuEntry(title: entry.title, detail: chord))
            }
        }
        var seen = Set<String>()
        return entries.filter { seen.insert($0.title + $0.detail).inserted }
    }
}

extension NSTableView {
    /// `reloadData` clears `selectedRowIndexes`, so a repaint that is only
    /// meant to redraw cells silently drops the row the user is acting on.
    /// Row identity here is the index -- callers use this when the row set is
    /// unchanged and only the cell contents differ.
    func reloadPreservingSelection() {
        let selection = selectedRowIndexes
        reloadData()
        guard !selection.isEmpty, let last = selection.last, last < numberOfRows else { return }
        selectRowIndexes(selection, byExtendingSelection: false)
    }
}
