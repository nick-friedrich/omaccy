import AppKit
import Foundation

/// Consumes configured Hyper chords and toggles their application by bundle ID.
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
    static func handle(keyCode: UInt16, keyDown: Bool) -> Bool {
        if keyDown {
            guard let bundleIdentifier = targets[keyCode] else { return false }
            if heldKeys.insert(keyCode).inserted {
                DispatchQueue.main.async {
                    toggle(bundleIdentifier: bundleIdentifier)
                }
            }
            return true
        }

        return heldKeys.remove(keyCode) != nil
    }

    @MainActor
    private static func toggle(bundleIdentifier: String) {
        let runningApps = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        )
        guard let app = runningApps.first(where: { !$0.isTerminated }) else {
            launch(bundleIdentifier: bundleIdentifier)
            return
        }

        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleIdentifier {
            if bundleIdentifier == "com.apple.finder",
               aeroSpaceWindowID(bundleIdentifier: bundleIdentifier) == nil {
                launch(bundleIdentifier: bundleIdentifier)
            } else {
                hideAndKeepWorkspace(app, bundleIdentifier: bundleIdentifier)
            }
            return
        }

        _ = app.unhide()
        if let windowID = aeroSpaceWindowID(bundleIdentifier: bundleIdentifier),
           focusAeroSpaceWindow(windowID: windowID) {
            return
        }

        // A running app without a managed window needs a reopen event. This is
        // especially important for Finder, which is always running.
        launch(bundleIdentifier: bundleIdentifier)
    }

    @MainActor
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

    @MainActor
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

    @MainActor
    private static func hideAndKeepWorkspace(
        _ app: NSRunningApplication,
        bundleIdentifier: String
    ) {
        let executableURL = aeroSpaceExecutableURL()
        let workspace = executableURL.flatMap {
            run($0, arguments: ["list-workspaces", "--focused"])?.output
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let fallbackWindowID = executableURL.flatMap {
            aeroSpaceFallbackWindowID(
                executableURL: $0,
                excludingBundleIdentifier: bundleIdentifier
            )
        }

        // If another window exists here, focus it before hiding the target.
        // The target is then a background app and macOS has no reason to jump
        // to the previously focused app on a different workspace.
        if let fallbackWindowID {
            _ = focusAeroSpaceWindow(windowID: fallbackWindowID)
        }

        if !app.hide() {
            fputs("omaccy-hyperkey: could not hide \(bundleIdentifier)\n", stderr)
            return
        }

        // On an otherwise empty workspace, hiding the only app makes macOS
        // asynchronously activate the previously used app. Wait for that
        // transition to finish before restoring the original workspace.
        if fallbackWindowID == nil,
           let executableURL,
           let workspace,
           !workspace.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                _ = run(executableURL, arguments: ["workspace", workspace])
            }
        }
    }

    private static func aeroSpaceFallbackWindowID(
        executableURL: URL,
        excludingBundleIdentifier: String
    ) -> String? {
        guard let listing = run(
            executableURL,
            arguments: [
                "list-windows", "--workspace", "focused",
                "--format", "%{window-id}\t%{app-bundle-id}",
            ]
        ), listing.status == 0 else {
            return nil
        }

        return listing.output.split(whereSeparator: \.isNewline).lazy.compactMap { line -> String? in
            let fields = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard fields.count == 2, fields[1] != excludingBundleIdentifier else { return nil }
            return fields[0]
        }.first
    }

    private static func aeroSpaceExecutableURL() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/aerospace",
            "/usr/local/bin/aerospace",
        ]
        return candidates.first(where: FileManager.default.isExecutableFile(atPath:))
            .map(URL.init(fileURLWithPath:))
    }

    private static func run(
        _ executableURL: URL,
        arguments: [String]
    ) -> (status: Int32, output: String)? {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
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
