import json

from django.test import Client, TestCase

from accounts.models import User
from audit.models import AuditEvent
from commerce import services as commerce_services
from commerce.providers import EventKind
from licensing.models import License
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
