import Foundation

/// The layout modes `config/aerospace/layout.sh` knows. Raw values are the
/// script's own mode names, which is what `default_layout` holds; titles are
/// the names the menu bar shows for them.
enum WorkspaceLayout: String, Sendable, CaseIterable {
    case horizontal, vertical, grid, accordion

    var title: String {
        switch self {
        case .horizontal: return "Columns"
        case .vertical: return "Rows"
        case .grid: return "Grid"
        case .accordion: return "Accordion"
        }
    }

    var summary: String {
        switch self {
        case .horizontal: return "Every window a full-height column, side by side"
        case .vertical: return "Every window full width, stacked top to bottom"
        case .grid: return "Windows squared off, four make a 2×2"
        case .accordion: return "One window at a time, the rest collapsed to the edge"
        }
    }

    var symbol: String {
        switch self {
        case .horizontal: return "rectangle.split.3x1"
        case .vertical: return "rectangle.split.1x2"
        case .grid: return "rectangle.split.2x2"
        case .accordion: return "rectangle.stack"
        }
    }

    /// What a workspace nobody has set falls back to, in the script as here.
    static let fallback = WorkspaceLayout.horizontal

    /// The bar shows the focused workspace's mode, and only re-reads it on
    /// this event or its five-second poll; nudging it makes a new default on
    /// an unset workspace show at once. Fails quietly without SketchyBar.
    static func refreshBar() {
        DispatchQueue.global(qos: .utility).async {
            guard let sketchybar = ["/opt/homebrew/bin/sketchybar", "/usr/local/bin/sketchybar"].first(where: {
                FileManager.default.isExecutableFile(atPath: $0)
            }) else { return }
            _ = HotkeyBindings.run(URL(fileURLWithPath: sketchybar),
                                   arguments: ["--trigger", "aerospace_workspace_change"], timeout: 5)
        }
    }
}
