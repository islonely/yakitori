import Foundation

/// Scrivener adapter.
///
/// Scrivener exposes a `.scriv` project bundle. Because deep AppleScript support
/// varies between versions, this adapter tracks focus/activity reliably and
/// leaves document/word-count detection to a future enhancement rather than
/// inventing values.
public final class ScrivenerAdapter: FocusOnlyAdapter {
    public init(bundleIdentifier: String = "com.literatureandlatte.scrivener3") {
        super.init(bundleIdentifier: bundleIdentifier, adapterType: .scrivener)
    }
}
