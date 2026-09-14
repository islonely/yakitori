# Social Architecture

Public identity (`profiles/`) and the social graph (`social/`) are separate from
the private account (`accounts/`) and from commerce. All three share the stable
`user_id`.

## Public identity

`profiles.Profile` is a one-to-one extension of the account:

- `username` (case-insensitively unique via `username_normalized`),
  `display_name`, `bio`, `avatar_url`.
- Independent privacy choices:
  - `profile_visibility`: public / private
  - `stats_visibility`: private / followers / public
  - `leaderboard_visibility`: off / followers / global
  - `allow_following`: bool

A public username does **not** imply public statistics. These are separate
switches, and privacy is enforced server-side on every read.

### Username policy

- Lowercase letters, digits, single underscores; 3–30 characters; must start and
  end with a letter or digit. This rejects whitespace, `@`, and other
  impersonation-sensitive characters.
- Reserved names are configurable: a built-in set in settings plus a
  `ReservedUsername` table editable in the admin.
- Uniqueness is enforced by a unique index on `username_normalized` and a
  `select_for_update` transaction, so two accounts cannot race to claim a name.
- Changes are recorded in `UsernameChange`. The **first** choice is free; later
  changes share a configurable cooldown (`USERNAME_CHANGE_COOLDOWN_DAYS`).
- A released username is held for the cooldown window so it cannot be
  immediately squatted. Old names are not redirected forever.

## Social graph

```
Follow(follower, followed)   UNIQUE(follower, followed)  CHECK follower <> followed
Block(blocker, blocked)      UNIQUE(blocker, blocked)    CHECK blocker <> blocked
Report(reporter, target, category, details, status, ...)
```

Indexes support "who I follow", "who follows me", follower/following counts, and
profile lookup.

### Visibility rules (single source of truth)

`social.services.can_view_profile(profile, viewer)`:

1. The owner always sees their own profile.
2. A block in either direction hides the profile entirely.
3. Public profiles are open.
4. Followers may see a private profile.
5. Otherwise, private profiles are indistinguishable from missing ones (404).

The same function is used by the HTML profile page and the JSON API, so the two
surfaces cannot drift.

### Blocking

A block is stored one-directionally but enforced mutually: neither party can
view the other or follow. Blocking also removes any existing follow edges in
both directions. Blocks are audited.

### Reporting

`Report` captures abuse (`spam`, `harassment`, `impersonation`, `cheating`,
`other`) with a status workflow (`pending`, `reviewing`, `actioned`,
`dismissed`). The schema and API boundaries exist now so a moderation UI can be
added without redesign. Reports are audited; the admin lists them.

## API

| Method | Path | Notes |
|---|---|---|
| GET | `/v1/users/<username>` | Public profile; privacy enforced |
| POST/DELETE | `/v1/users/<username>/follow` | Idempotent; rate limited |
| GET | `/v1/users/<username>/followers` | Cursor paginated |
| GET | `/v1/users/<username>/following` | Cursor paginated |
| POST/DELETE | `/v1/users/<username>/block` | Rate limited |
| POST | `/v1/users/<username>/report` | Rate limited |

Public navigation uses usernames, never internal UUIDs. Email addresses are
never returned in any public payload.

## Pagination

Follower/following lists use **cursor pagination** ordered by
`(created_at, id)`, so they stay correct and cheap as the graph grows. Offset
pagination is not used on high-growth collections.

## Rate limits

Follow/unfollow, profile mutations, and reports are rate limited by account via
`common.ratelimit`. Limits are server-side; client-side limits are never relied
upon.

## Threat considerations

| Threat | Mitigation |
|---|---|
| Enumeration of private users | 404 for unviewable profiles, same as missing |
| Impersonation | Username charset rules, reserved names, no email-as-username |
| Username squatting | Cooldown + released-name hold + unique index |
| Harassment / spam | Blocking, reporting, rate limits, audit trail |
| IDOR | Every endpoint resolves the resource from the authenticated user and explicit rules |
| Statistics leakage | `stats_visibility` is enforced independently of profile visibility |

## Explicit limitation

Client-reported writing statistics cannot be cryptographically trusted. Nothing
in the social layer claims otherwise; leaderboard trust is addressed (and its
limits documented) in `docs/leaderboard-architecture.md`.
