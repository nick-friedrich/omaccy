import AppKit
import Foundation

@_silgen_name("CGSSetSymbolicHotKeyEnabled")
private func CGSSetSymbolicHotKeyEnabled(_ hotKey: UInt32, _ isEnabled: Bool) -> Int32

@_silgen_name("CGSIsSymbolicHotKeyEnabled")
private func CGSIsSymbolicHotKeyEnabled(_ hotKey: UInt32) -> Bool

/// Launchie's global hotkey, in the three preferences its Settings recorder
/// writes. A key Launchie never wrote is nil: Launchie then uses its default,
/// ⌘K, switched on.
struct LaunchieHotkey: Equatable, Sendable {
    static let keyCodeKey = "hotkeyKeyCode"
    static let modifiersKey = "hotkeyModifiers"
    static let enabledKey = "hotkeyEnabled"

    /// kVK_Space with `NSEvent.ModifierFlags.command`, which is what recording
    /// ⌘Space in Launchie's own Settings saves.
    static let commandSpace = LaunchieHotkey(keyCode: 0x31,
                                             modifiers: Int(NSEvent.ModifierFlags.command.rawValue),
                                             enabled: true)

    var keyCode: Int?
    var modifiers: Int?
    var enabled: Bool?

    init(keyCode: Int?, modifiers: Int?, enabled: Bool?) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.enabled = enabled
    }

    /// Launchie's hotkey from `defaults export` output, or nil when there is
    /// nothing to read. macOS answers a process it has not let into Launchie's
    /// container with an empty dictionary and a zero exit status, not an
    /// error, and a Launchie that has been opened even once has written other
    /// preferences, so an empty export means unreadable rather than "no
    /// hotkey set".
    init?(exportStatus: Int32, output: Data) {
        guard exportStatus == 0,
              let plist = try? PropertyListSerialization.propertyList(from: output, format: nil),
              let preferences = plist as? [String: Any], !preferences.isEmpty else { return nil }
        self.init(preferences: preferences)
    }

    init(preferences: [String: Any]) {
        keyCode = (preferences[Self.keyCodeKey] as? NSNumber)?.intValue
        modifiers = (preferences[Self.modifiersKey] as? NSNumber)?.intValue
        enabled = (preferences[Self.enabledKey] as? NSNumber)?.boolValue
    }

    /// Whether Launchie registers ⌘Space from these values. Launchie turns only
    /// Command, Shift, Option and Control into its hotkey, so other recorded
    /// bits do not change the answer.
    var isCommandSpace: Bool {
        let chord = NSEvent.ModifierFlags([.command, .shift, .option, .control])
        guard keyCode == 0x31, let modifiers, enabled != false else { return false }
        return NSEvent.ModifierFlags(rawValue: UInt(modifiers)).intersection(chord) == .command
    }

    /// One `key=value` line per preference, the value left empty for one
    /// Launchie had never written, so restoring can delete it again.
    var fileContents: String {
        "\(Self.keyCodeKey)=\(keyCode.map(String.init) ?? "")\n"
            + "\(Self.modifiersKey)=\(modifiers.map(String.init) ?? "")\n"
            + "\(Self.enabledKey)=\(enabled.map(String.init) ?? "")\n"
    }

    init?(fileContents: String) {
        var values: [String: String] = [:]
        for line in fileContents.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            values[String(parts[0])] = String(parts[1])
        }
        guard let keyCode = values[Self.keyCodeKey], let modifiers = values[Self.modifiersKey],
              let enabled = values[Self.enabledKey] else { return nil }
        self.keyCode = Int(keyCode)
        self.modifiers = Int(modifiers)
        self.enabled = Bool(enabled)
    }
}

/// The Settings switch that lets Launchie answer ⌘Space in place of Spotlight.
///
/// Launchie can already take ⌘Space itself; it only needs its hotkey set to it
/// and Spotlight out of the way. The hotkey is Launchie's own preference, so
/// Omaccy writes it with `defaults` -- Launchie is sandboxed, and `defaults`
/// is what finds the preferences inside its container -- keeping whatever was
/// there before in `~/.omaccy/launchie-hotkey.original` for turning the switch
/// off. Launchie reads its hotkey once, at launch, so a running Launchie is
/// quit before the write and opened again after it.
///
/// Spotlight's shortcut is symbolic hot key 64, and WindowServer gives it the
/// keystroke ahead of any app's hotkey. It is paused with
/// `CGSSetSymbolicHotKeyEnabled` -- the runtime switch AltTab uses for ⌘Tab --
/// which lasts until logout and writes nothing to the user's preferences, so
/// System Settings keeps showing their own choice. Hyperkey pauses it again
/// every launch. `~/.omaccy/spotlight-shortcut-disabled` records that Omaccy
/// is the one who paused it, so only that is undone: a user who had already
/// unticked Spotlight's shortcut keeps it unticked.
enum LaunchieShortcut {
    static let bundleID = "de.nick-friedrich.Launchie"
    /// kCGSHotKeySpotlightSearchField, "Show Spotlight search" in System Settings.
    private static let spotlightHotKey: UInt32 = 64

    enum Outcome: Sendable, Equatable {
        case applied
        /// `defaults` could not read Launchie's preferences: it has never
        /// been opened, or macOS refused Omaccy access to its data.
        case preferencesUnreadable
    }

    static var spotlightMarkerPath: String { NSHomeDirectory() + "/.omaccy/spotlight-shortcut-disabled" }
    static var originalHotkeyPath: String { NSHomeDirectory() + "/.omaccy/launchie-hotkey.original" }

    static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    /// Brings Spotlight and Launchie in line with the setting. Quits and
    /// reopens Launchie and runs `defaults`, so call it off the main thread.
    /// Nothing is changed when Launchie's preferences cannot be read, so a
    /// failure never leaves ⌘Space answering to nothing.
    @discardableResult
    static func apply(enabled: Bool) -> Outcome {
        guard enabled, isInstalled else {
            restore()
            return .applied
        }
        guard let current = readHotkey() else { return .preferencesUnreadable }

        if current.isCommandSpace {
            // Launchie already asks for ⌘Space, but a hotkey registered while
            // Spotlight held the combination never received it, which is the
            // state after every login. Reopening makes it register again.
            if pauseSpotlight() { relaunchingLaunchie {} }
            return .applied
        }

        if !FileManager.default.fileExists(atPath: originalHotkeyPath) {
            write(current.fileContents, to: originalHotkeyPath)
        }
        // Spotlight is paused only once Launchie holds the shortcut, so a
        // write macOS refuses leaves ⌘Space with Spotlight.
        var wrote = false
        relaunchingLaunchie {
            wrote = writeHotkey(.commandSpace)
            if wrote { pauseSpotlight() }
        }
        return wrote ? .applied : .preferencesUnreadable
    }

    /// Gives Spotlight back what Omaccy paused and Launchie back the hotkey it
    /// had. Used by the switch, and by `--uninstall`.
    static func restore() {
        restoreSpotlight()
        guard let contents = try? String(contentsOfFile: originalHotkeyPath, encoding: .utf8) else { return }
        if isInstalled, let original = LaunchieHotkey(fileContents: contents),
           !relaunchingLaunchie({ writeHotkey(original) }) {
            return
        }
        try? FileManager.default.removeItem(atPath: originalHotkeyPath)
    }

    /// Only Spotlight: quitting Hyperkey hands ⌘Space back without touching
    /// Launchie, whose hotkey Spotlight outranks again anyway.
    static func restoreSpotlight() {
        guard FileManager.default.fileExists(atPath: spotlightMarkerPath) else { return }
        _ = CGSSetSymbolicHotKeyEnabled(spotlightHotKey, true)
        try? FileManager.default.removeItem(atPath: spotlightMarkerPath)
    }

    /// Returns whether Spotlight's shortcut was live and is now paused.
    @discardableResult
    private static func pauseSpotlight() -> Bool {
        guard CGSIsSymbolicHotKeyEnabled(spotlightHotKey) else { return false }
        if !FileManager.default.fileExists(atPath: spotlightMarkerPath) {
            write("", to: spotlightMarkerPath)
        }
        _ = CGSSetSymbolicHotKeyEnabled(spotlightHotKey, false)
        return true
    }

    // MARK: - Launchie's preferences

    private static func readHotkey() -> LaunchieHotkey? {
        guard let result = defaults(["export", bundleID, "-"]) else { return nil }
        return LaunchieHotkey(exportStatus: result.status, output: result.output)
    }

    /// Returns whether every write landed. Deleting a key Launchie never wrote
    /// fails too, so a delete's status is not held against it.
    @discardableResult
    private static func writeHotkey(_ hotkey: LaunchieHotkey) -> Bool {
        var succeeded = true
        let values: [(String, [String]?)] = [
            (LaunchieHotkey.keyCodeKey, hotkey.keyCode.map { ["-int", String($0)] }),
            (LaunchieHotkey.modifiersKey, hotkey.modifiers.map { ["-int", String($0)] }),
            (LaunchieHotkey.enabledKey, hotkey.enabled.map { ["-bool", String($0)] }),
        ]
        for (key, value) in values {
            if let value {
                if defaults(["write", bundleID, key] + value)?.status != 0 { succeeded = false }
            } else {
                _ = defaults(["delete", bundleID, key])
            }
        }
        return succeeded
    }

    private static func defaults(_ arguments: [String]) -> (status: Int32, output: Data)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, output)
    }

    // MARK: - Relaunching

    /// Runs `body` with Launchie quit, then opens it again in the background if
    /// it was running. Waits on the process itself rather than
    /// `NSRunningApplication.isTerminated`, which only updates on a running
    /// main loop that `--uninstall` does not have.
    @discardableResult
    private static func relaunchingLaunchie(_ body: () -> Void) -> Bool {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        let pids = running.map(\.processIdentifier)
        running.forEach { $0.terminate() }
        for _ in 0..<50 where pids.contains(where: { kill($0, 0) == 0 }) {
            usleep(100_000)
        }
        guard !pids.contains(where: { kill($0, 0) == 0 }) else {
            fputs("omaccy-hyperkey: Launchie did not quit; its hotkey was left as it was\n", stderr)
            return false
        }
        body()
        guard !pids.isEmpty else { return true }
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-g", "-b", bundleID]
        if (try? open.run()) != nil { open.waitUntilExit() }
        return true
    }

    private static func write(_ contents: String, to path: String) {
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        try? contents.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
