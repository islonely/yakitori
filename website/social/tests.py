from django.test import Client, TestCase

from accounts.models import User
from profiles.models import Profile
from profiles.services import set_username

from . import services
from .models import Block, Follow, Report


def make_user(email, username):
    user = User.objects.create_user(email=email)
    set_username(user.profile, username)
    return user


class FollowTests(TestCase):
    def setUp(self):
        self.alice = make_user("alice@example.com", "alice")
        self.bob = make_user("bob@example.com", "bob")

    def test_follow_and_unfollow(self):
        edge, created = services.follow(self.alice, self.bob)
        self.assertTrue(created)
        self.assertTrue(services.is_following(self.alice, self.bob))

        # Duplicate follow is a no-op.
        _edge, created_again = services.follow(self.alice, self.bob)
        self.assertFalse(created_again)
        self.assertEqual(Follow.objects.count(), 1)

        self.assertTrue(services.unfollow(self.alice, self.bob))
        self.assertFalse(services.is_following(self.alice, self.bob))

    def test_cannot_follow_self(self):
        with self.assertRaises(services.SocialError):
            services.follow(self.alice, self.alice)

    def test_follow_respects_allow_following(self):
        profile = Profile.objects.get(pk=self.bob.profile.pk)
        profile.allow_following = False
        profile.save(update_fields=["allow_following"])
        with self.assertRaises(services.SocialError):
            services.follow(self.alice, self.bob)

    def test_counts(self):
        services.follow(self.alice, self.bob)
        carol = make_user("carol@example.com", "carol")
        services.follow(carol, self.bob)
        self.assertEqual(services.counts(self.bob), (2, 0))
        self.assertEqual(services.counts(self.alice), (0, 1))


class VisibilityTests(TestCase):
    def setUp(self):
        self.owner = make_user("owner@example.com", "owner")
        self.follower = make_user("follower@example.com", "follower")
        self.stranger = make_user("stranger@example.com", "stranger")

        profile = Profile.objects.get(pk=self.owner.profile.pk)
        profile.profile_visibility = Profile.Visibility.PRIVATE
        profile.save(update_fields=["profile_visibility"])
        self.owner_profile = profile

    def test_owner_can_see_own_private_profile(self):
        self.assertTrue(services.can_view_profile(self.owner_profile, self.owner))

    def test_stranger_cannot_see_private_profile(self):
        self.assertFalse(services.can_view_profile(self.owner_profile, self.stranger))

    def test_follower_can_see_private_profile(self):
        services.follow(self.follower, self.owner)
        self.assertTrue(
            services.can_view_profile(self.owner_profile, self.follower)
        )

    def test_block_hides_profile_and_ends_follows(self):
        services.follow(self.follower, self.owner)
        services.block(self.owner, self.follower)

        self.assertTrue(services.blocks_between(self.owner, self.follower))
        self.assertFalse(services.can_view_profile(self.owner_profile, self.follower))
        self.assertEqual(Follow.objects.count(), 0)


class ReportTests(TestCase):
    def setUp(self):
        self.reporter = make_user("reporter@example.com", "reporter")
        self.target = make_user("target@example.com", "target")

    def test_report_created(self):
        report = services.report(
            self.reporter, self.target, Report.Category.SPAM, "noise"
        )
        self.assertEqual(report.status, Report.Status.PENDING)
        self.assertEqual(Report.objects.count(), 1)

    def test_cannot_report_self(self):
        with self.assertRaises(services.SocialError):
            services.report(self.reporter, self.reporter, Report.Category.OTHER)


class SocialApiTests(TestCase):
    def setUp(self):
        self.alice = make_user("alice@example.com", "alice")
        self.bob = make_user("bob@example.com", "bob")

    def test_follow_endpoint(self):
        self.client.force_login(self.alice)
        response = self.client.post("/v1/users/bob/follow")
        self.assertEqual(response.status_code, 201)
        self.assertTrue(response.json()["following"])

        duplicate = self.client.post("/v1/users/bob/follow")
        self.assertEqual(duplicate.status_code, 200)

        unfollow = self.client.delete("/v1/users/bob/follow")
        self.assertEqual(unfollow.status_code, 200)

    def test_follow_requires_auth(self):
        response = Client().post("/v1/users/bob/follow")
        self.assertEqual(response.status_code, 401)

    def test_followers_listing_and_pagination(self):
        for index in range(3):
            user = make_user(f"fan{index}@example.com", f"fan{index}")
            services.follow(user, self.bob)

        response = self.client.get("/v1/users/bob/followers?limit=2")
        payload = response.json()
        self.assertEqual(len(payload["followers"]), 2)
        self.assertIsNotNone(payload["next_cursor"])

        second = self.client.get(
            f"/v1/users/bob/followers?limit=2&cursor={payload['next_cursor']}"
        )
        self.assertEqual(len(second.json()["followers"]), 1)
        self.assertIsNone(second.json()["next_cursor"])

    def test_followers_hidden_for_private_profile(self):
        profile = Profile.objects.get(pk=self.bob.profile.pk)
        profile.profile_visibility = Profile.Visibility.PRIVATE
        profile.save(update_fields=["profile_visibility"])

        self.assertEqual(self.client.get("/v1/users/bob/followers").status_code, 404)

        self.client.force_login(self.alice)
        services.follow(self.alice, self.bob)
        self.assertEqual(self.client.get("/v1/users/bob/followers").status_code, 200)

    def test_block_endpoint(self):
        self.client.force_login(self.alice)
        response = self.client.post("/v1/users/bob/block")
        self.assertEqual(response.status_code, 200)
        self.assertTrue(Block.objects.filter(blocker=self.alice, blocked=self.bob).exists())

        self.client.delete("/v1/users/bob/block")
        self.assertFalse(Block.objects.filter(blocker=self.alice, blocked=self.bob).exists())

    def test_report_endpoint(self):
        self.client.force_login(self.alice)
        response = self.client.post(
            "/v1/users/bob/report",
            data='{"category": "harassment", "details": "rude"}',
            content_type="application/json",
        )
        self.assertEqual(response.status_code, 201)
        self.assertEqual(Report.objects.count(), 1)

    def test_reported_self_rejected(self):
        self.client.force_login(self.alice)
        response = self.client.post(
            "/v1/users/alice/report",
            data='{"category": "other"}',
            content_type="application/json",
        )
        self.assertEqual(response.status_code, 400)
