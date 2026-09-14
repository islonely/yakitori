import Foundation

/// Where the app talks to the platform and which license signing keys it trusts.
///
/// Values come from `Info.plist` (`YakitoriAPIBaseURL` and
/// `YakitoriLicensePublicKeys`, the latter as `kid=base64url` pairs). A
/// development default is used when the keys are absent so local builds work
/// against a local server. The embedded key is a **public** key; the matching
/// private key exists only server-side.
public struct PlatformConfiguration: Sendable {
    public var apiBaseURL: URL
    public var trustedLicenseKeys: [String: Data]
    public var appVersion: String

    public init(
        apiBaseURL: URL,
        trustedLicenseKeys: [String: Data],
        appVersion: String = PlatformConfiguration.currentAppVersion
    ) {
        self.apiBaseURL = apiBaseURL
        self.trustedLicenseKeys = trustedLicenseKeys
        self.appVersion = appVersion
    }

    /// Development key id/public key. Replace in production builds via
    /// `YakitoriLicensePublicKeys`. Public keys are safe to embed.
    public static let developmentTrustedKeys: [String: Data] = {
        var keys: [String: Data] = [:]
        if let data = Base64URL.decode("yIVNZcgsOIueUc3v7xySdD_xNWuQgr0s3UQt6fopni0") {
            keys["dev-1"] = data
        }
        return keys
    }()

    public static var currentAppVersion: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String
        return version ?? "1.0.0"
    }

    public static func fromBundle(_ bundle: Bundle = .main) -> PlatformConfiguration {
        let rawURL = bundle.object(forInfoDictionaryKey: "YakitoriAPIBaseURL") as? String
        let baseURL = rawURL.flatMap(URL.init(string:))
            ?? URL(string: "http://localhost:8000")!

        let rawKeys = bundle.object(
            forInfoDictionaryKey: "YakitoriLicensePublicKeys"
        ) as? String
        let parsed = parseTrustedKeys(rawKeys)

        return PlatformConfiguration(
            apiBaseURL: baseURL,
            trustedLicenseKeys: parsed.isEmpty
                ? Self.developmentTrustedKeys
                : parsed
        )
    }

    /// Parses `kid=base64url,kid2=base64url`.
    static func parseTrustedKeys(_ raw: String?) -> [String: Data] {
        guard let raw, !raw.isEmpty else { return [:] }
        var keys: [String: Data] = [:]
        for pair in raw.split(separator: ",") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let kid = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
            if let data = Base64URL.decode(value) {
                keys[kid] = data
            }
        }
        return keys
    }
}
