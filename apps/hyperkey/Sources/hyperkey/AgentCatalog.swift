import AppKit

/// Coding agents offered by the Agents collection: terminal agents run inside
/// herdr in Ghostty, desktop agents are regular macOS apps launched by bundle ID.
enum CodingAgent: String, CaseIterable, Sendable {
    case claudeDesktop = "claude-desktop"
    case chatGPTDesktop = "chatgpt-desktop"
    case t3Code = "t3-code"
    case opencodeDesktop = "opencode-desktop"
    case claudeCode = "claude-code"
    case codexCLI = "codex"
    case opencode = "opencode"

    enum Kind: Sendable { case terminal, desktop }

    var kind: Kind {
        switch self {
        case .claudeCode, .codexCLI, .opencode: return .terminal
        case .claudeDesktop, .chatGPTDesktop, .t3Code, .opencodeDesktop: return .desktop
        }
    }

    var title: String {
        switch self {
        case .claudeDesktop: return "Claude"
        case .chatGPTDesktop: return "ChatGPT"
        case .t3Code: return "T3 Code"
        case .opencodeDesktop: return "OpenCode Desktop"
        case .claudeCode: return "Claude Code"
        case .codexCLI: return "Codex CLI"
        case .opencode: return "opencode"
        }
    }

    var symbol: String {
        kind == .terminal ? "terminal" : "bubble.left.and.text.bubble.right"
    }

    /// The binary herdr runs in a new pane. Terminal agents only.
    var binaryName: String? {
        switch self {
        case .claudeCode: return "claude"
        case .codexCLI: return "codex"
        case .opencode: return "opencode"
        case .claudeDesktop, .chatGPTDesktop, .t3Code, .opencodeDesktop: return nil
        }
    }

    /// macOS bundle identifier. Desktop agents only.
    var bundleID: String? {
        switch self {
        case .claudeDesktop: return "com.anthropic.claudefordesktop"
        case .chatGPTDesktop: return "com.openai.codex"
        case .t3Code: return "com.t3tools.t3code"
        case .opencodeDesktop: return "ai.opencode.desktop"
        case .claudeCode, .codexCLI, .opencode: return nil
        }
    }

    /// The real Homebrew token, distinct from this case's config identity above.
    var brewToken: String {
        switch self {
        case .claudeCode: return "claude-code"
        case .codexCLI: return "codex"
        case .opencode: return "opencode"
        case .claudeDesktop: return "claude"
        case .chatGPTDesktop: return "chatgpt"
        case .t3Code: return "t3-code"
        case .opencodeDesktop: return "opencode-desktop"
        }
    }

    var brewKind: HomebrewPackage.Kind { self == .opencode ? .formula : .cask }

    var detail: String {
        kind == .terminal ? "Terminal agent · runs in herdr" : "Desktop app"
    }

    var isInstalled: Bool {
        switch kind {
        case .terminal:
            guard let binaryName else { return false }
            return Self.executableURL(binaryName) != nil
        case .desktop:
            guard let bundleID else { return false }
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
        }
    }

    static func executableURL(_ name: String) -> URL? {
        ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map(URL.init(fileURLWithPath:))
    }

    static var herdrExecutableURL: URL? { executableURL("herdr") }
    static var herdrInstalled: Bool { herdrExecutableURL != nil }
}

/// Talks to herdr's single default session (the one `brew services start herdr`
/// keeps running as a real daemon, surviving terminal closures and logins) over
/// its CLI/socket API. Each terminal agent kind gets one labeled workspace in
/// that shared session — matching herdr's own "one persistent session, many
/// workspaces" design — rather than a separate named session per agent, which
/// would need its own service supervision to survive a closed Ghostty window.
enum HerdrBridge {
    /// The workspace ID currently hosting a live agent named `binary`, if any.
    /// Agent names are fixed to the binary name (one agent per kind, at most).
    static func runningWorkspaceID(for binary: String) -> String? {
        guard let herdr = CodingAgent.herdrExecutableURL,
              let result = HotkeyBindings.run(herdr, arguments: ["agent", "get", binary], timeout: 1.5),
              result.status == 0, result.output.contains("\"agent\":\"\(binary)\"") else { return nil }
        return field("workspace_id", in: result.output)
    }

    static func focusWorkspace(_ id: String) {
        guard let herdr = CodingAgent.herdrExecutableURL else { return }
        _ = HotkeyBindings.run(herdr, arguments: ["workspace", "focus", id], timeout: 1.5)
    }

    /// Ensures herdr's shared default-session daemon is running, creates a
    /// freshly labeled workspace for `binary`, and starts that agent kind in
    /// it. Entirely headless — none of this needs a real terminal, only the
    /// final reveal (attaching Ghostty) does — so callers can decide whether a
    /// window is even needed only after this returns. Only called once the
    /// caller has confirmed herdr and the binary are already installed.
    static func provisionWorkspace(binary: String) -> String? {
        guard let herdr = CodingAgent.herdrExecutableURL else { return nil }
        if let brew = HomebrewInventory.executable {
            _ = HotkeyBindings.run(URL(fileURLWithPath: brew), arguments: ["services", "start", "herdr"], timeout: 10)
        }
        guard let created = HotkeyBindings.run(herdr, arguments: ["workspace", "create", "--label", binary, "--cwd", NSHomeDirectory()], timeout: 5)?.output,
              let workspaceID = field("workspace_id", in: created), let pane = field("pane_id", in: created) else { return nil }
        for _ in 0..<12 {
            if HotkeyBindings.run(herdr, arguments: ["agent", "start", binary, "--kind", binary, "--pane", pane], timeout: 2)?.status == 0 { break }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return workspaceID
    }

    /// Extracts `"key":"value"` from herdr's single-line JSON output. Good
    /// enough for our fixed, known response shapes without a JSON dependency.
    static func field(_ key: String, in json: String) -> String? {
        guard let range = json.range(of: "\"\(key)\":\"") else { return nil }
        let value = json[range.upperBound...].prefix { $0 != "\"" }
        return value.isEmpty ? nil : String(value)
    }
}
