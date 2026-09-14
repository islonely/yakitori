import json

from django.core import mail
from django.test import Client, TestCase, override_settings
from django.utils import timezone
from datetime import timedelta

from audit.models import AuditEvent
from common.ratelimit import check

from . import services
from .models import ApiToken, LoginChallenge, User


@override_settings(
    EMAIL_PROVIDER="console",
    EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend",
)
class PasswordlessLoginTests(TestCase):
    def test_request_login_creates_challenge_and_sends_email(self):
        response = self.client.post("/sign-in/", {"email": "Writer@Example.com"})
        self.assertEqual(response.status_code, 302)
        self.assertEqual(response.url, "/sign-in/sent/")

        challenge = LoginChallenge.objects.get()
        self.assertEqual(challenge.email_normalized, "writer@example.com")
        self.assertEqual(len(mail.outbox), 1)
        self.assertIn("Sign in to", mail.outbox[0].subject)

    def test_unknown_email_gets_identical_response(self):
        first = self.client.post("/sign-in/", {"email": "a@example.com"})
        second = self.client.post("/sign-in/", {"email": "b@example.com"})
        self.assertEqual(first.status_code, second.status_code)
        self.assertEqual(first.url, second.url)

    def test_verify_token_creates_account_and_signs_in(self):
        challenge = services.request_login("new@example.com")
        # Derive a fresh challenge whose token we know by re-creating directly.
        token = "known-token-value"
        LoginChallenge.objects.all().delete()
        LoginChallenge.objects.create(
            email_normalized="new@example.com",
            token_hash=services.sha256_hex(token),
            code_hash=services.sha256_hex("123456"),
            expires_at=timezone.now() + timedelta(minutes=10),
        )

        response = self.client.get(f"/sign-in/{token}/")
        self.assertEqual(response.status_code, 302)
        self.assertEqual(response.url, "/dashboard/")

        user = User.objects.get(email_normalized="new@example.com")
        self.assertIsNotNone(user.email_verified_at)
        self.assertTrue(
            AuditEvent.objects.filter(event_type=AuditEvent.Type.ACCOUNT_CREATED).exists()
        )
        self.assertTrue(
            AuditEvent.objects.filter(event_type=AuditEvent.Type.LOGIN_SUCCEEDED).exists()
        )

        dashboard = self.client.get("/dashboard/")
        self.assertEqual(dashboard.status_code, 200)
        self.assertContains(dashboard, "new@example.com")

    def test_token_is_single_use(self):
        token = "single-use-token"
        LoginChallenge.objects.create(
            email_normalized="once@example.com",
            token_hash=services.sha256_hex(token),
            code_hash=services.sha256_hex("000000"),
            expires_at=timezone.now() + timedelta(minutes=10),
        )
        first = self.client.get(f"/sign-in/{token}/")
        self.assertEqual(first.status_code, 302)
        self.client.logout()
        second = self.client.get(f"/sign-in/{token}/")
        self.assertEqual(second.status_code, 400)

    def test_expired_token_rejected(self):
        token = "expired-token"
        LoginChallenge.objects.create(
            email_normalized="late@example.com",
            token_hash=services.sha256_hex(token),
            code_hash=services.sha256_hex("000000"),
            expires_at=timezone.now() - timedelta(seconds=1),
        )
        response = self.client.get(f"/sign-in/{token}/")
        self.assertEqual(response.status_code, 400)
        self.assertFalse(User.objects.filter(email_normalized="late@example.com").exists())

    def test_code_login(self):
        challenge = services.request_login("code@example.com")
        code = "424242"
        challenge.code_hash = services.sha256_hex(code)
        challenge.save(update_fields=["code_hash"])

        response = self.client.post(
            "/sign-in/code/", {"email": "code@example.com", "code": code}
        )
        self.assertEqual(response.status_code, 302)
        self.assertTrue(User.objects.filter(email_normalized="code@example.com").exists())

    def test_suspended_user_cannot_sign_in(self):
        user = User.objects.create_user(email="suspended@example.com")
        user.status = User.Status.SUSPENDED
        user.save()

        token = "suspended-token"
        LoginChallenge.objects.create(
            email_normalized="suspended@example.com",
            token_hash=services.sha256_hex(token),
            code_hash=services.sha256_hex("000000"),
            expires_at=timezone.now() + timedelta(minutes=10),
        )
        response = self.client.get(f"/sign-in/{token}/")
        self.assertEqual(response.status_code, 400)

    def test_sign_up_throttle_shows_an_error(self):
        with override_settings(
            RATE_LIMIT_DEFAULTS={"login-request": (1, 3600)}
        ):
            first = self.client.post(
                "/sign-up/",
                {"email": "once@example.com", "accepted_terms": "on"},
            )
            self.assertEqual(first.status_code, 302)

            second = self.client.post(
                "/sign-up/",
                {"email": "once@example.com", "accepted_terms": "on"},
            )
            self.assertEqual(second.status_code, 200)
            self.assertContains(second, "Too many attempts")

    def test_rate_limit_records_attempts(self):
        for _ in range(5):
            self.assertTrue(check(None, "login-request", scope="ip:1.2.3.4"))
        # window and limit are configurable; verify the counter grew.
        from .models import RateLimitEntry

        entry = RateLimitEntry.objects.get(key="login-request:ip:1.2.3.4")
        self.assertEqual(entry.attempts, 5)


class DeviceAuthorizationTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(email="device@example.com")

    def _start(self):
        response = self.client.post(
            "/v1/auth/device/start",
            data=json.dumps({"client_name": "Yakitori for Mac"}),
            content_type="application/json",
        )
        return response.json()

    def test_full_device_flow(self):
        start = self._start()
        self.assertIn("user_code", start)
        self.assertIn("device_code", start)

        # Unauthenticated approval is redirected to sign in.
        page = self.client.get("/device/")
        self.assertEqual(page.status_code, 302)

        self.client.force_login(self.user)
        approval = self.client.post(
            "/device/",
            {"user_code": start["user_code"], "action": "approve"},
        )
        self.assertEqual(approval.status_code, 200)
        self.assertContains(approval, "Device approved")

        token_client = Client()
        exchange = token_client.post(
            "/v1/auth/device/token",
            data=json.dumps({"device_code": start["device_code"]}),
            content_type="application/json",
        )
        self.assertEqual(exchange.status_code, 200)
        token = exchange.json()["token"]
        self.assertTrue(token)

        me = token_client.get("/v1/me", HTTP_AUTHORIZATION=f"Bearer {token}")
        self.assertEqual(me.status_code, 200)
        self.assertEqual(me.json()["user"]["email"], "device@example.com")

        # The device code cannot be exchanged twice.
        again = token_client.post(
            "/v1/auth/device/token",
            data=json.dumps({"device_code": start["device_code"]}),
            content_type="application/json",
        )
        self.assertEqual(again.status_code, 400)

    def test_pending_device_returns_authorization_pending(self):
        start = self._start()
        response = self.client.post(
            "/v1/auth/device/token",
            data=json.dumps({"device_code": start["device_code"]}),
            content_type="application/json",
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json()["error"]["code"], "authorization_pending")

    def test_polling_is_not_rate_limited_per_ip(self):
        start = self._start()
        # A client polls once per interval; a burst must not be throttled.
        for _ in range(20):
            response = self.client.post(
                "/v1/auth/device/token",
                data=json.dumps({"device_code": start["device_code"]}),
                content_type="application/json",
            )
            self.assertEqual(response.status_code, 400)
            self.assertEqual(
                response.json()["error"]["code"], "authorization_pending"
            )

    def test_denied_device_cannot_be_exchanged(self):
        start = self._start()
        self.client.force_login(self.user)
        self.client.post(
            "/device/",
            {"user_code": start["user_code"], "action": "deny"},
        )
        response = self.client.post(
            "/v1/auth/device/token",
            data=json.dumps({"device_code": start["device_code"]}),
            content_type="application/json",
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json()["error"]["code"], "access_denied")


class ApiAuthTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(email="api@example.com")

    def test_me_requires_authentication(self):
        response = self.client.get("/v1/me")
        self.assertEqual(response.status_code, 401)

    def test_invalid_token_rejected(self):
        response = self.client.get("/v1/me", HTTP_AUTHORIZATION="Bearer nope")
        self.assertEqual(response.status_code, 401)

    def test_revoked_token_rejected(self):
        raw, token = services.issue_api_token(self.user, label="Test")
        services.revoke_api_token(self.user, token.pk)
        response = self.client.get("/v1/me", HTTP_AUTHORIZATION=f"Bearer {raw}")
        self.assertEqual(response.status_code, 401)

    def test_token_listing_and_revocation(self):
        raw, token = services.issue_api_token(self.user, label="Laptop")
        self.client.force_login(self.user)

        listing = self.client.get("/v1/me/tokens")
        self.assertEqual(listing.status_code, 200)
        self.assertEqual(len(listing.json()["tokens"]), 1)

        revoked = self.client.delete(f"/v1/me/tokens/{token.pk}")
        self.assertEqual(revoked.status_code, 200)
        self.assertFalse(ApiToken.objects.get(pk=token.pk).is_valid)
