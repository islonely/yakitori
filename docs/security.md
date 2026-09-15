# Security

Security is a release-blocking concern. This document is the threat model and
the checklist the platform is built against.

## Principles

- Least privilege everywhere: database, admin, and API.
- No server secrets in the macOS app.
- No payment-card data is ever handled or stored.
- No secrets in Git, in logs, or in client code.
- Fail closed: unsigned/invalid/expired input is rejected.

## Threat model and mitigations

| Threat | Mitigation |
|---|---|
| License forgery | Ed25519 signed authorization; the private key exists only server-side (`licensing/signing.py`) |
| Server impersonation | HTTPS in production, embedded trusted public key, no TLS-verification bypass |
| Account takeover | Passwordless single-use challenges, short expiry, rate limits, session rotation, audit log |
| Purchase theft | Verified email ownership; unguessable purchase references; **all** claims go to human review |
| Webhook spoofing | Provider signature verification (`verify_webhook`) |
| Webhook replay | Unique provider event id (`WebhookEvent.external_id`) + idempotent processing |
| IDOR | Every resource is resolved through the authenticated user and explicit rules |
| Username squatting | Charset rules, reserved names, cooldown, released-name hold, unique index |
| Social spam | Rate limits, blocking, reporting, audit trail |
| Leaderboard cheating | Plausibility validation, aggregation controls, documented trust limit |
| Repeat free trials | Per-account and per-installation records, plus a device-hashed hardware UUID digest (`MachineTrial`); the raw UUID never leaves the Mac |
| Database compromise | Least privilege, minimal stored data, encrypted backups, externalized secrets |
| Secret leakage | `.gitignore`, `.dockerignore`, secret scanning in CI, no secret logging |

## Authentication and authorization

- Passwordless email challenges: single-use, expiring, stored only as hashes
  (`accounts`).
- Browser sessions are HttpOnly, SameSite=Lax, Secure in production, rotated on
  login.
- Native clients use device authorization and a Keychain-stored bearer token,
  stored only as a hash.
- Admin endpoints use `api_admin_required`, which checks the account's
  staff/superuser flag **server-side**. A browser-supplied `is_admin` is never
  trusted.
- Suspension immediately invalidates sign-in and existing tokens
  (`User.can_sign_in`).

## Input handling

- All database access goes through the Django ORM with parameterized queries.
- JSON bodies must be objects; malformed input returns a structured `400`.
- Usernames, installation ids, metrics, periods, and report categories are
  validated against explicit allow-lists.
- Uploads are not part of the current surface; `client_max_body_size` is bounded
  at the proxy.

## Webhooks

- Signature verified before parsing.
- Invalid signature → `400` (no state change).
- Duplicate external id → acknowledged without reprocessing.
- Purchase state is updated inside a transaction with a row lock.

## Rate limiting

Server-side, database-backed (`common.ratelimit`), applied to login request and
verification, username changes, follow/unfollow, profile mutations, leaderboard
reads, purchase claims, license validation, installation registration, checkout,
statistics submission, and admin endpoints. Keys combine action with account, IP,
or subject as appropriate. Client-side limits are never relied upon.

## Headers, CSP, and CORS

- `SecurityHeadersMiddleware` sets a restrictive `Content-Security-Policy`
  (same-origin by default, HTMX from a pinned CDN).
- Django's `SecurityMiddleware` sets HSTS (production), `nosniff`, referrer
  policy, and SSL redirect.
- `X-Frame-Options: DENY` via `XFrameOptionsMiddleware`.
- CORS is not enabled: the API is same-origin for the browser and token-based
  for native clients. Credentialed wildcard CORS is never used.

## Secrets

Managed through environment variables / the host's secret manager (see
`.env.example`). Never committed. In particular:

- `SECRET_KEY`, `DATABASE_PASSWORD`, `STRIPE_SECRET_KEY`,
  `STRIPE_WEBHOOK_SECRET`, `EMAIL_PROVIDER_API_KEY`,
  `LICENSE_SIGNING_PRIVATE_KEY`.

`.env` and `.env.*` are ignored by Git and Docker. CI performs secret scanning.
The development console email provider refuses to run when `DEBUG` is false.

## Logging

Structured JSON to stdout. Logs must never contain passwords, login codes,
tokens, Stripe secrets, private keys, card data, or manuscript content. The
audit recorder additionally redacts a denylist of sensitive metadata keys.

## Dependencies

Pinned in `website/requirements.txt`. CI runs an audit (`pip-audit`) and the
test suite. New infrastructure (Redis, Kafka, Kubernetes) is intentionally not
introduced.

## Database and operations

- Migrations are committed and additive; no destructive auto-reset on startup.
- Backups are automated, encrypted, and restore-tested
  (`docs/disaster-recovery.md`).
- Production least-privilege database credentials.

## Security test coverage

Automated tests cover:

- security headers present,
- CSRF enforcement on HTML forms,
- malformed JSON rejected,
- IDOR (cross-account installation revocation denied),
- privilege escalation via profile update denied,
- suspended accounts' tokens rejected,
- SQL injection inert in search,
- login rate limiting,
- webhook signature rejection and replay idempotency,
- forged/tampered license authorization rejected (including a wrong public key),
- admin authorization (anonymous 401, non-staff 403),
- audit records for administrative actions.

## Invariant checklist

1. A client cannot create its own license. ✅
2. A duplicate webhook cannot create duplicate ownership. ✅
3. Knowing an email is insufficient to steal a purchase. ✅
4. A license is not tied to a Mac. ✅
5. There is no hard device limit. ✅
6. Server outage is not revocation. ✅
7. The app cannot forge an authorization without the private key. ✅
8. Licensing requires no manuscript data. ✅
9. Reinstalling does not destroy ownership. ✅
10. A replacement Mac can use the same license. ✅
11. Email is not a public identity. ✅
12. Stripe customer ids are not public identifiers. ✅
13. A private user never appears on a public leaderboard. ✅
14. A user cannot modify another user's profile or social graph. ✅
15. A user cannot alter another user's statistics. ✅
16. A user cannot assign themselves a leaderboard score. ✅
17. Deleting a local installation does not delete account ownership. ✅
18. Recovery can reconstruct ownership from authoritative records. ✅
    (Stripe remains an independent purchase record; see disaster recovery.)
