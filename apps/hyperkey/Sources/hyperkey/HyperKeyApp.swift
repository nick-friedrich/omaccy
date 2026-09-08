import AppKit
import ApplicationServices
import Foundation

@main
struct HyperKeyApp {
    static func main() {
        // Handle --uninstall flag
        if CommandLine.arguments.contains("--uninstall") {
            HIDMapping.clearMapping()
            fputs("hyperkey: CapsLock mapping cleared.\n", stderr)
            return
        }

        // Handle --version flag
        if CommandLine.arguments.contains("--version") {
            print("omaccy-hyperkey \(Constants.version)")
            return
        }

        // UI preview without installing mappings or starting keyboard capture.
        // An optional page name (home, help, agents, mail, editors) opens that
        // collection directly, since a preview cannot be navigated by chord.
        if let flag = CommandLine.arguments.firstIndex(of: "--preview-menu") {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            let name = CommandLine.arguments.indices.contains(flag + 1) ? CommandLine.arguments[flag + 1] : nil
            SuperMenuController.shared.toggle(section: .named(name))
            app.run()
            return
        }

        // 1. Check for already-running instance
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: Constants.bundleID)
        if runningApps.count > 1 {
            fputs("hyperkey: already running.\n", stderr)
            return
        }
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let others = NSWorkspace.shared.runningApplications.filter {
            $0.localizedName == "Omaccy Hyperkey" && $0.processIdentifier != selfPID
        }
        if !others.isEmpty {
            fputs("hyperkey: already running.\n", stderr)
            return
        }

        let configuration = Configuration.load()
        HotkeyBindings.configure(configuration.bindings)

        // 2. Check accessibility permissions (waits until granted)
        Accessibility.ensureAccessibility()

        // 3. Apply CapsLock -> F18 mapping via hidutil
        let hidMappingOK = HIDMapping.applyCapsLockToF18()

        // 4. Monitor for keyboard connect/disconnect and seize external keyboards
        KeyboardMonitor.start()

        // 5. Set up signal handlers for clean shutdown
        signal(SIGINT) { _ in
            HIDMapping.clearMapping()
            fputs("\nhyperkey: stopped, CapsLock mapping cleared.\n", stderr)
            exit(0)
        }
        signal(SIGTERM) { _ in
            HIDMapping.clearMapping()
            fputs("hyperkey: stopped, CapsLock mapping cleared.\n", stderr)
            exit(0)
        }

        // 6. Start the event tap (runs on the main run loop)
        EventTap.start()

        // 7. Set up NSApplication with menu bar item
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let delegate = AppDelegate(hidMappingOK: hidMappingOK, configuration: configuration)
        app.delegate = delegate

        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var warningMenuItem: NSMenuItem!
    private var keyboardsMenuItem: NSMenuItem!
    private let hidMappingOK: Bool
    private var configuration: Configuration

    init(hidMappingOK: Bool, configuration: Configuration) {
        self.hidMappingOK = hidMappingOK
        self.configuration = configuration
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let savedEscape = configuration.escapeOnTap
        escapeOnTap = savedEscape

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "capslock.fill",
                accessibilityDescription: "Omaccy Hyperkey"
            )
        }

        let menu = NSMenu()
        menu.delegate = self

        // Version
        let statusMenuItem = NSMenuItem(title: "Omaccy Hyperkey v\(Constants.version)", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        // Warning (hidden unless something is wrong)
        warningMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        warningMenuItem.isHidden = true
        menu.addItem(warningMenuItem)

        if !hidMappingOK {
            warningMenuItem.title = "Warning: HID mapping failed"
            warningMenuItem.isHidden = false
        }

        menu.addItem(NSMenuItem.separator())

        let helpItem = NSMenuItem(title: "Omaccy Launcher", action: #selector(showHelp), keyEquivalent: "")
        helpItem.target = self
        menu.addItem(helpItem)
        menu.addItem(NSMenuItem.separator())

        // Keyboards submenu
        keyboardsMenuItem = NSMenuItem(title: "Keyboards", action: nil, keyEquivalent: "")
        let keyboardsSubmenu = NSMenu()
        keyboardsMenuItem.submenu = keyboardsSubmenu
        menu.addItem(keyboardsMenuItem)

        menu.addItem(NSMenuItem.separator())

        // CapsLock -> Escape toggle
        let escapeItem = NSMenuItem(
            title: "CapsLock alone \u{2192} Escape",
            action: #selector(toggleEscape(_:)),
            keyEquivalent: ""
        )
        escapeItem.target = self
        escapeItem.state = savedEscape ? .on : .off
        menu.addItem(escapeItem)

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit Omaccy Hyperkey",
            action: #selector(quitApp(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        // Check accessibility on every menu open
        if !AXIsProcessTrusted() {
            warningMenuItem.title = "Warning: Accessibility permission revoked"
            warningMenuItem.isHidden = false
        } else if hidMappingOK {
            warningMenuItem.isHidden = true
        }

        // Refresh keyboards submenu
        if let submenu = keyboardsMenuItem.submenu {
            submenu.removeAllItems()
            let devices = KeyboardMonitor.connectedDevices
            if devices.isEmpty {
                let item = NSMenuItem(title: "No keyboards detected", action: nil, keyEquivalent: "")
                item.isEnabled = false
                submenu.addItem(item)
            } else {
                for device in devices {
                    let item = NSMenuItem(title: "\(device.name) (\(device.status))", action: nil, keyEquivalent: "")
                    item.isEnabled = false
                    submenu.addItem(item)
                }
            }
        }
    }

    // MARK: - Actions

    @objc private func showHelp() {
        SuperMenuController.shared.toggle(section: .help)
    }

    @objc private func toggleEscape(_ sender: NSMenuItem) {
        let newValue = sender.state != .on
        escapeOnTap = newValue
        sender.state = newValue ? .on : .off
        configuration.escapeOnTap = newValue
        configuration.save()
    }

    @objc private func quitApp(_ sender: NSMenuItem) {
        HIDMapping.clearMapping()
        NSApplication.shared.terminate(nil)
    }
}
