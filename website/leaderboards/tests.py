import json
from datetime import date, timedelta

from django.test import Client, TestCase

from accounts.models import User
from profiles.models import Profile
from profiles.services import set_username

from . import services
from .models import (
    LeaderboardAggregate,
    Metric,
    Period,
    StatisticSubmission,
)
from .periods import normalize_period_start


def make_user(email, username, *, public=True, boards=True):
    user = User.objects.create_user(email=email)
    set_username(user.profile, username)
    profile = Profile.objects.get(pk=user.profile.pk)
    profile.profile_visibility = (
        Profile.Visibility.PUBLIC if public else Profile.Visibility.PRIVATE
    )
    profile.leaderboard_visibility = (
        Profile.LeaderboardVisibility.GLOBAL
        if boards
        else Profile.LeaderboardVisibility.OFF
    )
    profile.save(
        update_fields=["profile_visibility", "leaderboard_visibility", "updated_at"]
    )
    user.profile = profile
    return user


class AggregationTests(TestCase):
    def setUp(self):
        self.alice = make_user("alice@example.com", "alice")
        self.bob = make_user("bob@example.com", "bob")

    def test_opt_in_required(self):
        make_user("off@example.com", "offboards", boards=False)
        services.record_aggregate(self.alice, Metric.NET_WORDS, Period.WEEK, date.today(), 100)
        services.record_aggregate(
            User.objects.get(email="off@example.com"),
            Metric.NET_WORDS,
            Period.WEEK,
            date.today(),
            9999,
        )

        entries, _cursor = services.leaderboard(
            Metric.NET_WORDS, Period.WEEK, date.today()
        )
        usernames = [aggregate.user.profile.username for _rank, aggregate in entries]
        self.assertIn("alice", usernames)
        self.assertNotIn("offboards", usernames)

    def test_private_profile_never_appears(self):
        make_user("private@example.com", "secret", public=False)
        private_user = User.objects.get(email="private@example.com")
        services.record_aggregate(
            private_user, Metric.NET_WORDS, Period.WEEK, date.today(), 99999
        )

        entries, _cursor = services.leaderboard(
            Metric.NET_WORDS, Period.WEEK, date.today()
        )
        self.assertEqual(entries, [])

    def test_ranking_and_determinism(self):
        services.record_aggregate(self.alice, Metric.NET_WORDS, Period.WEEK, date.today(), 500)
        services.record_aggregate(self.bob, Metric.NET_WORDS, Period.WEEK, date.today(), 1500)

        entries, _cursor = services.leaderboard(
            Metric.NET_WORDS, Period.WEEK, date.today()
        )
        self.assertEqual(entries[0][0], 1)
        self.assertEqual(entries[0][1].user, self.bob)
        self.assertEqual(entries[1][0], 2)

    def test_week_is_normalized_to_monday(self):
        wednesday = date(2026, 1, 7)
        start = normalize_period_start(Period.WEEK, wednesday)
        self.assertEqual(start, date(2026, 1, 5))

        services.record_aggregate(self.alice, Metric.NET_WORDS, Period.WEEK, wednesday, 42)
        aggregate = LeaderboardAggregate.objects.get(user=self.alice)
        self.assertEqual(aggregate.period_start, date(2026, 1, 5))

    def test_duplicate_aggregate_updates_in_place(self):
        services.record_aggregate(self.alice, Metric.NET_WORDS, Period.WEEK, date.today(), 100)
        services.record_aggregate(self.alice, Metric.NET_WORDS, Period.WEEK, date.today(), 200)
        self.assertEqual(
            LeaderboardAggregate.objects.filter(user=self.alice).count(), 1
        )
        self.assertEqual(
            LeaderboardAggregate.objects.get(user=self.alice).value, 200
        )


class ValidationTests(TestCase):
    def setUp(self):
        self.user = make_user("submitter@example.com", "submitter")

    def test_valid_submission_accepted(self):
        items = [
            {
                "metric": "net_words",
                "period": "week",
                "period_start": date.today().isoformat(),
                "value": 1234,
            }
        ]
        submission, result = services.submit_aggregates(self.user, items)
        self.assertTrue(result.ok)
        self.assertEqual(submission.status, StatisticSubmission.Status.ACCEPTED)
        self.assertEqual(LeaderboardAggregate.objects.count(), 1)

    def test_impossible_values_rejected(self):
        items = [
            {"metric": "active_seconds", "period": "day", "period_start": date.today().isoformat(), "value": 999_999_999},
            {"metric": "unknown", "period": "week", "period_start": date.today().isoformat(), "value": 1},
            {"metric": "net_words", "period": "week", "period_start": date.today().isoformat(), "value": -5},
        ]
        submission, result = services.submit_aggregates(self.user, items)
        # The third item is valid (net words can be negative), the first two are not.
        self.assertFalse(result.ok)
        self.assertEqual(submission.status, StatisticSubmission.Status.REJECTED)
        self.assertEqual(LeaderboardAggregate.objects.count(), 0)

    def test_future_period_rejected(self):
        future = (date.today() + timedelta(days=2)).isoformat()
        items = [
            {"metric": "net_words", "period": "day", "period_start": future, "value": 1}
        ]
        _submission, result = services.submit_aggregates(self.user, items)
        self.assertFalse(result.ok)

    def test_negative_net_words_allowed(self):
        items = [
            {"metric": "net_words", "period": "week", "period_start": date.today().isoformat(), "value": -120}
        ]
        _submission, result = services.submit_aggregates(self.user, items)
        self.assertTrue(result.ok)


class StandingTests(TestCase):
    def setUp(self):
        self.alice = make_user("alice@example.com", "alice")
        self.bob = make_user("bob@example.com", "bob")
        services.record_aggregate(self.bob, Metric.NET_WORDS, Period.WEEK, date.today(), 900)
        services.record_aggregate(self.alice, Metric.NET_WORDS, Period.WEEK, date.today(), 300)

    def test_user_standing_rank(self):
        standing = services.user_standing(
            self.alice, Metric.NET_WORDS, Period.WEEK, date.today()
        )
        self.assertEqual(standing["rank"], 2)
        self.assertEqual(standing["aggregate"].value, 300)

    def test_ineligible_user_has_no_rank(self):
        self.alice.profile.leaderboard_visibility = Profile.LeaderboardVisibility.OFF
        self.alice.profile.save(update_fields=["leaderboard_visibility"])
        standing = services.user_standing(
            self.alice, Metric.NET_WORDS, Period.WEEK, date.today()
        )
        self.assertIsNone(standing["rank"])


class LeaderboardApiTests(TestCase):
    def setUp(self):
        self.user = make_user("api@example.com", "apiuser")
        services.record_aggregate(self.user, Metric.NET_WORDS, Period.WEEK, date.today(), 777)

    def test_public_leaderboard(self):
        response = self.client.get("/v1/leaderboards/net_words?period=week")
        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertEqual(payload["metric"], "net_words")
        self.assertEqual(payload["entries"][0]["username"], "apiuser")

    def test_unknown_metric_returns_404(self):
        self.assertEqual(
            self.client.get("/v1/leaderboards/nonsense?period=week").status_code, 404
        )

    def test_invalid_period_returns_400(self):
        self.assertEqual(
            self.client.get("/v1/leaderboards/net_words?period=century").status_code,
            400,
        )

    def test_my_standing(self):
        self.client.force_login(self.user)
        response = self.client.get("/v1/leaderboards/net_words/me?period=week")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["rank"], 1)
        self.assertTrue(response.json()["eligible"])

    def test_submit_requires_auth(self):
        response = Client().post("/v1/statistics/aggregates")
        self.assertEqual(response.status_code, 401)

    def test_submit_aggregates(self):
        self.client.force_login(self.user)
        body = json.dumps(
            {
                "aggregates": [
                    {
                        "metric": "words_added",
                        "period": "day",
                        "period_start": date.today().isoformat(),
                        "value": 500,
                    }
                ]
            }
        )
        response = self.client.post(
            "/v1/statistics/aggregates",
            data=body,
            content_type="application/json",
        )
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()["accepted"])

        listing = self.client.get(
            "/v1/leaderboards/words_added?period=day"
        ).json()
        self.assertEqual(listing["entries"][0]["value"], 500)
