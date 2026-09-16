# Licensing and Commerce Architecture

Two apps, one concern: **proving ownership without tying it to a device**.

- `commerce/` records purchases and normalizes provider events.
- `licensing/` turns a verified purchase into a lifetime entitlement and issues
  signed authorizations the macOS app can verify offline.

## Product policy

- One product, `Yakitori`.
- A **one-time 14-day free trial**, then a one-time purchase, **lifetime**
  license: `license_type = "lifetime"`, `expires_at = NULL`, no renewal.
- **Unlimited installations.** There is no `max_installations`, no hardware
  fingerprinting, and no use of MAC address, serial number, hardware UUID, disk
  id, hostname, or CPU id anywhere in the codebase.
- The account owns the license. Installations are listed for support and
  security, never to impose a device limit.

## Free trial

The trial is deliberately account-bound so it cannot be restarted.

- The trial starts automatically on the **first successful license validation**
  by a signed-in account — there is no separate "start trial" button. In the app
  this happens right after you approve the device sign-in and the installation
  registers; creating an account on the website alone does **not** start it.
- The clock is server-side: `ends_at = now + TRIAL_DAYS` (14 by default) at that
  first validation, and it never restarts. The app is always signed in and
  installation-registered before it validates, so the trial starts reliably.
- One trial per account (`Trial` is one-to-one with the user), and the
  installation that consumed a trial is recorded (`Installation.trial_consumed_at`).
  A different account on the same Mac is therefore **not** given a second trial.
- The Mac is also recorded, so reinstalling or creating a new account on the
  same machine cannot produce a second trial. The app reads `IOPlatformUUID`
  (IOKit) and **hashes it on the device** (SHA-256 over a fixed namespace
  prefix); only that digest is sent, and the server stores it verbatim in
  `MachineTrial`. The raw UUID never leaves the Mac. This is a deliberate,
  **trial-only** exception to the "no hardware fingerprinting" rule — licenses
  remain tied to the account, not to a device. (Apple's DeviceCheck is a
  possible future, more privacy-preserving replacement.)
- A revoked or disabled license **never** falls back to a trial, so a refunded
  purchase cannot be replayed as a free trial.
- The trial is granted through the same signed authorization mechanism, with
  `type = "trial"` and a hard `ent_exp` (trial end). The app locks when it
  passes, even offline.
- Signing out does not extend or reset a trial, because the server already knows
  the account (and installation) has used it.

The app gates only **recording of new sessions**. Everything already written
remains viewable and exportable, and no local data is ever hidden or deleted.

When the trial ends while a session is running, the app stops that session. The
client schedules its next entitlement check for the exact trial end (from the
signed `ent_exp`), and re-checks on app activation and on wake from sleep, so an
open session cannot outlive the trial. An expired cached trial is treated as a
definitive expiry (`trial_expired`), not as a network problem.

For tests, `TRIAL_SECONDS` (non-zero) runs sub-day trials so expiry can be
observed without waiting 14 days. It is a test/tuning override and defaults to 0.

## Commerce

- `PaymentProvider` is the only seam the rest of the platform sees:
  `create_checkout`, `verify_webhook`, `normalize_event`, plus a
  development-only `build_event`.
- `MockPaymentProvider` runs the whole flow locally with no network and is the
  default in development and tests.
- `StripeManagedPaymentsProvider` uses Stripe's official SDK and is only
  constructed when `PAYMENT_PROVIDER=stripe` and `STRIPE_SECRET_KEY` exist.
- `PaymentPurchase` stores normalized fields (`amount`, `currency`, `status`,
  `provider_purchase_id`, …) rather than scattering Stripe-specific columns
  through the licensing domain.
- The authoritative ownership signal is a **verified server-side webhook**. A
  success-page redirect and any client-supplied flag are ignored.
- `WebhookEvent.external_id` is unique, which makes duplicate deliveries
  idempotent: the event is acknowledged but not reprocessed.
- Normalized kinds: `purchase_completed`, `refund_issued`, `dispute_opened`,
  `dispute_resolved`, `purchase_restored`. Refunds record full vs partial.

### Webhook endpoint

`POST /v1/webhooks/stripe`

- Stripe signature verified with `STRIPE_WEBHOOK_SECRET`.
- Invalid signature → `400`; valid signature → `200` (so providers retry only on
  genuine failure).
- Processing is transactional; the purchase row is locked while it updates.

## Licensing

### Schema

```
License
  id, user, product, license_type=lifetime, status(active|revoked|disabled),
  purchased_at, expires_at=NULL, payment_purchase, revocation_reason

Installation
  id, user, installation_id (UUID, client-generated), platform, app_version,
  first_seen_at, last_seen_at, revoked_at
```

Licenses are **never deleted**. A refund sets `revoked`, a dispute sets
`disabled`, and a resolution/restoration sets `active`.

### Keeping licenses in sync

Commerce emits a Django signal (`commerce.signals.purchase_event`) after a
verified event updates a purchase. Licensing listens and grants/revokes/
restores. Commerce has no dependency on licensing; the signal decouples them.

### Installations

- The macOS app generates a **random, cryptographically secure UUID** and stores
  it in the Keychain. It is never derived from hardware.
- Registration is idempotent per `installation_id`; re-registering updates
  version/last-seen and clears any earlier revocation. The same Mac can be
  re-bound to a different account after sign-out/sign-in.
- The dashboard and API both allow revoking a single installation.

### Signed authorization (offline licensing)

```
SERVER (private key)                    MAC APP (embedded public key)
  claims ──sign Ed25519──► token ───────────► verify signature
                                              check claims + exp
```

- Claims: `sub` (user), `lic` (license), `product`, `type`, `status`, `inst`
  (installation), `iat`, `revalidate_after`, `exp`.
- `exp` is the **offline grace deadline** (default 30 days), not a license
  expiry — a lifetime license has none.
- Token form: `base64url(header).base64url(payload).base64url(signature)`,
  `header = {"alg":"Ed25519","kid":...}`.
- Key id (`kid`) is included so keys can be rotated: the app trusts a set of
  key ids, the server may still verify with older public keys.

### Offline behavior

- The app caches the last valid authorization and keeps working during a server
  outage **until `exp`**.
- A server outage is never treated as revocation.
- An explicit server-side revocation overrides cached authorization the next
  time the app validates online. Because offline clients cannot be reached,
  the grace deadline is what bounds an offline revoked client.
- The client is responsible for detecting clock rollback; the app stores the
  issued-at time and refuses to extend its own grace window from a rolled-back
  clock.

### Key management

- Generate a development pair:

  ```bash
  python manage.py generate_signing_key --key-id dev-1
  ```

  Put `LICENSE_SIGNING_PRIVATE_KEY` (base64 raw seed) and
  `LICENSE_SIGNING_KEY_ID` in the server environment. Embed the printed **public**
  key in the macOS app.
- The private key exists only server-side. It is never committed and never
  placed in the app.

## Endpoints

| Method | Path | Purpose |
|---|---|---|
| POST | `/v1/checkout` | Start a purchase, return a checkout URL |
| GET | `/v1/me/purchases` | Purchase history |
| POST | `/v1/webhooks/stripe` | Verified provider webhook |
| GET | `/v1/me/license` | License status |
| POST | `/v1/me/license/validate` | Validate + return a signed authorization |
| GET/POST | `/v1/me/installations` | List / register installations |
| DELETE | `/v1/me/installations/<installation_id>` | Revoke an installation |

## Threat model

| Threat | Mitigation |
|---|---|
| License forgery | Ed25519 signature; only the server holds the private key |
| Client fabricating a license | Server grants only from verified purchase events |
| Device cloning / limit evasion | No device binding at all — ownership is the account |
| Webhook spoofing | Provider signature verification |
| Webhook replay | Unique external event id + idempotent processing |
| Offline lockout | Configurable grace period; outage ≠ revocation |
| Lost machine | Replacement Macs just register; license is unaffected |
| Reinstalling the app | Ownership lives on the account, not the install |

### Invariants covered by tests

1. A client cannot create its own license.
2. A duplicate webhook cannot create duplicate ownership.
3. Knowing an email address is insufficient to steal a purchase.
4. A license is not tied to a particular Mac.
5. There is no hard device limit.
6. A server outage is not treated as revocation.
7. The app cannot forge an authorization without the private key.
8. Licensing requires no manuscript data.
9. Reinstalling does not destroy ownership.
10. A replacement Mac can use the same lifetime license.
