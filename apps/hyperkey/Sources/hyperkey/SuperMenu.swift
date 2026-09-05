import AppKit

struct MenuEntry: Sendable {
    let title: String
    let detail: String
    var bundleID: String? = nil
}

private final class PaletteTable: NSTableView {
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 {
            if let doubleAction { NSApp.sendAction(doubleAction, to: target, from: self) }
        } else if event.keyCode == 53 {
            window?.cancelOperation(self)
        } else {
            super.keyDown(with: event)
        }
    }
}

private final class PalettePanel: NSPanel {
    var onDismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onDismiss?() }
}

@MainActor
final class SuperMenuController: NSObject, NSWindowDelegate, NSSearchFieldDelegate,
                                 NSTableViewDataSource, NSTableViewDelegate {
    enum Section: Int { case apps, help }
    static let shared = SuperMenuController()
    private var panel: PalettePanel!
    private let search = NSSearchField()
    private let tabs = NSSegmentedControl(labels: ["Apps", "Help"], trackingMode: .selectOne,
                                          target: nil, action: nil)
    private let table = PaletteTable()
    private let footer = NSTextField(labelWithString: "")
    private var apps: [MenuEntry] = []
    private var help: [MenuEntry] = []
    private var rows: [MenuEntry] = []
    private var installedApps: [String: MenuEntry] = [:]
    private var indexing = false
    private var previousApp: NSRunningApplication?

    func toggle(section: Section) {
        if panel == nil { build() }
        if panel.isVisible && tabs.selectedSegment == section.rawValue {
            dismiss()
            return
        }
        if !panel.isVisible { previousApp = NSWorkspace.shared.frontmostApplication }
        tabs.selectedSegment = section.rawValue
        search.stringValue = ""
        reloadCatalog()
        filter()
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2,
                                         y: frame.midY - panel.frame.height / 2 + frame.height * 0.12))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(search)
    }

    private func build() {
        // Accessory apps still need an Edit menu for standard text shortcuts.
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
            ] {
                submenu.addItem(NSMenuItem(title: title, action: action, keyEquivalent: key))
            }
            edit.submenu = submenu
            menu.addItem(edit)
            NSApp.mainMenu = menu
        }
        panel = PalettePanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
                             styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        panel.onDismiss = { [weak self] in self?.dismiss() }
        panel.title = "Omaccy"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        panel.contentView = background

        let title = NSTextField(labelWithString: "Omaccy")
        title.font = .systemFont(ofSize: 19, weight: .semibold)
        tabs.target = self
        tabs.action = #selector(changeSection)
        search.placeholderString = "Search apps or shortcuts"
        search.delegate = self
        search.sendsSearchStringImmediately = true
        search.sendsWholeSearchString = false
        table.headerView = nil
        table.rowHeight = 44
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .regular
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("entry")))
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.doubleAction = #selector(activateSelection)
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        footer.font = .systemFont(ofSize: 11)
        footer.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [title, tabs, search, scroll, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: background.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -16),
            search.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 260),
        ])
    }

    private func dismiss() {
        panel.orderOut(nil)
        if let previousApp, previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp.activate(options: [])
        }
    }

    func windowDidResignKey(_ notification: Notification) { panel.orderOut(nil) }
    @objc private func changeSection() { filter(); panel.makeFirstResponder(search) }
    func controlTextDidChange(_ notification: Notification) { filter() }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = rows[row]
        let title = NSTextField(labelWithString: entry.title)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.lineBreakMode = .byTruncatingTail
        let detail = NSTextField(labelWithString: entry.detail)
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        let stack = NSStackView(views: [title, detail])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        return stack
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
        switch command {
        case #selector(NSResponder.moveDown(_:)):
            select(delta: 1)
        case #selector(NSResponder.moveUp(_:)):
            select(delta: -1)
        case #selector(NSResponder.insertNewline(_:)):
            activateSelection()
        case #selector(NSResponder.cancelOperation(_:)):
            dismiss()
        default: return false
        }
        return true
    }

    private func select(delta: Int) {
        guard !rows.isEmpty else { return }
        let row = min(max(table.selectedRow + delta, 0), rows.count - 1)
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    @objc private func activateSelection() {
        guard rows.indices.contains(table.selectedRow),
              let bundleID = rows[table.selectedRow].bundleID else { return }
        panel.orderOut(nil)
        HotkeyBindings.focusOrLaunch(bundleIdentifier: bundleID)
    }

    private func filter() {
        let catalog = tabs.selectedSegment == Section.apps.rawValue ? apps : help
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        rows = catalog.filter { query.isEmpty || ($0.title + " " + $0.detail).localizedCaseInsensitiveContains(query) }
        table.reloadData()
        if !rows.isEmpty { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        footer.stringValue = rows.isEmpty ? "No results — try another search" :
            "Caps Lock = Hyper (⌘⌃⌥)    ·    ↑↓ Select    ·    ↵ Open app    ·    Esc Close"
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
                filter()
            }
        }
        byID = installedApps
        help = [MenuEntry(title: "Open shortcut help", detail: "Hyper + ?"),
                MenuEntry(title: "Open app launcher", detail: "Hyper + Space")]
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
