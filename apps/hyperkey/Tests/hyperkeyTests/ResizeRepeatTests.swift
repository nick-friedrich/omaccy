import CoreGraphics
import XCTest
@testable import hyperkey

final class ResizeRepeatTests: XCTestCase {
    func testHoldDelayAndCadenceWithoutCatchingUpAfterStalls() {
        var state = ResizeRepeatState()
        XCTAssertTrue(state.begin(keyCode: 0x22, flags: [], now: 0))
        XCTAssertEqual(state.chord?.0, 0x22)
        XCTAssertEqual(state.chord?.1, Constants.hyperFlags)
        XCTAssertNil(state.tick(now: 0.29))
        XCTAssertEqual(state.tick(now: 0.3)?.0, 0x22)
        XCTAssertNil(state.tick(now: 0.37))
        XCTAssertEqual(state.tick(now: 0.39)?.0, 0x22)
        XCTAssertEqual(state.tick(now: 10)?.0, 0x22)
        XCTAssertNil(state.tick(now: 10))
        XCTAssertTrue(state.release(keyCode: 0x22))
        XCTAssertNil(state.tick(now: 11))
    }

    func testHyperReleasedBeforeResizeKey() {
        var state = ResizeRepeatState()
        XCTAssertTrue(state.begin(keyCode: 0x20, flags: [], now: 0))
        state.cancel()
        XCTAssertNil(state.tick(now: 1))
        XCTAssertTrue(state.heldKeys.contains(0x20))
        // Repeated down events must not restart after Hyper release/cancellation.
        XCTAssertTrue(state.begin(keyCode: 0x20, flags: [], now: 2))
        XCTAssertNil(state.chord)
        XCTAssertTrue(state.release(keyCode: 0x20))
        XCTAssertFalse(state.release(keyCode: 0x20))
        XCTAssertTrue(state.begin(keyCode: 0x20, flags: [], now: 3))
        XCTAssertEqual(state.tick(now: 4)?.0, 0x20)
    }

    func testNativeRepeatDoesNotResetDelayAndLatestDirectionWins() {
        var state = ResizeRepeatState()
        XCTAssertTrue(state.begin(keyCode: 0x20, flags: [], now: 0))
        XCTAssertTrue(state.begin(keyCode: 0x20, flags: [], now: 0.2))
        XCTAssertEqual(state.tick(now: 0.3)?.0, 0x20)
        XCTAssertTrue(state.begin(keyCode: 0x22, flags: [], now: 1))
        XCTAssertTrue(state.release(keyCode: 0x20))
        XCTAssertEqual(state.tick(now: 1.4)?.0, 0x22)
        XCTAssertTrue(state.release(keyCode: 0x22))
        XCTAssertNil(state.tick(now: 2))
    }

    func testOtherKeysAndShiftChordsPassThrough() {
        var state = ResizeRepeatState()
        XCTAssertFalse(state.begin(keyCode: 0x04, flags: [], now: 0))
        XCTAssertFalse(state.begin(keyCode: 0x22, flags: .maskShift, now: 0))
        XCTAssertFalse(state.release(keyCode: 0x04))
        XCTAssertNil(state.chord)
    }
    func testResizeTriggersConfiguredBindingInCurrentMode() {
        for (keyCode, binding) in [(UInt16(0x20), "cmd-ctrl-alt-u"), (UInt16(0x22), "cmd-ctrl-alt-i")] {
            var calls: [[String]] = []
            ResizeKeyRepeat.trigger(keyCode: keyCode) { arguments in
                calls.append(arguments)
                return (0, "custom-mode\n")
            }
            XCTAssertEqual(calls, [
                ["list-modes", "--current"],
                ["trigger-binding", "--mode", "custom-mode", "--", binding],
            ])
        }
    }

    func testUnavailableModeDoesNotTriggerResize() {
        let responses: [(status: Int32, output: String)?] = [nil, (1, "main"), (0, "\n")]
        for response in responses {
            var calls = 0
            ResizeKeyRepeat.trigger(keyCode: 0x22) { _ in
                calls += 1
                return response
            }
            XCTAssertEqual(calls, 1)
        }
    }

}
