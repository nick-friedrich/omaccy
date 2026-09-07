import AppKit

/// Where a collection app comes from when it is not installed yet.
enum AppSource: Sendable, Equatable {
    /// Ships with macOS; there is nothing to install.
    case bundled
    /// A Homebrew cask token, optionally tap-qualified.
    case homebrew(token: String)
    /// A Mac App Store item that Homebrew does not carry.
    case appStore(id: String)
}

/// One interchangeable app in a picker collection (Mail, Editors).
///
/// Unlike `CodingAgent`, these are always ordinary GUI apps, so a choice names
/// the bundle it installs as and resolves the real bundle identifier from disk
/// instead of hardcoding one: an identifier we never build ourselves would rot
/// silently whenever a vendor changed it, and a wrong one breaks both launching
/// and installed-detection with no visible cause.
struct AppChoice: Sendable, Equatable {
    /// Stable token written to `hyperkey.toml`; independent of the app's name.
    let id: String
    let title: String
    /// The bundle Homebrew (or the App Store) installs, e.g. `Cursor.app`.
    let appName: String
    let summary: String
    let source: AppSource

    /// The standard locations casks and the App Store install into, matching
    /// the roots the Apps collection already indexes.
    private static let roots = ["/Applications", "/System/Applications",
                                NSHomeDirectory() + "/Applications"]

    var installedURL: URL? {
        Self.roots.lazy.map { URL(fileURLWithPath: $0).appendingPathComponent(appName) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    var isInstalled: Bool { installedURL != nil }

    var bundleID: String? { installedURL.flatMap { Bundle(url: $0)?.bundleIdentifier } }

    /// The Homebrew install this choice needs, or nil when it is bundled with
    /// macOS or only sold through the App Store.
    var package: HomebrewPackage? {
        guard case let .homebrew(token) = source else { return nil }
        return HomebrewPackage(token: token, name: title, description: summary, kind: .cask)
    }

    /// Opens the App Store app directly rather than a web page, so the user
    /// lands on the install button instead of a browser redirect.
    var appStoreURL: URL? {
        guard case let .appStore(id) = source else { return nil }
        return URL(string: "macappstore://apps.apple.com/app/id\(id)")
    }

    /// How the row's action reads when the app is missing.
    var installLabel: String? {
        switch source {
        case .bundled: return nil
        case .homebrew: return "Installs via Homebrew"
        case .appStore: return "Mac App Store"
        }
    }
}

/// A collection of interchangeable apps with one user-chosen default, opened by
/// its own Hyper chord. Mail and Editors share this; coding agents keep their
/// own type because terminal agents run inside herdr rather than launching as
/// plain apps.
enum AppCollection: String, CaseIterable, Sendable {
    case mail
    case editors

    var page: MenuPage {
        switch self {
        case .mail: return .mail
        case .editors: return .editors
        }
    }

    var title: String { page.rawValue }

    /// The letter that launches this collection's default app, and with Shift
    /// opens the collection itself.
    var chord: String {
        switch self {
        case .mail: return "E"
        case .editors: return "C"
        }
    }

    var itemLabel: String {
        switch self {
        case .mail: return "Mail client"
        case .editors: return "Code editor"
        }
    }

    var summary: String {
        switch self {
        case .mail: return "Launch your mail client or pick a different one"
        case .editors: return "Launch your code editor or pick a different one"
        }
    }

    var symbol: String {
        switch self {
        case .mail: return "envelope"
        case .editors: return "chevron.left.forwardslash.chevron.right"
        }
    }

    /// The `hyperkey.toml` key holding the chosen default.
    var configKey: String {
        switch self {
        case .mail: return "default_mail"
        case .editors: return "default_editor"
        }
    }

    var choices: [AppChoice] {
        switch self {
        case .mail: return Self.mailChoices
        case .editors: return Self.editorChoices
        }
    }

    func choice(id: String) -> AppChoice? { choices.first { $0.id == id } }

    // Cask tokens and bundle names below were read from Homebrew's own cask
    // metadata; `spark` in particular now resolves to the `spark-app` token.
    private static let mailChoices = [
        AppChoice(id: "emzero", title: "Emzero", appName: "Emzero.app",
                  summary: "Private, multi-account desktop mail",
                  source: .homebrew(token: "nick-friedrich/tap/emzero")),
        AppChoice(id: "apple-mail", title: "Mail", appName: "Mail.app",
                  summary: "Built into macOS", source: .bundled),
        AppChoice(id: "mimestream", title: "Mimestream", appName: "Mimestream.app",
                  summary: "Native Gmail client", source: .homebrew(token: "mimestream")),
        AppChoice(id: "thunderbird", title: "Thunderbird", appName: "Thunderbird.app",
                  summary: "Open-source mail, calendar, and chat",
                  source: .homebrew(token: "thunderbird")),
        AppChoice(id: "proton-mail", title: "Proton Mail", appName: "Proton Mail.app",
                  summary: "End-to-end encrypted mail", source: .homebrew(token: "proton-mail")),
        AppChoice(id: "spark", title: "Spark", appName: "Spark.app",
                  summary: "Shared inboxes and triage", source: .homebrew(token: "spark-app")),
        AppChoice(id: "outlook", title: "Microsoft Outlook", appName: "Microsoft Outlook.app",
                  summary: "Mail and calendar for Microsoft 365",
                  source: .homebrew(token: "microsoft-outlook")),
    ]

    private static let editorChoices = [
        AppChoice(id: "cursor", title: "Cursor", appName: "Cursor.app",
                  summary: "AI-first editor built on VS Code", source: .homebrew(token: "cursor")),
        AppChoice(id: "zed", title: "Zed", appName: "Zed.app",
                  summary: "High-performance collaborative editor", source: .homebrew(token: "zed")),
        AppChoice(id: "vscode", title: "Visual Studio Code", appName: "Visual Studio Code.app",
                  summary: "Microsoft's extensible editor",
                  source: .homebrew(token: "visual-studio-code")),
        // Apple ships Xcode only through the App Store; Homebrew has no cask.
        AppChoice(id: "xcode", title: "Xcode", appName: "Xcode.app",
                  summary: "Apple's IDE for macOS and iOS", source: .appStore(id: "497799835")),
        AppChoice(id: "sublime-text", title: "Sublime Text", appName: "Sublime Text.app",
                  summary: "Fast native text editor", source: .homebrew(token: "sublime-text")),
        AppChoice(id: "intellij-idea", title: "IntelliJ IDEA", appName: "IntelliJ IDEA.app",
                  summary: "JetBrains IDE for the JVM and more",
                  source: .homebrew(token: "intellij-idea")),
        AppChoice(id: "nova", title: "Nova", appName: "Nova.app",
                  summary: "Panic's native Mac editor", source: .homebrew(token: "nova")),
    ]
}
