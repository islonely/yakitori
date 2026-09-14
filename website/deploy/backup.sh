#!/usr/bin/env bash
#
# Back up the platform database, encrypted, with retention.
# Suggested cron (as root):
#   30 3 * * * /srv/yakitori/website/deploy/backup.sh >> /var/log/yakitori-backup.log 2>&1
#
# Requires: pg_dump, gpg. Set GPG_RECIPIENT to a public key you control, or
# remove encryption only if the destination is already encrypted at rest.

set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/var/backups/yakitori}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
GPG_RECIPIENT="${GPG_RECIPIENT:-}"

DB_NAME="${DATABASE_NAME:-yakitori}"
DB_USER="${DATABASE_USER:-yakitori}"
DB_HOST="${DATABASE_HOST:-localhost}"
DB_PORT="${DATABASE_PORT:-5432}"

mkdir -p "$BACKUP_DIR"
stamp="$(date +%Y%m%d-%H%M%S)"
target="$BACKUP_DIR/yakitori-$stamp.dump"

pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -Fc -f "$target"

if [ -n "$GPG_RECIPIENT" ]; then
    gpg --yes --encrypt --recipient "$GPG_RECIPIENT" "$target"
    rm -f "$target"
fi

# Verify a non-empty backup exists before pruning older ones.
if ! ls -1 "$BACKUP_DIR"/yakitori-* >/dev/null 2>&1; then
    echo "Backup failed: no dump was produced." >&2
    exit 1
fi

find "$BACKUP_DIR" -name 'yakitori-*' -type f -mtime "+$RETENTION_DAYS" -delete
echo "Backup complete: $target"
