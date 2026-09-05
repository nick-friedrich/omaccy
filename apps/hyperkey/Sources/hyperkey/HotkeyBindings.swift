import AppKit
import Foundation
import CoreGraphics

/// Consumes configured Hyper chords and focuses their application by bundle ID.
/// Access is confined to the main run loop used by both keyboard input paths.
enum HotkeyBindings {
    nonisolated(unsafe) private static var targets: [UInt16: String] = [:]
    nonisolated(unsafe) private static var heldKeys: Set<UInt16> = []

    static func configure(_ bindings: [String: String]) {
        targets.removeAll()
        heldKeys.removeAll()

        for (name, bundleIdentifier) in bindings {
            guard let keyCode = KeyNames.virtualKeyCode(for: name) else {
                fputs("omaccy-hyperkey: ignoring unknown binding key '\(name)'\n", stderr)
                continue
            }
            guard !bundleIdentifier.isEmpty else { continue }
            targets[keyCode] = bundleIdentifier
        }
    }

    /// Returns true when the event belongs to a configured chord and must not
    /// continue into the normal event stream.
    static func handle(keyCode: UInt16, keyDown: Bool, flags: CGEventFlags = []) -> Bool {
        if keyDown {
            // Repeats stay consumed even if modifiers change while held.
            if heldKeys.contains(keyCode) { return true }
            let help = MenuShortcut.isQuestionMark(keyCode: keyCode, flags: flags)
            let apps = keyCode == 0x31 && !flags.contains(.maskShift)
            if help || apps {
                heldKeys.insert(keyCode)
                DispatchQueue.main.async {
                    SuperMenuController.shared.toggle(section: help ? .help : .apps)
                }
                return true
            }
            guard let bundleIdentifier = targets[keyCode] else { return false }
            if heldKeys.insert(keyCode).inserted {
                DispatchQueue.main.async {
                    focusOrLaunch(bundleIdentifier: bundleIdentifier)
                }
            }
            return true
        }

        return heldKeys.remove(keyCode) != nil
    }

    @MainActor
    static func focusOrLaunch(bundleIdentifier: String) {
        let runningApps = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        )
        let app = runningApps.first(where: { !$0.isTerminated })
        _ = app?.unhide()
        let isRunning = app != nil
        // The main run loop also draws the palette and handles keyboard events.
        // Never wait for AeroSpace (or spawn a launch process) on that thread.
        Task.detached(priority: .userInitiated) {
            if isRunning,
               let windowID = aeroSpaceWindowID(bundleIdentifier: bundleIdentifier),
               focusAeroSpaceWindow(windowID: windowID) {
                return
            }

            // Reopen running apps without a managed window, including Finder.
            launch(bundleIdentifier: bundleIdentifier)
        }
    }

    private static func launch(bundleIdentifier: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        if bundleIdentifier == "com.apple.finder" {
            process.arguments = [
                "-b", bundleIdentifier,
                FileManager.default.homeDirectoryForCurrentUser.path,
            ]
        } else {
            process.arguments = ["-b", bundleIdentifier]
        }
        do {
            try process.run()
        } catch {
            fputs("omaccy-hyperkey: could not launch \(bundleIdentifier): \(error)\n", stderr)
        }
    }

    private static func aeroSpaceWindowID(bundleIdentifier: String) -> String? {
        guard let executableURL = aeroSpaceExecutableURL() else { return nil }
        guard let listing = run(
            executableURL,
            arguments: ["list-windows", "--all", "--format", "%{window-id}\t%{app-bundle-id}"]
        ), listing.status == 0 else {
            return nil
        }

        return listing.output.split(whereSeparator: \.isNewline).lazy.compactMap { line -> String? in
            let fields = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard fields.count == 2, fields[1] == bundleIdentifier else { return nil }
            return fields[0]
        }.first
    }

    private static func focusAeroSpaceWindow(windowID: String) -> Bool {
        guard let executableURL = aeroSpaceExecutableURL() else { return false }
        return run(
            executableURL,
            arguments: ["focus", "--window-id", windowID]
        )?.status == 0
    }

    private static func aeroSpaceExecutableURL() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/aerospace",
            "/usr/local/bin/aerospace",
        ]
        return candidates.first(where: FileManager.default.isExecutableFile(atPath:))
            .map(URL.init(fileURLWithPath:))
    }

    /// Called from the background launch task. Bound each AeroSpace request so
    /// an unresponsive server cannot delay the normal app-opening fallback.
    static func run(
        _ executableURL: URL,
        arguments: [String],
        timeout: TimeInterval = 0.5
    ) -> (status: Int32, output: String)? {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let deadline = DispatchWorkItem {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout, execute: deadline)
            defer { deadline.cancel() }
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        } catch {
            return nil
        }
    }
}

private enum KeyNames {
    private static let codes: [String: UInt16] = [
        "a": 0x00, "b": 0x0B, "c": 0x08, "d": 0x02,
        "e": 0x0E, "f": 0x03, "g": 0x05, "h": 0x04,
        "i": 0x22, "j": 0x26, "k": 0x28, "l": 0x25,
        "m": 0x2E, "n": 0x2D, "o": 0x1F, "p": 0x23,
        "q": 0x0C, "r": 0x0F, "s": 0x01, "t": 0x11,
        "u": 0x20, "v": 0x09, "w": 0x0D, "x": 0x07,
        "y": 0x10, "z": 0x06,
        "0": 0x1D, "1": 0x12, "2": 0x13, "3": 0x14,
        "4": 0x15, "5": 0x17, "6": 0x16, "7": 0x1A,
        "8": 0x1C, "9": 0x19,
        "enter": 0x24, "return": 0x24, "space": 0x31,
        "tab": 0x30, "escape": 0x35, "backspace": 0x33,
        "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,
    ]

    static func virtualKeyCode(for name: String) -> UInt16? {
        codes[name.lowercased()]
    }
}
