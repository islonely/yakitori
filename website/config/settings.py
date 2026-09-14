"""
Django settings for the Yakitori commercial platform.

The platform is intentionally boring: one Django project, one PostgreSQL
database, server-rendered HTML with HTMX, and a small versioned JSON API.
Everything is configured through environment variables (see .env.example).

Importantly, this project never stores manuscript data. It exists for identity,
commerce, licensing, social features, and (future) aggregate statistics.
"""

import os
from pathlib import Path

from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent

load_dotenv(BASE_DIR / ".env")


def _env(name, default=""):
    value = os.getenv(name)
    return default if value is None else value


def _env_bool(name, default=False):
    value = os.getenv(name)
    if value is None:
        return default
    return value.lower() in {"1", "true", "yes", "on"}


def _env_int(name, default):
    try:
        return int(os.getenv(name, ""))
    except (TypeError, ValueError):
        return default


def _env_list(name, default=None):
    raw = os.getenv(name, "")
    values = [item.strip() for item in raw.split(",") if item.strip()]
    return values or list(default or [])


# ---------------------------------------------------------------------------
# Core
# ---------------------------------------------------------------------------

SECRET_KEY = _env(
    "SECRET_KEY",
    "django-insecure-dev-only-change-me-0000000000000000000000000000",
)

DEBUG = _env_bool("DEBUG", default=True)

ALLOWED_HOSTS = _env_list("ALLOWED_HOSTS", ["localhost", "127.0.0.1"])

# Public base URLs. Never hard-code the production domain; supply it later.
APP_BASE_URL = _env("APP_BASE_URL", "http://localhost:8000").rstrip("/")
API_BASE_URL = _env("API_BASE_URL", APP_BASE_URL).rstrip("/")
PLATFORM_NAME = _env("PLATFORM_NAME", "Yakitori")

# The only reason the macOS app needs the network is licensing/social features.
# Nothing here may be used to make tracking cloud-dependent.


# ---------------------------------------------------------------------------
# Applications
# ---------------------------------------------------------------------------

INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",

    "accounts",
    "profiles",
    "social",
    "commerce",
    "licensing",
    "leaderboards",
    "audit",
    "web",
    "dashboard",
    "adminconsole",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
    "config.middleware.SecurityHeadersMiddleware",
]

ROOT_URLCONF = "config.urls"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [BASE_DIR / "templates"],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
                "web.context_processors.platform",
            ],
        },
    },
]

WSGI_APPLICATION = "config.wsgi.application"
ASGI_APPLICATION = "config.asgi.application"


# ---------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------

DATABASES = {
    "default": {
        "ENGINE": os.getenv("DATABASE_ENGINE", "django.db.backends.postgresql"),
        "NAME": os.getenv("DATABASE_NAME", "yakitori"),
        "USER": os.getenv("DATABASE_USER", "yakitori"),
        "PASSWORD": os.getenv("DATABASE_PASSWORD", "devpassword"),
        "HOST": os.getenv("DATABASE_HOST", "localhost"),
        "PORT": os.getenv("DATABASE_PORT", "5432"),
        "CONN_MAX_AGE": _env_int("DATABASE_CONN_MAX_AGE", 60),
    }
}

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"


# ---------------------------------------------------------------------------
# Authentication
# ---------------------------------------------------------------------------

AUTH_USER_MODEL = "accounts.User"

# Password validators exist only for staff/superusers using the Django admin.
# Ordinary accounts authenticate with passwordless email challenges.
AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator"},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

LOGIN_URL = "/sign-in/"
LOGIN_REDIRECT_URL = "/dashboard/"
LOGOUT_REDIRECT_URL = "/"

# Browser sessions: signed, HttpOnly cookies. Short-lived, rotated on login.
SESSION_ENGINE = "django.contrib.sessions.backends.db"
SESSION_COOKIE_HTTPONLY = True
SESSION_COOKIE_SAMESITE = "Lax"
SESSION_COOKIE_SECURE = _env_bool("SESSION_COOKIE_SECURE", default=not DEBUG)
SESSION_COOKIE_AGE = _env_int("SESSION_COOKIE_AGE", 60 * 60 * 24 * 14)
SESSION_SAVE_EVERY_REQUEST = True

CSRF_COOKIE_HTTPONLY = False  # HTMX reads the token from the DOM.
CSRF_COOKIE_SAMESITE = "Lax"
CSRF_COOKIE_SECURE = _env_bool("CSRF_COOKIE_SECURE", default=not DEBUG)
CSRF_TRUSTED_ORIGINS = _env_list("CSRF_TRUSTED_ORIGINS", [])

# Login challenge policy (passwordless).
LOGIN_CHALLENGE_TTL_SECONDS = _env_int("LOGIN_CHALLENGE_TTL_SECONDS", 15 * 60)
LOGIN_CODE_TTL_SECONDS = _env_int("LOGIN_CODE_TTL_SECONDS", 10 * 60)
API_TOKEN_TTL_DAYS = _env_int("API_TOKEN_TTL_DAYS", 365)
DEVICE_CODE_TTL_SECONDS = _env_int("DEVICE_CODE_TTL_SECONDS", 15 * 60)
DEVICE_CODE_POLL_INTERVAL = _env_int("DEVICE_CODE_POLL_INTERVAL", 5)


# ---------------------------------------------------------------------------
# Security
# ---------------------------------------------------------------------------

SECURE_SSL_REDIRECT = _env_bool("SECURE_SSL_REDIRECT", default=not DEBUG)
SECURE_HSTS_SECONDS = _env_int("SECURE_HSTS_SECONDS", 0 if DEBUG else 31536000)
SECURE_HSTS_INCLUDE_SUBDOMAINS = not DEBUG
SECURE_HSTS_PRELOAD = not DEBUG
SECURE_CONTENT_TYPE_NOSNIFF = True
SECURE_REFERRER_POLICY = "same-origin"
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")

# Content-Security-Policy applied by config.middleware.SecurityHeadersMiddleware.
# HTMX is loaded from a CDN; everything else is same-origin.
CONTENT_SECURITY_POLICY = _env(
    "CONTENT_SECURITY_POLICY",
    "default-src 'self'; "
    "script-src 'self' https://unpkg.com 'unsafe-inline'; "
    "style-src 'self' 'unsafe-inline'; "
    "img-src 'self' data: https:; "
    "connect-src 'self'; "
    "font-src 'self'; "
    "frame-ancestors 'none'; "
    "base-uri 'self'; "
    "form-action 'self'",
)

# CORS is not enabled: the API is same-origin for the browser and token-based
# for native clients. Credentialed wildcard CORS is explicitly never used.
CORS_ALLOWED_ORIGINS = _env_list("CORS_ALLOWED_ORIGINS", [])


# ---------------------------------------------------------------------------
# Email
# ---------------------------------------------------------------------------

# EMAIL_PROVIDER selects the adapter in common.emails:
#   console  -> development, prints the message (default)
#   smtp     -> django.core.mail via EMAIL_* below
#   resend   -> Resend HTTP API (cheapest hosted option; no self-hosted server)
EMAIL_PROVIDER = _env("EMAIL_PROVIDER", "console")
EMAIL_BACKEND = _env(
    "EMAIL_BACKEND",
    "django.core.mail.backends.console.EmailBackend",
)
EMAIL_HOST = _env("EMAIL_HOST", "")
EMAIL_PORT = _env_int("EMAIL_PORT", 587)
EMAIL_HOST_USER = _env("EMAIL_HOST_USER", "")
EMAIL_HOST_PASSWORD = _env("EMAIL_HOST_PASSWORD", "")
EMAIL_USE_TLS = _env_bool("EMAIL_USE_TLS", default=True)
EMAIL_TIMEOUT = _env_int("EMAIL_TIMEOUT", 10)
DEFAULT_FROM_EMAIL = _env("EMAIL_FROM", "Yakitori <noreply@example.com>")
EMAIL_PROVIDER_API_KEY = _env("EMAIL_PROVIDER_API_KEY", "")


# ---------------------------------------------------------------------------
# Commerce (Stripe Managed Payments)
# ---------------------------------------------------------------------------

# The active provider is "mock" until real credentials are supplied. The mock
# provider exists so the entire flow is testable without Stripe access.
PAYMENT_PROVIDER = _env("PAYMENT_PROVIDER", "mock")
STRIPE_SECRET_KEY = _env("STRIPE_SECRET_KEY", "")
STRIPE_PUBLISHABLE_KEY = _env("STRIPE_PUBLISHABLE_KEY", "")
STRIPE_WEBHOOK_SECRET = _env("STRIPE_WEBHOOK_SECRET", "")
STRIPE_API_VERSION = _env("STRIPE_API_VERSION", "")
STRIPE_PRODUCT_ID = _env("STRIPE_PRODUCT_ID", "")
STRIPE_PRICE_ID = _env("STRIPE_PRICE_ID", "")

# Business policy. The customer-facing meaning of "lifetime" is defined here
# and repeated in the license agreement. It is a perpetual, non-expiring
# license tied to the account, not to a device, with unlimited installations.
PRODUCT_NAME = _env("PRODUCT_NAME", "Yakitori")
PRODUCT_PRICE_AMOUNT = _env_int("PRODUCT_PRICE_AMOUNT", 2900)
PRODUCT_PRICE_CURRENCY = _env("PRODUCT_PRICE_CURRENCY", "usd")
LICENSE_TYPE = "lifetime"


# ---------------------------------------------------------------------------
# Licensing / cryptography
# ---------------------------------------------------------------------------

# Ed25519 signing. The private key lives only server-side (environment or a
# secret manager); the matching public key is embedded in the macOS app.
# Formats accepted: base64 of the raw 32-byte seed, or a PEM PKCS#8 key.
LICENSE_SIGNING_KEY_ID = _env("LICENSE_SIGNING_KEY_ID", "dev-1")
LICENSE_SIGNING_PRIVATE_KEY = _env("LICENSE_SIGNING_PRIVATE_KEY", "")
LICENSE_SIGNING_PRIVATE_KEY_FILE = _env("LICENSE_SIGNING_PRIVATE_KEY_FILE", "")
# Which key id to embed as trusted is a client concern; the server may have
# older keys available for verification only. Format: "keyid=base64pub,keyid2=..."
LICENSE_VERIFICATION_PUBLIC_KEYS = _env("LICENSE_VERIFICATION_PUBLIC_KEYS", "")

# Offline behavior. A server outage must never lock a legitimate customer out.
LICENSE_OFFLINE_GRACE_DAYS = _env_int("LICENSE_OFFLINE_GRACE_DAYS", 30)


# ---------------------------------------------------------------------------
# Social / leaderboards
# ---------------------------------------------------------------------------

USERNAME_MIN_LENGTH = _env_int("USERNAME_MIN_LENGTH", 3)
USERNAME_MAX_LENGTH = _env_int("USERNAME_MAX_LENGTH", 30)
USERNAME_CHANGE_COOLDOWN_DAYS = _env_int("USERNAME_CHANGE_COOLDOWN_DAYS", 30)
USERNAME_RESERVED_EXTRA = _env_list("USERNAME_RESERVED_EXTRA", [])
FOLLOW_PAGE_SIZE = _env_int("FOLLOW_PAGE_SIZE", 50)
LEADERBOARD_PAGE_SIZE = _env_int("LEADERBOARD_PAGE_SIZE", 100)

# Rate limiting defaults, expressed as (limit, window_seconds).
RATE_LIMIT_DEFAULTS = {
    "login-request": (_env_int("RL_LOGIN_REQUEST", 8), 15 * 60),
    "login-verify": (_env_int("RL_LOGIN_VERIFY", 12), 15 * 60),
    "username-change": (_env_int("RL_USERNAME_CHANGE", 5), 24 * 60 * 60),
    "username-search": (_env_int("RL_USERNAME_SEARCH", 120), 60 * 60),
    "follow": (_env_int("RL_FOLLOW", 300), 60 * 60),
    "profile-mutation": (_env_int("RL_PROFILE_MUTATION", 60), 60 * 60),
    "leaderboard": (_env_int("RL_LEADERBOARD", 300), 60 * 60),
    "purchase-claim": (_env_int("RL_PURCHASE_CLAIM", 10), 60 * 60),
    "license-validate": (_env_int("RL_LICENSE_VALIDATE", 600), 60 * 60),
    "installation-register": (_env_int("RL_INSTALLATION_REGISTER", 60), 60 * 60),
    "admin": (_env_int("RL_ADMIN", 600), 60 * 60),
    "checkout": (_env_int("RL_CHECKOUT", 30), 60 * 60),
    "statistics-submit": (_env_int("RL_STATISTICS_SUBMIT", 120), 60 * 60),
}


# ---------------------------------------------------------------------------
# Static files
# ---------------------------------------------------------------------------

STATIC_URL = "/static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
STATICFILES_DIRS = [BASE_DIR / "static"]

MEDIA_URL = "/media/"
MEDIA_ROOT = BASE_DIR / "media"

STORAGES = {
    "default": {
        "BACKEND": "django.core.files.storage.FileSystemStorage",
    },
    "staticfiles": {
        "BACKEND": (
            "django.contrib.staticfiles.storage.StaticFilesStorage"
            if DEBUG
            else "whitenoise.storage.CompressedManifestStaticFilesStorage"
        ),
    },
}


# ---------------------------------------------------------------------------
# Internationalization
# ---------------------------------------------------------------------------

LANGUAGE_CODE = "en-us"
TIME_ZONE = _env("TIME_ZONE", "UTC")
USE_I18N = True
USE_TZ = True


# ---------------------------------------------------------------------------
# Logging (structured JSON to stdout; never log secrets or manuscript content)
# ---------------------------------------------------------------------------

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "json": {"()": "common.logging.JsonFormatter"},
        "plain": {"format": "[{levelname}] {name}: {message}", "style": "{"},
    },
    "handlers": {
        "stdout": {
            "class": "logging.StreamHandler",
            "formatter": "json" if not DEBUG else "plain",
        },
    },
    "root": {"handlers": ["stdout"], "level": _env("LOG_LEVEL", "INFO")},
    "loggers": {
        "django.request": {
            "handlers": ["stdout"],
            "level": "WARNING",
            "propagate": False,
        },
    },
}


# ---------------------------------------------------------------------------
# Platform policy (kept in one place rather than hard-coded in views)
# ---------------------------------------------------------------------------

RESERVED_USERNAMES = {
    "admin", "administrator", "support", "help", "billing", "security",
    "moderator", "official", "yakitori", "api", "system", "staff", "team",
    "root", "www", "about", "contact", "legal", "privacy", "terms", "login",
    "signup", "sign-in", "sign-up", "settings", "account", "accounts",
    "dashboard", "explore", "search", "static", "media", "null", "undefined",
    "me", "user", "users", "profile", "profiles", "download", "pricing",
}
RESERVED_USERNAMES |= set(USERNAME_RESERVED_EXTRA)
