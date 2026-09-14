# Deployment

This document explains how to put the Yakitori platform into production. It is
provider-agnostic but describes one concrete, boring path: **one small Linux
server** running nginx + Gunicorn (systemd) + PostgreSQL, with a managed
PostgreSQL option. No Kubernetes, no microservices.

You do **not** need any external accounts to run the platform locally. This
document is for production only.

## 1. External accounts you will need

| # | Service | Purpose | Notes |
|---|---|---|---|
| 1 | Domain / DNS | `APP_BASE_URL` | Any registrar; add an A record later |
| 2 | Hosting | runs the app | A 2 GB Ubuntu instance is enough to start |
| 3 | PostgreSQL | managed DB, or local on the same box | Managed is recommended for backups |
| 4 | Stripe | Managed Payments | Live keys + webhook signing secret |
| 5 | Transactional email | login links/codes | e.g. Resend free tier, Postmark, SES |
| 6 | Apple Developer | signing/notarizing the macOS app | Required for commercial macOS distribution |

Nothing here must be created before local development; the platform is built to
run with placeholders (`PAYMENT_PROVIDER=mock`, `EMAIL_PROVIDER=console`).

## 2. DNS

Choose one of:

```text
yakitori.example                     # simplest: website + API on one host
```

or, if the host prefers separate origins:

```text
yakitori.example
www.yakitori.example
api.yakitori.example
```

Point the chosen host at the server's static IP. Set `APP_BASE_URL` and
`API_BASE_URL` to the real origin(s). Never hard-code a domain in source.

## 3. Configuration

Copy `.env.example` to `.env` on the server (mode `600`, owned by the service
user) and fill in:

```text
SECRET_KEY=<long random string>
DEBUG=false
ALLOWED_HOSTS=yakitori.example
TIME_ZONE=UTC

DATABASE_*=<your database>

APP_BASE_URL=https://yakitori.example
API_BASE_URL=https://yakitori.example

PAYMENT_PROVIDER=stripe
STRIPE_SECRET_KEY=...
STRIPE_WEBHOOK_SECRET=...
STRIPE_API_VERSION=...
STRIPE_PRICE_ID=...
STRIPE_PRODUCT_ID=...

EMAIL_PROVIDER=resend
EMAIL_PROVIDER_API_KEY=...
EMAIL_FROM=Yakitori <noreply@yakitori.example>

LICENSE_SIGNING_KEY_ID=prod-1
LICENSE_SIGNING_PRIVATE_KEY=<generated with manage.py generate_signing_key>
LICENSE_OFFLINE_GRACE_DAYS=30
```

Generate a random `SECRET_KEY`:

```bash
python3 -c "import secrets; print(secrets.token_urlsafe(50))"
```

Generate the license signing keypair and keep the private half only here:

```bash
python -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/python manage.py generate_signing_key --key-id prod-1
```

Embed the printed **public** key in the macOS app. Rotate by generating a new
key id and shipping an app build that trusts both, then stop signing with the
old id.

Never commit `.env`.

## 4. Server preparation (single-server option)

```bash
sudo apt update && sudo apt upgrade -y
sudo adduser --disabled-password yakitori
sudo apt install -y python3.12-venv python3-pip postgresql postgresql-contrib \
    nginx certbot python3-certbot-nginx git

sudo mkdir -p /srv/yakitori
sudo chown yakitori:yakitori /srv/yakitori
sudo -u yakitori git clone git@github.com:islonely/yakitori.git /srv/yakitori
```

### PostgreSQL

```bash
sudo -u postgres psql -c "CREATE USER yakitori WITH PASSWORD 'changeme';"
sudo -u postgres createdb -O yakitori yakitori
```

Create the database with least-privilege credentials; point `DATABASE_*` at it.

## 5. Install and migrate

```bash
cd /srv/yakitori/website
sudo -u yakitori python3 -m venv .venv
sudo -u yakitori .venv/bin/pip install -r requirements.txt

sudo -u yakitori .venv/bin/python manage.py migrate
sudo -u yakitori .venv/bin/python manage.py collectstatic --noinput
sudo -u yakitori .venv/bin/python manage.py createsuperuser
```

Migrations are additive and committed; they are never auto-reset. Run them as an
explicit deploy step.

## 6. Application service (Gunicorn + systemd)

```bash
sudo cp /srv/yakitori/website/deploy/yakitori.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now yakitori
sudo systemctl status yakitori
```

Useful commands:

```bash
sudo journalctl -u yakitori -f     # live logs
sudo systemctl restart yakitori    # after a deploy
```

## 7. nginx and TLS

```bash
sudo cp /srv/yakitori/website/deploy/nginx.conf /etc/nginx/sites-available/yakitori
sudo ln -s /etc/nginx/sites-available/yakitori /etc/nginx/sites-enabled/
# edit server_name to your domain, then:
sudo nginx -t
sudo certbot --nginx -d yakitori.example
sudo systemctl reload nginx
```

`deploy/nginx.conf` sets `X-Forwarded-Proto`, which the app trusts for
`SECURE_PROXY_SSL_HEADER`.

## 8. Stripe

1. Create the product and a one-time price in Stripe (Managed Payments).
2. Put the price/product ids in `.env` (`STRIPE_PRICE_ID`, `STRIPE_PRODUCT_ID`).
3. Add a webhook endpoint pointing at `https://yakitori.example/v1/webhooks/stripe`.
4. Subscribe to at least: checkout session completed, charge refunded, dispute
   created, dispute closed.
5. Put the webhook signing secret in `STRIPE_WEBHOOK_SECRET`.
6. Set `PAYMENT_PROVIDER=stripe`.

Local development uses the mock provider and takes no real payment.

## 9. Email

In development the default is `EMAIL_PROVIDER=console`, which **prints the email
to the server terminal** instead of delivering it — so there is nothing in your
inbox until you configure a provider. Verify any configuration with:

```bash
cd website
.venv/bin/python manage.py send_test_email you@example.com
```

Choose one:

- **Resend** (easiest real delivery; free tier):
  `EMAIL_PROVIDER=resend`, `EMAIL_PROVIDER_API_KEY=re_...`,
  `EMAIL_FROM=Yakitori <onboarding@resend.dev>` (test mode only sends to your
  own address). After verifying a domain, use
  `EMAIL_FROM=Yakitori <noreply@yourdomain>`.
- **SMTP** (Gmail app password, Postmark, SES, …): `EMAIL_PROVIDER=smtp` plus
  `EMAIL_HOST`, `EMAIL_PORT`, `EMAIL_USE_TLS`, `EMAIL_HOST_USER`,
  `EMAIL_HOST_PASSWORD`, and `EMAIL_FROM`. Selecting `smtp` always sends over
  SMTP; it does not depend on `EMAIL_BACKEND`.

The console provider refuses to run when `DEBUG` is false, so production cannot
silently drop mail. Verify the sending domain (SPF/DKIM) before launch.

### Why a sign-up might show "check your email" with no email

Two intentional behaviours can look like this:

1. **Console provider in development.** The link/code is in the terminal, not
   your inbox. Configure a provider as above.
2. **Rate limiting.** Sign-up/sign-in requests are limited per IP and per
   address. When the limit is hit the form now shows "Too many attempts" rather
   than pretending an email was sent. Wait a few minutes and retry.

## 10. Backups

Use the provided script, ideally on managed PostgreSQL plus an off-host copy:

```bash
sudo mkdir -p /var/backups/yakitori
sudo crontab -e
# 30 3 * * * /srv/yakitori/website/deploy/backup.sh >> /var/log/yakitori-backup.log 2>&1
```

The script dumps in custom format, optionally GPG-encrypts, verifies a dump was
produced, and prunes old files. See `docs/disaster-recovery.md` for restore and
reconciliation.

## 11. Monitoring

- **Health check:** `GET /healthz` returns `200` when the app and database are
  reachable, `503` otherwise. Point uptime monitoring at it.
- **Logs:** structured JSON on stdout; collect via `journalctl` or your host's
  log drain.
- **Errors:** optionally add Sentry (or equivalent) to `config/settings.py`;
  never send secrets or manuscript data.
- **Metrics to watch:** login failures, webhook failures, license validations,
  5xx rate, database connections.

## 12. Deploying updates

```bash
cd /srv/yakitori
sudo -u yakitori git pull
cd website
sudo -u yakitori .venv/bin/pip install -r requirements.txt
sudo -u yakitori .venv/bin/python manage.py migrate
sudo -u yakitori .venv/bin/python manage.py collectstatic --noinput
sudo systemctl restart yakitori
```

### Rollback

1. `git checkout <previous-tag-or-sha>`
2. Reinstall requirements, `collectstatic`, `systemctl restart yakitori`.
3. If a migration must be reversed, restore from the pre-deploy backup (never
   `migrate zero` on production data).

### Pre-deploy checklist

```bash
cd website
.venv/bin/python manage.py check --deploy
.venv/bin/python manage.py makemigrations --check --dry-run
.venv/bin/python manage.py test
python scripts/secret_scan.py
```

`check --deploy` should be clean (aside from intentionally disabled features);
CI runs the test suite, migration check, dependency audit, and secret scan
before anything is deployed.
