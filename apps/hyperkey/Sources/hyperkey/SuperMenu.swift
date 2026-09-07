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
}

enum MenuPage: String, Sendable {
    case home = "Home", apps = "Apps", help = "Help", install = "Install"
    case omaccy = "Omaccy", system = "System", agents = "Agents"
    case mail = "Mail", editors = "Editors"
    case settings = "Settings", theme = "Theme", font = "Font"
}

enum MenuCatalog {
    static let categories = [
        MenuEntry(title: "Apps", detail: "Find and open an application", destination: .apps),
        MenuEntry(title: "Agents", detail: "Launch a coding agent in a terminal or its own app", destination: .agents),
        MenuEntry(title: "Mail", detail: AppCollection.mail.summary, destination: .mail, collection: .mail),
        MenuEntry(title: "Editors", detail: AppCollection.editors.summary, destination: .editors, collection: .editors),
        MenuEntry(title: "Install", detail: "Search Homebrew apps and command-line tools", destination: .install),
        MenuEntry(title: "Omaccy", detail: "Update Omaccy from your local checkout", destination: .omaccy),
        MenuEntry(title: "Help", detail: "Explore your keyboard shortcuts", destination: .help),
        MenuEntry(title: "System", detail: "Sleep, restart, or shut down your Mac", destination: .system),
        MenuEntry(title: "Settings", detail: "Pick the theme and font for the bar and launcher", destination: .settings),
    ]

    static let settings = [
        MenuEntry(title: "Theme", detail: "Color palettes for SketchyBar and this launcher", destination: .theme),
        MenuEntry(title: "Font", detail: "UI font for SketchyBar and this launcher", destination: .font),
    ]

    static let system = SystemAction.allCases.map {
        MenuEntry(title: $0.title, detail: $0.detail, systemAction: $0)
    }

    static func results(query: String, page: MenuPage, apps: [MenuEntry], help: [MenuEntry],
                        defaultAgent: String? = nil,
                        defaultApps: [AppCollection: String] = [:]) -> [MenuEntry] {
        if page == .install { return [] }
        if page == .omaccy {
            let entry = MenuEntry(title: "Update Omaccy", detail: "Run update.sh from your local checkout · Opens Ghostty", updatesOmaccy: true)
            let words = query.split(whereSeparator: \.isWhitespace)
            return words.allSatisfy { (entry.title + " " + entry.detail).localizedCaseInsensitiveContains(String($0)) } ? [entry] : []
        }
        if page == .settings {
            return matching(query, in: settings) { "\($0.title) \($0.detail)" }
        }
        if page == .theme { return themeEntries(matching: query) }
        if page == .font { return fontEntries(matching: query) }
        if page == .agents { return agentEntries(matching: query, defaultToken: defaultAgent) }
        if let collection = AppCollection.allCases.first(where: { $0.page == page }) {
            return choiceEntries(matching: query, in: collection, defaultToken: defaultApps[collection])
        }
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        if words.isEmpty {
            switch page {
            case .home: return categories
            case .apps: return apps
            case .help: return help
            case .system: return system
            case .install, .omaccy, .settings, .theme, .font, .agents, .mail, .editors: return []
            }
        }
        // Search always spans the whole menu, even while browsing a category.
        var seenApps = Set<String>()
        return (categories + settings + apps + help + system).filter { entry in
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

    static func agentEntries(matching query: String, defaultToken: String?) -> [MenuEntry] {
        matching(query, in: CodingAgent.allCases.map { agent in
            MenuEntry(title: agent.title,
                      detail: "\(agent.detail) · \(agent.isInstalled ? "Installed" : "Installs via Homebrew")",
                      bundleID: agent.bundleID,
                      agent: agent,
                      isDefaultChoice: agent.rawValue == defaultToken)
        }, searchText: { "\($0.title) \($0.detail)" })
    }

    /// Rows for a picker collection: every choice, installed or not, so an app
    /// can be set as the default and installed from the same place.
    static func choiceEntries(matching query: String, in collection: AppCollection,
                              defaultToken: String?) -> [MenuEntry] {
        matching(query, in: collection.choices.map { choice in
            let status = choice.isInstalled ? "Installed" : (choice.installLabel ?? "Included with macOS")
            return MenuEntry(title: choice.title,
                             detail: "\(collection.itemLabel) · \(choice.summary) · \(status)",
                             collection: collection,
                             choice: choice,
                             isDefaultChoice: choice.id == defaultToken)
        }, searchText: { "\($0.title) \($0.detail)" })
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
    enum Section { case apps, help, agents, collection(AppCollection)

        var page: MenuPage {
            switch self {
            case .apps: return .home
            case .help: return .help
            case .agents: return .agents
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
        search.stringValue = ""
        reloadCatalog()
        filter()
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2,
                                         y: frame.midY - panel.frame.height / 2 + frame.height * 0.12))
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
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            switch event.keyCode {
            case 125: self.select(delta: 1)
            case 126: self.select(delta: -1)
            case 48: self.select(delta: event.modifierFlags.contains(.shift) ? -1 : 1)
            case 36, 76:
                if self.isPickerPage, event.modifierFlags.contains(.command) {
                    self.setDefaultChoice()
                } else if self.page == .install, event.modifierFlags.contains(.command) {
                    self.openSelectedPackageOnHomebrew()
                } else {
                    self.activateSelection()
                }
            case 53: self.back()
            case 51 where self.search.stringValue.isEmpty && self.page != .home: self.back()
            default:
                if self.panel.firstResponder === self.table { self.panel.makeFirstResponder(self.search) }
                return event
            }
            return nil
        }
        builtFor = PaletteStyle.theme.identity
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
        else if page != .home { page = .home; filter() }
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
            actionHint.stringValue = "↵  Open updater…"
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
            || entry.agent != nil || entry.choice != nil
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
        let keys = PaletteStyle.label(Self.keyHint(for: entry, isApp: isApp), size: 11, weight: .medium)
        keys.textColor = entry.destination != nil || entry.package?.outdated == true
            || entry.theme != nil || entry.font != nil ? PaletteStyle.accent : PaletteStyle.muted
        keys.alignment = .right
        keys.setContentCompressionResistancePriority(.required, for: .horizontal)
        for view in [icon, title, detail, keys] { view.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(view) }
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
            title.trailingAnchor.constraint(lessThanOrEqualTo: keys.leadingAnchor, constant: -16),
            detail.trailingAnchor.constraint(lessThanOrEqualTo: keys.leadingAnchor, constant: -16),
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
        if let agent = entry.agent { return agent.symbol }
        if let collection = entry.collection { return collection.symbol }
        if let action = entry.systemAction { return action.symbol }
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
        if entry.agent != nil || entry.choice != nil { return entry.isDefaultChoice ? "✓" : "" }
        if entry.detail.hasPrefix("Hyper") { return entry.detail }
        if entry.destination != nil { return "›" }
        let isShortcut = !isApp && entry.systemAction == nil && entry.package == nil
            && !entry.upgradesAll && !entry.updatesOmaccy
        return isShortcut ? entry.detail : ""
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
        } else if let action = entry.systemAction {
            performSystemAction(action)
        }
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

    private func filter(preservingSelection: Bool = false) {
        let selected = preservingSelection && rows.indices.contains(table.selectedRow) ? rows[table.selectedRow] : nil
        rows = page == .install
            ? HomebrewCatalog.search(search.stringValue, packages: HomebrewInventory.merge(catalog: packages, installed: installedPackages)).map {
                MenuEntry(title: $0.name, detail: $0.detail, package: $0)
            }
            : MenuCatalog.results(query: search.stringValue, page: page, apps: apps, help: help,
                                  defaultAgent: defaultAgentToken, defaultApps: defaultAppTokens)
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
        location.stringValue = page == .install ? (inventoryError ? "HOMEBREW · INVENTORY UNAVAILABLE — REOPEN TO RETRY" : loadingInventory ? "HOMEBREW · CHECKING INSTALLED PACKAGES…" : packageError ? "HOMEBREW · CATALOG UNAVAILABLE — INSTALLED ONLY" : searching ? "OMACCY  /  INSTALL · HOMEBREW" : "HOMEBREW · INSTALLED PACKAGES") : searching ? "SEARCH RESULTS · ALL" : page == .home ? "BROWSE" : "OMACCY  /  \(page.rawValue.uppercased())"
        let noun = searching ? "result" : page == .home ? "collection" : "item"
        count.stringValue = "\(page == .install && searching && rows.count == 100 ? "100+" : String(rows.count)) \(noun)\(rows.count == 1 ? "" : "s")"
        emptyState.isHidden = !rows.isEmpty
        tableViewSelectionDidChange(Notification(name: NSTableView.selectionDidChangeNotification))
        // Home stays compact; long collections and results get room to breathe.
        // Home lists 9 collections: 211pt of chrome + 9 * 62pt rows ≈ 769pt,
        // measured directly against the table, so it needs no scrollbar on a
        // display with room for it and is clamped to the screen otherwise.
        let available = ((panel.screen ?? NSScreen.main)?.visibleFrame.height ?? 900) - 80
        let height: CGFloat = rows.count <= 3
            ? 250 + CGFloat(max(rows.count, 2)) * 64
            : min(769, available)
        var frame = panel.frame
        frame.origin.y += frame.height - height
        frame.size.height = height
        panel.setFrame(frame, display: true)
    }
    private func reloadCatalog(refreshApps: Bool = true) {
        let config = Configuration.load()
        defaultAgentToken = config.defaultAgent
        defaultAppTokens = AppCollection.allCases.reduce(into: [:]) { tokens, collection in
            tokens[collection] = config[collection]
        }
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
                MenuEntry(title: "Open app launcher", detail: "Hyper + Space", destination: .home),
                MenuEntry(title: "Launch default agent", detail: "Hyper + A", destination: .agents),
                MenuEntry(title: "Open Agents", detail: "Hyper + Shift + A", destination: .agents)]
        for collection in AppCollection.allCases where config.bindings[collection.chord.lowercased()] == nil {
            help.append(MenuEntry(title: "Launch default \(collection.itemLabel.lowercased())",
                                  detail: "Hyper + \(collection.chord)", destination: collection.page))
            help.append(MenuEntry(title: "Open \(collection.title)",
                                  detail: "Hyper + Shift + \(collection.chord)", destination: collection.page))
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
