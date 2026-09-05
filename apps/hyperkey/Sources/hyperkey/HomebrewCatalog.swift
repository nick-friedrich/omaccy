import Foundation

struct HomebrewPackage: Sendable, Equatable {
    enum Kind: String, Sendable { case formula, cask }
    let token: String
    let name: String
    let description: String
    let kind: Kind

    var installedVersion: String? = nil
    var outdated = false
    var pinned = false
    var id: String { "\(kind.rawValue):\(token)" }
    var status: String {
        guard let installedVersion else { return "" }
        return "\(pinned ? "Pinned" : outdated ? "Update available" : "Installed") · \(installedVersion)"
    }
    var actionTitle: String? {
        installedVersion == nil ? "Install" : outdated && !pinned ? "Update" : nil
    }
    var actionCommand: String? {
        guard actionTitle != nil, let installCommand else { return nil }
        return installedVersion == nil ? installCommand : installCommand.replacingOccurrences(of: "brew install ", with: "brew upgrade ")
    }

    // A separate Ghostty instance owns this job window. Its exit leaves existing
    // Ghostty windows alone; wait-after-command keeps success and error output visible.
    func ghosttyArguments(brew: String) -> [String]? {
        guard let command = actionCommand else { return nil }
        return HomebrewUpgrade.ghosttyArguments(brew: brew, command: command)
    }

    var detail: String { "\(kind == .cask ? "App" : "Command-line tool") · \(token) · \(description)" }

    // Only validated catalog or installed-package identifiers become shell arguments, never search text.
    var installCommand: String? {
        guard !token.isEmpty, token.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0.first != "-" && $0 != "." && $0 != ".." }),
              token.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789@+._-/").contains($0) }) else { return nil }
        return "brew install --\(kind.rawValue) '\(token)'"
    }
}

enum HomebrewCatalog {
    private struct Formula: Decodable {
        let name: String
        let desc: String?
        let disabled: Bool?
    }
    private struct Cask: Decodable {
        let token: String
        let name: [String]
        let desc: String?
        let disabled: Bool?
    }

    static func decode(_ data: Data, kind: HomebrewPackage.Kind) throws -> [HomebrewPackage] {
        let decoder = JSONDecoder()
        switch kind {
        case .formula:
            return try decoder.decode([Formula].self, from: data).filter { $0.disabled != true }.map {
                HomebrewPackage(token: $0.name, name: $0.name, description: $0.desc ?? "", kind: .formula)
            }
        case .cask:
            return try decoder.decode([Cask].self, from: data).filter { $0.disabled != true }.map {
                HomebrewPackage(token: $0.token, name: $0.name.first ?? $0.token, description: $0.desc ?? "", kind: .cask)
            }
        }
    }

    static func load() async throws -> [HomebrewPackage] {
        async let formulae = fetch(.formula)
        async let casks = fetch(.cask)
        return try await (formulae + casks).filter { $0.installCommand != nil }
    }

    private static func fetch(_ kind: HomebrewPackage.Kind) async throws -> [HomebrewPackage] {
        let url = URL(string: "https://formulae.brew.sh/api/\(kind.rawValue).json")!
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 45))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try decode(data, kind: kind)
    }

    static func search(_ query: String, packages: [HomebrewPackage]) -> [HomebrewPackage] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else {
            return packages.filter { $0.installedVersion != nil }.sorted {
                let leftUpdate = $0.outdated && !$0.pinned
                let rightUpdate = $1.outdated && !$1.pinned
                if leftUpdate != rightUpdate { return leftUpdate }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        func rank(_ package: HomebrewPackage) -> Int {
            if package.token == query || package.name.lowercased() == query { return 0 }
            if package.token.hasPrefix(query) || package.name.lowercased().hasPrefix(query) { return 1 }
            return 2
        }
        return Array(packages.filter { package in
            let text = "\(package.name) \(package.token) \(package.description)".lowercased()
            return words.allSatisfy { text.contains($0) }
        }.sorted {
            if rank($0) != rank($1) { return rank($0) < rank($1) }
            if $0.name != $1.name { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return $0.kind.rawValue < $1.kind.rawValue
        }.prefix(100))
    }
}

// Read-only inventory queries run off the UI thread. No brew update or upgrade
// occurs until the user confirms an individual package action.
enum HomebrewInventory {
    static var executable: String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    private struct Inventory: Decodable {
        let formulae: [Formula]
        let casks: [Cask]
    }
    private struct Version: Decodable { let version: String }
    private struct Formula: Decodable {
        let name: String
        let full_name: String
        let desc: String?
        let installed: [Version]
        let outdated: Bool
        let pinned: Bool?
    }
    private struct Cask: Decodable {
        let token: String
        let full_token: String?
        let name: [String]
        let desc: String?
        let installed: String?
        let outdated: Bool
        let pinned: Bool?
    }

    static func decode(_ data: Data) throws -> [HomebrewPackage] {
        let inventory = try JSONDecoder().decode(Inventory.self, from: data)
        let formulae = inventory.formulae.filter { !$0.installed.isEmpty }.map {
            HomebrewPackage(token: $0.full_name, name: $0.name, description: $0.desc ?? "", kind: .formula,
                installedVersion: $0.installed.map(\.version).joined(separator: ", "), outdated: $0.outdated, pinned: $0.pinned ?? false)
        }
        let casks = inventory.casks.filter { $0.installed != nil }.map {
            HomebrewPackage(token: $0.full_token ?? $0.token, name: $0.name.first ?? $0.token,
                description: $0.desc ?? "", kind: .cask, installedVersion: $0.installed,
                outdated: $0.outdated, pinned: $0.pinned ?? false)
        }
        return formulae + casks
    }

    static func load() throws -> [HomebrewPackage] {
        guard let executable else { throw URLError(.fileDoesNotExist) }
        guard let result = HotkeyBindings.run(URL(fileURLWithPath: "/usr/bin/env"), arguments: [
            "HOMEBREW_NO_AUTO_UPDATE=1", "HOMEBREW_NO_ANALYTICS=1", executable,
            "info", "--json=v2", "--installed"
        ], timeout: 45), result.status == 0 else { throw URLError(.cannotLoadFromNetwork) }
        return try decode(Data(result.output.utf8))
    }

    static func merge(catalog: [HomebrewPackage], installed: [HomebrewPackage]) -> [HomebrewPackage] {
        var entries = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for package in installed { entries[package.id] = package }
        return Array(entries.values)
    }
}

enum HomebrewUpgrade {
    static func availableCount(_ packages: [HomebrewPackage]) -> Int {
        packages.filter { $0.installedVersion != nil && $0.outdated && !$0.pinned }.count
    }

    static func allArguments(brew: String) -> [String]? {
        ghosttyArguments(brew: brew, command: "brew upgrade")
    }

    // Called only with a fixed bulk command or a validated package action.
    fileprivate static func ghosttyArguments(brew: String, command: String) -> [String]? {
        guard ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].contains(brew) else { return nil }
        let prefix = String(brew.dropLast("/bin/brew".count))
        let script = "export PATH=\(prefix)/bin:\(prefix)/sbin:$PATH; exec " + brew + command.dropFirst(4)
        return ["--wait-after-command=true", "--quit-after-last-window-closed=true",
                "-e", "/bin/bash", "-c", script]
    }
}
