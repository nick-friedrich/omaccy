import Foundation

struct Configuration {
    var escapeOnTap: Bool
    var bindings: [String: String]

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
            let line = rawLine.split(separator: "#", maxSplits: 1).first?
                .trimmingCharacters(in: .whitespaces) ?? ""
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
            }
        }
        return configuration
    }

    func save() {
        let destination = Self.fileURL.resolvingSymlinksInPath()
        var contents = "# Send Escape when Caps Lock is tapped without another key.\n"
        contents += "escape_on_tap = \(escapeOnTap)\n"
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
