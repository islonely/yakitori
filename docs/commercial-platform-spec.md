# Yakitori Account, Commerce, Licensing, Social & Web Platform
## Comprehensive OpenCode Implementation Specification

**Project:** Yakitori  
**Target:** Native macOS writing-statistics application plus its commercial/account/social web platform  
**Primary implementation agent:** OpenCode / DeepSeek  
**Repository requirement:** The website and all server-side platform code must live in a root-level `website/` directory inside the Yakitori repository.

---

# 0. Important instruction to the coding agent

Before changing code, inspect the ENTIRE existing Yakitori repository.

You must inspect:

- all source files
- all existing documentation
- all `AGENTS.md` files
- existing Git state
- Swift package/Xcode project structure
- persistence/database code
- tracking architecture
- analytics architecture
- authentication/account code, if any
- networking code, if any
- Keychain code
- test targets
- build scripts
- configuration/environment handling
- existing assets
- existing app icon/branding
- any existing website/backend code

The repository currently may not have a website or server. If it does not, create them.

Do not replace working existing architecture merely because you prefer another approach.

Do not delete persistent data.

Do not rewrite the existing macOS application unnecessarily.

Before implementation, create a short architecture audit at:

`docs/commercial-platform-architecture-audit.md`

The audit must describe the existing application and exactly where the new account/platform system integrates with it.

---

# 1. Goal

Build the complete foundation for Yakitori's future commercial and social ecosystem.

This is larger than payment processing.

The platform must support:

1. Yakitori user accounts
2. verified email authentication
3. lifetime software ownership
4. Stripe Managed Payments
5. unlimited Mac installations
6. secure licensing
7. a public username
8. public/private user profiles
9. followers/following
10. future worldwide writing leaderboards
11. privacy controls
12. future cloud-backed writing-statistics aggregation
13. a production website
14. a production API
15. PostgreSQL persistence
16. administrative tools
17. secure webhook processing
18. secure app-to-server authentication
19. account recovery
20. future social features without redesigning the identity system

The platform must NOT turn Yakitori's local-first writing tracker into a cloud-dependent application.

The macOS app must continue tracking writing locally when the network is unavailable.

---

# 2. Core architecture

Use this conceptual model:

```text
                         YAKITORI PLATFORM
                                │
                         ┌──────┴──────┐
                         │   User ID   │
                         └──────┬──────┘
                                │
       ┌────────────────────────┼────────────────────────┐
       │                        │                        │
       ▼                        ▼                        ▼
   COMMERCE                 SOCIAL IDENTITY          WRITING DATA
       │                        │                        │
   Stripe purchase          username/profile       local sessions
       │                     followers             local statistics
       ▼                     privacy               optional cloud
   Purchase record           settings              aggregation
       │                        │                        │
       ▼                        ▼                        ▼
    License               Social graph             Leaderboards
       │
       ▼
 Installations
```

The stable `user_id` is the common identity.

Do NOT use:

- email address as the primary key
- Stripe customer ID as the primary key
- license key as the primary identity
- installation ID as the identity
- Mac hardware identity as the identity

The account owns the license.

The account owns the social identity.

The account may eventually own cloud writing-statistics aggregates.

The Mac installation is merely an installation belonging to an account.

---

# 3. Repository layout

If the repository currently has no website/backend, create:

```text
yakitori/
├── [existing macOS application files]
├── website/
│   ├── app/
│   ├── api/
│   ├── database/
│   ├── migrations/
│   ├── tests/
│   ├── public/
│   ├── scripts/
│   ├── docs/
│   ├── Dockerfile
│   ├── docker-compose.yml
│   ├── .env.example
│   ├── package.json / equivalent
│   └── README.md
├── docs/
│   ├── commercial-platform-architecture-audit.md
│   ├── account-architecture.md
│   ├── licensing-architecture.md
│   ├── social-architecture.md
│   ├── leaderboard-architecture.md
│   ├── deployment.md
│   ├── security.md
│   └── disaster-recovery.md
├── AGENTS.md
└── ...
```

The exact framework may be selected after inspecting the repository.

Prefer a boring, well-supported stack.

A reasonable default is:

- TypeScript
- a modern server-rendered web framework
- PostgreSQL
- a mature ORM/query layer with real migrations
- Stripe's official SDK
- standard email provider
- Docker Compose for local development

Do not introduce Kubernetes, microservices, Redis, Kafka, or other infrastructure unless the existing project or a demonstrated requirement justifies it.

The initial platform should be one web application/API service plus PostgreSQL.

---

# 4. Website responsibility

The website is not merely a marketing page.

It should eventually provide:

- home page
- product information
- pricing
- purchase flow
- sign-in
- account creation
- account dashboard
- license status
- installation list
- profile
- username
- follower/following pages
- privacy settings
- future leaderboard pages
- future public profiles
- support/contact
- legal pages
- privacy policy
- terms/license policy
- download page
- account deletion
- future changelog/news

Build the architecture so public pages can be added without redesigning authentication.

---

# 5. Authentication

Use passwordless authentication initially.

Preferred flow:

```text
User enters email
        ↓
Server creates short-lived login challenge
        ↓
Email sent
        ↓
User clicks secure link or enters code
        ↓
Email ownership verified
        ↓
Server creates authenticated session
```

Requirements:

- short expiration for login challenges
- single-use challenges
- hashed challenge/token storage where practical
- rate limiting
- anti-enumeration behavior
- no passwords initially
- no plaintext authentication secrets
- no authentication tokens in logs

For browser sessions:

- use secure, HttpOnly cookies
- SameSite protection
- Secure flag in production
- appropriate CSRF protection
- short-lived session/access credentials
- refresh/session rotation where appropriate

For the macOS application:

Use a secure browser-based account login/device authorization flow rather than embedding a web password form inside the application.

Store long-lived native credentials in macOS Keychain, never UserDefaults.

---

# 6. User identity schema

Create:

## users

```text
id UUID PRIMARY KEY
email
email_normalized
email_verified_at NULL
status
created_at
updated_at
deleted_at NULL
```

Constraints:

- UUID primary key
- normalized email indexed/unique as appropriate
- email must not be publicly exposed
- deleted accounts must be handled deliberately
- account deletion must not destroy legally/commercially necessary transaction history

Potential status values:

```text
active
suspended
pending_deletion
deleted
```

Do not hard-delete commercial records merely because an account is deleted.

---

# 7. Public profile

Create a separate `profiles` table.

```text
id UUID PRIMARY KEY
user_id UUID UNIQUE REFERENCES users(id)
username
display_name
bio
avatar_url
visibility
created_at
updated_at
```

Username requirements:

- case-insensitive uniqueness
- normalized lookup
- reasonable length limit
- safe character set
- no whitespace
- no impersonation-sensitive characters
- reserved-name list
- rate-limited username changes
- username change history
- no email addresses as usernames
- no automatic exposure of email

Reserve names such as:

```text
admin
administrator
support
help
billing
security
moderator
official
yakitori
api
system
staff
team
root
```

The reserved-name system must be configurable rather than hard-coded throughout the application.

---

# 8. Username changes

Do not allow unlimited rapid username changes.

Implement:

- username change history
- cooldown
- audit event
- uniqueness transaction
- protection against race conditions
- old-name reservation policy

Do not automatically redirect old usernames forever unless that is deliberately chosen.

Document the policy.

---

# 9. Social graph

Create:

## follows

```text
id UUID PRIMARY KEY
follower_user_id UUID REFERENCES users(id)
followed_user_id UUID REFERENCES users(id)
created_at
```

Constraints:

```text
UNIQUE(follower_user_id, followed_user_id)
CHECK(follower_user_id <> followed_user_id)
```

Indexes must support:

- users I follow
- users following me
- follower counts
- following counts
- username/profile lookup

Implement eventually:

```text
POST   /v1/users/:username/follow
DELETE /v1/users/:username/follow
GET    /v1/users/:username/followers
GET    /v1/users/:username/following
```

Do not expose internal UUIDs unnecessarily in public URLs.

Use usernames for public profile navigation.

---

# 10. Privacy

Create explicit privacy settings.

At minimum:

```text
profile_visibility
leaderboard_visibility
stats_visibility
allow_following
```

Possible values should be documented and enforced server-side.

Do not assume that a user's public username means all statistics are public.

A user should be able to have:

- a public username
- a public profile
- private writing statistics
- no leaderboard participation

These are separate choices.

---

# 11. Blocking and reporting

Do not necessarily build the full moderation UI in the first implementation, but design the schema/API boundaries so they can be added without redesign.

Plan for:

```text
blocks
reports
moderation_actions
```

Social systems need an abuse path.

Do not build a social platform with no way to handle harassment, impersonation, spam, or abuse.

---

# 12. Commerce

Use Stripe Managed Payments as the initial commerce provider.

Stripe Managed Payments is designed for digital products/software and can handle merchant-of-record responsibilities including supported indirect taxes, fraud, disputes, and transaction-level customer support. It currently adds 3.5% per successful Managed Payments transaction on top of standard Stripe processing fees.

Use Stripe's official SDK and current documentation.

Do NOT:

- process card numbers yourself
- store card numbers
- build a custom card form
- trust a client-side "payment succeeded" flag
- grant licenses from a success-page redirect
- put Stripe secret keys in the Mac app

The authoritative purchase signal is a verified Stripe server-side event.

---

# 13. Product model

Initial commercial product:

```text
Product: Yakitori
Purchase: one-time
License: lifetime/perpetual
Renewal: none
Installations: unlimited
Expiration: none
```

The exact customer-facing meaning of "lifetime" must be written in the commercial/legal documentation.

Do not leave ambiguous whether lifetime means:

- lifetime of purchaser
- lifetime of company
- current major version
- all future versions

Make this a business configuration/policy.

Database representation:

```text
license_type = lifetime
expires_at = NULL
```

---

# 14. Purchase records

Separate payment records from licenses.

Create:

## payment_purchases

```text
id UUID PRIMARY KEY
user_id NULL
provider
provider_customer_id
provider_purchase_id
provider_product_id
provider_price_id
amount
currency
status
purchased_at
created_at
updated_at
```

Do not put Stripe-specific fields throughout the licensing domain.

Create a narrow provider abstraction:

```text
PaymentProvider
    ├── create checkout
    ├── retrieve purchase
    ├── verify purchase
    └── normalize webhook events

StripeManagedPaymentsProvider
```

This allows the commerce provider to change later without rewriting account/licensing logic.

---

# 15. License schema

Create:

## licenses

```text
id UUID PRIMARY KEY
user_id UUID REFERENCES users(id)
product
license_type
status
purchased_at
expires_at NULL
payment_purchase_id REFERENCES payment_purchases(id)
created_at
updated_at
```

Possible status:

```text
active
revoked
disabled
```

Never delete a license record.

A refund or chargeback changes its state according to the documented policy.

---

# 16. Unlimited installations

This is a hard product requirement.

A customer may use the license on unlimited Macs.

Do NOT implement:

```text
max_installations = 3
```

Do NOT use hardware fingerprinting.

Do NOT tie licenses to:

- MAC address
- serial number
- Apple hardware UUID
- disk ID
- hostname
- CPU ID

Installations exist for:

- security
- account management
- support
- troubleshooting
- auditability
- revocation
- abuse detection

They do not exist to impose an arbitrary machine limit.

---

# 17. Installations

Create:

## installations

```text
id UUID PRIMARY KEY
user_id UUID REFERENCES users(id)
installation_id
platform
app_version
first_seen_at
last_seen_at
revoked_at NULL
created_at
updated_at
```

The native app creates a random cryptographically secure installation ID.

Store it in macOS Keychain.

Never derive it from hardware identifiers.

The same account may have any number of active installations.

---

# 18. License cryptography

The Mac app must not contain a server secret.

Use asymmetric cryptography.

Recommended:

```text
SERVER
private signing key
        ↓
signed authorization

MAC APP
embedded public verification key
        ↓
verify authorization
```

The server signs authorization data.

The application verifies it.

The private signing key must exist only server-side.

Support key IDs and future key rotation.

Do not invent cryptographic algorithms.

Use a mature standard library.

---

# 19. Offline licensing

The app should continue working during a temporary licensing-server outage.

Implement a signed cached authorization with an explicit offline grace period.

Recommended initial policy:

```text
30 days
```

The exact duration should be configurable.

Important distinction:

```text
server unavailable
≠
license revoked
```

A temporary outage must not lock out a legitimate customer.

An explicit server-side revocation must eventually override cached authorization.

Handle:

- clock rollback
- expired cached authorization
- signature failure
- stale authorization
- server outage
- revoked license
- network unavailable

Do not trust local wall-clock state blindly.

---

# 20. Account purchase association

The purchase must become associated with the correct Yakitori account.

Do not allow:

```text
POST /claim
{
  "email": "victim@example.com"
}
```

to claim somebody else's purchase.

Preferred flow:

```text
Stripe purchase
      ↓
verified purchase record
      ↓
user creates/signs into Yakitori account
      ↓
verified email ownership
      ↓
secure purchase association
      ↓
lifetime license
```

If a purchase predates account creation, support a secure claim process.

Ambiguous ownership must go to support/admin review rather than automatic account merging.

---

# 21. Stripe webhooks

Create:

```text
POST /v1/webhooks/stripe
```

Requirements:

- HTTPS in production
- verify Stripe webhook signature
- reject invalid signatures
- validate payload
- idempotent processing
- store external event IDs
- protect against replay
- never trust client-supplied payment status
- transactionally update purchase/license state
- return appropriate success/error status

At minimum design for:

- successful purchase
- refund
- full refund
- partial refund if relevant
- dispute/chargeback
- restoration/resolution where applicable

Do not assume a particular Stripe event is authoritative until verified against the current Stripe Managed Payments documentation.

Normalize Stripe events internally:

```text
PurchaseCompleted
RefundIssued
DisputeOpened
DisputeResolved
PurchaseRestored
```

---

# 22. Account dashboard

The website account area should eventually provide:

```text
Account
├── Profile
├── Username
├── Privacy
├── License
├── Purchase history
├── Installations
├── Followers
├── Following
├── Statistics privacy
└── Account deletion
```

The user should be able to see:

- license status
- license type
- purchase date
- installation list
- last-seen installation time
- app versions

The user must NOT be able to activate/revoke their own license through arbitrary client input.

---

# 23. Future writing-statistics cloud model

Yakitori remains local-first.

The existing application must continue to store and calculate detailed writing statistics locally.

Do not move raw writing data to the server merely because social features exist.

The future cloud system should send only the minimum data needed for social/leaderboard features.

Possible future architecture:

```text
Local Yakitori
      ↓
validated aggregate statistics
      ↓
privacy-controlled sync
      ↓
Yakitori API
      ↓
leaderboard aggregation
```

Never upload:

- manuscript contents
- document contents
- raw keystrokes
- clipboard contents
- private document text

Do not upload document names unless a future feature explicitly requires it and the user consents.

---

# 24. Leaderboards

Leaderboards are a future first-class platform feature and must be considered now.

Do not build the first leaderboard implementation by querying raw writing sessions on every page load.

Use aggregation.

Conceptually:

```text
Local writing sessions
        ↓
validated statistics
        ↓
daily aggregate
        ↓
weekly/monthly/all-time aggregate
        ↓
leaderboard materialization
        ↓
public leaderboard
```

Potential leaderboards:

- words written
- writing time
- sessions
- consistency
- improvement
- productivity
- project velocity

Do not create arbitrary new metric definitions.

Use Yakitori's existing metric definitions.

For example:

- net words
- words added
- words removed
- active time
- focus time
- session count

must remain distinct.

---

# 25. Leaderboard aggregation schema

Design for tables such as:

```text
leaderboard_daily
leaderboard_weekly
leaderboard_monthly
leaderboard_all_time
```

Possible fields:

```text
user_id
period_start
period_end
metric
value
rank/materialization metadata
updated_at
```

Do not necessarily store rank permanently if ranking can be computed efficiently.

For large populations, use materialized/precomputed rankings.

Index for:

- metric
- period
- value descending
- user_id

A user's private statistics must never appear on a public leaderboard simply because they exist in the database.

Leaderboard eligibility must be determined by privacy settings and participation status.

---

# 26. Leaderboard anti-cheat

This is a major architectural concern.

A malicious client could potentially fabricate statistics if the server blindly trusts client-submitted values.

Do not solve this by collecting keystrokes or manuscript contents.

Instead design a future validation layer.

Potential approaches:

- signed statistic batches
- server-issued session IDs
- plausibility checks
- event sequencing
- anomaly detection
- consistency checks against locally generated session data
- rate limits
- server-side aggregation
- trust/reputation levels

Do not claim that client-reported statistics are cryptographically truthful if they are not.

Document the threat model before enabling competitive global leaderboards.

For the initial implementation, create the interfaces and schema needed for validated aggregates, but do not pretend that an untrusted client can produce perfectly trustworthy worldwide rankings.

---

# 27. Public leaderboard privacy

A user may choose:

```text
leaderboards = off
leaderboards = public
```

Potential future options:

- global
- followers-only
- private

Do not expose email.

Do not expose private projects.

Do not expose manuscript contents.

A leaderboard row should contain only deliberately public information, such as:

```text
rank
username
display name
avatar
metric value
period
```

---

# 28. Public profile

Public profile should eventually support:

```text
/y/username
```

or another stable username route.

Display:

- username
- display name
- avatar
- optional bio
- follower count
- following count
- selected public statistics
- selected achievements
- leaderboard placement where permitted

Do not display email.

Do not display internal IDs.

Do not expose private statistics.

---

# 29. Social API design

Version APIs:

```text
/v1/...
```

Examples:

```text
GET    /v1/me
GET    /v1/users/:username
PATCH  /v1/me/profile

POST   /v1/users/:username/follow
DELETE /v1/users/:username/follow

GET    /v1/users/:username/followers
GET    /v1/users/:username/following

GET    /v1/leaderboards/:metric
GET    /v1/leaderboards/:metric/me
```

All endpoints must implement explicit authorization.

For every authenticated request ask:

```text
Who is the caller?
Which user/account do they belong to?
What resource are they requesting?
Are they allowed to access it?
```

Prevent IDOR.

---

# 30. Pagination

Social and leaderboard endpoints must use pagination.

Do not return unlimited rows.

Prefer cursor-based pagination for large/high-growth collections.

At minimum support:

- limit
- cursor
- deterministic ordering

Do not use offset pagination everywhere if the dataset will eventually be large.

---

# 31. Rate limiting

Implement rate limits for:

- login requests
- login-code verification
- username searches
- username changes
- follow/unfollow
- profile mutations
- leaderboard requests
- purchase claim attempts
- license validation
- installation registration
- admin endpoints

Rate-limit by appropriate combinations of:

- account
- IP
- endpoint
- installation where relevant

Do not rely on client-side rate limits.

---

# 32. Administration

Create a protected admin area/API.

Admin capabilities:

- search user
- inspect account
- inspect license
- inspect purchase record
- inspect installations
- revoke/restore license
- inspect webhook status
- inspect audit events
- handle purchase claims
- suspend account
- review abuse reports

Every administrative action must be audited.

Administrators must use separate authorization from normal users.

Do not rely on an `isAdmin` value supplied by the browser.

---

# 33. Audit events

Create an append-only audit/event system.

Possible table:

```text
audit_events

id UUID PRIMARY KEY
actor_user_id NULL
target_user_id NULL
event_type
source
metadata JSONB
created_at
```

Record:

- login
- failed login
- account changes
- username changes
- purchase association
- license creation
- license validation
- refund
- chargeback
- license revocation
- license restoration
- installation registration
- installation revocation
- follow events if needed for moderation/security
- administrative actions
- security events

Never store secrets in audit metadata.

---

# 34. Security requirements

Security is a release-blocking concern.

Implement:

- HTTPS
- secure cookies
- CSRF protection
- strict authentication
- authorization checks
- rate limiting
- input validation
- parameterized SQL
- ORM/query safety
- webhook signature verification
- replay protection
- secret management
- least-privilege database credentials
- encrypted production database/storage where provided
- encrypted backups
- dependency auditing
- security headers
- secure CORS policy
- no wildcard credentialed CORS
- no secrets in Git
- no secrets in client code
- no secrets in logs
- no payment-card storage
- no manuscript content in platform logs

Use a CSP appropriate to the chosen framework.

Do not disable TLS verification.

Do not add "temporary" security bypasses to production code.

---

# 35. Secret management

Create:

```text
website/.env.example
```

with placeholders such as:

```text
DATABASE_URL=
STRIPE_SECRET_KEY=
STRIPE_WEBHOOK_SECRET=
STRIPE_API_VERSION=
SESSION_SECRET=
EMAIL_PROVIDER_API_KEY=
EMAIL_FROM=
APP_BASE_URL=
API_BASE_URL=
LICENSE_SIGNING_PRIVATE_KEY=
LICENSE_SIGNING_KEY_ID=
```

Actual secrets must never be committed.

Add:

```text
.env
.env.*
!.env.example
```

or the equivalent appropriate ignore rules.

Do not put production secrets into the macOS application.

---

# 36. Local development

Create a local development environment.

Prefer:

```text
Docker Compose
├── website/API
└── PostgreSQL
```

The macOS application can point to the local API during development.

Development must have separate:

- database
- Stripe test mode
- signing keys
- email configuration
- API URL

Never accidentally point a development build at production.

---

# 37. Production hosting

The user currently has no website/server infrastructure.

The implementation must therefore include deployment documentation and production setup instructions.

Do NOT make deployment dependent on a specific provider unless there is a strong technical reason.

A sensible initial production architecture is:

```text
Domain
  ↓
HTTPS reverse proxy / managed ingress
  ↓
Yakitori website + API
  ↓
Managed PostgreSQL
```

Use one production application service initially.

Do not introduce Kubernetes.

Recommended deployment properties:

- automatic TLS
- automatic application restart
- environment/secret management
- managed PostgreSQL
- automated database backups
- database restore capability
- application health check
- logs
- uptime monitoring
- error monitoring
- DNS documentation

The deployment documentation must explicitly tell the user what external accounts/services they need to create.

At minimum:

1. domain/DNS provider
2. hosting provider
3. managed PostgreSQL
4. Stripe account
5. email delivery provider
6. Apple Developer account for commercial macOS distribution

The implementation must NOT require the user to know how to configure these services before OpenCode builds the local system.

OpenCode should build the platform so production configuration can be supplied later.

---

# 38. Website deployment structure

The website must live in the repository root:

```text
yakitori/website/
```

Do not put it outside the repository.

The website directory should contain everything necessary to build/deploy the web platform except secrets and external infrastructure state.

Keep infrastructure configuration documented in:

```text
docs/deployment.md
```

---

# 39. DNS plan

Document a future production DNS layout.

Example:

```text
yakitori.example
www.yakitori.example
api.yakitori.example
```

Possible simplification:

```text
yakitori.example
```

for website and API routes.

Choose the simpler design unless the selected hosting provider makes a subdomain architecture preferable.

Never hard-code the actual production domain before the user has selected it.

Use configuration:

```text
APP_BASE_URL
API_BASE_URL
```

---

# 40. Email

The platform needs transactional email for:

- login
- account verification
- purchase/account association
- security notifications
- possibly account recovery

Do not build an SMTP server.

Use a transactional email provider.

Create an abstraction:

```text
EmailProvider
    └── selected provider
```

Templates must not expose secrets.

Do not log login codes.

---

# 41. Database migrations

Use real migrations.

Requirements:

- migrations committed to Git
- no destructive auto-reset
- no production schema recreation
- migration tests
- production migration procedure
- backup before risky migrations
- documented recovery

Never run destructive database resets as part of normal startup.

---

# 42. Backups

The commercial database is critical.

Implement/document:

- automated backups
- retention
- encrypted backups
- restoration procedure
- periodic restore testing

Document the exact recovery procedure:

> If the production database is destroyed, how do we reconstruct user accounts, license ownership, and social identity?

Stripe remains an independent purchase record.

The platform should be able to reconcile purchases from Stripe after a catastrophic database loss.

---

# 43. Observability

Use structured logs.

Monitor:

- login failures
- login success
- account creation
- purchase events
- webhook receipt
- webhook failures
- webhook retries
- license creation
- license revocation
- license validation
- installation registration
- suspicious request volume
- API errors
- database errors
- email failures
- social abuse patterns

Never log:

- passwords
- login codes
- access tokens
- refresh tokens
- Stripe secrets
- signing private keys
- payment-card information
- manuscript content

---

# 44. Account deletion

Implement an explicit account deletion workflow.

Before deletion:

- require recent authentication
- explain consequences
- require confirmation

Determine what happens to:

- license history
- purchase records
- audit records
- username
- followers
- following
- leaderboard aggregates
- public profile

Do not accidentally erase legally/commercially necessary transaction records.

Historical public statistics must be either:

- removed
- anonymized
- retained under a clearly documented policy

Do not leave an orphaned profile.

---

# 45. Data separation

Keep these conceptual domains separate:

```text
Identity
Commerce
Licensing
Social
Writing Statistics
Leaderboards
Administration
```

Do not create one enormous "User" object that contains everything.

The domains may share `user_id`, but their responsibilities must remain clear.

Especially:

```text
Stripe customer/payment data
```

must not become public profile data.

---

# 46. Local-first writing application requirement

Nothing in this platform work may make the core tracker require an Internet connection.

The app must still:

- track locally
- calculate local statistics
- record sessions
- function during server outage
- function during temporary network loss

Cloud features are additive.

Licensing is the only reason the app needs periodic server communication before the social cloud exists.

---

# 47. Existing Yakitori analytics must remain authoritative

Do not rewrite the existing statistics system merely to support leaderboards.

Preserve the existing distinctions:

```text
focus time
active time
writing time
net manuscript change
words added
words removed
gross words worked
```

Never calculate leaderboard values from keystroke counts.

Never claim word precision for applications where Yakitori cannot obtain exact word counts.

The existing application-specific adapters remain responsible for exact word-count collection where supported.

---

# 48. Testing

Create automated tests for all new server functionality.

## Authentication

Test:

- valid login
- invalid login
- expired code
- reused code
- rate limit
- session creation
- session expiration
- logout
- session rotation
- unauthorized request

## Accounts

Test:

- creation
- email verification
- duplicate email
- deleted account
- suspended account
- profile creation

## Username

Test:

- valid username
- invalid username
- case-insensitive collision
- reserved username
- concurrent username claim
- cooldown
- change history

## Social

Test:

- follow
- unfollow
- duplicate follow
- self-follow rejection
- pagination
- privacy enforcement
- blocked-user behavior when implemented

## Stripe

Test:

- valid webhook
- invalid signature
- duplicate webhook
- malformed webhook
- purchase
- refund
- dispute
- event ordering
- retry behavior

## Licensing

Test:

- lifetime license creation
- validation
- revoked license
- disabled license
- unlimited installations
- installation registration
- multiple simultaneous Macs
- replacement Mac
- account claim
- duplicate claim
- unauthorized claim

## Offline

Test:

- valid cached authorization
- within grace period
- beyond grace period
- server outage
- explicit revocation
- clock rollback
- stale authorization
- signature failure

## Security

Test:

- SQL injection
- malformed input
- IDOR
- authorization bypass
- token theft scenarios
- replay
- rate limits
- admin authorization
- forged license authorization
- webhook spoofing

## Leaderboards

Test:

- opt-in
- opt-out
- private statistics
- public statistics
- aggregation correctness
- period boundaries
- timezone behavior
- duplicate aggregate submission
- impossible values
- ranking consistency

---

# 49. Critical invariants

Add tests/assertions for these.

1. A client cannot create its own license.
2. A Stripe webhook cannot create duplicate ownership when delivered twice.
3. Knowing another person's email is insufficient to steal their purchase.
4. A license is not tied to a particular Mac.
5. There is no hard device limit.
6. Server outage is not treated as revocation.
7. The app cannot forge a server authorization without the private signing key.
8. The licensing system does not require manuscript data.
9. Reinstalling Yakitori does not destroy ownership.
10. A replacement Mac can use the same lifetime license.
11. Email is not a public identity.
12. Stripe customer IDs are not public profile identifiers.
13. A private user never appears on a public leaderboard.
14. A user cannot modify another user's profile or social graph.
15. A user cannot alter another user's statistics.
16. A user cannot directly assign themselves a leaderboard score.
17. Deleting a local app installation does not delete account ownership.
18. Database recovery can reconstruct commercial ownership from authoritative records.

---

# 50. Security threat model

Document threats and mitigations for:

### License forgery
Signed server authorization.

### Server impersonation
TLS plus trusted public verification key and appropriate secure networking.

### Account takeover
Passwordless authentication, short-lived challenges, rate limits, session rotation, audit logs.

### Purchase theft
Verified email ownership and secure purchase claim flow.

### Webhook spoofing
Stripe signature verification.

### Webhook replay
External event ID idempotency.

### IDOR
Resource-level authorization.

### Username squatting
Reserved names, rate limits, username policies.

### Social spam
Rate limits and future moderation.

### Leaderboard cheating
Server validation, aggregation controls, anomaly detection, and explicit trust model.

### Database compromise
Least privilege, minimal data, encryption, backups, secret management.

### Secret leakage
Secret scanning and CI checks.

---

# 51. CI/CD

Add CI for:

- build
- unit tests
- integration tests
- database migration validation
- linting
- formatting
- dependency audit
- secret scanning
- website build
- API tests

Do not deploy if tests fail.

Do not deploy if production secrets are present in source.

---

# 52. Git requirements

The coding agent must:

1. inspect Git state first
2. never discard unrelated user work
3. never reset/clean the repository destructively
4. make logical commits
5. run tests before committing
6. commit completed logical changes
7. never commit secrets
8. explain migrations in commit messages
9. never silently delete data

Suggested commit groups:

```text
platform: add website foundation
platform: add PostgreSQL schema
auth: add passwordless authentication
commerce: add Stripe integration
licensing: add lifetime entitlement system
social: add profile and username system
social: add follow graph
leaderboards: add aggregate schema
security: harden authentication and API
deploy: add production configuration
docs: add commercial platform documentation
```

---

# 53. Implementation phases

Do NOT attempt to blindly build every feature in one giant untested change.

Implement in logical phases.

## Phase 1 — Audit

- inspect repository
- inspect existing architecture
- inspect Git
- write architecture audit
- identify integration points

No destructive changes.

## Phase 2 — Website/backend foundation

Create:

- `website/`
- application/API
- PostgreSQL
- migrations
- environment configuration
- health endpoint
- structured logging
- error handling
- tests
- Docker Compose

## Phase 3 — Identity

Implement:

- users
- email verification
- passwordless login
- sessions
- Keychain integration
- `/v1/me`
- account dashboard foundation

## Phase 4 — Public identity

Implement:

- profiles
- usernames
- reserved names
- username lookup
- username changes
- privacy settings

## Phase 5 — Stripe

Implement:

- product/price configuration
- Stripe Checkout / Managed Payments
- webhook endpoint
- signature verification
- idempotency
- purchase normalization
- refund/dispute handling

## Phase 6 — Licensing

Implement:

- license model
- purchase-to-license association
- secure claim
- validation
- revocation
- restoration
- signed authorization
- unlimited installations
- audit events

## Phase 7 — macOS integration

Implement:

- account login
- Keychain credentials
- installation ID
- license validation
- signed authorization verification
- offline grace period
- licensing state machine

Do not make the tracker cloud-dependent.

## Phase 8 — Social graph

Implement:

- follow/unfollow
- followers
- following
- privacy enforcement
- profile UI
- pagination

## Phase 9 — Leaderboard foundation

Implement:

- aggregate schema
- participation settings
- metric abstraction
- period abstraction
- validation interface
- leaderboard query API
- tests

If the existing app does not yet have a secure cloud-statistics submission mechanism, do not pretend the leaderboard is cheat-proof.

## Phase 10 — Admin

Implement:

- admin authorization
- user search
- license management
- purchase lookup
- installation management
- webhook monitoring
- audit log

## Phase 11 — Security hardening

Perform:

- threat-model review
- authorization review
- IDOR testing
- rate-limit review
- token review
- webhook review
- secret review
- dependency audit
- logging review
- abuse review

## Phase 12 — Production deployment

Document and prepare:

- domain
- DNS
- TLS
- hosting
- PostgreSQL
- Stripe production
- email provider
- backups
- monitoring
- deployment
- rollback
- disaster recovery

---

# 54. Production acceptance criteria

Do not declare this system complete until:

### Website

- website builds
- website can run locally
- production configuration is documented
- account UI works
- privacy/legal pages have locations
- website does not expose secrets

### Account

- user can create account
- email can be verified
- user can sign in
- user can sign out
- sessions are secure
- account can be deleted

### Commerce

- user can purchase Yakitori
- Stripe webhook is verified
- duplicate webhooks are safe
- purchase is recorded
- refunds are handled

### Licensing

- purchase produces lifetime entitlement
- entitlement belongs to user account
- unlimited Macs work
- reinstall works
- replacement Mac works
- cached authorization works offline
- explicit revocation works

### Social

- username can be created
- username is unique
- profile privacy works
- follow/unfollow works
- followers/following paginate
- private users remain private

### Leaderboards

- participation is opt-in/configurable
- private statistics remain private
- aggregate schema works
- rankings are deterministic
- metric definitions are documented
- cheating limitations are documented

### Operations

- database backups exist
- restore procedure exists
- logs exist
- monitoring exists
- secrets are externalized
- migrations are documented
- production deployment is reproducible

---

# 55. Important architectural boundary

Do not let the website become the application's writing engine.

The website/server exists for:

```text
identity
commerce
licensing
social
optional cloud aggregation
```

The macOS application remains responsible for:

```text
tracking
local persistence
word-count collection
session state
statistics calculation
analytics
privacy-sensitive writing data
```

The two communicate through explicit APIs.

---

# 56. What OpenCode should do if the existing repository conflicts with this document

Do not blindly overwrite the existing project.

If existing code already solves a problem:

1. inspect it
2. determine whether it is secure/correct
3. reuse it where appropriate
4. migrate it if necessary
5. document the decision

If a major architectural conflict exists, stop before making destructive changes and document the conflict in:

`docs/commercial-platform-architecture-audit.md`

Do not silently choose a new architecture that breaks existing Yakitori functionality.

---

# 57. Final instruction to OpenCode

Treat this as a commercial product, not a prototype.

Customers will pay money for Yakitori.

A compromised account, forged license, lost license database, incorrect refund handling, leaked email address, or corrupted leaderboard can damage the product and its users.

Security, correctness, data integrity, privacy, and recoverability take priority over speed.

At the same time, do not overengineer.

The desired initial production architecture is:

```text
              ┌─────────────────────┐
              │  Yakitori Website   │
              │      + API          │
              └──────────┬──────────┘
                         │
              ┌──────────┴──────────┐
              │     PostgreSQL      │
              └──────────┬──────────┘
                         │
       ┌─────────────────┼──────────────────┐
       │                 │                  │
     Stripe           Social           Licensing
       │                 │                  │
   purchases         usernames          lifetime
   refunds           follows            unlimited Macs
   disputes          profiles           signed auth
       │                 │                  │
       └─────────────────┼──────────────────┘
                         │
                  ┌──────┴──────┐
                  │ Yakitori    │
                  │ macOS App   │
                  └─────────────┘
```

Keep the system small, auditable, recoverable, and secure.

Do not build unnecessary infrastructure.

Do not sacrifice the local-first privacy model to make social features convenient.

Do not make a user's license depend on a specific machine.

Do not make payment provider data the user's identity.

Use `user_id` as the stable identity tying the platform together.
