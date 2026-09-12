import Foundation

/// Obsidian adapter. Vault/note detection would require UI scripting, which
/// needs Accessibility permission; it is tracked as focus/activity only for now.
public final class ObsidianAdapter: FocusOnlyAdapter {
    public init(bundleIdentifier: String = "md.obsidian") {
        super.init(bundleIdentifier: bundleIdentifier, adapterType: .obsidian)
    }
}
