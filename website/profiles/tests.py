from datetime import timedelta

from django.test import TestCase
from django.utils import timezone

from accounts.models import User

from .models import Profile, ReservedUsername, UsernameChange
from .services import (
    UsernameError,
    change_cooldown_remaining,
    set_username,
    username_available,
    validate_username,
)


class UsernamePolicyTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(email="writer@example.com")
        self.profile = self.user.profile

    def test_profile_is_created_with_user(self):
        self.assertTrue(Profile.objects.filter(user=self.user).exists())
        self.assertIsNone(self.profile.username)

    def test_valid_username(self):
        self.assertEqual(validate_username("Writer_01"), "writer_01")

    def test_reserved_username_rejected(self):
        with self.assertRaises(UsernameError):
            validate_username("admin")

    def test_admin_reserved_name_is_configurable(self):
        ReservedUsername.objects.create(name="canonkeeper")
        with self.assertRaises(UsernameError):
            validate_username("canonkeeper")

    def test_invalid_usernames_rejected(self):
        for bad in ["ab", "has space", "has@sign", "two__underscores", "_leading", "trailing_", "has-dash"]:
            with self.assertRaises(UsernameError, msg=bad):
                validate_username(bad)

    def test_case_insensitive_collision(self):
        other = User.objects.create_user(email="other@example.com")
        set_username(self.profile, "SharedName")
        with self.assertRaises(UsernameError):
            set_username(other.profile, "sharedname")

    def test_first_assignment_has_no_cooldown(self):
        set_username(self.profile, "firstname")
        self.assertEqual(change_cooldown_remaining(self.profile), 0)
        self.assertEqual(UsernameChange.objects.count(), 0)

    def test_second_change_starts_cooldown(self):
        set_username(self.profile, "firstname")
        set_username(self.profile, "secondname")
        self.assertGreater(change_cooldown_remaining(self.profile), 0)
        with self.assertRaises(UsernameError):
            set_username(self.profile, "thirdname")

    def test_history_is_recorded(self):
        set_username(self.profile, "firstname")
        set_username(self.profile, "secondname")
        change = UsernameChange.objects.get(profile=self.profile)
        self.assertEqual(change.old_username, "firstname")
        self.assertEqual(change.new_username, "secondname")

    def test_released_username_is_reserved_for_cooldown(self):
        set_username(self.profile, "released")
        set_username(self.profile, "movedon")

        other = User.objects.create_user(email="claimer@example.com")
        self.assertFalse(username_available("released", for_profile=other.profile))
        with self.assertRaises(UsernameError):
            set_username(other.profile, "released")

    def test_released_username_becomes_available_after_cooldown(self):
        set_username(self.profile, "released")
        set_username(self.profile, "movedon")
        UsernameChange.objects.filter(profile=self.profile).update(
            created_at=timezone.now() - timedelta(days=999)
        )
        other = User.objects.create_user(email="claimer@example.com")
        self.assertTrue(username_available("released", for_profile=other.profile))


class ProfileApiTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(email="api@example.com")
        set_username(self.user.profile, "apiuser")

    def test_public_lookup(self):
        response = self.client.get("/v1/users/apiuser")
        self.assertEqual(response.status_code, 200)
        profile = response.json()["profile"]
        self.assertEqual(profile["username"], "apiuser")
        self.assertNotIn("email", profile)
        self.assertNotIn("id", profile)

    def test_unknown_lookup_returns_404(self):
        self.assertEqual(self.client.get("/v1/users/nobody").status_code, 404)

    def test_update_own_profile(self):
        self.client.force_login(self.user)
        response = self.client.patch(
            "/v1/me/profile",
            data='{"display_name": "A Writer", "bio": "Novelist."}',
            content_type="application/json",
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["profile"]["display_name"], "A Writer")

        self.user.profile.refresh_from_db()
        self.assertEqual(self.user.profile.bio, "Novelist.")

    def test_unknown_field_rejected(self):
        self.client.force_login(self.user)
        response = self.client.patch(
            "/v1/me/profile",
            data='{"is_admin": true}',
            content_type="application/json",
        )
        self.assertEqual(response.status_code, 400)

    def test_change_username_via_api(self):
        self.client.force_login(self.user)
        response = self.client.post(
            "/v1/me/username",
            data='{"username": "newname"}',
            content_type="application/json",
        )
        self.assertEqual(response.status_code, 200)
        self.user.profile.refresh_from_db()
        self.assertEqual(self.user.profile.username, "newname")

    def test_private_profile_hidden_from_others(self):
        profile = Profile.objects.get(pk=self.user.profile.pk)
        profile.profile_visibility = Profile.Visibility.PRIVATE
        profile.save(update_fields=["profile_visibility", "updated_at"])

        self.assertEqual(self.client.get("/v1/users/apiuser").status_code, 404)

        self.client.force_login(self.user)
        self.assertEqual(self.client.get("/v1/users/apiuser").status_code, 200)


class PrivacyTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(email="privacy@example.com")
        set_username(self.user.profile, "privatewriter")

    def test_privacy_defaults_are_conservative(self):
        profile = self.user.profile
        self.assertEqual(profile.stats_visibility, Profile.StatsVisibility.PRIVATE)
        self.assertEqual(
            profile.leaderboard_visibility, Profile.LeaderboardVisibility.OFF
        )

    def test_privacy_update_via_dashboard(self):
        self.client.force_login(self.user)
        response = self.client.post(
            "/dashboard/privacy/",
            {
                "profile_visibility": "private",
                "stats_visibility": "public",
                "leaderboard_visibility": "global",
                "allow_following": "on",
            },
        )
        self.assertEqual(response.status_code, 302)

        self.user.profile.refresh_from_db()
        self.assertEqual(self.user.profile.profile_visibility, "private")
        self.assertEqual(self.user.profile.stats_visibility, "public")
        self.assertEqual(self.user.profile.leaderboard_visibility, "global")
