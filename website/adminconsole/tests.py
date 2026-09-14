import json
import uuid

from django.test import Client, TestCase, override_settings

from accounts.models import User
from audit.models import AuditEvent
from commerce import services as commerce_services
from commerce.providers import EventKind
from licensing import services as licensing_services
from licensing.models import Installation, License
from profiles.services import set_username
from social import services as social_services
from social.models import Report


class AdminAuthorizationTests(TestCase):
    def setUp(self):
        self.admin = User.objects.create_superuser(email="admin@example.com", password="x")
        self.user = User.objects.create_user(email="user@example.com")

    def test_anonymous_is_unauthorized(self):
        self.assertEqual(Client().get("/v1/admin/users").status_code, 401)

    def test_normal_user_is_forbidden(self):
        self.client.force_login(self.user)
        self.assertEqual(self.client.get("/v1/admin/users").status_code, 403)

    def test_admin_can_list_users(self):
        self.client.force_login(self.admin)
        response = self.client.get("/v1/admin/users")
        self.assertEqual(response.status_code, 200)
        self.assertIn("users", response.json())


class AdminActionTests(TestCase):
    def setUp(self):
        self.admin = User.objects.create_superuser(email="admin@example.com", password="x")
        self.user = User.objects.create_user(email="writer@example.com")
        set_username(self.user.profile, "writer")

        self.purchase, _checkout = commerce_services.start_purchase(self.user)
        commerce_services.simulate_event(self.purchase, EventKind.PURCHASE_COMPLETED)
        self.license = License.objects.get(user=self.user)

        self.client.force_login(self.admin)

    def test_search_users(self):
        response = self.client.get("/v1/admin/users?q=writer")
        self.assertEqual(response.status_code, 200)
        usernames = [u["username"] for u in response.json()["users"]]
        self.assertIn("writer", usernames)

    def test_user_detail_includes_related_records(self):
        response = self.client.get(f"/v1/admin/users/{self.user.pk}")
        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertEqual(payload["user"]["email"], "writer@example.com")
        self.assertEqual(len(payload["licenses"]), 1)
        self.assertEqual(len(payload["purchases"]), 1)

    def test_suspend_and_unsuspend(self):
        suspend = self.client.post(f"/v1/admin/users/{self.user.pk}/suspend")
        self.assertEqual(suspend.status_code, 200)

        self.user.refresh_from_db()
        self.assertEqual(self.user.status, User.Status.SUSPENDED)
        self.assertFalse(self.user.can_sign_in)
        self.assertTrue(
            AuditEvent.objects.filter(
                event_type=AuditEvent.Type.ACCOUNT_SUSPENDED
            ).exists()
        )

        unsuspend = self.client.post(f"/v1/admin/users/{self.user.pk}/unsuspend")
        self.assertEqual(unsuspend.status_code, 200)
        self.user.refresh_from_db()
        self.assertEqual(self.user.status, User.Status.ACTIVE)
        self.assertTrue(self.user.can_sign_in)

    def test_revoke_and_restore_license(self):
        revoke = self.client.post(f"/v1/admin/licenses/{self.license.pk}/revoke")
        self.assertEqual(revoke.status_code, 200)
        self.license.refresh_from_db()
        self.assertEqual(self.license.status, License.Status.REVOKED)

        restore = self.client.post(f"/v1/admin/licenses/{self.license.pk}/restore")
        self.assertEqual(restore.status_code, 200)
        self.license.refresh_from_db()
        self.assertEqual(self.license.status, License.Status.ACTIVE)

    def test_admin_actions_are_audited(self):
        self.client.post(f"/v1/admin/users/{self.user.pk}/suspend")
        self.assertTrue(
            AuditEvent.objects.filter(
                event_type=AuditEvent.Type.ADMIN_ACTION,
                metadata__action="user_suspend",
            ).exists()
        )

    def test_webhook_listing(self):
        response = self.client.get("/v1/admin/webhooks")
        self.assertEqual(response.status_code, 200)
        self.assertGreaterEqual(len(response.json()["webhooks"]), 1)

    def test_audit_log_listing(self):
        response = self.client.get("/v1/admin/audit")
        self.assertEqual(response.status_code, 200)
        self.assertIn("events", response.json())

    def test_report_resolution(self):
        report = social_services.report(
            self.user, self.admin, Report.Category.SPAM, "noise"
        )
        response = self.client.post(
            f"/v1/admin/reports/{report.pk}/resolve",
            data=json.dumps({"status": "actioned"}),
            content_type="application/json",
        )
        self.assertEqual(response.status_code, 200)
        report.refresh_from_db()
        self.assertEqual(report.status, Report.Status.ACTIONED)
        self.assertEqual(report.reviewed_by, self.admin)

    def test_purchase_claim_review(self):
        claimant = User.objects.create_user(email="claimant@example.com")
        commerce_services.request_claim(claimant, str(self.purchase.id))

        listing = self.client.get("/v1/admin/purchase-claims")
        claims = listing.json()["claims"]
        self.assertEqual(len(claims), 1)

        claim_id = claims[0]["id"]
        approve = self.client.post(f"/v1/admin/purchase-claims/{claim_id}/approve")
        self.assertEqual(approve.status_code, 200)
        self.assertTrue(License.objects.filter(user=claimant).exists())


class SecurityHardeningTests(TestCase):
    def setUp(self):
        self.alice = User.objects.create_user(email="alice@example.com")
        self.bob = User.objects.create_user(email="bob@example.com")

    def test_security_headers_present(self):
        response = self.client.get("/healthz")
        self.assertIn("Content-Security-Policy", response)
        self.assertEqual(response["X-Content-Type-Options"], "nosniff")
        self.assertEqual(response["X-Frame-Options"], "DENY")
        self.assertEqual(response["Referrer-Policy"], "same-origin")

    def test_csrf_is_enforced_on_html_forms(self):
        csrf_client = Client(enforce_csrf_checks=True)
        response = csrf_client.post("/sign-out/")
        self.assertEqual(response.status_code, 403)

    def test_malformed_json_body_rejected(self):
        self.client.force_login(self.alice)
        response = self.client.patch(
            "/v1/me/profile",
            data="[1, 2, 3]",
            content_type="application/json",
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json()["error"]["code"], "invalid_json")

    def test_idor_cannot_revoke_another_users_installation(self):
        installation, _created = licensing_services.register_installation(
            self.bob, uuid.uuid4()
        )

        self.client.force_login(self.alice)
        response = self.client.delete(
            f"/v1/me/installations/{installation.installation_id}"
        )
        self.assertEqual(response.status_code, 404)

        installation.refresh_from_db()
        self.assertTrue(installation.is_active)
        self.assertEqual(installation.user, self.bob)

    def test_profile_update_cannot_escalate_privileges(self):
        self.client.force_login(self.alice)
        response = self.client.patch(
            "/v1/me/profile",
            data='{"is_staff": true, "is_superuser": true}',
            content_type="application/json",
        )
        self.assertEqual(response.status_code, 400)

        self.alice.refresh_from_db()
        self.assertFalse(self.alice.is_staff)
        self.assertFalse(self.alice.is_superuser)

    def test_suspended_user_token_stops_working(self):
        from accounts import services as account_services

        raw_token, _token = account_services.issue_api_token(self.alice, label="Mac")
        self.assertEqual(
            self.client.get("/v1/me", HTTP_AUTHORIZATION=f"Bearer {raw_token}").status_code,
            200,
        )

        self.alice.status = User.Status.SUSPENDED
        self.alice.save(update_fields=["status", "is_active", "updated_at"])

        self.assertEqual(
            self.client.get("/v1/me", HTTP_AUTHORIZATION=f"Bearer {raw_token}").status_code,
            401,
        )

    def test_sql_injection_in_admin_search_is_inert(self):
        admin = User.objects.create_superuser(email="admin@example.com", password="x")
        self.client.force_login(admin)
        response = self.client.get("/v1/admin/users?q=%27%20OR%201%3D1--")
        self.assertEqual(response.status_code, 200)
        # Parameterized queries mean the string is data, not SQL: nobody matches.
        self.assertEqual(response.json()["users"], [])

    def test_login_rate_limit_caps_challenges(self):
        from accounts.models import LoginChallenge

        with override_settings(
            RATE_LIMIT_DEFAULTS={"login-request": (3, 3600)},
            EMAIL_PROVIDER="console",
            EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend",
        ):
            for index in range(6):
                self.client.post("/sign-in/", {"email": f"user{index}@example.com"})

        # The per-IP limit stops new challenges once exceeded.
        self.assertLessEqual(LoginChallenge.objects.count(), 3)

    def test_webhook_rejects_malformed_body(self):
        response = self.client.post(
            "/v1/webhooks/stripe",
            data="not json",
            content_type="application/json",
            HTTP_X_MOCK_SIGNATURE="bad",
        )
        self.assertEqual(response.status_code, 400)
