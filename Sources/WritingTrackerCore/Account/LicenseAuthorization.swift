import CryptoKit
import Foundation

/// Decoded, verified claims from a signed license authorization.
public struct LicenseClaims: Equatable, Sendable {
    public let version: Int
    public let keyID: String
    public let subject: String
    public let licenseID: String
    public let product: String
    public let licenseType: String
    public let status: String
    public let installation: String
    public let issuedAt: Date
    public let revalidateAfter: Date
    /// The offline grace deadline, **not** a license expiry.
    public let expiresAt: Date
}

public enum LicenseVerificationError: Error, Equatable {
    case malformed
    case unsupportedAlgorithm(String)
    case unknownKey(String)
    case invalidSignature
    case unsupportedVersion(Int)
}

/// Verifies the server's Ed25519 authorization offline using an embedded public
/// key. The private key never exists in the app.
public enum LicenseVerifier {
    private struct Header: Decodable {
        let alg: String
        let kid: String
    }

    private struct Payload: Decodable {
        let v: Int
        let key: String
        let sub: String
        let lic: String
        let product: String
        let type: String
        let status: String
        let inst: String
        let iat: Int
        let revalidateAfter: Int
        let exp: Int

        enum CodingKeys: String, CodingKey {
            case v, key, sub, lic, product, type, status, inst, iat, exp
            case revalidateAfter = "revalidate_after"
        }
    }

    public static func verify(
        token: String,
        trustedKeys: [String: Data]
    ) throws -> LicenseClaims {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let headerData = Base64URL.decode(String(parts[0])),
              let payloadData = Base64URL.decode(String(parts[1])),
              let signature = Base64URL.decode(String(parts[2]))
        else {
            throw LicenseVerificationError.malformed
        }

        let header: Header
        let payload: Payload
        do {
            header = try JSONDecoder().decode(Header.self, from: headerData)
            payload = try JSONDecoder().decode(Payload.self, from: payloadData)
        } catch {
            throw LicenseVerificationError.malformed
        }

        guard header.alg == "Ed25519" else {
            throw LicenseVerificationError.unsupportedAlgorithm(header.alg)
        }
        guard let keyData = trustedKeys[header.kid] else {
            throw LicenseVerificationError.unknownKey(header.kid)
        }

        let publicKey: Curve25519.Signing.PublicKey
        do {
            publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        } catch {
            throw LicenseVerificationError.unknownKey(header.kid)
        }

        let signingInput = Data("\(parts[0]).\(parts[1])".utf8)
        guard publicKey.isValidSignature(signature, for: signingInput) else {
            throw LicenseVerificationError.invalidSignature
        }

        guard payload.v == 1 else {
            throw LicenseVerificationError.unsupportedVersion(payload.v)
        }

        return LicenseClaims(
            version: payload.v,
            keyID: header.kid,
            subject: payload.sub,
            licenseID: payload.lic,
            product: payload.product,
            licenseType: payload.type,
            status: payload.status,
            installation: payload.inst,
            issuedAt: Date(timeIntervalSince1970: TimeInterval(payload.iat)),
            revalidateAfter: Date(timeIntervalSince1970: TimeInterval(payload.revalidateAfter)),
            expiresAt: Date(timeIntervalSince1970: TimeInterval(payload.exp))
        )
    }
}
