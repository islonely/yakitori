import Foundation

/// Browser-based editor adapter (Google Docs, etc.).
///
/// Browser content is not exposed through a stable native API; reading the
/// active tab URL would require UI scripting. The adapter therefore tracks
/// focus/activity only and does not pretend to know word counts.
public final class BrowserDocumentAdapter: FocusOnlyAdapter {
    public init(bundleIdentifier: String = "com.apple.Safari") {
        super.init(bundleIdentifier: bundleIdentifier, adapterType: .browser)
    }
}
