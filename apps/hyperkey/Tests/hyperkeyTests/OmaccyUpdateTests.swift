import XCTest
@testable import hyperkey

final class OmaccyUpdateTests: XCTestCase {
    func testUpdatePathIsAnArgumentAndConfirmationCannotBeInheritedAway() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("omaccy space ' $ test-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for path in ["scripts/update.sh", "scripts/install.sh", "scripts/lib/paths.sh", "apps/hyperkey/Package.swift"] {
            let file = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: file)
        }
        let args = try XCTUnwrap(OmaccyUpdate.ghosttyArguments(checkout: root))
        XCTAssertEqual(Array(args.suffix(2)), ["/bin/bash", root.appendingPathComponent("scripts/update.sh").path])
        XCTAssertTrue(args.contains("OMACCY_ASSUME_YES=0"))
        XCTAssertFalse(args.contains("-c"))
        try FileManager.default.removeItem(at: root.appendingPathComponent("scripts/update.sh"))
        XCTAssertNil(OmaccyUpdate.ghosttyArguments(checkout: root))
    }
}
