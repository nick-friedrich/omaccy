import CoreGraphics
import Foundation

/// Main-run-loop state shared by the event-tap and seized-keyboard paths.
/// Trigger AeroSpace through IPC; synthetic taps can be lost by its hotkey listener.
struct ResizeRepeatState {
    private(set) var heldKeys: Set<UInt16> = []
    private(set) var keyCode: UInt16?
    private var flags: CGEventFlags = []
    private var nextRepeat: TimeInterval = 0

    mutating func begin(keyCode: UInt16, flags: CGEventFlags, now: TimeInterval) -> Bool {
        guard [UInt16(0x20), 0x22].contains(keyCode), !flags.contains(.maskShift) else { return false }
        guard heldKeys.insert(keyCode).inserted else { return true }
        self.keyCode = keyCode
        self.flags = CGEventFlags(rawValue: flags.rawValue | Constants.hyperFlags.rawValue)
        nextRepeat = now + 0.3
        return true
    }

    mutating func release(keyCode: UInt16) -> Bool {
        if self.keyCode == keyCode { cancel() }
        return heldKeys.remove(keyCode) != nil
    }

    mutating func cancel() {
        keyCode = nil
        // Keep consuming releases and native repeats until the physical key is up.
    }

    var chord: (UInt16, CGEventFlags)? {
        keyCode.map { ($0, flags) }
    }

    mutating func tick(now: TimeInterval) -> (UInt16, CGEventFlags)? {
        guard now >= nextRepeat, let chord else { return nil }
        nextRepeat = now + 0.08
        return chord
    }
}

enum ResizeKeyRepeat {
    nonisolated(unsafe) private static var state = ResizeRepeatState()
    nonisolated(unsafe) private static var timer: DispatchSourceTimer?
    nonisolated(unsafe) private static var requestInFlight = false

    /// Called before normal routing, including after Hyper has been released.
    static func consumeHeld(keyCode: UInt16, keyDown: Bool) -> Bool {
        if keyDown { return state.heldKeys.contains(keyCode) }
        let consumed = state.release(keyCode: keyCode)
        if state.keyCode == nil { stopTimer() }
        return consumed
    }

    static func begin(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        guard state.begin(keyCode: keyCode, flags: flags, now: ProcessInfo.processInfo.systemUptime) else { return false }
        if let chord = state.chord { post(chord) }
        stopTimer()
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + 0.3, repeating: .milliseconds(20))
        source.setEventHandler {
            if let chord = state.tick(now: ProcessInfo.processInfo.systemUptime) { post(chord) }
        }
        timer = source
        source.resume()
        return true
    }

    static func cancel() {
        state.cancel()
        stopTimer()
    }

    static func reset() {
        cancel()
        state = ResizeRepeatState()
    }

    private static func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    private static func post(_ chord: (UInt16, CGEventFlags)) {
        // Never queue resize steps: a slow server must not create a backlog that
        // continues resizing after release. The main run loop stays responsive.
        guard !requestInFlight, let executable = HotkeyBindings.aeroSpaceExecutableURL() else { return }
        requestInFlight = true
        let keyCode = chord.0
        DispatchQueue.global(qos: .userInitiated).async {
            trigger(keyCode: keyCode) { arguments in
                HotkeyBindings.run(executable, arguments: arguments)
            }
            DispatchQueue.main.async { requestInFlight = false }
        }
    }

    /// Resolve the current mode rather than hardcoding commands or bypassing
    /// customized bindings. Called on a worker queue; injectable for IPC tests.
    static func trigger(
        keyCode: UInt16,
        run: ([String]) -> (status: Int32, output: String)?
    ) {
        let binding: String
        switch keyCode {
        case 0x20: binding = "cmd-ctrl-alt-u"
        case 0x22: binding = "cmd-ctrl-alt-i"
        default: return
        }
        guard let mode = run(["list-modes", "--current"]), mode.status == 0 else { return }
        let name = mode.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        _ = run(["trigger-binding", "--mode", name, "--", binding])
    }
}
