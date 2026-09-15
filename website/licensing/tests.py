import json
import time
import uuid
from datetime import timedelta

from django.test import Client, TestCase, override_settings
from django.utils import timezone

from accounts.models import User
from commerce import services as commerce_services
from commerce.providers import EventKind
from licensing import services
from licensing.models import Installation, License, MachineTrial, Trial
from licensing.signing import (
    SigningError,
    verify_authorization,
)

TEST_SEED = "80NcwChXuTOlXQCI5DfDrdoF9RLZdYA_crZa8ORrt7s"
TEST_PUBLIC = "m9dLUiC0Fk8dsITaDYgOxXqHTlVxuoia_SRxp131fqs"

LICENSE_SETTINGS = dict(
    LICENSE_SIGNING_KEY_ID="test-1",
    LICENSE_SIGNING_PRIVATE_KEY=TEST_SEED,
    LICENSE_OFFLINE_GRACE_DAYS=30,
    PRODUCT_NAME="Yakitori",
)


@override_settings(**LICENSE_SETTINGS)
class LicenseLifecycleTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(email="owner@example.com")

    def _complete_purchase(self):
        purchase, _checkout = commerce_services.start_purchase(self.user)
        commerce_services.simulate_event(purchase, EventKind.PURCHASE_COMPLETED)
        return purchase

    def test_completed_purchase_grants_lifetime_license(self):
        self._complete_purchase()
        license_obj = License.objects.get(user=self.user)
        self.assertEqual(license_obj.status, License.Status.ACTIVE)
        self.assertEqual(license_obj.license_type, License.Type.LIFETIME)
        self.assertIsNone(license_obj.expires_at)

    def test_grant_is_idempotent(self):
        purchase = self._complete_purchase()
        commerce_services.simulate_event(purchase, EventKind.PURCHASE_COMPLETED)
        self.assertEqual(License.objects.filter(user=self.user).count(), 1)

    def test_refund_revokes_license(self):
        purchase = self._complete_purchase()
        commerce_services.simulate_event(purchase, EventKind.REFUND_ISSUED)
        self.assertEqual(
            License.objects.get(user=self.user).status, License.Status.REVOKED
        )

    def test_dispute_disables_and_resolution_restores(self):
        purchase = self._complete_purchase()
        commerce_services.simulate_event(purchase, EventKind.DISPUTE_OPENED)
        self.assertEqual(
            License.objects.get(user=self.user).status, License.Status.DISABLED
        )

        commerce_services.simulate_event(purchase, EventKind.DISPUTE_RESOLVED)
        self.assertEqual(
            License.objects.get(user=self.user).status, License.Status.ACTIVE
        )


@override_settings(**LICENSE_SETTINGS)
class InstallationTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(email="installs@example.com")

    def test_multiple_installations_allowed(self):
        services.register_installation(self.user, uuid.uuid4(), app_version="1.0")
        services.register_installation(self.user, uuid.uuid4(), app_version="1.0")
        services.register_installation(self.user, uuid.uuid4(), app_version="1.1")
        self.assertEqual(Installation.objects.filter(user=self.user).count(), 3)

    def test_re_registration_updates_metadata(self):
        installation_id = uuid.uuid4()
        services.register_installation(self.user, installation_id, app_version="1.0")
        services.register_installation(self.user, installation_id, app_version="1.1")

        installation = Installation.objects.get(installation_id=installation_id)
        self.assertEqual(installation.app_version, "1.1")
        self.assertEqual(Installation.objects.count(), 1)

    def test_installation_can_move_to_another_account(self):
        installation_id = uuid.uuid4()
        services.register_installation(self.user, installation_id)

        other = User.objects.create_user(email="newaccount@example.com")
        services.register_installation(other, installation_id)

        installation = Installation.objects.get(installation_id=installation_id)
        self.assertEqual(installation.user, other)

    def test_revoke_installation(self):
        installation_id = uuid.uuid4()
        services.register_installation(self.user, installation_id)
        self.assertTrue(services.revoke_installation(self.user, installation_id))
        self.assertFalse(
            Installation.objects.get(installation_id=installation_id).is_active
        )


@override_settings(**LICENSE_SETTINGS)
class AuthorizationTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(email="signer@example.com")
        purchase, _checkout = commerce_services.start_purchase(self.user)
        commerce_services.simulate_event(purchase, EventKind.PURCHASE_COMPLETED)
        self.installation, _ = services.register_installation(
            self.user, uuid.uuid4(), app_version="1.0"
        )

    def test_validate_returns_verifiable_authorization(self):
        result = services.validate_license(self.user, self.installation)
        self.assertTrue(result["valid"])

        claims = verify_authorization(result["authorization"], TEST_PUBLIC)
        self.assertEqual(claims["sub"], str(self.user.id))
        self.assertEqual(claims["inst"], str(self.installation.installation_id))
        self.assertEqual(claims["status"], "active")
        self.assertEqual(claims["type"], "lifetime")
        self.assertGreater(claims["exp"], claims["iat"])

    def test_authorization_without_installation_is_invalid(self):
        result = services.validate_license(self.user, None)
        self.assertFalse(result["valid"])
        self.assertEqual(result["reason"], "installation_not_registered")

    def test_authorization_fails_with_wrong_public_key(self):
        result = services.validate_license(self.user, self.installation)
        wrong_key = "A" * 43  # base64url of 32 zero bytes
        with self.assertRaises(SigningError):
            verify_authorization(result["authorization"], wrong_key)

    def test_tampered_authorization_fails_verification(self):
        result = services.validate_license(self.user, self.installation)
        header, payload, signature = result["authorization"].split(".")
        tampered = f"{header}.{payload}x.{signature}"
        with self.assertRaises(SigningError):
            verify_authorization(tampered, TEST_PUBLIC)

    def test_revoked_license_cannot_validate(self):
        purchase = self.user.purchases.get()
        commerce_services.simulate_event(purchase, EventKind.REFUND_ISSUED)
        result = services.validate_license(self.user, self.installation)
        self.assertFalse(result["valid"])
        self.assertEqual(result["reason"], "revoked")

    def test_no_license_starts_a_trial(self):
        other = User.objects.create_user(email="nolicense@example.com")
        installation, _ = services.register_installation(other, uuid.uuid4())
        result = services.validate_license(other, installation)
        self.assertTrue(result["valid"])
        self.assertEqual(result["kind"], "trial")
        self.assertGreater(result["trial"].days_remaining, 0)


@override_settings(**LICENSE_SETTINGS)
class TrialTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(email="trial@example.com")
        self.installation, _ = services.register_installation(
            self.user, uuid.uuid4()
        )

    def test_first_validation_starts_a_14_day_trial(self):
        result = services.validate_license(self.user, self.installation)
        self.assertTrue(result["valid"])
        self.assertEqual(result["kind"], "trial")

        trial = Trial.objects.get(user=self.user)
        self.assertAlmostEqual(trial.days_remaining, 14, delta=1)

        claims = verify_authorization(result["authorization"], TEST_PUBLIC)
        self.assertEqual(claims["type"], "trial")
        self.assertIsNotNone(claims["ent_exp"])
        self.assertEqual(claims["ent_exp"], claims["exp"])

    def test_trial_is_never_restarted(self):
        services.validate_license(self.user, self.installation)
        trial = Trial.objects.get(user=self.user)
        trial.ends_at = timezone.now() + timedelta(days=2)
        trial.save(update_fields=["ends_at"])

        services.validate_license(self.user, self.installation)

        trial.refresh_from_db()
        self.assertLessEqual(trial.days_remaining, 2)
        self.assertEqual(Trial.objects.count(), 1)

    @override_settings(TRIAL_SECONDS=1)
    def test_trial_expires_once_its_duration_passes(self):
        # A short trial so we can observe the real transition, not just a
        # hand-constructed past end date.
        first = services.validate_license(self.user, self.installation)
        self.assertTrue(first["valid"])
        self.assertEqual(first["kind"], "trial")

        time.sleep(1.1)

        second = services.validate_license(self.user, self.installation)
        self.assertFalse(second["valid"])
        self.assertEqual(second["reason"], "trial_expired")

    def test_expired_trial_is_invalid(self):
        Trial.objects.create(
            user=self.user,
            ends_at=timezone.now() - timedelta(days=1),
            installation_uuid=self.installation.installation_id,
        )
        result = services.validate_license(self.user, self.installation)
        self.assertFalse(result["valid"])
        self.assertEqual(result["reason"], "trial_expired")

    def test_new_account_on_used_installation_gets_no_trial(self):
        services.validate_license(self.user, self.installation)

        other = User.objects.create_user(email="reuser@example.com")
        installation, _ = services.register_installation(
            other, self.installation.installation_id
        )
        result = services.validate_license(other, installation)
        self.assertFalse(result["valid"])
        self.assertEqual(result["reason"], "trial_unavailable")

    def test_second_trial_refused_when_machine_already_used(self):
        machine = "HW-UUID-AAAA"
        first = services.validate_license(
            self.user, self.installation, machine_id=machine
        )
        self.assertTrue(first["valid"])

        other = User.objects.create_user(email="machine2@example.com")
        installation, _ = services.register_installation(other, uuid.uuid4())
        second = services.validate_license(other, installation, machine_id=machine)

        self.assertFalse(second["valid"])
        self.assertEqual(second["reason"], "trial_machine_used")

    def test_only_a_hash_of_the_machine_is_stored(self):
        machine = "HW-UUID-SECRET-1234"
        services.validate_license(self.user, self.installation, machine_id=machine)

        record = MachineTrial.objects.get()
        self.assertNotEqual(record.machine_hash, machine)
        self.assertNotIn(machine, record.machine_hash)
        self.assertEqual(record.machine_hash, services.machine_hash(machine))

    def test_different_machines_each_get_a_trial(self):
        self.assertTrue(
            services.validate_license(
                self.user, self.installation, machine_id="M-A"
            )["valid"]
        )
        other = User.objects.create_user(email="machine-b@example.com")
        installation, _ = services.register_installation(other, uuid.uuid4())
        self.assertTrue(
            services.validate_license(
                other, installation, machine_id="M-B"
            )["valid"]
        )
        self.assertEqual(MachineTrial.objects.count(), 2)

    def test_missing_machine_id_falls_back_to_installation_guard(self):
        result = services.validate_license(
            self.user, self.installation, machine_id=None
        )
        self.assertTrue(result["valid"])
        self.assertEqual(MachineTrial.objects.count(), 0)

    def test_revoked_license_does_not_fall_back_to_trial(self):
        purchase, _checkout = commerce_services.start_purchase(self.user)
        commerce_services.simulate_event(purchase, EventKind.PURCHASE_COMPLETED)
        commerce_services.simulate_event(purchase, EventKind.REFUND_ISSUED)

        result = services.validate_license(self.user, self.installation)
        self.assertFalse(result["valid"])
        self.assertEqual(result["reason"], "revoked")


@override_settings(**LICENSE_SETTINGS)
class LicensingApiTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(email="api@example.com")
        self.client.force_login(self.user)
        self.installation_id = uuid.uuid4()

    def test_register_installation(self):
        response = self.client.post(
            "/v1/me/installations",
            data=f'{{"installation_id": "{self.installation_id}", "app_version": "1.0"}}',
            content_type="application/json",
        )
        self.assertEqual(response.status_code, 201)
        self.assertEqual(
            response.json()["installation"]["installation_id"],
            str(self.installation_id),
        )

    def test_installations_require_uuid(self):
        response = self.client.post(
            "/v1/me/installations",
            data='{"installation_id": "not-a-uuid"}',
            content_type="application/json",
        )
        self.assertEqual(response.status_code, 400)

    def test_validate_starts_trial_when_unlicensed(self):
        self.client.post(
            "/v1/me/installations",
            data=f'{{"installation_id": "{self.installation_id}"}}',
            content_type="application/json",
        )
        response = self.client.post(
            "/v1/me/license/validate",
            data=f'{{"installation_id": "{self.installation_id}"}}',
            content_type="application/json",
        )
        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertTrue(payload["valid"])
        self.assertEqual(payload["kind"], "trial")
        self.assertGreater(payload["trial"]["days_remaining"], 0)

    def test_api_refuses_second_trial_on_same_machine(self):
        self.client.post(
            "/v1/me/installations",
            data=json.dumps({"installation_id": str(self.installation_id)}),
            content_type="application/json",
        )
        first = self.client.post(
            "/v1/me/license/validate",
            data=json.dumps(
                {
                    "installation_id": str(self.installation_id),
                    "machine_id": "HW-API-1",
                }
            ),
            content_type="application/json",
        )
        self.assertTrue(first.json()["valid"])

        other = User.objects.create_user(email="othermachine@example.com")
        other_installation = uuid.uuid4()
        second_client = Client()
        second_client.force_login(other)
        second_client.post(
            "/v1/me/installations",
            data=json.dumps({"installation_id": str(other_installation)}),
            content_type="application/json",
        )
        second = second_client.post(
            "/v1/me/license/validate",
            data=json.dumps(
                {
                    "installation_id": str(other_installation),
                    "machine_id": "HW-API-1",
                }
            ),
            content_type="application/json",
        )
        self.assertFalse(second.json()["valid"])
        self.assertEqual(second.json()["reason"], "trial_machine_used")

    def test_full_api_validation_after_purchase(self):
        purchase, _checkout = commerce_services.start_purchase(self.user)
        commerce_services.simulate_event(purchase, EventKind.PURCHASE_COMPLETED)

        self.client.post(
            "/v1/me/installations",
            data=f'{{"installation_id": "{self.installation_id}"}}',
            content_type="application/json",
        )
        response = self.client.post(
            "/v1/me/license/validate",
            data=f'{{"installation_id": "{self.installation_id}"}}',
            content_type="application/json",
        )
        payload = response.json()
        self.assertTrue(payload["valid"])
        self.assertEqual(payload["offline_grace_days"], 30)

        claims = verify_authorization(payload["authorization"], TEST_PUBLIC)
        self.assertEqual(claims["sub"], str(self.user.id))

    def test_license_detail_and_installation_revocation(self):
        purchase, _checkout = commerce_services.start_purchase(self.user)
        commerce_services.simulate_event(purchase, EventKind.PURCHASE_COMPLETED)
        self.client.post(
            "/v1/me/installations",
            data=f'{{"installation_id": "{self.installation_id}"}}',
            content_type="application/json",
        )

        detail = self.client.get("/v1/me/license")
        self.assertEqual(detail.status_code, 200)
        self.assertEqual(detail.json()["license"]["status"], "active")

        revoked = self.client.delete(f"/v1/me/installations/{self.installation_id}")
        self.assertEqual(revoked.status_code, 200)

        listing = self.client.get("/v1/me/installations")
        self.assertTrue(listing.json()["installations"][0]["revoked"])
