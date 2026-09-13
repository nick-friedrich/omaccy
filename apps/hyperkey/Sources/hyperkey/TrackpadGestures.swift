import Foundation

/// Three-finger horizontal swipes, read straight off the trackpad, switch
/// AeroSpace workspaces.
///
/// macOS claims this gesture for "swipe between full-screen apps" and the
/// WindowServer consumes it before an event tap could see it, so the raw
/// contact stream from the private MultitouchSupport framework is the only way
/// in. `scripts/lib/macos.sh` turns the macOS gesture off during install;
/// while both are live one swipe moves an AeroSpace workspace and a macOS
/// Space at once.
///
/// The framework is opened with dlopen rather than linked against, so a macOS
/// release that drops it costs the gesture rather than the app's launch.
enum TrackpadGestures {
    private typealias DeviceRef = UnsafeMutableRawPointer
    private typealias CreateList = @convention(c) () -> Unmanaged<CFMutableArray>?
    private typealias ContactCallback = @convention(c) (
        DeviceRef?, UnsafeMutableRawPointer?, Int32, Double, Int32
    ) -> Int32
    private typealias RegisterCallback = @convention(c) (DeviceRef, ContactCallback) -> Void
    private typealias DeviceStart = @convention(c) (DeviceRef, Int32) -> Void

    /// Byte offsets into the C MTTouch struct. Reading by offset avoids
    /// depending on Swift reproducing the C layout field for field.
    private static let touchStride = 96
    private static let offsetPositionX = 32
    private static let offsetVelocityX = 40

    /// Measured on a built-in trackpad: a deliberate swipe crosses 0.08 of the
    /// pad's width while still moving at 0.3 or more, and resting or shifting
    /// fingers stay well under both.
    private static let travelThreshold: Float = 0.08
    private static let velocityThreshold: Float = 0.1

    /// Written from the contact callback's thread and read only there.
    nonisolated(unsafe) private static var gestureStartX: Float?
    nonisolated(unsafe) private static var gestureFired = false
    nonisolated(unsafe) private static var naturalDirection = true
    nonisolated(unsafe) private static var started = false

    /// Begins watching the trackpad. Safe to call when no trackpad is attached
    /// or the framework has gone: the gesture is simply unavailable.
    static func start(naturalDirection useNatural: Bool) {
        guard !started else { return }
        naturalDirection = useNatural

        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
            RTLD_NOW
        ) else {
            fputs("omaccy-hyperkey: no MultitouchSupport; trackpad swipes are off\n", stderr)
            return
        }
        guard let createListSymbol = dlsym(handle, "MTDeviceCreateList"),
              let registerSymbol = dlsym(handle, "MTRegisterContactFrameCallback"),
              let startSymbol = dlsym(handle, "MTDeviceStart") else {
            fputs("omaccy-hyperkey: MultitouchSupport is missing symbols; trackpad swipes are off\n", stderr)
            return
        }

        let createList = unsafeBitCast(createListSymbol, to: CreateList.self)
        let register = unsafeBitCast(registerSymbol, to: RegisterCallback.self)
        let startDevice = unsafeBitCast(startSymbol, to: DeviceStart.self)

        guard let devices = createList()?.takeRetainedValue() else { return }
        let count = CFArrayGetCount(devices)
        guard count > 0 else { return }

        for index in 0..<count {
            guard let device = CFArrayGetValueAtIndex(devices, index) else { continue }
            let deviceRef = DeviceRef(mutating: device)
            register(deviceRef, contactCallback)
            startDevice(deviceRef, 0)
        }
        started = true
    }

    /// Runs on the framework's own thread for every frame of contact, so it
    /// only measures and hands the workspace switch to a detached process.
    private static let contactCallback: ContactCallback = { _, touches, numTouches, _, _ in
        guard let touches, numTouches >= 3 else {
            // Fingers lifted (or dropped below three): arm the next gesture.
            if numTouches == 0 {
                gestureStartX = nil
                gestureFired = false
            }
            return 0
        }

        // Averaging across contacts keeps one finger drifting from registering
        // as a swipe, and rides out the finger count changing mid-gesture.
        var sumX: Float = 0
        var sumVelocityX: Float = 0
        for index in 0..<Int(numTouches) {
            let base = touches.advanced(by: index * touchStride)
            sumX += base.load(fromByteOffset: offsetPositionX, as: Float.self)
            sumVelocityX += base.load(fromByteOffset: offsetVelocityX, as: Float.self)
        }
        let averageX = sumX / Float(numTouches)
        let averageVelocityX = sumVelocityX / Float(numTouches)

        guard let startX = gestureStartX else {
            gestureStartX = averageX
            return 0
        }
        guard !gestureFired else { return 0 }

        let travel = averageX - startX
        guard abs(travel) > travelThreshold, abs(averageVelocityX) > velocityThreshold else {
            return 0
        }

        // One switch per set of fingers; the rest of the swipe is ignored
        // until they lift, so a long swipe cannot skip several workspaces.
        gestureFired = true
        switchWorkspace(movingRight: travel > 0)
        return 0
    }

    /// With natural scrolling the workspace follows the fingers: sliding them
    /// right pulls the workspace on the left into view.
    private static func switchWorkspace(movingRight: Bool) {
        let goesToPrevious = naturalDirection ? movingRight : !movingRight
        let direction = goesToPrevious ? "prev" : "next"

        guard let aerospace = HotkeyBindings.aeroSpaceExecutableURL() else { return }
        let path = aerospace.path

        // Mirrors the Hyper+Tab binding in aerospace.toml: only workspaces with
        // windows on the focused monitor, wrapping at either end.
        let pipeline = "\(path) list-workspaces --monitor focused --empty no"
            + " | \(path) workspace --wrap-around --stdin \(direction)"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", pipeline]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
