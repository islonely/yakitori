import Foundation

public struct LicenseSnapshot: Equatable, Sendable {
    public let product: String
    public let licenseType: String
    public let status: String
    /// The offline grace deadline. Lifetime licenses have no expiry.
    public let offlineGraceUntil: Date?
    /// True when this snapshot came from a cached authorization, not a server check.
    public let verifiedOffline: Bool
}

public enum LicensingState: Equatable {
    case signedOut
    case checking
    case active(LicenseSnapshot)
    case grace(LicenseSnapshot)
    case invalid(reason: String)
    case unavailable(reason: String)
    case clockAnomaly

    public var isUsable: Bool {
        switch self {
        case .active, .grace: return true
        default: return false
        }
    }
}

public enum CachedEvaluation: Equatable {
    case none
    case clockAnomaly
    case snapshot(LicenseSnapshot)
}

/// Validates the account's license online and keeps a signed authorization for
/// offline use.
///
/// A server outage is never treated as revocation. An explicit server-side
/// revocation overrides the cache the next time the app can reach the server.
public final class LicensingService: @unchecked Sendable {
    private let api: APIClient
    private let installation: InstallationIdentity
    private let secrets: SecretStoring
    private let configuration: PlatformConfiguration
    private let dateProvider: DateProviding
    private let lock = NSLock()

    private let authorizationKey = "license-authorization"
    private let lastSeenKey = "license-last-seen"

    /// Tolerance before a clock is considered rolled back.
    private let clockTolerance: TimeInterval = 60

    private var _state: LicensingState = .signedOut
    public var onStateChange: ((LicensingState) -> Void)?

    public init(
        configuration: PlatformConfiguration,
        transport: HTTPTransport,
        secrets: SecretStoring = KeychainSecretStore(),
        dateProvider: DateProviding = SystemDateProvider()
    ) {
        self.configuration = configuration
        self.api = APIClient(configuration: configuration, transport: transport)
        self.installation = InstallationIdentity(store: secrets)
        self.secrets = secrets
        self.dateProvider = dateProvider
    }

    public var state: LicensingState {
        lock.lock(); defer { lock.unlock() }
        return _state
    }

    private func setState(_ newState: LicensingState) {
        lock.lock()
        _state = newState
        lock.unlock()
        onStateChange?(newState)
    }

    public func setSignedIn(_ signedIn: Bool) async {
        if !signedIn {
            clearCache()
            setState(.signedOut)
        }
    }

    /// Validates online. Falls back to the cached authorization when the server
    /// cannot be reached; an explicit "invalid" response always wins.
    public func refresh() async {
        setState(.checking)

        guard let installationID = try? installation.installationID() else {
            setState(.invalid(reason: "installation_unavailable"))
            return
        }

        do {
            let response: LicenseValidation = try await api.post(
                "/v1/me/license/validate",
                json: ["installation_id": installationID.uuidString],
                as: LicenseValidation.self
            )

            if response.valid, let authorization = response.authorization,
               let license = response.license {
                try? secrets.set(authorization, for: authorizationKey)
                recordLastSeen()
                let claims = try? LicenseVerifier.verify(
                    token: authorization,
                    trustedKeys: configuration.trustedLicenseKeys
                )
                let snapshot = LicenseSnapshot(
                    product: license.product,
                    licenseType: license.licenseType,
                    status: license.status,
                    offlineGraceUntil: claims?.expiresAt,
                    verifiedOffline: false
                )
                setState(.active(snapshot))
            } else {
                // Server says no: this overrides any cached authorization.
                clearCache()
                setState(.invalid(reason: response.reason ?? "not_valid"))
            }
        } catch let error as APIError where error.isNetworkFailure {
            applyOfflineFallback()
        } catch {
            applyOfflineFallback()
        }
    }

    private func applyOfflineFallback() {
        switch evaluateCached() {
        case .snapshot(let snapshot):
            setState(.grace(snapshot))
        case .clockAnomaly:
            setState(.clockAnomaly)
        case .none:
            setState(.unavailable(reason: "offline"))
        }
    }

    /// Verifies the cached authorization without contacting the server.
    public func evaluateCached() -> CachedEvaluation {
        guard let token = try? secrets.string(for: authorizationKey), !token.isEmpty,
              let claims = try? LicenseVerifier.verify(
                  token: token,
                  trustedKeys: configuration.trustedLicenseKeys
              )
        else {
            return .none
        }

        let now = dateProvider.now

        if let lastSeen = lastSeenDate(), now.addingTimeInterval(clockTolerance) < lastSeen {
            return .clockAnomaly
        }
        if now.addingTimeInterval(clockTolerance) < claims.issuedAt {
            return .clockAnomaly
        }
        guard now <= claims.expiresAt else {
            return .none
        }

        return .snapshot(
            LicenseSnapshot(
                product: claims.product,
                licenseType: claims.licenseType,
                status: claims.status,
                offlineGraceUntil: claims.expiresAt,
                verifiedOffline: true
            )
        )
    }

    public func clearCache() {
        try? secrets.remove(authorizationKey)
        try? secrets.remove(lastSeenKey)
    }

    private func recordLastSeen() {
        let value = String(dateProvider.now.timeIntervalSince1970)
        try? secrets.set(value, for: lastSeenKey)
    }

    private func lastSeenDate() -> Date? {
        guard let raw = try? secrets.string(for: lastSeenKey),
              let interval = TimeInterval(raw)
        else {
            return nil
        }
        return Date(timeIntervalSince1970: interval)
    }
}
