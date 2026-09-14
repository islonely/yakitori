import Foundation

/// The authenticated account as returned by `/v1/me`.
public struct AccountUser: Codable, Equatable, Sendable {
    public let id: String
    public let email: String
    public let status: String
    public let emailVerified: Bool
    public let createdAt: String?

    public init(
        id: String,
        email: String,
        status: String,
        emailVerified: Bool,
        createdAt: String? = nil
    ) {
        self.id = id
        self.email = email
        self.status = status
        self.emailVerified = emailVerified
        self.createdAt = createdAt
    }
}

public struct MeResponse: Codable, Sendable {
    public let user: AccountUser

    public init(user: AccountUser) {
        self.user = user
    }
}

public struct DeviceAuthorization: Codable, Equatable, Sendable {
    public let deviceCode: String
    public let userCode: String
    public let verificationUri: String
    public let verificationUriComplete: String?
    public let expiresIn: Int
    public let interval: Int

    public init(
        deviceCode: String,
        userCode: String,
        verificationUri: String,
        verificationUriComplete: String?,
        expiresIn: Int,
        interval: Int
    ) {
        self.deviceCode = deviceCode
        self.userCode = userCode
        self.verificationUri = verificationUri
        self.verificationUriComplete = verificationUriComplete
        self.expiresIn = expiresIn
        self.interval = interval
    }
}

public struct TokenResponse: Codable, Equatable, Sendable {
    public let token: String
    public let tokenType: String
    public let expiresIn: Int?

    public init(token: String, tokenType: String, expiresIn: Int?) {
        self.token = token
        self.tokenType = tokenType
        self.expiresIn = expiresIn
    }
}

public struct LicenseInfo: Codable, Equatable, Sendable {
    public let id: String
    public let product: String
    public let licenseType: String
    public let status: String
    public let purchasedAt: String?
    public let expiresAt: String?

    public init(
        id: String,
        product: String,
        licenseType: String,
        status: String,
        purchasedAt: String? = nil,
        expiresAt: String? = nil
    ) {
        self.id = id
        self.product = product
        self.licenseType = licenseType
        self.status = status
        self.purchasedAt = purchasedAt
        self.expiresAt = expiresAt
    }
}

public struct LicenseValidation: Codable, Equatable, Sendable {
    public let valid: Bool
    public let reason: String?
    public let authorization: String?
    public let offlineGraceDays: Int?
    public let license: LicenseInfo?

    public init(
        valid: Bool,
        reason: String? = nil,
        authorization: String? = nil,
        offlineGraceDays: Int? = nil,
        license: LicenseInfo? = nil
    ) {
        self.valid = valid
        self.reason = reason
        self.authorization = authorization
        self.offlineGraceDays = offlineGraceDays
        self.license = license
    }
}

public struct InstallationInfo: Codable, Equatable, Sendable {
    public let installationId: String
    public let platform: String
    public let appVersion: String
    public let firstSeenAt: String
    public let lastSeenAt: String
    public let revoked: Bool
}

public struct InstallationRegistration: Codable, Equatable, Sendable {
    public let installation: InstallationInfo
    public let created: Bool
}
