# Account Architecture

The platform's identity layer lives in the `accounts` app. It is intentionally
passwordless for customers while remaining compatible with the Django admin for
staff.

## Identity

- `accounts.User` is a custom user model with a **UUID primary key** and
  **email as the login identifier**. `email_normalized` (lowercase) is unique
  and indexed, so case differences cannot create duplicate accounts.
- The email address is never exposed publicly. Public identity lives in
  `profiles.Profile` (see `docs/social-architecture.md`).
- `status` is the lifecycle source of truth: `active`, `suspended`,
  `pending_deletion`, `deleted`. Suspension or deletion immediately blocks
  sign-in because `User.save()` mirrors `status` into Django's `is_active`.
- `password` exists only so staff/superusers can use the Django admin. Ordinary
  accounts are created with `set_unusable_password()`.

## Passwordless sign-in

```
user submits email
        │
        ▼
LoginChallenge created (single-use, short-lived)
  • token_hash = sha256(random link token)
  • code_hash  = sha256(6-digit code)
        │
        ▼
email sent with link and code
        │
        ▼
user opens link  (or enters code)
        │
        ▼
challenge verified + consumed
        │
        ▼
account found or created; email marked verified
        │
        ▼
Django session established
```

Properties:

- Challenges expire (`LOGIN_CHALLENGE_TTL_SECONDS`, default 15 minutes) and are
  single-use. Consumption happens inside a transaction with `select_for_update`.
- Only **hashes** of the token and code are stored.
- The response to the sign-in request is identical whether or not the address
  exists (anti-enumeration). The same is true on the sign-up path.
- Requests are rate limited per IP and per email
  (`common.ratelimit.check`), using the `RateLimitEntry` table.
- Login success and failure are written to the append-only audit log.
- There is no password to reset: **recovery is the normal login flow**. Signing
  in from an existing email address is the recovery path.

## Browser sessions

- Django's database-backed sessions.
- `HttpOnly`, `SameSite=Lax` cookies; `Secure` in production.
- Rotated on login and refreshed while active
  (`SESSION_SAVE_EVERY_REQUEST`). 14-day default lifetime.
- CSRF protection on every state-changing HTML form.

## Native clients (macOS)

The app never embeds a web password form and never contains a server secret.

### Device authorization (RFC 8628 style)

```
app                         server                        browser
 │  POST /v1/auth/device/start                              │
 │ ───────────────────────►  creates DeviceAuthorization    │
 │                           returns user_code/device_code   │
 │                                                          │
 │  shows user_code, opens verification_uri ───────────────►│
 │                                                          │ sign in (if needed)
 │                                                          │ POST /device/ approve
 │  POST /v1/auth/device/token (poll)                       │
 │ ───────────────────────►  approved? issues ApiToken      │
 │  stores token in Keychain                                │
```

- `device_code` is returned once and stored hashed.
- `user_code` is short, unambiguous (no `I`, `O`, `0`, `1`) and shown in the
  browser; approval requires an authenticated account.
- Approval/denial is audited. An approved code can be exchanged exactly once.

### API tokens

- `accounts.ApiToken` rows store only `sha256(token)`.
- Tokens are sent as `Authorization: Bearer <token>` for all `/v1/` calls.
- They can be listed and revoked from the account dashboard; the macOS app
  stores its token in the **Keychain**, never `UserDefaults`.
- A token is invalid if revoked, expired, or if its user can no longer sign in.
- `last_used_at` is updated at most once per minute to avoid write amplification.

## Endpoints

| Method | Path | Purpose |
|---|---|---|
| POST | `/v1/auth/device/start` | Begin device authorization |
| POST | `/v1/auth/device/token` | Poll / exchange for an API token |
| GET | `/v1/me` | The authenticated account |
| GET | `/v1/me/tokens` | List active device credentials |
| DELETE | `/v1/me/tokens/<id>` | Revoke one device credential |

## Account lifecycle and deletion

- Deletion is an explicit, confirmed workflow (requires recent authentication).
- Deleting an account does **not** destroy legally/commercially necessary
  transaction history. Purchase and license records are retained under a
  documented retention policy; the public profile is removed or anonymized and
  never left orphaned.
- Suspension is reversible; deletion is not.

## macOS app integration

The account and licensing services live in
`Sources/WritingTrackerCore/Account/` and are injected through `AppContainer`.
They are optional: the tracker continues to run locally when signed out or
offline.

- `AccountService` drives the device authorization flow, stores the bearer token
  in the **Keychain** (`KeychainSecretStore`, never `UserDefaults`), registers
  the installation, and exposes the signed-in account.
- `InstallationIdentity` creates a random UUID on first use and stores it in the
  Keychain. It is never derived from hardware identifiers.
- `LicensingService` validates online and caches the signed authorization for
  offline use, with a clock-rollback guard.
- `LicenseVerifier` verifies the Ed25519 authorization using public keys read
  from `Info.plist` (`YakitoriLicensePublicKeys`). The private key never exists
  in the app.
- The API base URL comes from `Info.plist` (`YakitoriAPIBaseURL`); release builds
  must point it at the production origin.

The Account screen (`UI/Account/AccountView.swift`) shows sign-in, the device
code, the license state (active / offline grace / invalid / unavailable / clock
anomaly), and the installation id. None of this blocks tracking.

## Threat considerations

| Threat | Mitigation |
|---|---|
| Account takeover | Single-use short-lived challenges, rate limits, audit logs, no reusable password |
| Enumeration | Uniform responses on request and verify paths |
| Token theft | Hashed at rest, revocable, bound to a device label, `Secure` transport |
| CSRF | Django CSRF middleware; API is token-based and CSRF-exempt |
| Replay | Single-use codes, idempotent device exchange |
