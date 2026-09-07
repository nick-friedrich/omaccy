import Foundation

// Setup records its checkout outside the app bundle so re-signing the
// downloaded, notarized release build is never required. Debug builds can
// resolve the checkout from their source path.
enum OmaccyUpdate {
    static func checkout(bundle: Bundle = .main) -> URL? {
        let checkoutFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".omaccy/hyperkey-checkout.txt")
        if let path = try? String(contentsOf: checkoutFile, encoding: .utf8), path.hasPrefix("/") {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        guard bundle.bundleURL.pathExtension != "app" else { return nil }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    static func ghosttyArguments(checkout: URL) -> [String]? {
        let script = checkout.appendingPathComponent("scripts/update.sh")
        guard ["scripts/update.sh", "scripts/install.sh", "scripts/lib/paths.sh", "apps/hyperkey/Package.swift"].allSatisfy({
            FileManager.default.isReadableFile(atPath: checkout.appendingPathComponent($0).path)
        }) else { return nil }
        return ["--wait-after-command=true", "--quit-after-last-window-closed=true",
                "-e", "/usr/bin/env", "OMACCY_ASSUME_YES=0",
                "PATH=/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin",
                "/bin/bash", script.path]
    }
}
