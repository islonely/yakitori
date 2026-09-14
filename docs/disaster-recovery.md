# Disaster Recovery

The commercial database is critical: it holds accounts, purchases, licenses, and
social identity. This document defines what to protect and exactly how to
recover.

## Objectives

| Metric | Target |
|---|---|
| RPO (acceptable data loss) | ≤ 24 hours (daily backups); ≤ 5 minutes with managed PITR |
| RTO (time to restore) | ≤ 1 hour with a current backup and a prepared host |

Both improve if you use a managed PostgreSQL with point-in-time recovery and
automated snapshots. Use the provided `deploy/backup.sh` for a self-managed
server and **also** keep a copy off the host.

## What must never be lost

1. **Accounts** — `accounts_user` (email, status).
2. **Profiles** — the public identity.
3. **Purchases** — `commerce_paymentpurchase`.
4. **Licenses** — `licensing_license`, `licensing_installation`.
5. **Audit history** — `audit_auditevent` (append-only).

Writing data is **not** in this database. It lives on each customer's Mac and is
never uploaded, so a platform disaster cannot lose anyone's manuscript.

## Backups

- Automated daily `pg_dump` (custom format), optionally GPG-encrypted.
- Retention of at least 30 days (local) plus periodic off-host copies.
- Managed PostgreSQL: enable automated backups and PITR if available.
- **Test restores**: periodically restore into an isolated database and run
  `manage.py migrate` and a sanity query (row counts per table).

Verify a backup exists and is non-empty before trusting it. `backup.sh` fails
loudly if no dump was produced.

## Restore procedure

1. Stop the application (`sudo systemctl stop yakitori`) to freeze writes.
2. Create a fresh target database if needed.
3. Restore:

   ```bash
   cd /srv/yakitori/website
   ./deploy/restore.sh /var/backups/yakitori/yakitori-YYYYMMDD-HHMMSS.dump.gpg
   ```

   The script asks you to type the database name to confirm.
4. Apply any migrations committed after the backup was taken:

   ```bash
   .venv/bin/python manage.py migrate
   ```

5. Start the application and verify:

   ```bash
   sudo systemctl start yakitori
   curl -fsS https://yakitori.example/healthz
   ```

6. Spot-check: sign in, view the dashboard, validate a license.

## Reconstructing ownership after catastrophic loss

If the database is destroyed and no backup is usable:

1. **Stripe is the independent purchase record.** Export customers, payments,
   and subscriptions from the Stripe dashboard/API. Each completed payment has
   an email and a provider purchase id.
2. **Recreate accounts** for the purchase emails. Passwordless login means users
   can verify their own email; no password reset is required.
3. **Re-associate purchases.** Use the admin purchase-claim review flow
   (`/v1/admin/purchase-claims`) rather than bulk-creating licenses blindly. If
   you script it, require the purchase email to match a verified account email.
4. **Re-grant licenses** for each completed, non-refunded purchase.

This is why the platform separates purchases from licenses and keeps the Stripe
record authoritative: ownership can be rebuilt even if the database cannot.

## Signing key recovery

- The Ed25519 **private** key is a secret; keep it in a secret manager and in a
  secure offline copy. Losing it means you can no longer issue authorizations
  that existing app builds trust.
- If it is lost, generate a new key id, ship an app update that trusts the new
  public key, and re-validate all clients.
- If it is **compromised**, rotate immediately: create a new key id, publish an
  app update, and revoke/restore affected licenses as needed.

## Account deletion vs. disaster

Account deletion is a deliberate, reviewed workflow that retains legally
necessary transaction history and never leaves an orphaned profile. It is not a
backup event and does not delete purchase or audit records.

## Runbook summary

```
Backup daily (encrypted) ──► off-host copy ──► periodic restore test
        │
        ├─ database lost ──► restore latest dump ──► migrate ──► verify
        │
        └─ no usable dump ──► rebuild accounts from Stripe ──► review claims
                              ──► re-grant licenses
```

## What NOT to do

- Do not delete production records to make an application problem go away.
- Do not `migrate zero` on production data.
- Do not empty tables as a troubleshooting step.
- Do not treat a migration file as a backup.
