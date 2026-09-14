"""Serialization for profiles.

Public and private representations are deliberately different: the public shape
never contains the email address, internal UUIDs, or private statistics.
"""


def public_profile(profile, viewer=None):
    from social.services import counts, is_following

    followers, following = counts(profile.user)
    return {
        "username": profile.username,
        "display_name": profile.display_name or profile.username,
        "avatar_url": profile.avatar_url or None,
        "bio": profile.bio or None,
        "profile_visibility": profile.profile_visibility,
        "followers": followers,
        "following": following,
        "viewer_following": is_following(viewer, profile.user),
    }


def own_profile(profile):
    payload = public_profile(profile)
    payload.update(
        {
            "id": str(profile.pk),
            "stats_visibility": profile.stats_visibility,
            "leaderboard_visibility": profile.leaderboard_visibility,
            "allow_following": profile.allow_following,
        }
    )
    return payload
