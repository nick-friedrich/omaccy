import Foundation

struct Configuration {
    var escapeOnTap: Bool
    var bindings: [String: String]
    var defaultAgent: String? = nil
    var defaultMail: String? = nil
    var defaultEditor: String? = nil
    var clipboardHistory: Bool = true
    /// Off by default: a password copied from a browser extension cannot be
    /// told apart from an ordinary copy, so history stays in memory unless
    /// the user asks for it on disk.
    var clipboardPersist: Bool = false
    var clipboardLimit: Int = 200
    /// Switch AeroSpace workspaces on a three-finger horizontal trackpad swipe.
    var trackpadSwipe: Bool = true
    /// Off sends the workspace the other way, for anyone who turned macOS
    /// natural scrolling off.
    var trackpadSwipeNatural: Bool = true
    /// Layout mode of a workspace that has never been given one; read by
    /// `layout.sh`, which is what actually arranges the windows.
    var defaultLayout: WorkspaceLayout = .fallback
    /// ⌘Space opens Launchie rather than Spotlight. Off by default, so nobody
    /// finds Spotlight gone without having asked for it.
    var launchieCommandSpace: Bool = false

    /// The app a picker collection launches directly from its own Hyper chord.
    subscript(collection: AppCollection) -> String? {
        get {
            switch collection {
            case .mail: return defaultMail
            case .editors: return defaultEditor
            }
        }
        set {
            switch collection {
            case .mail: defaultMail = newValue
            case .editors: defaultEditor = newValue
            }
        }
    }

    static var fileURL: URL {
        if let override = ProcessInfo.processInfo.environment["OMACCY_HYPERKEY_CONFIG"],
           !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/omaccy/hyperkey.toml")
    }

    static func load() -> Configuration {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return Configuration(escapeOnTap: false, bindings: [:])
        }

        var configuration = Configuration(escapeOnTap: false, bindings: [:])
        var section = ""

        for rawLine in contents.split(whereSeparator: \.isNewline) {
            // omittingEmptySubsequences would drop the empty piece before a
            // leading '#', turning a commented-out setting into a live one.
            let line = rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
                .first?.trimmingCharacters(in: .whitespaces) ?? ""
            guard !line.isEmpty else { continue }

            if line.hasPrefix("["), line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast()).lowercased()
                continue
            }

            let parts = line.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2 else { continue }

            let key = parts[0].lowercased()
            let value = unquote(parts[1])
            if section == "bindings" {
                configuration.bindings[key] = value
            } else if key == "escape_on_tap" {
                configuration.escapeOnTap = value.lowercased() == "true"
            } else if key == "clipboard_history", section.isEmpty {
                configuration.clipboardHistory = value.lowercased() != "false"
            } else if key == "clipboard_persist", section.isEmpty {
                configuration.clipboardPersist = value.lowercased() == "true"
            } else if key == "clipboard_limit", section.isEmpty {
                configuration.clipboardLimit = Int(value) ?? configuration.clipboardLimit
            } else if key == "trackpad_swipe", section.isEmpty {
                configuration.trackpadSwipe = value.lowercased() != "false"
            } else if key == "trackpad_swipe_natural", section.isEmpty {
                configuration.trackpadSwipeNatural = value.lowercased() != "false"
            } else if key == "default_layout", section.isEmpty {
                configuration.defaultLayout = WorkspaceLayout(rawValue: value.lowercased()) ?? .fallback
            } else if key == "launchie_command_space", section.isEmpty {
                configuration.launchieCommandSpace = value.lowercased() == "true"
            } else if key == "default_agent", section.isEmpty {
                configuration.defaultAgent = value.isEmpty ? nil : value
            } else if section.isEmpty,
                      let collection = AppCollection.allCases.first(where: { $0.configKey == key }) {
                configuration[collection] = value.isEmpty ? nil : value
            }
        }
        return configuration
    }

    func save() {
        let destination = Self.fileURL.resolvingSymlinksInPath()
        var contents = "# Send Escape when Caps Lock is tapped without another key.\n"
        contents += "escape_on_tap = \(escapeOnTap)\n"
        contents += "\n# Record what you copy, browsable in the launcher.\n"
        contents += "clipboard_history = \(clipboardHistory)\n"
        contents += "# Keep that history in ~/.omaccy/clipboard across restarts.\n"
        contents += "clipboard_persist = \(clipboardPersist)\n"
        contents += "# How many entries to keep.\n"
        contents += "clipboard_limit = \(clipboardLimit)\n"
        contents += "\n# Switch workspaces with a three-finger horizontal swipe.\n"
        contents += "trackpad_swipe = \(trackpadSwipe)\n"
        contents += "# Off sends the workspace the opposite way.\n"
        contents += "trackpad_swipe_natural = \(trackpadSwipeNatural)\n"
        contents += "\n# Layout of a workspace not yet set: horizontal, vertical, grid, or accordion.\n"
        contents += "default_layout = \"\(defaultLayout.rawValue)\"\n"
        contents += "\n# Open Launchie with Command+Space instead of Spotlight.\n"
        contents += "launchie_command_space = \(launchieCommandSpace)\n"
        if let defaultAgent {
            contents += "\n# Coding agent launched directly by Hyper+A.\n"
            contents += "default_agent = \"\(defaultAgent)\"\n"
        }
        for collection in AppCollection.allCases {
            guard let choice = self[collection] else { continue }
            contents += "\n# \(collection.itemLabel) launched directly by Hyper+\(collection.chord).\n"
            contents += "\(collection.configKey) = \"\(choice)\"\n"
        }
        if !bindings.isEmpty {
            contents += "\n# Launch-or-focus application bundle identifiers.\n[bindings]\n"
            for key in bindings.keys.sorted() {
                let value = bindings[key] ?? ""
                contents += "\(key) = \"\(value)\"\n"
            }
        }

        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: destination, atomically: true, encoding: .utf8)
        } catch {
            fputs("omaccy-hyperkey: could not save config: \(error)\n", stderr)
        }
    }
}

private func unquote(_ value: String) -> String {
    guard value.count >= 2,
          let first = value.first,
          let last = value.last,
          (first == "\"" && last == "\"") || (first == "'" && last == "'") else {
        return value
    }
    return String(value.dropFirst().dropLast())
}
