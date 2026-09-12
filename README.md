# Writing Tracker

A native macOS writing analytics and session tracker. It observes writing activity
in the applications you already use (Microsoft Word first), associates it with
projects, records statistics, and presents analytics — **without ever recording
the words you type**.

> Track the writer, not the writing.

This repository implements the product described in
[`DESIGN_DOCUMENT.md`](DESIGN_DOCUMENT.md) and the
[`IMPLEMENTATION_ROADMAP.md`](IMPLEMENTATION_ROADMAP.md). [`AGENTS.md`](AGENTS.md)
contains the operating rules used while building it.

---

## Highlights

- **Menu bar utility** that keeps tracking while the dashboard window is closed.
- **Background tracking engine** independent of the SwiftUI layer.
- **Session state machine** (`IDLE → FOCUSED → ACTIVE → PAUSED → ACTIVE → ENDED`)
  with pause/resume, inactivity timeout, sleep/wake handling and crash recovery.
- **Frontmost application detection** and **listen-only activity monitoring**
  (keyboard/mouse signals only — never key contents).
- **Microsoft Word adapter** using Word's AppleScript interface (verified against
  Word for Mac 16.x) for active document, path and word count.
- **Adapter architecture** (`WritingApplicationAdapter`) so new editors can be
  added without touching the tracking engine. Scrivener, Pages, Ulysses,
  LibreOffice, Obsidian and browsers ship as focus/activity-only adapters.
- **Local-first SQLite persistence** behind a `Database` abstraction and
  repositories, with versioned migrations.
- **Statistics engine** for daily/weekly/monthly/yearly/lifetime totals, streaks,
  goals, productivity patterns and completion projections.
- **Full GUI**: dashboard, statistics, calendar heatmap, sessions, projects,
  goals, reports, achievements, settings and a Permission Center.
- **CSV/JSON export**, verified database backups, and safe destructive operations.
- **Privacy by design**: no manuscript text, keystrokes, clipboard, screenshots,
  or cloud.

---

## Requirements

- macOS 13 or later
- Xcode 15+ / Swift 5.9+ toolchain
- The Swift package has **no third-party dependencies** (SQLite is a system library).

## Build & run

```bash
# Build and test the core library and app
swift build
swift test

# Build a launchable .app bundle (recommended for permissions/login item)
./Scripts/build-app.sh release
open dist/WritingTracker.app
```

The app is a menu bar utility (`LSUIElement`), so it does not appear in the Dock.
Click the pencil icon in the menu bar to open the popover, then **Dashboard**.

The database lives at:

```
~/Library/Application Support/WritingTracker/WritingTracker.sqlite
```

Backups are written to `.../WritingTracker/Backups/`.

---

## macOS permissions

Permissions are requested progressively and only when a feature needs them.
Nothing is bypassed, and every feature degrades gracefully.

| Capability | Permission | If denied |
|---|---|---|
| Keyboard activity detection | Accessibility | Focus/active timing still works from the frontmost app and the system idle counter; manual sessions still work |
| Word document + word count | Automation (Apple Events) | Sessions, focus/activity and manual word entry still work; Word word counts are unavailable |
| Specific file/folder access | Files & Folders (via `NSOpenPanel`) | Only that specific feature is disabled |
| Notifications | Notifications | Requested only when you enable notifications |
| Launch at Login | Login Items (`SMAppService`) | Start the app manually |

Full Disk Access, Screen Recording, Camera, Microphone and Location are **never**
requested.

### Notes on development builds

The bundle is ad-hoc signed by `Scripts/build-app.sh`. Rebuilding changes the
signature, so macOS may ask you to re-grant Accessibility/Automation permission
after a rebuild. This is expected during development.

---

## Architecture

```
SwiftUI UI  →  AppState / ViewModels  →  Services  →  Repositories  →  SQLite
                                              │
                              ┌───────────────┼────────────────┐
                              ▼               ▼                ▼
                       TrackingEngine   StatisticsService   PermissionManager
                              │               │
                       Activity events   Aggregates
                              │               │
                              └───────┬───────┘
                                      ▼
                             Repositories / Database
                                      │
                              Application Adapters
                         (Word, Scrivener, Pages, …)
```

- `Sources/WritingTrackerCore` — models, persistence, repositories, services,
  statistics, tracking engine, permissions, adapters. **No SwiftUI.**
- `Sources/WritingTrackerApp` — SwiftUI UI, `AppState`, `AppDelegate`.
- `Tests/WritingTrackerCoreTests` — unit/integration tests using isolated
  in-memory or temporary databases.

Key design rules enforced by the code:

- The tracking engine never depends on SwiftUI and keeps running when the window
  closes.
- The UI never touches SQLite directly.
- Application-specific behaviour lives only in adapters.
- Net manuscript change is never labelled "words written".
- `wordsAdded` / `wordsRemoved` are `nil` unless edit-level data exists.
- All statistics are derived from raw sessions and can be rebuilt.

---

## Data model

`WritingApplication`, `Project`, `Document`, `Session`, `ActivityEvent`,
`WordCountSnapshot`, `DailyAggregate`, `Goal`, `Milestone`, `WritingSchedule`,
`AssociationRule`, `UserSettings`.

Timestamps are stored as absolute epoch seconds and all day boundaries are
computed through a timezone-aware `CalendarContext`, so midnight, DST and
timezone changes are handled correctly. Sessions store exact active/focus ranges
so multi-day sessions are split accurately.

## Testing

```bash
swift test
```

Coverage includes: session state transitions, inactivity, sleep/wake, manual and
automatic modes, word-count semantics, daily aggregation across midnight and DST,
crash recovery, repository persistence, association rules, manual entry,
statistics (daily/weekly/monthly/yearly/lifetime/streaks/projections/patterns),
export, backup, and destructive-operation safety.

## Known limitations

- Additional writing-application adapters (Scrivener, Pages, Ulysses,
  LibreOffice, Obsidian, browsers) currently provide focus/activity tracking
  only; deep document/word-count integration is Word-only.
- `wordsAdded`/`wordsRemoved` are only populated for manual entries because Word
  exposes net word count, not edit-level deltas.
- The tracking engine runs in-process with the menu bar app (which keeps running
  when the dashboard is closed) rather than as a separate XPC/LaunchAgent.
  The engine is GUI-independent and the boundary would allow extracting it later.
- Automatic project inference is rule-based as documented; no ML inference.
- Widgets, cloud sync, accounts, AI analysis and monetization enforcement are
  intentionally not implemented (roadmap phases scheduled for later), though
  `Entitlement`/`FeatureFlags` abstractions exist.
