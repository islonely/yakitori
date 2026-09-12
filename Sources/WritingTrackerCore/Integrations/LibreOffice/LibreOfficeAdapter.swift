import Foundation

/// LibreOffice adapter. Tracked as focus/activity only.
public final class LibreOfficeAdapter: FocusOnlyAdapter {
    public init(bundleIdentifier: String = "org.libreoffice.script") {
        super.init(bundleIdentifier: bundleIdentifier, adapterType: .libreOffice)
    }
}
