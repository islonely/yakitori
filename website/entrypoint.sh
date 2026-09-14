#!/usr/bin/env bash
set -euo pipefail

# Apply committed migrations and collect static assets, then serve.
# `migrate` is additive and never resets the database.
python manage.py migrate --noinput
python manage.py collectstatic --noinput

exec gunicorn config.wsgi:application \
    --bind 0.0.0.0:8000 \
    --workers "${GUNICORN_WORKERS:-2}" \
    --threads "${GUNICORN_THREADS:-2}" \
    --worker-class gthread \
    --max-requests 2000 \
    --max-requests-jitter 200 \
    --timeout 60 \
    --graceful-timeout 30 \
    --access-logfile - \
    --error-logfile -
