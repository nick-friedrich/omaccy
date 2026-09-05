import AppKit
import Carbon

enum SystemAction: CaseIterable, Sendable {
    case sleep, restart, shutDown

    var title: String {
        switch self {
        case .sleep: return "Sleep"
        case .restart: return "Restart"
        case .shutDown: return "Shut Down"
        }
    }

    var detail: String {
        switch self {
        case .sleep: return "Put your Mac to sleep"
        case .restart: return "Restart your Mac…"
        case .shutDown: return "Power off your Mac (shutdown)…"
        }
    }

    var symbol: String {
        switch self {
        case .sleep: return "moon.zzz"
        case .restart: return "arrow.clockwise"
        case .shutDown: return "power"
        }
    }

    var requiresConfirmation: Bool { self != .sleep }

    var eventID: AEEventID {
        switch self {
        case .sleep: return AEEventID(kAESleep)
        case .restart: return AEEventID(kAERestart)
        case .shutDown: return AEEventID(kAEShutDown)
        }
    }

    func perform() throws {
        // Send the standard power event to the system process. macOS handles
        // application termination normally, including unsaved-document prompts.
        var process = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: UInt32(kSystemProcess))
        let target = NSAppleEventDescriptor(descriptorType: DescType(typeProcessSerialNumber),
                                            bytes: &process, length: MemoryLayout.size(ofValue: process))!
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass),
                                           eventID: eventID, targetDescriptor: target,
                                           returnID: AEReturnID(kAutoGenerateReturnID),
                                           transactionID: AETransactionID(kAnyTransactionID))
        _ = try event.sendEvent(options: .noReply, timeout: 1)
    }
}
