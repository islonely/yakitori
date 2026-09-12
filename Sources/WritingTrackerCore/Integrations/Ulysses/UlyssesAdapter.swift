import Foundation

/// Ulysses adapter. Ulysses does not expose a stable public scripting
/// interface for word counts, so it is tracked as focus/activity only.
public final class UlyssesAdapter: FocusOnlyAdapter {
    public init(bundleIdentifier: String = "com.ulyssesapp.mac") {
        super.init(bundleIdentifier: bundleIdentifier, adapterType: .ulysses)
    }
}
