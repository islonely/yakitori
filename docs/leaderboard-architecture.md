# Leaderboard Architecture

Leaderboards are a first-class future feature, so the schema, metric
definitions, privacy gating, and validation interface exist now. **No claim is
made that current rankings are cheat-proof** — see the trust model below.

Leaderboards never query raw writing sessions. They read precomputed aggregates.

## Metrics

Only Yakitori's existing metric definitions are used; no new metric is invented:

| Metric | Definition |
|---|---|
| `net_words` | Net manuscript change (added − removed) |
| `words_added` | Words added |
| `words_removed` | Words removed |
| `active_seconds` | Active writing time |
| `focus_seconds` | Focus time |
| `session_count` | Recorded sessions |

Keeping these distinct is intentional; a leaderboard cannot silently collapse
"words added" into "net words" or derive values from keystrokes.

## Periods

`day`, `week`, `month`, `all_time`. Boundaries are calendar-based. The client
decides which day a session belongs to using the user's timezone; the server
stores the resulting date so aggregation and ranking are deterministic.

## Aggregation schema

```
LeaderboardAggregate
  user, metric, period, period_start, period_end, value, source
  UNIQUE(user, metric, period, period_start)
  INDEX(metric, period, period_start, -value)
  INDEX(user, metric, period)

StatisticSubmission
  user, installation, payload, status(accepted|rejected), validation_error
```

A `record_aggregate` call is an upsert, so re-syncing the same period updates in
place rather than duplicating. The same shape can back daily, weekly, monthly,
and all-time materializations.

## Privacy and eligibility

A user appears on a public leaderboard only when **all** of the following hold:

- the account is active,
- `profile_visibility = public`,
- `leaderboard_visibility = global`.

This is enforced in `leaderboards.services.eligible_queryset`, so a private user
can never appear simply because a row exists. A user can still see their own
aggregate and rank via `/v1/leaderboards/:metric/me`, but `rank` is null when
they are not eligible.

## Ranking

- Ordered by `value DESC, id ASC` — deterministic even under ties.
- A ranked page computes each row's absolute rank, including when a cursor is
  used, by counting the rows that precede it.
- Public navigation uses usernames, never internal UUIDs.

## Pagination

Cursor pagination over `(value, id)`. The cursor encodes the last row's value
and id; the next page filters to lower values (or equal value with a greater
id). Offset pagination is not used.

## Validation interface (anti-cheat foundation)

`POST /v1/statistics/aggregates` accepts a list of aggregates. Each submission
is stored (accepted or rejected) so anomalies and abuse can be reviewed, and
`leaderboards.validation` applies plausibility checks:

- known metric and period only,
- `period_start` is a real, non-future date,
- integer values within an absolute bound,
- durations cannot exceed the number of seconds in the period,
- word counts cannot exceed a plausible per-period maximum,
- a bounded batch size.

Rejected submissions write nothing to the aggregate table.

### Trust model (explicit)

> A malicious client can fabricate statistics. The server does not, and does not
> claim to, cryptographically prove that client-reported writing happened.

This is deliberate. The alternative — collecting keystrokes or manuscript
content to "prove" writing — violates the product's privacy model and is not
done. Before competitive global leaderboards are enabled, a validation layer
should be added on top of this foundation, for example:

- signed statistic batches from the licensed installation,
- server-issued session identifiers and sequencing,
- cross-checks against the app's locally generated session data,
- anomaly detection and rate limits (already present),
- trust/reputation levels.

Until then, leaderboards are presented as **plausible, not proven**.

## API

| Method | Path | Notes |
|---|---|---|
| GET | `/v1/leaderboards/<metric>?period=&period_start=&limit=&cursor=` | Public, privacy-gated |
| GET | `/v1/leaderboards/<metric>/me?period=&period_start=` | Own value + rank |
| POST | `/v1/statistics/aggregates` | Validated submission; rate limited |

## What is intentionally not uploaded

Document names, project names, paths, manuscript text, raw keystrokes, and
clipboard contents never leave the Mac. Only deliberately public aggregate
numbers may be submitted.
