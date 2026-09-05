import AppKit

struct MenuEntry: Sendable {
    let title: String
    let detail: String
    var bundleID: String? = nil
    var destination: MenuPage? = nil
    var systemAction: SystemAction? = nil
    var package: HomebrewPackage? = nil
    var upgradesAll = false
}

enum MenuPage: String, Sendable { case home = "Home", apps = "Apps", help = "Help", install = "Install", system = "System" }

enum MenuCatalog {
    static let categories = [
        MenuEntry(title: "Apps", detail: "Find and open an application", destination: .apps),
        MenuEntry(title: "Install", detail: "Search Homebrew apps and command-line tools", destination: .install),
        MenuEntry(title: "Help", detail: "Explore your keyboard shortcuts", destination: .help),
        MenuEntry(title: "System", detail: "Sleep, restart, or shut down your Mac", destination: .system),
    ]

    static let system = SystemAction.allCases.map {
        MenuEntry(title: $0.title, detail: $0.detail, systemAction: $0)
    }

    static func results(query: String, page: MenuPage, apps: [MenuEntry], help: [MenuEntry]) -> [MenuEntry] {
        if page == .install { return [] }
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        if words.isEmpty {
            switch page {
            case .home: return categories
            case .apps: return apps
            case .help: return help
            case .system: return system
            case .install: return []
            }
        }
        // Search always spans the whole menu, even while browsing a category.
        var seenApps = Set<String>()
        return (categories + apps + help + system).filter { entry in
            words.allSatisfy { (entry.title + " " + entry.detail).localizedCaseInsensitiveContains($0) }
        }.filter { entry in
            guard let id = entry.bundleID else { return true }
            return seenApps.insert(id).inserted
        }
    }
}

private enum PaletteStyle {
    static let accent = NSColor(calibratedRed: 0.65, green: 0.88, blue: 0.76, alpha: 1)
    static let muted = NSColor(calibratedWhite: 0.57, alpha: 1)
    @MainActor static func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = .white
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
    enum Section: Int { case apps, help }
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
    private var apps: [MenuEntry] = []
    private var help: [MenuEntry] = []
    private var rows: [MenuEntry] = []
    private var installedApps: [String: MenuEntry] = [:]
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
        if panel == nil { build() }
        if panel.isVisible && openingSection == section { dismiss(); return }
        if !panel.isVisible { previousApp = NSWorkspace.shared.frontmostApplication }
        openingSection = section
        page = section == .help ? .help : .home
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
        panel = PalettePanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
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
        background.layer?.backgroundColor = NSColor(calibratedRed: 0.095, green: 0.105, blue: 0.115, alpha: 0.98).cgColor
        background.layer?.cornerRadius = 18
        background.layer?.borderWidth = 1
        background.layer?.borderColor = NSColor.white.withAlphaComponent(0.13).cgColor
        panel.contentView = background

        let brand = PaletteStyle.label("O M A C C Y", size: 10, weight: .bold)
        brand.textColor = PaletteStyle.accent
        let subtitle = PaletteStyle.label("Your keyboard. Your workspace.", size: 11)
        subtitle.textColor = PaletteStyle.muted
        search.placeholderAttributedString = NSAttributedString(string: "Search anything…", attributes: [
            .foregroundColor: PaletteStyle.muted,
            .font: NSFont.systemFont(ofSize: 23, weight: .regular)
        ])
        search.font = .systemFont(ofSize: 23)
        search.textColor = .white
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
            case 36, 76: self.activateSelection()
            case 53: self.back()
            case 51 where self.search.stringValue.isEmpty && self.page != .home: self.back()
            default:
                if self.panel.firstResponder === self.table { self.panel.makeFirstResponder(self.search) }
                return event
            }
            return nil
        }
    }

    private func dismiss() {
        panel.orderOut(nil)
        if let previousApp, previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp.activate(options: [])
        }
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
        if entry.upgradesAll {
            actionHint.stringValue = HomebrewUpgrade.availableCount(installedPackages) > 0 ? "↵  Confirm upgrade all…" : "No updates available"
        } else if let package = entry.package {
            actionHint.stringValue = !inventoryReady
                ? (inventoryError ? "Reopen Install to retry" : "Checking installed packages…")
                : package.actionTitle.map { "↵  " + $0 + "…" } ?? (package.pinned ? "Pinned in Homebrew" : "Installed")
        } else {
            actionHint.stringValue = entry.destination != nil ? "↵  Browse" : entry.bundleID != nil ? "↵  Open app" : entry.systemAction != nil ? "↵  " + (entry.systemAction == .sleep ? "Sleep" : "Confirm…") : "Shortcut reference"
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = rows[row]
        let cell = NSView()
        let title = PaletteStyle.label(entry.title, size: 14, weight: .medium)
        let isApp = entry.bundleID != nil
        let detail = PaletteStyle.label((entry.upgradesAll || entry.package != nil || entry.destination != nil || entry.systemAction != nil) && !entry.detail.hasPrefix("Hyper") ? entry.detail : isApp ? "Application" : "Keyboard shortcut", size: 11)
        detail.textColor = PaletteStyle.muted
        let image: NSImage
        if let id = entry.bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            image = NSImage(systemSymbolName: entry.systemAction?.symbol ?? (entry.upgradesAll || entry.package != nil || entry.destination == .install ? "arrow.down.circle" : entry.destination == .system ? "power" : entry.destination == .apps ? "square.grid.2x2" : entry.destination == .help ? "keyboard" : "command"), accessibilityDescription: nil)!
        }
        let icon = NSImageView(image: image)
        icon.contentTintColor = PaletteStyle.accent
        icon.imageScaling = .scaleProportionallyUpOrDown
        let keys = PaletteStyle.label(entry.package?.status ?? (entry.detail.hasPrefix("Hyper") ? entry.detail : entry.destination != nil ? "›" : !isApp && entry.systemAction == nil && entry.package == nil && !entry.upgradesAll ? entry.detail : ""), size: 11, weight: .medium)
        keys.textColor = entry.destination != nil || entry.package?.outdated == true ? PaletteStyle.accent : NSColor(calibratedWhite: 0.72, alpha: 1)
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

    private func select(delta: Int) {
        guard !rows.isEmpty else { return }
        let row = (max(table.selectedRow, 0) + delta + rows.count) % rows.count
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    @objc private func activateClickedRow() {
        activate(row: table.clickedRow)
    }

    private func activateSelection() {
        activate(row: table.selectedRow)
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
        } else if entry.upgradesAll {
            upgradeAll()
        } else if let package = entry.package {
            install(package)
        } else if let action = entry.systemAction {
            performSystemAction(action)
        }
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
        guard !loadingPackages, catalogLoadedAt.map({ Date().timeIntervalSince($0) > 3600 }) ?? true else { return }
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
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(search)
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
            : MenuCatalog.results(query: search.stringValue, page: page, apps: apps, help: help)
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
        let height: CGFloat = rows.count <= 3 ? 230 + CGFloat(max(rows.count, 2)) * 64 : 530
        var frame = panel.frame
        frame.origin.y += frame.height - height
        frame.size.height = height
        panel.setFrame(frame, display: true)
    }
    private func reloadCatalog(refreshApps: Bool = true) {
        let config = Configuration.load()
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
