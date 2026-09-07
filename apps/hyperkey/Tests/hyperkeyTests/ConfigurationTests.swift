import XCTest
@testable import hyperkey

final class ConfigurationTests: XCTestCase {
    private var configURL: URL!

    override func setUp() {
        super.setUp()
        configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("omaccy-config-\(UUID().uuidString).toml")
        setenv("OMACCY_HYPERKEY_CONFIG", configURL.path, 1)
    }

    override func tearDown() {
        unsetenv("OMACCY_HYPERKEY_CONFIG")
        try? FileManager.default.removeItem(at: configURL)
        super.tearDown()
    }

    private func write(_ contents: String) throws {
        try contents.write(to: configURL, atomically: true, encoding: .utf8)
    }

    func testReadsCollectionDefaultsFromTheRootSection() throws {
        try write("""
        escape_on_tap = true
        default_agent = "codex"
        default_mail = "emzero"
        default_editor = "zed"

        [bindings]
        t = "com.mitchellh.ghostty"
        """)
        let config = Configuration.load()
        XCTAssertEqual(config.defaultAgent, "codex")
        XCTAssertEqual(config[.mail], "emzero")
        XCTAssertEqual(config[.editors], "zed")
        XCTAssertEqual(config.bindings["t"], "com.mitchellh.ghostty")
    }

    func testCollectionDefaultsSurviveASaveAndReload() {
        var config = Configuration(escapeOnTap: false, bindings: ["t": "com.mitchellh.ghostty"])
        config[.mail] = "mimestream"
        config[.editors] = "cursor"
        config.defaultAgent = "claude-code"
        config.save()

        let reloaded = Configuration.load()
        XCTAssertEqual(reloaded[.mail], "mimestream")
        XCTAssertEqual(reloaded[.editors], "cursor")
        XCTAssertEqual(reloaded.defaultAgent, "claude-code")
        XCTAssertEqual(reloaded.bindings, ["t": "com.mitchellh.ghostty"])
    }

    func testUnsetCollectionDefaultsAreOmittedRatherThanWrittenEmpty() {
        Configuration(escapeOnTap: false, bindings: [:]).save()
        let contents = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        for collection in AppCollection.allCases {
            XCTAssertFalse(contents.contains(collection.configKey), collection.configKey)
        }
        XCTAssertNil(Configuration.load()[.mail])
    }

    /// A key the shipped config comments out must not read back as a value.
    func testCommentedDefaultsStayUnset() throws {
        try write("""
        escape_on_tap = false
        # default_mail = "emzero"
        """)
        XCTAssertNil(Configuration.load()[.mail])
    }
}
