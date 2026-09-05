import XCTest
@testable import hyperkey

final class HomebrewCatalogTests: XCTestCase {
    func testDecodesBothCatalogsAndExcludesDisabledPackages() throws {
        let formulae = try HomebrewCatalog.decode(Data(#"[{"name":"wget","desc":"Download files"},{"name":"old","disabled":true}]"#.utf8), kind: .formula)
        let casks = try HomebrewCatalog.decode(Data(#"[{"token":"visual-studio-code","name":["Visual Studio Code"],"desc":null}]"#.utf8), kind: .cask)
        XCTAssertEqual(formulae.map(\.token), ["wget"])
        XCTAssertEqual(casks.first?.name, "Visual Studio Code")
        XCTAssertEqual(casks.first?.description, "")
        XCTAssertThrowsError(try HomebrewCatalog.decode(Data("{}".utf8), kind: .formula))
    }

    func testSearchMatchesDescriptionsAndPrioritizesExactNames() {
        let packages = [
            HomebrewPackage(token: "wget-helper", name: "A helper", description: "Download files", kind: .formula),
            HomebrewPackage(token: "wget", name: "wget", description: "Download files", kind: .formula),
            HomebrewPackage(token: "editor", name: "Editor", description: "Edit text", kind: .cask)
        ]
        XCTAssertEqual(HomebrewCatalog.search(" WGET ", packages: packages).map(\.token), ["wget", "wget-helper"])
        XCTAssertEqual(HomebrewCatalog.search("edit text", packages: packages).map(\.token), ["editor"])
        XCTAssertTrue(HomebrewCatalog.search("  ", packages: packages).isEmpty)
        XCTAssertTrue(HomebrewCatalog.search("missing", packages: packages).isEmpty)
        XCTAssertTrue(MenuCatalog.results(query: "sleep", page: .install, apps: [], help: []).isEmpty)
    }

    func testInstallCommandRejectsShellSyntaxAndOptions() {
        for token in ["", "--help", "bad;touch /tmp/test", "$(whoami)", "foo'bar", "foo\nbar", "tap/../name", "tap/--name"] {
            XCTAssertNil(HomebrewPackage(token: token, name: token, description: "", kind: .formula).installCommand)
        }
        XCTAssertEqual(HomebrewPackage(token: "python@3.13", name: "Python", description: "", kind: .formula).installCommand, "brew install --formula 'python@3.13'")
        XCTAssertEqual(HomebrewPackage(token: "ghostty", name: "Ghostty", description: "", kind: .cask).installCommand, "brew install --cask 'ghostty'")
    }
    func testInventoryMergesKindsAndCustomTapsWithUpdateActions() throws {
        let data = Data(#"{"formulae":[{"name":"shared","full_name":"shared","installed":[{"version":"1.0"}],"outdated":true},{"name":"custom","full_name":"team/tools/custom","installed":[{"version":"2"}],"outdated":true,"pinned":true}],"casks":[{"token":"shared","name":["Shared App"],"installed":"3","outdated":false}]}"#.utf8)
        let installed = try HomebrewInventory.decode(data)
        let catalog = [HomebrewPackage(token: "shared", name: "shared", description: "", kind: .formula)]
        let merged = HomebrewInventory.merge(catalog: catalog, installed: installed)
        XCTAssertEqual(merged.count, 3)
        let results = HomebrewCatalog.search("", packages: merged)
        XCTAssertEqual(results.first?.id, "formula:shared")
        XCTAssertEqual(results.first?.actionCommand, "brew upgrade --formula 'shared'")
        XCTAssertNil(installed.first { $0.pinned }?.actionCommand)
        XCTAssertEqual(installed.first { $0.pinned }?.installCommand, "brew install --formula 'team/tools/custom'")
        XCTAssertNil(installed.first { $0.kind == .cask }?.actionCommand)
        XCTAssertEqual(HomebrewCatalog.search("shared", packages: merged).count, 2)
        XCTAssertEqual(HomebrewInventory.merge(catalog: catalog, installed: []).first?.installedVersion, nil)
        XCTAssertThrowsError(try HomebrewInventory.decode(Data("{}".utf8)))
    }

    func testInstalledListIsNotCappedAndCaskUpdatesUseUpgrade() {
        let packages = (0..<150).map {
            HomebrewPackage(token: "app-\($0)", name: "App \($0)", description: "", kind: .cask,
                installedVersion: "1", outdated: true)
        }
        XCTAssertEqual(HomebrewCatalog.search("", packages: packages).count, 150)
        XCTAssertEqual(HomebrewCatalog.search("app", packages: packages).count, 100)
        XCTAssertEqual(packages[0].actionCommand, "brew upgrade --cask 'app-0'")
    }

    func testGhosttyLaunchUsesDedicatedWindowAndValidatedCommand() throws {
        let package = HomebrewPackage(token: "kitty", name: "kitty", description: "", kind: .cask,
            installedVersion: "0.46.2", outdated: true)
        let arguments = try XCTUnwrap(package.ghosttyArguments(brew: "/opt/homebrew/bin/brew"))
        XCTAssertEqual(Array(arguments.prefix(5)), ["--wait-after-command=true", "--quit-after-last-window-closed=true", "-e", "/bin/bash", "-c"])
        XCTAssertEqual(arguments.last, "export PATH=/opt/homebrew/bin:/opt/homebrew/sbin:$PATH; exec /opt/homebrew/bin/brew upgrade --cask 'kitty'")
        XCTAssertTrue(package.ghosttyArguments(brew: "/usr/local/bin/brew")!.last!.contains("exec /usr/local/bin/brew"))
        XCTAssertNil(package.ghosttyArguments(brew: "/tmp/brew;bad"))
        let invalid = HomebrewPackage(token: "kitty;bad", name: "", description: "", kind: .cask)
        XCTAssertNil(invalid.ghosttyArguments(brew: "/opt/homebrew/bin/brew"))
    }

    func testUpgradeAllCountsOnlyInstalledUnpinnedUpdatesAndUsesNativeBrewUpgrade() throws {
        let packages = [
            HomebrewPackage(token: "a", name: "A", description: "", kind: .formula, installedVersion: "1", outdated: true),
            HomebrewPackage(token: "b", name: "B", description: "", kind: .cask, installedVersion: "1", outdated: true),
            HomebrewPackage(token: "c", name: "C", description: "", kind: .cask, installedVersion: "1", outdated: true, pinned: true),
            HomebrewPackage(token: "d", name: "D", description: "", kind: .formula, installedVersion: "1"),
            HomebrewPackage(token: "e", name: "E", description: "", kind: .formula)
        ]
        XCTAssertEqual(HomebrewUpgrade.availableCount(packages), 2)
        XCTAssertEqual(HomebrewUpgrade.availableCount([]), 0)
        let arguments = try XCTUnwrap(HomebrewUpgrade.allArguments(brew: "/opt/homebrew/bin/brew"))
        XCTAssertEqual(arguments.last, "export PATH=/opt/homebrew/bin:/opt/homebrew/sbin:$PATH; exec /opt/homebrew/bin/brew upgrade")
        XCTAssertTrue(arguments.contains("--wait-after-command=true"))
        XCTAssertNil(HomebrewUpgrade.allArguments(brew: "/tmp/untrusted-brew"))
    }

}
