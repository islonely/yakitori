#!/usr/bin/env bash
#
# Restore the platform database from a backup.
#
#   ./restore.sh /var/backups/yakitori/yakitori-20260101-030000.dump.gpg
#
# This is destructive to the target database. Always confirm the target first,
# and take a fresh backup of the current database before restoring.

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <backup-file>" >&2
    exit 1
fi

backup="$1"
DB_NAME="${DATABASE_NAME:-yakitori}"
DB_USER="${DATABASE_USER:-yakitori}"
DB_HOST="${DATABASE_HOST:-localhost}"
DB_PORT="${DATABASE_PORT:-5432}"

echo "Target database: $DB_NAME on $DB_HOST:$DB_PORT"
read -r -p "Type the database name to confirm restore: " confirm
if [ "$confirm" != "$DB_NAME" ]; then
    echo "Aborted." >&2
    exit 1
fi

work="$backup"
if [[ "$backup" == *.gpg ]]; then
    work="${backup%.gpg}"
    gpg --yes --output "$work" --decrypt "$backup"
fi

pg_restore -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
    --clean --if-exists --no-owner "$work"

echo "Restore complete. Run migrations to confirm the schema is current:"
echo "  .venv/bin/python manage.py migrate"
