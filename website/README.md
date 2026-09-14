# Yakitori Platform (`website/`)

The account, commerce, licensing, social, and web platform for Yakitori.

It is deliberately small and boring: **Django 6.1 + PostgreSQL + HTMX**, one web
service, one database. The macOS app remains local-first; nothing here makes the
tracker depend on the network.

- User-facing identity, purchases, licenses, social graph, and (future)
  leaderboards live here.
- Manuscript contents, document text, and raw keystrokes are **never** stored.

## Local development

Requires Docker (for PostgreSQL) and Python 3.12+.

```bash
cd website
docker compose up -d db            # PostgreSQL on localhost:5432

python3 -m venv .venv
.venv/bin/pip install -r requirements.txt

cp .env.example .env               # then edit SECRET_KEY etc.
.venv/bin/python manage.py migrate
.venv/bin/python manage.py createsuperuser
.venv/bin/python manage.py runserver
```

Open http://localhost:8000.

### Tests

```bash
.venv/bin/python manage.py test
```

Tests run against a temporary PostgreSQL test database created from the
credentials in `.env`.

## Configuration

All configuration is environment-driven; see `.env.example`. Two values matter
immediately:

- `PAYMENT_PROVIDER` — `mock` (default) runs the whole purchase/license flow
  without contacting Stripe. Set to `stripe` once credentials exist.
- `LICENSE_SIGNING_PRIVATE_KEY` — the Ed25519 private key used to sign license
  authorizations. Generate a development key with
  `python manage.py generate_signing_key`.

Never commit `.env` or real keys.

## Layout

| Path | Purpose |
|---|---|
| `config/` | Django project: settings, URLs, health check, middleware |
| `common/` | Shared helpers (JSON API, rate limiting, pagination, email, logging) |
| `accounts/` | Users, passwordless login, sessions, API tokens, device auth |
| `profiles/` | Public profile, username policy, privacy settings |
| `social/` | Follow graph, blocks, reports |
| `commerce/` | Payment providers, purchases, Stripe webhooks |
| `licensing/` | Lifetime licenses, installations, signed authorization |
| `leaderboards/` | Aggregate statistics and leaderboard queries |
| `audit/` | Append-only audit events |
| `web/` | Public marketing and legal pages |
| `dashboard/` | Authenticated account area |

## Documentation

Platform design and operations docs live in the repository root:

- `docs/commercial-platform-architecture-audit.md`
- `docs/account-architecture.md`
- `docs/licensing-architecture.md`
- `docs/social-architecture.md`
- `docs/leaderboard-architecture.md`
- `docs/security.md`
- `docs/deployment.md`
- `docs/disaster-recovery.md`

## Deployment

See `docs/deployment.md`. The intended production shape is one small server
running nginx + Gunicorn (systemd) + PostgreSQL, with automated backups.
