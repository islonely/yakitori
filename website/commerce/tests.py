import json

from django.test import TestCase, override_settings

from accounts.models import User

from licensing.models import License

from . import services
from .models import PaymentPurchase, PurchaseClaim, WebhookEvent
from .providers import EventKind, ProviderError, get_provider
from .providers.mock import build_event, sign_payload


class ProviderTests(TestCase):
    def test_default_provider_is_mock(self):
        self.assertEqual(get_provider().name, "mock")

    def test_unknown_provider_raises(self):
        with self.assertRaises(ProviderError):
            get_provider("bogus")

    @override_settings(PAYMENT_PROVIDER="stripe", STRIPE_SECRET_KEY="")
    def test_stripe_without_key_raises(self):
        with self.assertRaises(ProviderError):
            get_provider("stripe")


class CheckoutFlowTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(email="buyer@example.com")
        self.client.force_login(self.user)

    def test_start_purchase_creates_pending_purchase_and_checkout(self):
        purchase, checkout = services.start_purchase(self.user)
        self.assertEqual(purchase.status, PaymentPurchase.Status.PENDING)
        self.assertEqual(purchase.provider, "mock")
        self.assertTrue(checkout.url.endswith(f"/buy/mock/{purchase.id}/"))

    def test_buy_redirects_to_mock_checkout(self):
        response = self.client.get("/buy/")
        self.assertEqual(response.status_code, 302)
        self.assertIn("/buy/mock/", response.url)

    def test_mock_checkout_pay_completes_purchase(self):
        purchase, _checkout = services.start_purchase(self.user)
        page = self.client.get(f"/buy/mock/{purchase.id}/")
        self.assertEqual(page.status_code, 200)

        response = self.client.post(
            f"/buy/mock/{purchase.id}/", {"action": "pay"}
        )
        self.assertEqual(response.status_code, 302)
        self.assertEqual(response.url, "/buy/success/")

        purchase.refresh_from_db()
        self.assertEqual(purchase.status, PaymentPurchase.Status.COMPLETED)
        self.assertIsNotNone(purchase.purchased_at)

    def test_mock_checkout_cancel(self):
        purchase, _checkout = services.start_purchase(self.user)
        self.client.post(f"/buy/mock/{purchase.id}/", {"action": "cancel"})
        purchase.refresh_from_db()
        self.assertEqual(purchase.status, PaymentPurchase.Status.CANCELLED)

    def test_other_user_cannot_open_checkout(self):
        purchase, _checkout = services.start_purchase(self.user)
        other = User.objects.create_user(email="other@example.com")
        self.client.force_login(other)
        self.assertEqual(self.client.get(f"/buy/mock/{purchase.id}/").status_code, 404)

    def test_buy_denied_when_already_owned(self):
        purchase, _checkout = services.start_purchase(self.user)
        services.simulate_event(purchase, EventKind.PURCHASE_COMPLETED)
        response = self.client.get("/buy/")
        self.assertEqual(response.status_code, 302)
        self.assertEqual(response.url, "/dashboard/")


class WebhookTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(email="hook@example.com")
        self.purchase, _checkout = services.start_purchase(self.user)

    def _post(self, payload, signature=None):
        body = json.dumps(payload).encode("utf-8")
        if signature is None:
            signature = sign_payload(body)
        return self.client.post(
            "/v1/webhooks/stripe",
            data=body,
            content_type="application/json",
            HTTP_X_MOCK_SIGNATURE=signature,
        )

    def test_valid_webhook_completes_purchase(self):
        payload = build_event(EventKind.PURCHASE_COMPLETED, self.purchase)
        response = self._post(payload)
        self.assertEqual(response.status_code, 200)
        self.assertFalse(response.json()["duplicate"])

        self.purchase.refresh_from_db()
        self.assertEqual(self.purchase.status, PaymentPurchase.Status.COMPLETED)

    def test_invalid_signature_rejected(self):
        payload = build_event(EventKind.PURCHASE_COMPLETED, self.purchase)
        response = self._post(payload, signature="deadbeef")
        self.assertEqual(response.status_code, 400)
        self.purchase.refresh_from_db()
        self.assertNotEqual(self.purchase.status, PaymentPurchase.Status.COMPLETED)

    def test_duplicate_webhook_is_idempotent(self):
        payload = build_event(EventKind.PURCHASE_COMPLETED, self.purchase)
        first = self._post(payload)
        second = self._post(payload)
        self.assertEqual(first.status_code, 200)
        self.assertEqual(second.status_code, 200)
        self.assertTrue(second.json()["duplicate"])
        self.assertEqual(WebhookEvent.objects.count(), 1)

    def test_refund_changes_status(self):
        services.simulate_event(self.purchase, EventKind.PURCHASE_COMPLETED)
        services.simulate_event(self.purchase, EventKind.REFUND_ISSUED)
        self.purchase.refresh_from_db()
        self.assertEqual(self.purchase.status, PaymentPurchase.Status.REFUNDED)

    def test_partial_refund_changes_status(self):
        services.simulate_event(self.purchase, EventKind.PURCHASE_COMPLETED)
        services.simulate_event(
            self.purchase,
            EventKind.REFUND_ISSUED,
            amount=self.purchase.amount // 2,
        )
        self.purchase.refresh_from_db()
        self.assertEqual(
            self.purchase.status, PaymentPurchase.Status.PARTIALLY_REFUNDED
        )

    def test_dispute_then_resolution(self):
        services.simulate_event(self.purchase, EventKind.PURCHASE_COMPLETED)
        services.simulate_event(self.purchase, EventKind.DISPUTE_OPENED)
        self.purchase.refresh_from_db()
        self.assertEqual(self.purchase.status, PaymentPurchase.Status.DISPUTED)

        services.simulate_event(self.purchase, EventKind.DISPUTE_RESOLVED)
        self.purchase.refresh_from_db()
        self.assertEqual(self.purchase.status, PaymentPurchase.Status.COMPLETED)


class CommerceApiTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(email="api@example.com")
        self.client.force_login(self.user)

    def test_checkout_requires_auth(self):
        from django.test import Client

        response = Client().post("/v1/checkout")
        self.assertEqual(response.status_code, 401)

    def test_checkout_returns_url(self):
        response = self.client.post("/v1/checkout")
        self.assertEqual(response.status_code, 200)
        self.assertIn("checkout_url", response.json())

    def test_purchases_listing(self):
        _purchase, _checkout = services.start_purchase(self.user)
        response = self.client.get("/v1/me/purchases")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.json()["purchases"]), 1)


class PurchaseClaimTests(TestCase):
    def setUp(self):
        self.owner = User.objects.create_user(email="owner@example.com")
        self.claimant = User.objects.create_user(email="claimant@example.com")
        self.admin = User.objects.create_superuser(
            email="admin@example.com", password="x"
        )

        self.purchase, _checkout = services.start_purchase(self.owner)
        services.simulate_event(self.purchase, EventKind.PURCHASE_COMPLETED)

    def test_claim_is_never_auto_associated(self):
        claim, created = services.request_claim(
            self.claimant, str(self.purchase.id)
        )
        self.assertTrue(created)
        self.assertEqual(claim.status, PurchaseClaim.Status.PENDING)

        self.purchase.refresh_from_db()
        self.assertEqual(self.purchase.user, self.owner)
        self.assertFalse(License.objects.filter(user=self.claimant).exists())

    def test_approval_moves_purchase_and_grants_license(self):
        claim, _created = services.request_claim(
            self.claimant, str(self.purchase.id)
        )
        services.approve_claim(claim, self.admin)

        self.purchase.refresh_from_db()
        self.assertEqual(self.purchase.user, self.claimant)
        self.assertTrue(License.objects.filter(user=self.claimant).exists())

    def test_rejection_keeps_ownership(self):
        claim, _created = services.request_claim(
            self.claimant, str(self.purchase.id)
        )
        services.reject_claim(claim, self.admin)
        self.purchase.refresh_from_db()
        self.assertEqual(self.purchase.user, self.owner)

    def test_unknown_reference_creates_nothing(self):
        claim, created = services.request_claim(self.claimant, "does-not-exist")
        self.assertIsNone(claim)
        self.assertFalse(created)

    def test_cannot_claim_own_purchase(self):
        with self.assertRaises(services.ClaimError):
            services.request_claim(self.owner, str(self.purchase.id))

    def test_claim_endpoint_is_uniform(self):
        self.client.force_login(self.claimant)
        real = self.client.post(
            "/v1/me/purchase-claims",
            data=json.dumps({"reference": str(self.purchase.id)}),
            content_type="application/json",
        )
        fake = self.client.post(
            "/v1/me/purchase-claims",
            data=json.dumps({"reference": "nope"}),
            content_type="application/json",
        )
        self.assertEqual(real.status_code, 202)
        self.assertEqual(fake.status_code, 202)
