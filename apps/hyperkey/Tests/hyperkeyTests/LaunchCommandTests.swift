import XCTest
@testable import hyperkey

final class LaunchCommandTests: XCTestCase {
    func testCapturesOutputAndExitStatus() throws {
        let result = try XCTUnwrap(HotkeyBindings.run(
            URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf '123\\tcom.google.Chrome\\n'; exit 7"]
        ))
        XCTAssertEqual(result.output, "123\tcom.google.Chrome\n")
        XCTAssertEqual(result.status, 7)
    }

    func testUnresponsiveCommandIsStoppedPromptly() throws {
        let start = Date()
        let result = try XCTUnwrap(HotkeyBindings.run(
            URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"], timeout: 0.1
        ))
        XCTAssertNotEqual(result.status, 0)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.5)
    }

    func testDrainsOutputLargerThanPipeBuffer() throws {
        let result = try XCTUnwrap(HotkeyBindings.run(
            URL(fileURLWithPath: "/usr/bin/head"),
            arguments: ["-c", "131072", "/dev/zero"], timeout: 2
        ))
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.output.utf8.count, 131072)
    }
}
