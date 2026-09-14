# Commercial Platform — Architecture Audit

**Status:** complete (Phase 1)
**Date:** 2026-09-13
**Scope:** Audit of the existing Yakitori macOS application and the integration
points for the account / commerce / licensing / social / web platform described
in `docs/commercial-platform-spec.md`.

This document records the state of the repository **before** platform work
began, the conventions the platform follows, and the decisions made where the
specification left room. It is intentionally written before any platform code so
that the existing application is not altered by assumption.

---

## 1. Repository and Git state at audit time

- **Branch:** `master`
- **Remote:** `origin` = `git@github.com:islonely/yakitori.git`
- **Working tree:** clean before the platform work; the only untracked file was
  the platform specification, which has since been moved to
  `docs/commercial-platform-spec.md`.
- **Recent history (before this work):**
  - `4ee9585 feat: show numeric progress on achievements`
  - `ee5266a fix: restore Word word-count parsing after trimming the adapter script`
  - `97300ce perf: activity via idle counter, pause-gated word sampling, no Accessibility`
  - `50f9fd7 feat: add ten additional analytics visualizations`
- **Existing tracked documentation:** `README.md`, `DESIGN_DOCUMENT.md`
  (moved to `docs/DESIGN_DOCUMENT.md` as part of this phase).
- `AGENTS.md` is local-only and gitignored by design.

No conflicting or in-progress work existed. No persistent data was modified.

---

## 2. Existing macOS application architecture

Yakitori is a single Swift Package (`Package.swift`, Swift 5.9+, macOS 13+)
with three targets:

| Target | Path | Role |
|---|---|---|
| `WritingTrackerCore` | `Sources/WritingTrackerCore` | Non-UI engine: persistence, tracking, statistics, services |
| `WritingTracker` (executable) | `Sources/WritingTrackerApp` | SwiftUI menu-bar app |
| `WritingTrackerCoreTests` | `Tests/WritingTrackerCoreTests` | 140 unit tests |

The app is local-first. All writing data lives on the user's Mac in
`~/Library/Application Support/Yakitori/Yakitori.sqlite`. There is **no
networking code, no Keychain code, and no account code** anywhere in the current
codebase.

### 2.1 Persistence

- `Persistence/Database.swift`, `SQLiteDatabase.swift`, `Migrator.swift` — a
  hand-rolled SQLite layer using the system `sqlite3` library (linked via
  `Package.swift`). Migrations are versioned inside the migrator.
- Repositories under `Repositories/` (`SessionRepository`,
  `DocumentRepository`, `ProjectRepository`, statistics repositories, etc.).
- `Services/ProjectAssociationService.swift` defines `AppPaths`, the single
  source of truth for on-disk locations:
  - application support directory: `.../Application Support/Yakitori/`
  - database: `.../Yakitori/Yakitori.sqlite`
  - `Backups/`, `Exports/`, `community.json`
- The existing database is **never** touched by the platform. There is no
  migration or schema coupling between the local SQLite store and the server.

### 2.2 Tracking engine

- `Tracking/TrackingEngine.swift` — polls the frontmost application, samples
  exact word counts from supported applications, and manages sessions.
- `Tracking/Monitors.swift` — `FrontmostApplicationMonitor`,
  `SystemIdleProviding` / `CGSystemIdleProvider` (idle counter polling at 2s),
  sleep and time-change monitors. **No global keyboard/mouse event monitors.**
- `Tracking/SessionStateMachine.swift` and `SessionRecordingPolicy.swift` —
  time accounting (active / focus time) and the rule that word-count sessions
  are only recorded when the net change is non-zero.
- `Integrations/*` — per-application adapters. Only Microsoft Word and Apple
  Pages obtain **exact** word counts (via AppleScript). All other applications
  (Scrivener, Ulysses, LibreOffice, Obsidian, browsers, etc.) are time-only and
  report that a word count is unavailable. Yakitori never estimates or infers
  words from keystrokes.
- Permissions: `Permissions/PermissionManager.swift` covers word-count
  automation, file access, notifications, and launch-at-login. **Accessibility
  is deliberately not required.**

### 2.3 Statistics and analytics

- `Statistics/StatisticsService.swift`, `StatisticsMath.swift`,
  `DailyAggregateBuilder.swift`, `ChartModels.swift` — bounded queries and
  local aggregation. The existing metric distinctions are authoritative and must
  be preserved: focus time, active time, writing time, net manuscript change,
  words added, words removed, gross words worked.
- `Analytics/AnalyticsService.swift` — the additional visualizations.
- `Services/ReportService.swift` — goals, streaks, achievements (with numeric
  progress).
- `Services/ExportService.swift`, `BackupService.swift`,
  `NotificationService.swift`.

### 2.4 Existing "social" code (placeholder only)

`Sources/WritingTrackerCore/Social/` contains the only thing resembling
platform code:

- `SocialBackend` protocol with a `JSONFileSocialBackend` that reads/writes
  `.../Yakitori/community.json`.
- `SocialService` — local, opt-in publishing of aggregate stats only; no
  document names, project names, paths, or manuscript text.
- `CommunityModels.swift` — `PublicStats`, `CommunityProfile`,
  `CommunityData`, `LeaderboardKind`, `LeaderboardEntry`, `WriterComparison`.
- `UI/Community/CommunityView.swift` and the Community settings section render
  this placeholder, clearly labelled sample entries.

This is a local prototype. It is **not** an online service and contains no
authentication, identity, or transport. It is the natural seam where the macOS
app can later talk to the real platform, but it must not be mistaken for an
existing backend.

### 2.5 App identity and distribution

- Bundle identifier `com.yakitori.app`, display name Yakitori, `LSUIElement`
  (menu-bar agent), macOS 13.0+, currently ad-hoc signed.
- `Packaging/Info.plist`, `Scripts/build-app.sh` (builds `dist/Yakitori.app`),
  `Scripts/make-icon.sh` + `Scripts/RenderIcon.swift` (icon generation).
- No Apple Developer distribution identity or notarization is configured yet.
  Commercial distribution will require an Apple Developer account (documented in
  `docs/deployment.md`).

---

## 3. Toolchain available in the development environment

- Node 23.7, npm 11.7, Bun 1.3 (not used by the chosen stack).
- Docker 29.7 (daemon running) — used to run PostgreSQL locally.
- Python 3.13.1 (Homebrew) — matches the reference project.
- Xcode / Swift 6 toolchain for the macOS app.

The reference project `~/Documents/naphtali-canon` is a production Django 6.1 +
PostgreSQL + HTMX application. The user selected **the same stack** for the
Yakitori platform in preference to the TypeScript default suggested by the spec.

---

## 4. Chosen platform architecture and rationale

The platform lives entirely inside a root-level `website/` directory, as the
spec requires. It is a **Django 6.1** project (one web application + one JSON
API service) talking to **PostgreSQL 18** through **psycopg 3**. Server-rendered
Django templates plus **HTMX** provide the website; a hand-rolled versioned JSON
API under `/v1/` serves the macOS app and future clients.

This deliberately mirrors `naphtali-canon` conventions:

- `config/` project package with environment-driven `settings.py` via
  `python-dotenv`.
- One Django app per domain, function-based views, templates under
  `templates/`, HTMX partials prefixed with `_`.
- Dependencies pinned in `requirements.txt` (`Django`, `psycopg`,
  `psycopg-binary`, `python-dotenv`, `whitenoise`, plus `gunicorn`, the Stripe
  SDK, and `cryptography` for Ed25519 signing).
- Tests use Django's `TestCase` and `Client` (`manage.py test`).
- `compose.yaml` runs PostgreSQL for local development only.
- Deployment is documented for a single small server (nginx + Gunicorn +
  systemd + local/managed PostgreSQL), consistent with `DEPLOY.md`.

The spec's directory names (`app/`, `api/`) are satisfied functionally by Django
apps (`web/`, `dashboard/`, plus one app per domain) and a versioned API layer;
the spec explicitly permits framework selection after inspection.

### 4.1 Domain separation

The spec's identity/commerce/licensing/social/statistics/leaderboards/admin
boundaries are implemented as separate Django apps sharing a `user_id`:

| Domain | App |
|---|---|
| Identity / login / sessions / API tokens | `accounts` |
| Public profile / username / privacy | `profiles` |
| Follow graph / blocks / reports | `social` |
| Purchases / payment providers / webhooks | `commerce` |
| Lifetime licenses / installations / signed authorization | `licensing` |
| Aggregate statistics / leaderboards | `leaderboards` |
| Append-only audit events | `audit` |
| Public marketing / legal pages | `web` |
| Authenticated account area (HTML) | `dashboard` |
| Administrative API (staff-only, audited) | `adminconsole` |

No giant "User" object holds commerce or profile data.

### 4.2 Identity model

- `accounts.User` is a custom `AbstractUser` with `username = None`, `email`
  as `USERNAME_FIELD`, a UUID primary key, `email_normalized`, verification
  timestamp, and a lifecycle `status`. It retains Django's `password` field
  **only** so staff/superusers can use the Django admin; ordinary accounts are
  created with an unusable password and authenticate with passwordless email
  challenges. This resolves the spec's "no passwords" requirement without
  losing admin access.
- Public identity (`username`, `display_name`, `bio`, `avatar_url`,
  `visibility`) lives in `profiles.Profile`, never on `User`.
- Browser sessions use Django's signed, HttpOnly cookie sessions.
- The macOS app uses a browser-based device authorization flow and receives a
  long-lived API token stored in the macOS Keychain.

### 4.3 Licensing

- Lifetime licenses only (`license_type = "lifetime"`, `expires_at = NULL`),
  unlimited installations, no hardware fingerprints, no device limits.
- The client receives a **signed authorization** (Ed25519) from the server and
  verifies it with an embedded public key. The private signing key exists only
  server-side. Key IDs and rotation are supported.
- An explicit offline grace period (default 30 days, configurable) keeps the
  app working during a licensing-server outage. Server outage is never treated
  as revocation; an explicit server-side revocation overrides cached
  authorization.
- The macOS local database is never uploaded. Only deliberately public
  aggregate numbers may ever leave the device.

---

## 5. Integration points with the existing macOS application

The platform is additive. Nothing in this work makes the tracker require a
network connection.

1. **Identity / ownership (Phase 7)** — a new account/licensing service in
   `WritingTrackerCore` will hold the API token in the Keychain, create a random
   cryptographically secure `installation_id` (not derived from hardware),
   register the installation, verify the signed authorization offline, and
   expose license state to the UI. It is injected through `AppContainer`, like
   every other service.
2. **Social / leaderboards (later)** — the existing `SocialBackend` protocol is
   the seam. A future `APISocialBackend` can implement the same protocol against
   the platform's `/v1/` endpoints without changing `SocialService` or the
   community UI. This phase builds the server side; it does not replace the
   local JSON placeholder.
3. **No changes** are made to tracking, word-count collection, statistics,
   persistence, or existing privacy behavior.

---

## 6. Decisions where the specification left room

| Decision | Choice |
|---|---|
| Web framework | Django 6.1 (spec default was TypeScript; user selected Django/HTMX, matching `naphtali-canon`) |
| ORM / migrations | Django ORM + Django migrations |
| API style | Hand-rolled versioned JSON (`/v1/`) using Django views; no DRF dependency |
| Passwordless transport | Short-lived single-use login challenges delivered by email link + code |
| macOS auth | RFC-8628-style device authorization flow + Keychain API token |
| Payments | `PaymentProvider` abstraction with a `MockPaymentProvider` (dev/tests) and `StripeManagedPaymentsProvider` (real) |
| Email | `EmailProvider` abstraction; Django console backend in development, SMTP/transactional provider configured by environment |
| Signing | Ed25519 (`cryptography`), dev keypair generated by a management command |
| Database | PostgreSQL 18 (Docker Compose locally; managed or local in production) |
| Localization / time | `USE_TZ = True`; period boundaries computed in a configured timezone |
| Deployment | One application service (nginx + Gunicorn + systemd) + PostgreSQL; provider-agnostic, documented |

## 7. Known limitation carried forward (documented, not hidden)

The spec's anti-cheat section is explicit that **client-reported statistics
cannot be cryptographically trusted**. This phase builds the aggregate schema,
the participation/privacy controls, and a validation interface — it does not
claim that global rankings are cheat-proof. The threat model and the trust
limitations are documented in `docs/leaderboard-architecture.md` and
`docs/security.md`.

---

## 8. Explicit non-goals

- The website is **not** the application's writing engine. Tracking, local
  persistence, word-count collection, session state, and statistics remain on
  the Mac.
- No manuscript contents, document text, raw keystrokes, clipboard contents, or
  private document names are uploaded.
- The local SQLite database is not modified, migrated, or deleted by any
  platform work.
- Kubernetes, microservices, Redis, Kafka, and similar infrastructure are not
  introduced.

---

## 9. Phase plan

1. Audit (this document).
2. Website / backend foundation.
3. Identity.
4. Public identity.
5. Stripe / commerce.
6. Licensing.
7. macOS integration.
8. Social graph.
9. Leaderboard foundation.
10. Admin.
11. Security hardening.
12. Production deployment.
