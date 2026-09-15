import CryptoKit
import XCTest

@testable import WritingTrackerCore

/// A transport that replays queued responses and records requests.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    struct Route {
        let method: String
        let path: String
        let status: Int
        let body: Data
    }

    private let lock = NSLock()
    private var routes: [Route]
    private(set) var requests: [HTTPRequest] = []

    init(routes: [Route]) {
        self.routes = routes
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.lock()
        defer { lock.unlock() }

        requests.append(request)

        for index in routes.indices
        where routes[index].method == request.method
            && request.url.path.contains(routes[index].path) {
            let route = routes[index]
            routes.remove(at: index)
            return HTTPResponse(statusCode: route.status, data: route.body)
        }

        throw URLError(.notConnectedToInternet)
    }
}

enum TestJSON {
    static func data(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }
}

enum TestLicense {
    static func keyPair() -> Curve25519.Signing.PrivateKey {
        Curve25519.Signing.PrivateKey()
    }

    static func publicKeyData(_ key: Curve25519.Signing.PrivateKey) -> Data {
        key.publicKey.rawRepresentation
    }

    static func token(
        privateKey: Curve25519.Signing.PrivateKey,
        kid: String = "test-1",
        subject: String = "user-1",
        licenseID: String = "lic-1",
        product: String = "Yakitori",
        type: String = "lifetime",
        status: String = "active",
        installation: UUID,
        issuedAt: Date,
        revalidateAfter: Date,
        expiresAt: Date,
        entitlementExpiresAt: Date? = nil,
        version: Int = 1
    ) -> String {
        let header: [String: Any] = ["alg": "Ed25519", "kid": kid]
        var payload: [String: Any] = [
            "v": version,
            "key": kid,
            "sub": subject,
            "lic": licenseID,
            "product": product,
            "type": type,
            "status": status,
            "inst": installation.uuidString,
            "iat": Int(issuedAt.timeIntervalSince1970),
            "revalidate_after": Int(revalidateAfter.timeIntervalSince1970),
            "exp": Int(expiresAt.timeIntervalSince1970),
        ]
        payload["ent_exp"] = entitlementExpiresAt.map {
            Int($0.timeIntervalSince1970)
        } ?? NSNull()

        let headerPart = Base64URL.encode(TestJSON.data(header))
        let payloadPart = Base64URL.encode(TestJSON.data(payload))
        let signingInput = "\(headerPart).\(payloadPart)"
        let signature = try! privateKey.signature(for: Data(signingInput.utf8))
        return "\(signingInput).\(Base64URL.encode(signature))"
    }
}

final class LicenseVerifierTests: XCTestCase {
    func testVerifiesValidAuthorization() throws {
        let key = TestLicense.keyPair()
        let installation = UUID()
        let now = Date()
        let token = TestLicense.token(
            privateKey: key,
            installation: installation,
            issuedAt: now,
            revalidateAfter: now.addingTimeInterval(86_400),
            expiresAt: now.addingTimeInterval(30 * 86_400)
        )

        let claims = try LicenseVerifier.verify(
            token: token,
            trustedKeys: ["test-1": TestLicense.publicKeyData(key)]
        )
        XCTAssertEqual(claims.keyID, "test-1")
        XCTAssertEqual(claims.licenseType, "lifetime")
        XCTAssertEqual(claims.installation, installation.uuidString)
        XCTAssertEqual(claims.status, "active")
    }

    func testRejectsWrongKey() {
        let key = TestLicense.keyPair()
        let other = TestLicense.keyPair()
        let now = Date()
        let token = TestLicense.token(
            privateKey: key,
            installation: UUID(),
            issuedAt: now,
            revalidateAfter: now,
            expiresAt: now.addingTimeInterval(100)
        )

        XCTAssertThrowsError(
            try LicenseVerifier.verify(
                token: token,
                trustedKeys: ["test-1": TestLicense.publicKeyData(other)]
            )
        ) { error in
            XCTAssertEqual(error as? LicenseVerificationError, .invalidSignature)
        }
    }

    func testRejectsUnknownKeyID() {
        let key = TestLicense.keyPair()
        let now = Date()
        let token = TestLicense.token(
            privateKey: key,
            kid: "unknown",
            installation: UUID(),
            issuedAt: now,
            revalidateAfter: now,
            expiresAt: now.addingTimeInterval(100)
        )

        XCTAssertThrowsError(
            try LicenseVerifier.verify(
                token: token,
                trustedKeys: ["test-1": TestLicense.publicKeyData(key)]
            )
        ) { error in
            XCTAssertEqual(error as? LicenseVerificationError, .unknownKey("unknown"))
        }
    }

    func testRejectsTamperedPayload() {
        let key = TestLicense.keyPair()
        let now = Date()
        let token = TestLicense.token(
            privateKey: key,
            installation: UUID(),
            issuedAt: now,
            revalidateAfter: now,
            expiresAt: now.addingTimeInterval(100)
        )

        var parts = token.split(separator: ".").map(String.init)
        parts[1] = Base64URL.encode(TestJSON.data(["v": 1, "key": "test-1"]))
        let tampered = parts.joined(separator: ".")

        XCTAssertThrowsError(
            try LicenseVerifier.verify(
                token: tampered,
                trustedKeys: ["test-1": TestLicense.publicKeyData(key)]
            )
        )
    }

    func testRejectsMalformedToken() {
        XCTAssertThrowsError(
            try LicenseVerifier.verify(token: "not-a-token", trustedKeys: [:])
        ) { error in
            XCTAssertEqual(error as? LicenseVerificationError, .malformed)
        }
    }

    func testParsesTrialEntitlementExpiry() throws {
        let key = TestLicense.keyPair()
        let now = Date()
        let trialEnd = now.addingTimeInterval(14 * 86_400)
        let token = TestLicense.token(
            privateKey: key,
            type: "trial",
            installation: UUID(),
            issuedAt: now,
            revalidateAfter: now,
            expiresAt: trialEnd,
            entitlementExpiresAt: trialEnd
        )

        let claims = try LicenseVerifier.verify(
            token: token,
            trustedKeys: ["test-1": TestLicense.publicKeyData(key)]
        )
        XCTAssertEqual(claims.licenseType, "trial")
        XCTAssertNotNil(claims.entitlementExpiresAt)
        XCTAssertEqual(
            claims.entitlementExpiresAt?.timeIntervalSince1970 ?? 0,
            trialEnd.timeIntervalSince1970,
            accuracy: 1
        )
    }
}

final class AccountServiceTests: XCTestCase {
    private func makeConfiguration(keys: [String: Data] = [:]) -> PlatformConfiguration {
        PlatformConfiguration(
            apiBaseURL: URL(string: "https://api.example.test")!,
            trustedLicenseKeys: keys,
            appVersion: "1.0.0"
        )
    }

    func testDeviceSignInFlowStoresTokenAndRegistersInstallation() async throws {
        let user: [String: Any] = [
            "id": "u1",
            "email": "writer@example.com",
            "status": "active",
            "email_verified": true,
            "created_at": "2026-01-01T00:00:00Z",
        ]
        let transport = MockTransport(routes: [
            .init(method: "POST", path: "/v1/auth/device/start", status: 200, body: TestJSON.data([
                "device_code": "device-123",
                "user_code": "ABCD-EFGH",
                "verification_uri": "https://example.test/device/",
                "verification_uri_complete": "https://example.test/device/?user_code=ABCD-EFGH",
                "expires_in": 900,
                "interval": 5,
            ])),
            .init(method: "POST", path: "/v1/auth/device/token", status: 400, body: TestJSON.data([
                "error": ["code": "authorization_pending", "message": "pending"],
            ])),
            .init(method: "POST", path: "/v1/auth/device/token", status: 200, body: TestJSON.data([
                "token": "api-token-value",
                "token_type": "Bearer",
                "expires_in": 100,
            ])),
            .init(method: "GET", path: "/v1/me", status: 200, body: TestJSON.data(["user": user])),
            .init(method: "POST", path: "/v1/me/installations", status: 201, body: TestJSON.data([
                "installation": [
                    "installation_id": UUID().uuidString,
                    "platform": "macOS",
                    "app_version": "1.0.0",
                    "first_seen_at": "2026-01-01T00:00:00Z",
                    "last_seen_at": "2026-01-01T00:00:00Z",
                    "revoked": false,
                ],
                "created": true,
            ])),
        ])

        let secrets = InMemorySecretStore()
        let service = AccountService(
            configuration: makeConfiguration(),
            transport: transport,
            secrets: secrets
        )

        let authorization = try await service.beginSignIn()
        XCTAssertEqual(authorization.userCode, "ABCD-EFGH")

        let pending = try await service.pollForToken(authorization)
        XCTAssertEqual(pending, .pending)

        let authorized = try await service.pollForToken(authorization)
        guard case .authorized(let token) = authorized else {
            return XCTFail("expected authorized")
        }

        try await service.completeSignIn(token: token.token)
        XCTAssertTrue(service.isSignedIn)
        XCTAssertEqual(try secrets.string(for: "api-token"), "api-token-value")
        XCTAssertNotNil(try secrets.string(for: "installation-id"))

        await service.signOut()
        XCTAssertFalse(service.isSignedIn)
        XCTAssertNil(try secrets.string(for: "api-token"))
    }

    func testRestoreSessionClearsInvalidToken() async {
        let transport = MockTransport(routes: [
            .init(method: "GET", path: "/v1/me", status: 401, body: TestJSON.data([
                "error": ["code": "unauthorized", "message": "no"],
            ])),
        ])
        let secrets = InMemorySecretStore(seed: ["api-token": "stale"])
        let service = AccountService(
            configuration: makeConfiguration(),
            transport: transport,
            secrets: secrets
        )

        let restored = await service.restoreSession()
        XCTAssertFalse(restored)
        XCTAssertNil(try? secrets.string(for: "api-token"))
    }
}

final class LicensingServiceTests: XCTestCase {
    private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

    private func configuration(key: Curve25519.Signing.PrivateKey) -> PlatformConfiguration {
        PlatformConfiguration(
            apiBaseURL: URL(string: "https://api.example.test")!,
            trustedLicenseKeys: ["test-1": TestLicense.publicKeyData(key)],
            appVersion: "1.0.0"
        )
    }

    private func validToken(
        key: Curve25519.Signing.PrivateKey,
        installation: UUID,
        issuedAt: Date,
        expiresAt: Date
    ) -> String {
        TestLicense.token(
            privateKey: key,
            installation: installation,
            issuedAt: issuedAt,
            revalidateAfter: issuedAt.addingTimeInterval(86_400),
            expiresAt: expiresAt
        )
    }

    private func trialToken(
        key: Curve25519.Signing.PrivateKey,
        installation: UUID,
        issuedAt: Date,
        trialEnd: Date
    ) -> String {
        TestLicense.token(
            privateKey: key,
            type: "trial",
            installation: installation,
            issuedAt: issuedAt,
            revalidateAfter: issuedAt,
            expiresAt: trialEnd,
            entitlementExpiresAt: trialEnd
        )
    }

    func testOnlineValidationBecomesActiveAndCachesAuthorization() async throws {
        let key = TestLicense.keyPair()
        let secrets = InMemorySecretStore()
        let installation = try InstallationIdentity(store: secrets).installationID()
        let token = validToken(
            key: key,
            installation: installation,
            issuedAt: fixedNow,
            expiresAt: fixedNow.addingTimeInterval(30 * 86_400)
        )

        let transport = MockTransport(routes: [
            .init(method: "POST", path: "/v1/me/license/validate", status: 200, body: TestJSON.data([
                "valid": true,
                "authorization": token,
                "offline_grace_days": 30,
                "license": [
                    "id": "lic-1",
                    "product": "Yakitori",
                    "license_type": "lifetime",
                    "status": "active",
                    "purchased_at": "2026-01-01T00:00:00Z",
                ],
            ])),
        ])

        let service = LicensingService(
            configuration: configuration(key: key),
            transport: transport,
            secrets: secrets,
            dateProvider: MutableDateProvider(fixedNow)
        )

        await service.refresh()
        guard case .active(let snapshot) = service.state else {
            return XCTFail("expected active, got \(service.state)")
        }
        XCTAssertFalse(snapshot.verifiedOffline)
        XCTAssertNotNil(try secrets.string(for: "license-authorization"))
    }

    func testOfflineFallbackUsesGraceWhenCacheValid() async {
        let key = TestLicense.keyPair()
        let secrets = InMemorySecretStore()
        let installation = try! InstallationIdentity(store: secrets).installationID()
        let token = validToken(
            key: key,
            installation: installation,
            issuedAt: fixedNow,
            expiresAt: fixedNow.addingTimeInterval(30 * 86_400)
        )
        try? secrets.set(token, for: "license-authorization")
        try? secrets.set(String(fixedNow.timeIntervalSince1970), for: "license-last-seen")

        let service = LicensingService(
            configuration: configuration(key: key),
            transport: MockTransport(routes: []),
            secrets: secrets,
            dateProvider: MutableDateProvider(fixedNow)
        )

        await service.refresh()
        guard case .grace(let snapshot) = service.state else {
            return XCTFail("expected grace, got \(service.state)")
        }
        XCTAssertTrue(snapshot.verifiedOffline)
        XCTAssertEqual(snapshot.licenseType, "lifetime")
    }

    func testOfflineWithExpiredCacheIsUnavailable() async {
        let key = TestLicense.keyPair()
        let secrets = InMemorySecretStore()
        let installation = try! InstallationIdentity(store: secrets).installationID()
        let token = validToken(
            key: key,
            installation: installation,
            issuedAt: fixedNow.addingTimeInterval(-60 * 86_400),
            expiresAt: fixedNow.addingTimeInterval(-86_400)
        )
        try? secrets.set(token, for: "license-authorization")

        let service = LicensingService(
            configuration: configuration(key: key),
            transport: MockTransport(routes: []),
            secrets: secrets,
            dateProvider: MutableDateProvider(fixedNow)
        )

        await service.refresh()
        guard case .unavailable = service.state else {
            return XCTFail("expected unavailable, got \(service.state)")
        }
    }

    func testClockRollbackIsDetected() async {
        let key = TestLicense.keyPair()
        let secrets = InMemorySecretStore()
        let installation = try! InstallationIdentity(store: secrets).installationID()
        let token = validToken(
            key: key,
            installation: installation,
            issuedAt: fixedNow,
            expiresAt: fixedNow.addingTimeInterval(30 * 86_400)
        )
        try? secrets.set(token, for: "license-authorization")
        // The last successful check was one hour in the "future".
        try? secrets.set(
            String(fixedNow.addingTimeInterval(3600).timeIntervalSince1970),
            for: "license-last-seen"
        )

        let service = LicensingService(
            configuration: configuration(key: key),
            transport: MockTransport(routes: []),
            secrets: secrets,
            dateProvider: MutableDateProvider(fixedNow)
        )

        await service.refresh()
        XCTAssertEqual(service.state, .clockAnomaly)
    }

    func testExplicitRevocationOverridesCachedAuthorization() async {
        let key = TestLicense.keyPair()
        let secrets = InMemorySecretStore()
        let installation = try! InstallationIdentity(store: secrets).installationID()
        let token = validToken(
            key: key,
            installation: installation,
            issuedAt: fixedNow,
            expiresAt: fixedNow.addingTimeInterval(30 * 86_400)
        )
        try? secrets.set(token, for: "license-authorization")

        let transport = MockTransport(routes: [
            .init(method: "POST", path: "/v1/me/license/validate", status: 200, body: TestJSON.data([
                "valid": false,
                "reason": "revoked",
            ])),
        ])

        let service = LicensingService(
            configuration: configuration(key: key),
            transport: transport,
            secrets: secrets,
            dateProvider: MutableDateProvider(fixedNow)
        )

        await service.refresh()
        XCTAssertEqual(service.state, .invalid(reason: "revoked"))
        XCTAssertNil(try? secrets.string(for: "license-authorization"))
    }

    func testOnlineTrialBecomesTrialState() async throws {
        let key = TestLicense.keyPair()
        let secrets = InMemorySecretStore()
        let installation = try InstallationIdentity(store: secrets).installationID()
        let trialEnd = fixedNow.addingTimeInterval(14 * 86_400)
        let token = trialToken(
            key: key,
            installation: installation,
            issuedAt: fixedNow,
            trialEnd: trialEnd
        )

        let transport = MockTransport(routes: [
            .init(method: "POST", path: "/v1/me/license/validate", status: 200, body: TestJSON.data([
                "valid": true,
                "kind": "trial",
                "authorization": token,
                "offline_grace_days": 0,
                "trial": ["ends_at": "2026-01-15T00:00:00Z", "days_remaining": 14],
            ])),
        ])

        let service = LicensingService(
            configuration: configuration(key: key),
            transport: transport,
            secrets: secrets,
            dateProvider: MutableDateProvider(fixedNow)
        )

        await service.refresh()
        guard case .trial(let snapshot) = service.state else {
            return XCTFail("expected trial, got \(service.state)")
        }
        XCTAssertTrue(service.state.isUsable)
        XCTAssertTrue(snapshot.isTrial)
        XCTAssertGreaterThan(snapshot.daysRemaining ?? 0, 0)
    }

    func testExpiredTrialCacheIsNotUsableOffline() async {
        let key = TestLicense.keyPair()
        let secrets = InMemorySecretStore()
        let installation = try! InstallationIdentity(store: secrets).installationID()
        let token = trialToken(
            key: key,
            installation: installation,
            issuedAt: fixedNow.addingTimeInterval(-30 * 86_400),
            trialEnd: fixedNow.addingTimeInterval(-86_400)
        )
        try? secrets.set(token, for: "license-authorization")
        try? secrets.set(String(fixedNow.timeIntervalSince1970), for: "license-last-seen")

        let service = LicensingService(
            configuration: configuration(key: key),
            transport: MockTransport(routes: []),
            secrets: secrets,
            dateProvider: MutableDateProvider(fixedNow)
        )

        await service.refresh()
        // An expired trial is deterministic, not merely "offline": the cached
        // authorization carries a hard entitlement end.
        XCTAssertEqual(service.state, .invalid(reason: "trial_expired"))
        XCTAssertFalse(service.state.isUsable)
    }

    func testTrialExpiresWhenTheClockPassesItsEnd() async throws {
        let key = TestLicense.keyPair()
        let secrets = InMemorySecretStore()
        let installation = try InstallationIdentity(store: secrets).installationID()
        let trialEnd = fixedNow.addingTimeInterval(10)
        let token = trialToken(
            key: key,
            installation: installation,
            issuedAt: fixedNow,
            trialEnd: trialEnd
        )

        let transport = MockTransport(routes: [
            .init(method: "POST", path: "/v1/me/license/validate", status: 200, body: TestJSON.data([
                "valid": true,
                "kind": "trial",
                "authorization": token,
                "offline_grace_days": 0,
                "trial": ["ends_at": "2026-01-15T00:00:00Z", "days_remaining": 1],
            ])),
        ])

        let clock = MutableDateProvider(fixedNow)
        let service = LicensingService(
            configuration: configuration(key: key),
            transport: transport,
            secrets: secrets,
            dateProvider: clock
        )

        await service.refresh()
        guard case .trial = service.state else {
            return XCTFail("expected trial, got \(service.state)")
        }

        // The app schedules its next check exactly at the trial end.
        XCTAssertEqual(
            service.nextEvaluationDate(now: fixedNow)?.timeIntervalSince1970 ?? 0,
            trialEnd.timeIntervalSince1970,
            accuracy: 1
        )

        // Time passes; the server is now unreachable.
        clock.advance(by: 11)
        await service.refresh()

        XCTAssertEqual(service.state, .invalid(reason: "trial_expired"))
        XCTAssertFalse(service.state.isUsable)
    }

    func testServerReportedExpiredTrialIsInvalid() async {
        let key = TestLicense.keyPair()
        let secrets = InMemorySecretStore()
        _ = try? InstallationIdentity(store: secrets).installationID()

        let transport = MockTransport(routes: [
            .init(method: "POST", path: "/v1/me/license/validate", status: 200, body: TestJSON.data([
                "valid": false,
                "reason": "trial_expired",
                "kind": "trial",
            ])),
        ])

        let service = LicensingService(
            configuration: configuration(key: key),
            transport: transport,
            secrets: secrets,
            dateProvider: MutableDateProvider(fixedNow)
        )

        await service.refresh()
        XCTAssertEqual(service.state, .invalid(reason: "trial_expired"))
        XCTAssertFalse(service.state.isUsable)
    }
}
