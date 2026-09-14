import Foundation

/// The app's stable installation identity.
///
/// It is a random UUID created on first use and stored in the Keychain. It is
/// never derived from hardware identifiers, and losing it only means the app
/// registers a new installation (the license is unaffected).
public final class InstallationIdentity {
    private let store: SecretStoring
    private let key = "installation-id"

    public init(store: SecretStoring) {
        self.store = store
    }

    public func installationID() throws -> UUID {
        if let existing = try store.string(for: key),
           let uuid = UUID(uuidString: existing) {
            return uuid
        }
        let uuid = UUID()
        try store.set(uuid.uuidString, for: key)
        return uuid
    }
}
