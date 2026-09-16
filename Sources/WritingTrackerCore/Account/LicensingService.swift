import Foundation

public enum LicenseKind: String, Equatable, Sendable {
    case license
    case trial
}

public struct LicenseSnapshot: Equatable, Sendable {
    public let kind: LicenseKind
    public let product: String
    public let licenseType: String
    public let status: String
    /// Hard end of the entitlement (trial end). `nil` for a lifetime license.
    public let entitlementExpiresAt: Date?
    /// The offline grace deadline. Lifetime licenses have no expiry.
    public let offlineGraceUntil: Date?
    /// When the authorization should next be checked against the server.
    public let revalidateAfter: Date?
    /// True when this snapshot came from a cached authorization, not a server check.
    public let verifiedOffline: Bool

    public init(
        kind: LicenseKind,
        product: String,
        licenseType: String,
        status: String,
        entitlementExpiresAt: Date? = nil,
        offlineGraceUntil: Date? = nil,
        revalidateAfter: Date? = nil,
        verifiedOffline: Bool = false
    ) {
        self.kind = kind
        self.product = product
        self.licenseType = licenseType
        self.status = status
        self.entitlementExpiresAt = entitlementExpiresAt
        self.offlineGraceUntil = offlineGraceUntil
        self.revalidateAfter = revalidateAfter
        self.verifiedOffline = verifiedOffline
    }

    public var isTrial: Bool { kind == .trial }

    public var daysRemaining: Int? {
        guard let entitlementExpiresAt else { return nil }
        let seconds = entitlementExpiresAt.timeIntervalSinceNow
        return max(0, Int(ceil(seconds / 86_400)))
    }
}

public enum LicensingState: Equatable {
    case signedOut
    case checking
    case active(LicenseSnapshot)
    case trial(LicenseSnapshot)
    case grace(LicenseSnapshot)
    case invalid(reason: String)
    case unavailable(reason: String)
    case clockAnomaly

    /// Whether the app is allowed to record new sessions.
    public var isUsable: Bool {
        switch self {
        case .active, .trial, .grace: return true
        default: return false
        }
    }

    /// A transient validation in progress. Callers should keep the previous
    /// gate rather than treating this as "not entitled".
    public var isChecking: Bool {
        if case .checking = self { return true }
        return false
    }

    public var snapshot: LicenseSnapshot? {
        switch self {
        case .active(let value), .trial(let value), .grace(let value): return value
        default: return nil
        }
    }
}

public enum CachedEvaluation: Equatable {
    case none
    case clockAnomaly
    /// The cached authorization verified, but its entitlement has ended (a
    /// trial that ran out). Distinct from `none`, which means "no cache".
    case expired(reason: String)
    case snapshot(LicenseSnapshot)
}

/// Validates the account's license or trial online and keeps a signed
/// authorization for offline use.
///
/// A server outage is never treated as revocation. An explicit server-side
/// revocation overrides the cache the next time the app can reach the server.
public final class LicensingService: @unchecked Sendable {
    private let api: APIClient
    private let installation: InstallationIdentity
    private let secrets: SecretStoring
    private let configuration: PlatformConfiguration
    private let dateProvider: DateProviding
    private let machineIdentity: MachineIdentifying
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
        dateProvider: DateProviding = SystemDateProvider(),
        machineIdentity: MachineIdentifying = IOKitMachineIdentity()
    ) {
        self.configuration = configuration
        self.api = APIClient(configuration: configuration, transport: transport)
        self.installation = InstallationIdentity(store: secrets)
        self.secrets = secrets
        self.dateProvider = dateProvider
        self.machineIdentity = machineIdentity
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

        var body: [String: Any] = ["installation_id": installationID.uuidString]
        // A device-computed digest of the hardware UUID, sent only so a trial
        // can be limited to one per Mac. The raw UUID never leaves the device.
        if let machineDigest = machineIdentity.machineDigest() {
            body["machine_id"] = machineDigest
        }

        do {
            let response: LicenseValidation = try await api.post(
                "/v1/me/license/validate",
                json: body,
                as: LicenseValidation.self
            )

            if response.valid, let authorization = response.authorization {
                try? secrets.set(authorization, for: authorizationKey)
                recordLastSeen()

                let claims = try? LicenseVerifier.verify(
                    token: authorization,
                    trustedKeys: configuration.trustedLicenseKeys
                )
                // Reject an authorization that verifies to a trial but whose
                // entitlement has already ended.
                if let claims, claims.entitlementExpiresAt != nil,
                   dateProvider.now > claims.entitlementExpiresAt! {
                    clearCache()
                    setState(.invalid(reason: "trial_expired"))
                    return
                }

                let kind: LicenseKind = response.kind == "trial" ? .trial : .license
                let snapshot = makeSnapshot(
                    kind: kind,
                    response: response,
                    claims: claims,
                    verifiedOffline: false
                )
                setState(kind == .trial ? .trial(snapshot) : .active(snapshot))
            } else {
                // Server says no: this overrides any cached authorization.
                clearCache()
                setState(.invalid(reason: response.reason ?? "not_valid"))
            }
        } catch let error as APIError where error.isNetworkFailure {
            applyCacheFallback(reason: "offline")
        } catch let error as APIError where error.statusCode == 401 || error.statusCode == 403 {
            // The stored API token is no longer valid (revoked, expired, or the
            // account was removed). This is not an offline condition; the app
            // should sign out and ask the user to sign in again.
            clearCache()
            setState(.invalid(reason: "session_expired"))
        } catch {
            // A reachable server returned an error. Keep any usable cache;
            // otherwise report a server problem rather than "offline".
            applyCacheFallback(reason: "server_error")
        }
    }

    private func makeSnapshot(
        kind: LicenseKind,
        response: LicenseValidation?,
        claims: LicenseClaims?,
        verifiedOffline: Bool
    ) -> LicenseSnapshot {
        LicenseSnapshot(
            kind: kind,
            product: response?.license?.product ?? claims?.product ?? "Yakitori",
            licenseType: response?.license?.licenseType
                ?? claims?.licenseType
                ?? kind.rawValue,
            status: response?.license?.status ?? claims?.status ?? "active",
            entitlementExpiresAt: claims?.entitlementExpiresAt,
            offlineGraceUntil: claims?.expiresAt,
            revalidateAfter: claims?.revalidateAfter,
            verifiedOffline: verifiedOffline
        )
    }

    /// Falls back to the cached authorization. `reason` is used only when there
    /// is no usable cache (for example `"offline"` or `"server_error"`).
    private func applyCacheFallback(reason: String) {
        switch evaluateCached() {
        case .snapshot(let snapshot):
            if snapshot.kind == .trial {
                setState(.trial(snapshot))
            } else {
                setState(.grace(snapshot))
            }
        case .expired(let reason):
            setState(.invalid(reason: reason))
        case .clockAnomaly:
            setState(.clockAnomaly)
        case .none:
            setState(.unavailable(reason: reason))
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

        let kind: LicenseKind = claims.licenseType == "trial" ? .trial : .license

        if let entitlementEnd = claims.entitlementExpiresAt {
            // Trial: the entitlement must still be running. Once it has passed,
            // this is a definitive expiry (not merely "offline"), so the app can
            // lock and stop any running session without contacting the server.
            guard now <= entitlementEnd else {
                return .expired(reason: "trial_expired")
            }
        } else {
            // Lifetime: bounded only by the offline grace deadline. Past it we
            // stay uncertain (the server may still consider the license valid),
            // so this is an "unavailable/offline" case, not a revocation.
            guard now <= claims.expiresAt else { return .none }
        }

        return .snapshot(
            LicenseSnapshot(
                kind: kind,
                product: claims.product,
                licenseType: claims.licenseType,
                status: claims.status,
                entitlementExpiresAt: claims.entitlementExpiresAt,
                offlineGraceUntil: claims.expiresAt,
                revalidateAfter: claims.revalidateAfter,
                verifiedOffline: true
            )
        )
    }

    /// When the app should next re-check entitlement with the server, or `nil`
    /// when there is nothing to schedule (signed out or definitively invalid).
    ///
    /// For a trial this is the trial end, so a running session is stopped
    /// promptly even if the app never talks to the server again.
    public func nextEvaluationDate(now: Date? = nil) -> Date? {
        let reference = now ?? dateProvider.now
        guard let snapshot = state.snapshot else { return nil }

        var candidates: [Date] = []
        if let revalidate = snapshot.revalidateAfter, revalidate > reference {
            candidates.append(revalidate)
        }
        if let entitlementEnd = snapshot.entitlementExpiresAt, entitlementEnd > reference {
            candidates.append(entitlementEnd)
        }
        return candidates.min()
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
