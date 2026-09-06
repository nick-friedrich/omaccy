import AppKit

/// Coding agents offered by the Agents collection: terminal agents run inside
/// herdr in Ghostty, desktop agents are regular macOS apps launched by bundle ID.
enum CodingAgent: String, CaseIterable, Sendable {
    case claudeCode = "claude-code"
    case codexCLI = "codex"
    case opencode = "opencode"
    case claudeDesktop = "claude-desktop"
    case chatGPTDesktop = "chatgpt-desktop"
    case t3Code = "t3-code"

    enum Kind: Sendable { case terminal, desktop }

    var kind: Kind {
        switch self {
        case .claudeCode, .codexCLI, .opencode: return .terminal
        case .claudeDesktop, .chatGPTDesktop, .t3Code: return .desktop
        }
    }

    var title: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codexCLI: return "Codex CLI"
        case .opencode: return "opencode"
        case .claudeDesktop: return "Claude"
        case .chatGPTDesktop: return "ChatGPT"
        case .t3Code: return "T3 Code"
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
        case .claudeDesktop, .chatGPTDesktop, .t3Code: return nil
        }
    }

    /// macOS bundle identifier. Desktop agents only.
    var bundleID: String? {
        switch self {
        case .claudeDesktop: return "com.anthropic.claudefordesktop"
        case .chatGPTDesktop: return "com.openai.codex"
        case .t3Code: return "com.t3tools.t3code"
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
            return ["/opt/homebrew/bin/\(binaryName)", "/usr/local/bin/\(binaryName)"]
                .contains { FileManager.default.isExecutableFile(atPath: $0) }
        case .desktop:
            guard let bundleID else { return false }
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
        }
    }

    static var herdrInstalled: Bool {
        ["/opt/homebrew/bin/herdr", "/usr/local/bin/herdr"]
            .contains { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
