import Foundation

public enum AccountState: Equatable {
    case signedOut
    case signedIn(AccountUser)
    case error(String)
}

public enum TokenPollResult: Equatable {
    case pending
    case slowDown
    case authorized(TokenResponse)
}

/// Manages the account session: device authorization, Keychain token storage,
/// installation registration, and the current account.
///
/// The tracker never depends on this service. Signing out simply removes the
/// account view; writing continues to be tracked locally.
public final class AccountService: @unchecked Sendable {
    private let api: APIClient
    private let installation: InstallationIdentity
    private let secrets: SecretStoring
    private let configuration: PlatformConfiguration
    private let lock = NSLock()

    private let tokenKey = "api-token"

    private var _state: AccountState = .signedOut
    public var onStateChange: ((AccountState) -> Void)?

    public init(
        configuration: PlatformConfiguration,
        transport: HTTPTransport,
        secrets: SecretStoring = KeychainSecretStore()
    ) {
        self.configuration = configuration
        self.api = APIClient(configuration: configuration, transport: transport)
        self.installation = InstallationIdentity(store: secrets)
        self.secrets = secrets
    }

    public var state: AccountState {
        lock.lock(); defer { lock.unlock() }
        return _state
    }

    public var isSignedIn: Bool {
        if case .signedIn = state { return true }
        return false
    }

    public var installationID: UUID? {
        try? installation.installationID()
    }

    private func setState(_ newState: AccountState) {
        lock.lock()
        _state = newState
        lock.unlock()
        onStateChange?(newState)
    }

    /// Restores a stored session on launch, if the token still works.
    @discardableResult
    public func restoreSession() async -> Bool {
        guard let token = try? secrets.string(for: tokenKey), !token.isEmpty else {
            return false
        }
        api.authToken = token
        do {
            let response: MeResponse = try await api.get("/v1/me", as: MeResponse.self)
            setState(.signedIn(response.user))
            await ensureInstallationRegistered()
            return true
        } catch {
            try? secrets.remove(tokenKey)
            api.authToken = nil
            setState(.signedOut)
            return false
        }
    }

    public func beginSignIn() async throws -> DeviceAuthorization {
        try await api.post(
            "/v1/auth/device/start",
            json: ["client_name": "Yakitori for Mac"],
            as: DeviceAuthorization.self
        )
    }

    public func pollForToken(_ authorization: DeviceAuthorization) async throws -> TokenPollResult {
        do {
            let response: TokenResponse = try await api.post(
                "/v1/auth/device/token",
                json: [
                    "device_code": authorization.deviceCode,
                    "client_name": "Yakitori for Mac",
                ],
                as: TokenResponse.self
            )
            return .authorized(response)
        } catch let error as APIError {
            switch error.code {
            case "authorization_pending":
                return .pending
            case "slow_down", "rate_limited":
                return .slowDown
            default:
                // A 429 without a structured code still means "back off".
                if error.statusCode == 429 { return .slowDown }
                throw error
            }
        }
    }

    /// Stores the token, loads the account, and registers the installation.
    public func completeSignIn(token: String) async throws {
        try secrets.set(token, for: tokenKey)
        api.authToken = token
        let response: MeResponse = try await api.get("/v1/me", as: MeResponse.self)
        setState(.signedIn(response.user))
        await ensureInstallationRegistered()
    }

    /// Registers this installation. Best-effort: a failure does not sign out.
    public func ensureInstallationRegistered() async {
        do {
            let id = try installation.installationID()
            let response: InstallationRegistration = try await api.post(
                "/v1/me/installations",
                json: [
                    "installation_id": id.uuidString,
                    "platform": "macOS",
                    "app_version": configuration.appVersion,
                ],
                as: InstallationRegistration.self
            )
            Log.account.debug(
                "installation registered: \(response.installation.installationId, privacy: .private)"
            )
        } catch {
            Log.account.error("installation registration failed")
        }
    }

    public func refreshAccount() async {
        do {
            let response: MeResponse = try await api.get("/v1/me", as: MeResponse.self)
            setState(.signedIn(response.user))
        } catch let error as APIError {
            if error.statusCode == 401 {
                try? secrets.remove(tokenKey)
                api.authToken = nil
                setState(.signedOut)
            } else {
                setState(.error(error.message))
            }
        } catch {
            setState(.error(error.localizedDescription))
        }
    }

    /// Revokes the token server-side (best effort) and clears it locally.
    public func signOut() async {
        if api.authToken != nil {
            _ = try? await api.perform(method: "DELETE", path: "/v1/me/tokens/current")
        }
        try? secrets.remove(tokenKey)
        api.authToken = nil
        setState(.signedOut)
    }
}
