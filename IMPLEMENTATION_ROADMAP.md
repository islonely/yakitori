# Writing Tracker for macOS
## Implementation Roadmap for Coding AI

**Document status:** Implementation specification  
**Repository:** git@github.com:islonely/yakitori.git (all completed commits are pushed here)  
**Target platform:** macOS  
**Primary stack:** Swift + SwiftUI  
**Architecture:** Native menu bar app + persistent background tracking service + local database  
**Initial writing application:** Microsoft Word for Mac  
**Word-count integrations:** Microsoft Word and Apple Pages (applications that expose an exact,
scriptable word count). Applications without a word-count API may still be tracked for
focus/activity but are **not** advertised as supported, and word counts are never estimated.

## Supported writing applications

The product only claims word-count support for applications from which an **exact**
word count can be read through a supported macOS interface. As of this document:

| Application | Focus/activity | Exact word count | Mechanism / verdict |
|---|---|---|---|
| Microsoft Word | Yes | Yes | AppleScript `compute statistics` (verified) |
| Apple Pages | Yes | Yes | AppleScript `count of words of body text` (verified) |
| Scrivener | Yes (time only) | **No** | Literature & Latte confirm Scrivener has never had AppleScript; project files are RTF, so counting would mean reading the manuscript |
| Ulysses | Yes (time only) | **No** | Has an x-callback-url API (`get-item`, `read-sheet`), but no word count and no way to identify the active sheet. `read-sheet` only returns text, which we will not read |
| LibreOffice | Yes (time only) | **No** | A UNO API exists (`getWordCount`) but requires an enabled UNO socket / macro bridge; not a supported macOS automation interface and not installed |
| Obsidian | Yes (time only) | **No** | Electron app; no AppleScript. URI scheme opens files only. A vault's markdown would have to be read to count |
| Browsers (Chrome/Brave/Edge/Safari) | Yes (time only) | **No** | `execute javascript` / `do JavaScript` exist but are **off by default** ("Allow JavaScript from Apple Events"); Google Docs renders to a canvas so the DOM has no reliable text |
| Lacuna Book Formatter | Yes (time only) | **No** | Tauri app with an internal `get_word_count` command but no external API, URL scheme or AppleScript. Project is a zip of TipTap JSON; counts are computed at runtime, not stored |
| Atticus / Vellum / other formatters | Yes (time only) | **No** | No documented external automation interface |

Rules:

- **Never estimate a word count from keystrokes.** If an application does not
  expose an exact count, the UI reports "Word count unavailable".
- Applications without a count API can still be added and tracked for focus and
  active time, but they are labelled as time-only.
- Adding a new count-supported adapter requires a verified, documented interface
  that returns a word count **without reading manuscript text**.
- Reading document/sheet/project files (Scrivener RTF, Ulysses `read-sheet`,
  Obsidian markdown, Lacuna TipTap JSON) is explicitly **not** an acceptable
  word-count mechanism.


---

## 1. Mission

Build a **writing analytics and session tracker**, not a writing editor.

The user continues writing in the application they already use, especially Microsoft Word. The product observes writing activity, associates it with projects, records statistics, and presents useful analytics.

The tracker must:

- Work while Microsoft Word or another writing application has focus.
- Continue tracking when the main GUI window is closed.
- Launch automatically at login.
- Support both manual and automatic tracking.
- Never record manuscript text or actual keystrokes.
- Use native application integrations for document and word-count information where available.
- Store data locally first.
- Remain useful when optional permissions are denied.
- Be designed around adapters so new writing applications can be added without rewriting the tracking engine.

### Core principle

> Track the writer, not the writing.

---

# 2. Non-Negotiable Requirements

These rules apply throughout implementation.

1. **Do not create a proprietary writing editor.**
2. **Do not require the user to write inside the tracker.**
3. **Do not record typed characters.**
4. **Do not store keyboard event contents.**
5. **Do not capture screenshots.**
6. **Do not read the clipboard.**
7. **Do not require Screen Recording permission.**
8. **Do not require Full Disk Access.**
9. **Do not equate keyboard activity with words written.**
10. **Do not treat net word-count change as exact words typed.**
11. **The GUI must not be responsible for background tracking.**
12. **Closing the GUI must not stop tracking.**
13. **All persistent data must be reproducible from underlying records where practical.**
14. **Every significant implementation step should be committed to Git in a small logical commit.**
15. **Do not add cloud infrastructure to the MVP.**
16. **Do not add telemetry that contains document names, file paths, project names, manuscript text, or keyboard content.**

---

# 3. Recommended Project Structure

Use a native macOS application.

Suggested Xcode structure:

```text
WritingTracker/
├── App/
│   ├── WritingTrackerApp.swift
│   ├── AppDelegate.swift
│   └── AppLifecycleCoordinator.swift
│
├── Core/
│   ├── Models/
│   ├── Services/
│   ├── Repositories/
│   ├── Statistics/
│   ├── Tracking/
│   ├── Permissions/
│   └── Utilities/
│
├── Integrations/
│   ├── WritingApplicationAdapter.swift
│   ├── Word/
│   ├── Scrivener/
│   ├── Pages/
│   ├── Ulysses/
│   ├── Browser/
│   └── Generic/
│
├── UI/
│   ├── MenuBar/
│   ├── Dashboard/
│   ├── Statistics/
│   ├── Calendar/
│   ├── Sessions/
│   ├── Projects/
│   ├── Goals/
│   ├── Reports/
│   └── Settings/
│
├── Resources/
│   ├── Assets.xcassets
│   └── Localizable.xcstrings
│
└── Tests/
    ├── Unit/
    ├── Integration/
    └── UI/
```

Use clear boundaries between:

```text
UI
 ↓
ViewModel
 ↓
Service
 ↓
Repository
 ↓
Database
```

The tracking engine must not depend on SwiftUI views.

---

# 4. Phase 0: Repository and Application Foundation

## Goal

Create a stable native macOS application before implementing tracking.

### Tasks

- Create the Xcode macOS application.
- Use Swift and SwiftUI.
- Create the application bundle identifier.
- Set up Git.
- Create the directory/module structure.
- Add a README.
- Add an `AGENTS.md` containing these implementation rules.
- Configure Debug and Release builds.
- Establish a basic logging system.
- Establish a dependency-injection approach where useful.
- Add unit-test targets.
- Add UI-test targets.
- Decide whether SwiftData or SQLite is the persistence implementation.

### Persistence recommendation

Prefer a persistence abstraction:

```swift
protocol Database {
    // CRUD and transaction operations
}
```

This keeps the rest of the application independent from the chosen storage engine.

SQLite is a strong choice for analytics-heavy data. SwiftData is acceptable if it does not create limitations for querying, migrations, or long-term data portability.

### First UI

Create a minimal menu bar application with:

- Menu bar icon.
- Popover.
- Start Session.
- Stop Session.
- Pause Session.
- Open Dashboard.
- Settings.
- Quit.

At this stage, buttons may be non-functional.

### Commit

```text
chore: initialize native macOS tracker application
```

---

# 5. Phase 1: Data Model

Implement the persistent model before building complex UI.

## Core entities

### WritingApplication

```text
id
bundleIdentifier
displayName
iconReference
adapterType
enabled
createdAt
updatedAt
configuration
```

### Project

```text
id
title
type
description
status
targetWordCount
startingWordCount
currentWordCount
deadline
createdAt
startedAt
completedAt
archivedAt
```

Project types:

```text
Novel
Novella
ShortStory
Screenplay
Nonfiction
Article
Academic
Other
```

Project statuses:

```text
Idea
Planning
Drafting
Revising
Editing
Proofreading
Complete
Published
Abandoned
Archived
```

### Document

```text
id
projectID
applicationID
displayName
stableIdentifier
filePath
createdAt
lastSeenAt
```

Do not assume every application exposes a stable file path.

Identity priority:

1. Application-provided stable identifier
2. Document URL/path
3. Window/document identity
4. Window title
5. Manual association

### Session

```text
id
projectID
documentID
applicationID
startedAt
endedAt
activeSeconds
focusSeconds
startingWordCount
endingWordCount
wordsAdded
wordsRemoved
netWordChange
sessionType
notes
```

Session types:

```text
Drafting
Editing
Revising
Proofreading
Research
Planning
Other
Unknown
```

### ActivityEvent

```text
id
timestamp
applicationID
eventType
sessionID
metadata
```

Event types:

```text
applicationFocused
applicationUnfocused
keyboardActivity
mouseActivity
documentChanged
wordCountSampled
sessionStarted
sessionPaused
sessionResumed
sessionEnded
systemSleep
systemWake
```

Do not put typed characters in metadata.

### WordCountSnapshot

```text
id
timestamp
documentID
projectID
wordCount
source
```

### Goal

```text
id
projectID
period
target
metric
startDate
endDate
enabled
```

### Milestone

```text
id
projectID
title
targetValue
metric
completedAt
```

### WritingSchedule

```text
id
weekday
enabled
targetMinutes
targetWords
```

### UserSettings

Store:

- tracking mode
- selected applications
- inactivity timeout
- default session type
- streak threshold
- notification preferences
- writing schedule
- privacy settings
- launch-at-login setting
- onboarding completion state

---

# 6. Phase 2: Permission Architecture

Permissions are a first-class subsystem.

Do not scatter permission checks throughout the application.

Create:

```swift
PermissionManager
PermissionStatus
PermissionRequirement
PermissionCenter
```

## Permission categories

### Accessibility

Used for global activity monitoring and Accessibility APIs where required.

Purpose:

- Observe keyboard activity without recording key content.
- Observe activity outside the tracker application.
- Potentially inspect accessibility information required by an application adapter.

The app must explain why this permission is needed before directing the user to System Settings.

Use the appropriate macOS Accessibility trust APIs, such as:

```swift
AXIsProcessTrustedWithOptions(...)
```

Do not grant or bypass permissions programmatically.

### Automation / Apple Events

Required for deep integrations such as Microsoft Word if AppleScript/Apple Events are used to query document state or word count.

Important:

- Automation permission is separate from Accessibility.
- Permission may be requested separately for each target application.
- Do not request Word automation until the user enables Word integration or the application actually needs it.

### File access

Do not request Full Disk Access.

When the user explicitly selects a document or folder:

- Use `NSOpenPanel`.
- Store security-scoped bookmarks where necessary.
- Access only user-selected locations.
- Gracefully handle revoked access.

### Notifications

Only request notification authorization when the user enables notifications or when a notification-related feature is first activated.

Do not request notification permission during initial launch unless the user has explicitly enabled the feature.

### Login at startup

Use the current macOS supported login-item/background-launch mechanism.

Present launch-at-login as a setting rather than treating it as an unexplained permission request.

### Permissions that should NOT be requested

Do not request:

- Camera
- Microphone
- Location
- Screen Recording
- Clipboard access
- Full Disk Access

unless a future feature genuinely requires one. MVP functionality must not require them.

---

# 7. Permission Onboarding Flow

The onboarding process must be progressive.

Do **not** show a wall of macOS permission prompts immediately after first launch.

## Step 1: Explain the product

Show:

> Writing Tracker runs in the background while you write in apps such as Microsoft Word. It records writing activity and statistics, not the words you type.

Explain privacy:

- No manuscript text is stored.
- No actual keystrokes are stored.
- No screenshots.
- Data stays on the Mac in the MVP.

Button:

```text
Continue
```

## Step 2: Choose writing applications

Display detected applications such as:

- Microsoft Word
- Scrivener
- Pages
- Ulysses
- LibreOffice
- Obsidian
- Supported browsers

Let the user select which applications should count toward automatic tracking.

Do not request permissions yet.

## Step 3: Accessibility

If the user enables automatic activity tracking:

Explain:

> Accessibility permission lets Writing Tracker detect keyboard activity while another application is active. The app records activity timestamps only; it does not save what you type.

Buttons:

```text
Grant Accessibility Permission
Skip for Now
```

If granted, verify status immediately.

If denied, continue onboarding.

## Step 4: Word integration

When the user enables Microsoft Word integration:

Explain:

> Word integration lets Writing Tracker ask Microsoft Word for information such as the active document and word count. Your document text is not stored by Writing Tracker.

Then trigger the appropriate Apple Events/Automation request.

If denied:

- Do not block the application.
- Mark Word integration as degraded.
- Continue tracking focus/activity where possible.
- Explain that word-count integration is unavailable.

## Step 5: File access

Only request file access when the user selects a document or project folder that requires direct filesystem access.

Explain why the specific file/folder is being accessed.

Never request broad disk access merely for convenience.

## Step 6: Notifications

Only ask when the user turns notifications on.

## Step 7: Final permission summary

Provide a Permission Center showing:

| Capability | Status |
|---|---|
| Accessibility | Granted / Not Granted |
| Microsoft Word Automation | Granted / Not Granted |
| Selected File Access | Granted / Not Granted |
| Notifications | Granted / Not Granted |
| Launch at Login | Enabled / Disabled |

Each unavailable permission gets:

```text
Open System Settings
```

and an explanation of what functionality is affected.

## Permission degradation

The application must remain useful without permissions.

Examples:

### Accessibility denied

Still allow:

- Manual sessions.
- Application selection.
- Focus tracking where available.
- Dashboard.
- Projects.
- Manual word-count entry if implemented.
- Existing historical data.

Disable or degrade:

- Global keyboard-activity detection.
- Accurate active-writing detection based on keyboard activity.

### Word Automation denied

Still allow:

- Session timing.
- Application tracking.
- Project tracking.
- Focus/activity statistics.
- Manual word-count entry.

Disable:

- Automated Word word-count sampling.

### File access denied

Still allow:

- Manual project association.
- Application-level tracking.

Disable only features requiring direct access to the selected file/folder.

## Permission re-check

Check permissions:

- On launch.
- When automatic tracking is enabled.
- When a relevant integration is enabled.
- Before beginning a feature requiring a permission.
- When returning from System Settings.

Do not repeatedly prompt after denial.

---

# 8. Phase 3: Background Tracking Engine

This is the core of the application.

The tracking engine must operate independently of the GUI.

Suggested architecture:

```text
macOS Events
     ↓
Event Monitor
     ↓
Tracking Engine
     ↓
Session State Machine
     ↓
Persistence
     ↓
Statistics
```

## Session state machine

Implement:

```text
IDLE
  ↓
FOCUSED
  ↓
ACTIVE
  ↓
PAUSED
  ↓
ACTIVE
  ↓
ENDED
```

Transitions:

- Writing app becomes frontmost → `FOCUSED`
- Activity detected → `ACTIVE`
- Inactivity timeout → `PAUSED`
- Activity resumes → `ACTIVE`
- App loses focus → `PAUSED` or `ENDED`, according to tracking mode
- User stops tracking → `ENDED`
- System sleeps → pause
- System wakes → remain paused until activity resumes

### Session recording rule

A session is only persisted when it represents real writing work:

- For applications that report a word count, the session must have a non-zero
  net word change (words added or removed). A session in which the manuscript did
  not change is discarded, including manual entries that add no words.
- For time-only applications (no word count available), a session is kept when it
  contains meaningful active or focus time.

Discarded sessions are never written to the database and never affect statistics.

---

# 9. Frontmost Application Detection

Use macOS workspace APIs such as:

```swift
NSWorkspace.shared.frontmostApplication
```

Track:

- Bundle identifier.
- Application name.
- Process identifier where needed.
- Focus start/end timestamps.

Never use application focus alone as proof that the user is writing.

Example:

```text
Word focused for 20 minutes
Keyboard activity for 8 minutes
```

The tracker should report approximately:

```text
Focus time: 20 min
Active time: 8 min
```

rather than pretending all 20 minutes were writing.

---

# 10. Keyboard Activity Monitoring

Use a listen-only event mechanism such as a Quartz Event Tap where appropriate.

Observe events only as activity signals.

Allowed:

```text
timestamp = 12:03:17
event = keyboardActivity
```

Forbidden:

```text
key = "A"
```

or:

```text
typedText = "The dragon entered the room."
```

Never store:

- key codes as a representation of manuscript content
- characters
- modifier combinations that could reveal content
- passwords
- clipboard contents

The monitor should emit a generic activity event:

```swift
ActivitySignal.keyboard(timestamp)
```

The tracking engine decides what that signal means.

---

# 11. Mouse Activity

Mouse activity may optionally be used as an activity signal.

Do not record:

- cursor positions
- screenshots
- click targets
- application content

Only record a generic activity timestamp.

Mouse activity should never be interpreted as words written.

---

# 12. Inactivity

Default:

```text
5 minutes
```

User-configurable:

```text
30 seconds
1 minute
2 minutes
5 minutes
10 minutes
15 minutes
Never
```

When no relevant activity occurs for the configured period:

```text
ACTIVE → PAUSED
```

When activity resumes:

```text
PAUSED → ACTIVE
```

---

# 13. Sleep and Wake

Register for macOS sleep/wake notifications.

On sleep:

- Pause active sessions.
- Record `systemSleep`.
- Do not count sleep time as active writing.

On wake:

- Record `systemWake`.
- Wait for normal activity before resuming active time.

Test:

- Sleep during session.
- Wake after several minutes.
- Sleep across midnight.
- Sleep while GUI is closed.

---

# 14. Automatic Tracking Modes

Implement three modes.

## Manual

User explicitly starts and stops sessions.

## Automatic

Configured writing applications are tracked automatically.

## Automatic with application filter

Only selected applications count.

The setting should allow:

```text
Tracking Mode:
( ) Manual
( ) Automatic
( ) Automatic, selected applications only
```

---

# 15. Writing Application Adapter System

Create:

```swift
protocol WritingApplicationAdapter
```

Suggested capabilities:

```swift
canDetectActiveDocument
canGetDocumentPath
canGetWordCount
canGetText
canDetectProject
canDetectChanges
canDetermineEditingActivity
```

Do not require every adapter to implement every capability.

Return unavailable values rather than inventing them.

Example:

```swift
struct ApplicationCapabilities {
    let activeDocument: Bool
    let documentPath: Bool
    let wordCount: Bool
    let textAccess: Bool
    let projectDetection: Bool
    let changeDetection: Bool
}
```

---

# 16. Microsoft Word Adapter

Word is the first deep integration.

The adapter should attempt to determine:

- Active document.
- Document name.
- Document path where available.
- Word count.
- Whether the document is still open.
- Potential project association.

Use Word's supported macOS automation interfaces where practical.

Do not assume exact AppleScript terminology without testing against the installed Word version.

Build a small isolated Word integration test harness before coupling it to the tracker.

## Word word-count sampling

Sample periodically while the document is active.

For example:

```text
09:00 → 50,000
09:02 → 50,342
09:05 → 50,891
```

The tracker can derive:

```text
Net change = +891
```

But it must not claim:

```text
Words typed = 891
```

because the user could have:

- Pasted text.
- Deleted text.
- Undone text.
- Redone text.
- Moved text.
- Changed formatting.
- Made other edits.

---

# 17. Word Count Semantics

Track separately:

### Starting word count

Word count when the session begins.

### Ending word count

Word count when the session ends.

### Net word change

```text
ending - starting
```

### Words added

Only calculate when reliable edit-level information exists.

### Words removed

Only calculate when reliable edit-level information exists.

### Gross work

May be implemented later if edit-level data becomes available.

Never fabricate precision.

If the system only knows net change, label it:

```text
Net manuscript change
```

not:

```text
Words written
```

### Typing pace (WPM)

Typing pace is **derived**, not measured from keystrokes. It is computed from
growth in the document's character count (5 characters = 1 word) divided by
active minutes. Deletions and modifier keys add nothing (backspace lowers the
count, shift does not change it), so they never inflate the pace. Pasted text is
indistinguishable from typing and therefore counts. Pace is only available for
applications that report a character count (Word and Pages) and is always labelled
as estimated. Per-keystroke counting is not used.

---

# 18. Document and Project Association

A project can use multiple applications.

Example:

```text
Project: Novel X

Microsoft Word
    Manuscript.docx

Scrivener
    NovelX.scriv

Obsidian
    Research vault
```

Association mechanisms, in priority order:

1. Explicit user association.
2. Exact document association.
3. Folder rule.
4. Project file recognition.
5. Application-specific project recognition.
6. Manual assignment.

Do not force a one-application-per-project architecture.

---

# 19. Phase 4: Projects

Build project management after tracking is functional.

Project dashboard must answer:

> How is this book progressing?

Show:

- Current words.
- Target words.
- Percentage complete.
- Start date.
- Last activity.
- Total active time.
- Number of sessions.
- Writing days.
- Average words/day.
- Average words/session.
- Current pace.
- Projected completion date.
- Milestones.
- Recent sessions.

---

# 20. Project Phases

Allow users to classify sessions as:

```text
Drafting
Editing
Revising
Proofreading
Research
Planning
Other
Unknown
```

Do not attempt automatic classification in the MVP.

Design the data model so future inference is possible.

---

# 21. Phase 5: Statistics Engine

Create a dedicated:

```swift
StatisticsService
```

The UI must not calculate statistics directly from database records.

Provide APIs such as:

```swift
dailyStatistics(date:)
weeklyStatistics(startDate:)
monthlyStatistics(month:)
yearlyStatistics(year:)
projectStatistics(projectID:)
lifetimeStatistics()
streakStatistics()
productivityPatterns()
```

## Daily statistics

Track:

- Words changed.
- Active minutes.
- Focus minutes.
- Sessions.
- Writing days.
- First session.
- Last session.
- Average session length.
- WPM where meaningful.

## Weekly statistics

Track:

- Total words changed.
- Active time.
- Sessions.
- Writing days.
- Average/day.
- Best day.
- Goal completion.
- Streak.

## Lifetime statistics

Track:

- Lifetime net words.
- Writing days.
- Total active hours.
- Total sessions.
- Projects.
- Completed projects.
- Best day.
- Best session.
- Best WPM.
- Longest streak.
- Average words/day.
- Average words/session.

---

# 22. Daily Aggregates

Do not repeatedly scan every raw event to render the dashboard.

Maintain aggregate records for:

```text
date
words
activeSeconds
focusSeconds
sessions
writingDays
projectsWorked
```

Raw sessions and events remain the source of truth.

Aggregates may be rebuilt if necessary.

Implement:

```text
rebuildDailyAggregates()
```

for data recovery and migration.

---

# 23. Goals

Implement:

- Daily word goals.
- Weekly word goals.
- Monthly word goals.
- Project word goals.
- Daily time goals.
- Weekly time goals.
- Deadline goals.

Examples:

```text
500 words/day
3,000 words/week
30 minutes/day
50,000 words by December 1
```

Goals should be independent of streaks.

---

# 24. Streaks

Support configurable streak thresholds:

```text
Any writing activity
100 words
250 words
500 words
Custom
```

Allow scheduled days off.

Example:

```text
Writing days:
Monday
Tuesday
Wednesday
Friday
Saturday
```

Thursday should not break a streak.

---

# 25. Projections

Provide projections based on:

- 7-day average.
- 30-day average.
- Project lifetime average.

Example:

```text
Current:
42,000 / 80,000

Needed:
38,000

Current pace:
620 words/day

Projected completion:
approximately 61 days
```

If insufficient data exists, say so.

Never produce a false precise projection.

---

# 26. Phase 6: Main User Interface

Use native SwiftUI.

## Menu bar popover

Display:

```text
Today

1,240 words
1h 17m active
3 sessions

Current Project
Novel X

Current Session
Active for 24m

[Pause] [Stop]

Streak: 8 days

[Open Dashboard]
```

Keep it compact.

---

# 27. Main Navigation

Sidebar:

```text
Dashboard
Statistics
Calendar
Sessions

Projects
    All
    Active
    Completed

Goals
Reports
Achievements
Community

Settings
Privacy
```

---

# 28. Dashboard

The dashboard must answer:

> How am I doing today?

within approximately two seconds.

Primary cards:

- Today's words.
- Active time.
- Sessions.
- Current project.
- Current streak.
- Goal progress.

Secondary:

- Today's timeline (hourly bars).
- Recent sessions.
- Weekly trend (daily bars with 7-day and 30-day moving averages).
- This week vs last week momentum by weekday.
- Goal progress gauges.
- Project progress.

The menu bar popover shows a compact hourly sparkline for today.

---

# 29. Project Dashboard

The project dashboard must answer:

> How is this book progressing?

Show:

- Progress ring.
- Current word count.
- Target.
- Words remaining.
- Average pace.
- Estimated completion.
- Active time.
- Sessions.
- Writing days.
- Recent activity.
- Milestones.
- Trend chart.
- Projection cone (7-day, 30-day and lifetime pace lines to the target).
- Burn-down of remaining words against the straight required-pace line.
- Word-count history per document.
- Milestone timeline.

---

# 30. Statistics

Use Swift Charts where appropriate. The implemented chart set:

Output and time:

- Daily words with 7-day and 30-day moving-average overlays.
- Daily active time (area).
- Weekly totals.
- Monthly totals.
- Focus vs active time (stacked bars; the gap is reading/thinking time).
- Added vs removed words (diverging bars, labelled estimated).
- Output by month (months-by-years grid).

Patterns:

- Time-of-day activity.
- Day-of-week activity.
- Day-of-week x hour heatmap (7x24).
- Radial 24-hour "writing clock".
- Session duration distribution.
- Session-type breakdown over time (stacked).
- Project mix over time (stacked area).

Sessions and pace:

- Session efficiency scatter (active minutes vs net words, coloured by type).
- Typing pace over time.
- Typing pace distribution.

Consistency and records:

- Writing streak history (one bar per streak).
- Personal records (best day, session, pace, week, longest streak).
- Lifetime totals.

Project and career:

- Project progress.
- Cumulative project progress with pace projections.
- Burn-down.
- Per-document word-count history.
- Milestone timeline.
- Project comparison.
- Career output by year and project type.
- Year in pixels.

Avoid decorative charts with no useful information.

---

# 31. Calendar

Create a GitHub-style writing heatmap.

Allow metric selection:

```text
Words
Active Minutes
Sessions
```

Clicking a day opens daily detail.

Additional views:

- A daily bar chart for the selected day's month.
- Year in pixels (a compact month x day grid for the last year).

Daily detail:

- Words.
- Active time.
- Focus time.
- Sessions.
- Projects.
- WPM.
- First/last session.
- Session list.

---

# 32. Session History

Search and filter by:

- Date.
- Project.
- Application.
- Session type.
- Duration.
- Word change.

Each session should show:

```text
Project
Application
Document
Start
End
Active time
Focus time
Word-count change
Session type
Notes
```

---

# 33. Settings

Sections:

### Tracking

- Tracking mode.
- Inactivity timeout.
- Selected applications.
- Start automatically.
- Global start/stop hotkey (user-configurable, optional).

### Applications

List all detected writing applications.

For each:

```text
Application
Enabled
Adapter
Capabilities
Permission status
```

### Projects

Project management and association rules.

### Goals

Goal configuration.

### Notifications

Notification preferences.

### Privacy

Explicitly display:

```text
Manuscript text: Never stored
Keyboard contents: Never stored
Clipboard: Not accessed
Screenshots: Not taken
Cloud sync: Disabled
```

### Permissions

Open Permission Center.

### Data

- Export CSV.
- Export JSON.
- Backup database.
- Rebuild aggregates.
- Reset tracking data.

---

# 34. Phase 7: Export and Data Integrity

Implement exports before considering cloud sync.

## CSV

Export:

- Sessions.
- Daily statistics.
- Projects.
- Word-count snapshots.

## JSON

Export complete structured data.

## Database backup

Allow the user to make a local database backup.

Data must survive:

- App restart.
- Computer restart.
- GUI closure.
- Crash recovery.
- Sleep/wake.
- Midnight.
- Time-zone changes.
- DST changes.

---

# 35. Crash Recovery

At launch:

1. Load unfinished sessions.
2. Determine whether the application was closed unexpectedly.
3. Close or repair the stale session.
4. Do not count time while the tracker was not actually running.
5. Preserve historical data.

Example:

```text
Session started 10:00
App crashed 10:47
App restarted 12:00
```

Do not record 10:00–12:00 as active.

---

# 36. Midnight and Time Zones

Sessions may span midnight.

Split daily aggregates correctly:

```text
23:50–00:10
```

becomes:

```text
Day 1: 10 minutes
Day 2: 10 minutes
```

Handle daylight-saving transitions using proper timezone-aware dates.

Do not perform statistics using naive fixed 24-hour assumptions.

---

# 37. Launch at Login and Background Operation

The tracker must be able to run without its dashboard window being open.

Recommended architecture:

```text
Login
 ↓
Tracker process starts
 ↓
Background tracking service initializes
 ↓
Menu bar UI connects to tracking service
```

The UI may disconnect without terminating the tracking engine.

If using an XPC helper architecture, keep the communication contract small and explicit.

Do not make the database dependent on the UI process.

---

# 38. Low Resource Usage

The application should be appropriate for continuous operation.

Avoid:

- Tight polling loops.
- Constant database writes.
- Frequent expensive AppleScript calls.
- Repeated full-document scans.
- High-frequency word-count queries.

Prefer:

- Event-driven activity detection.
- Debounced writes.
- Periodic word-count sampling.
- Cached application information.
- Batched aggregate updates.

Target behavior:

- Negligible CPU while idle.
- Low memory footprint.
- No noticeable typing latency.
- No interference with Word.

---

# 39. Testing Strategy

Create tests for:

## Tracking

- Focus detection.
- Activity detection.
- Inactivity timeout.
- Pause/resume.
- Manual start/stop.
- Automatic mode.
- Application filtering.

## Sleep

- Sleep during session.
- Wake during session.
- Sleep across midnight.

## Database

- Insert session.
- Update session.
- Crash recovery.
- Migration.
- Aggregate rebuilding.

## Word counts

Test:

```text
1000 → 1200
1200 → 1150
1150 → 1300
```

Expected net:

```text
+300
```

Do not report:

```text
+500 words written
```

unless edit-level data actually supports it.

## Permissions

Test every combination:

| Accessibility | Word Automation | Expected |
|---|---|---|
| Granted | Granted | Full functionality |
| Granted | Denied | Activity tracking; Word word count degraded |
| Denied | Granted | Limited activity detection; Word integration where possible |
| Denied | Denied | Manual/focus-based functionality |

Also test:

- Permission granted after launch.
- Permission revoked.
- System Settings opened.
- User returns to app.

---

# 40. Manual Test Matrix

Test on a clean macOS installation/profile where practical.

### Word

- New document.
- Existing document.
- Save.
- Save As.
- Close document.
- Multiple documents.
- Switching documents.
- Word count changes.
- Paste.
- Delete.
- Undo.
- Redo.
- Formatting without word changes.

### Application switching

```text
Word → Safari → Word
Word → Finder → Word
Word → Writing Tracker → Word
```

The tracker should not count unrelated applications as writing.

### GUI

- Close dashboard.
- Reopen dashboard.
- Quit menu bar UI if supported.
- Relaunch.
- Restart Mac.

Tracking should recover correctly.

---

# 41. Privacy Requirements

The privacy model is a product feature.

The database may contain:

- Application identity.
- Timestamps.
- Session duration.
- Document identifier/path where user has permitted it.
- Word counts.
- Project names.
- Statistics.

The database must not contain:

- Manuscript text.
- Typed characters.
- Clipboard contents.
- Passwords.
- Screenshots.
- Keystroke sequences.
- Content-derived analytics that reveal manuscript text.

Logs must follow the same rule.

For example, never log:

```text
User typed: "The king entered..."
```

Log:

```text
Keyboard activity detected
```

---

# 42. Architecture for Future Integrations

Implement the adapter system now even though only Word needs deep integration initially.

Future adapters:

```text
WordAdapter        (exact word count)
PagesAdapter       (exact word count)
ScrivenerAdapter   (time only)
UlyssesAdapter     (time only)
BrowserDocumentAdapter (time only)
LibreOfficeAdapter (time only)
ObsidianAdapter    (time only)
GenericApplicationAdapter (time only)
```

Only adapters marked "exact word count" may report word counts; the rest must
return unavailable values rather than estimating.

The generic adapter should at minimum support:

- Application detection.
- Focus time.
- Activity time.

A deep adapter can add:

- Document identity.
- Project identity.
- Word count.
- Change detection.

---

# 43. Generic Application Fallback

If no specialized adapter exists:

```text
Application detected
+
Application selected by user
=
Track focus/activity
```

Do not pretend to know document word counts.

UI should communicate capability honestly:

```text
Activity tracking available
Word count unavailable
```

---

# 44. Phase 8: Advanced Analytics

Only after the basic product is reliable.

Potential features:

- Project comparisons.
- Historical comparisons.
- Best writing hours.
- Best days of week.
- Average session length.
- Productivity patterns.
- Year in Review.
- Advanced editing analytics.
- Milestone analytics.
- WPM trends.
- Project pace changes.

Do not prioritize these ahead of core tracking correctness.

---

# 45. Phase 9: Additional Integrations (exact word counts only)

After Word is stable:

1. Pages (implemented — verified AppleScript word count).
2. Any future application **only if** it exposes a supported, documented word
   count that does not require reading manuscript text.

Applications without such an interface (Scrivener, Ulysses, LibreOffice,
Obsidian, browsers, generic apps) may be tracked for focus/activity time, but
must be presented as time-only and must never produce an estimated word count.

Each integration should be developed as an isolated adapter.

Adding an adapter must not require modifying the core session state machine.

---

# 46. Phase 10: Monetization Architecture

Do not monetize the MVP yet.

However, keep monetization separate from the tracking engine.

Create abstractions such as:

```swift
enum Entitlement {
    case free
    case pro
    case cloud
}
```

and:

```swift
FeatureFlags
```

Potential future free features:

- Local tracking.
- Basic dashboard.
- Basic statistics.
- Limited projects.

Potential Pro features:

- Unlimited projects.
- Lifetime analytics.
- Advanced charts.
- Advanced integrations.
- Reports.
- Advanced productivity analysis.
- Historical comparisons.
- Advanced goals.

Potential Cloud features:

- Sync.
- Cloud backup.
- Web dashboard.
- Cross-device support.

**Core local tracking must never depend on a server.**

---

# 47. Future Cloud Architecture

Do not implement in MVP.

Potential future architecture:

```text
macOS Tracker
      ↓
Local database
      ↓
Optional Sync Layer
      ↓
Cloud API
      ↓
Web / Mobile
```

The local database remains authoritative enough to function offline.

Future cloud synchronization should be designed around record IDs, timestamps, conflict handling, and migrations.

---

# 48. Future Relationship / Project Intelligence

The data model should eventually support relationships such as:

```text
Project
 ├── Documents
 ├── Applications
 ├── Sessions
 ├── Goals
 ├── Milestones
 └── Statistics
```

This should make future visualizations possible without redesigning the underlying model.

---

# 49. Implementation Order

The coding AI should follow this order.

## Milestone 1: Foundation

- Xcode project.
- SwiftUI.
- Menu bar app.
- Git.
- Tests.
- Logging.
- Architecture.

## Milestone 2: Persistence

- Database.
- Models.
- Repository layer.
- Migrations.
- Basic CRUD.

## Milestone 3: Permissions

- PermissionManager.
- Permission Center.
- Onboarding.
- Accessibility flow.
- Word Automation flow.
- File access flow.
- Notification flow.
- Graceful degradation.

## Milestone 4: Tracking

- Frontmost app detection.
- Activity monitoring.
- Session state machine.
- Inactivity.
- Sleep/wake.
- Manual sessions.
- Automatic sessions.

## Milestone 5: Word

- Word adapter.
- Document detection.
- Word count sampling.
- Automation error handling.
- Permission integration.

## Milestone 6: Projects

- Project CRUD.
- Document association.
- Application association.
- Project dashboard.

## Milestone 7: Statistics

- Daily aggregates.
- Statistics service.
- Goals.
- Streaks.
- Projections.

## Milestone 8: UI

- Dashboard.
- Statistics.
- Calendar.
- Session history.
- Projects.
- Goals.
- Settings.
- Permission Center.

## Milestone 9: Reliability

- Crash recovery.
- Data repair.
- Export.
- Backup.
- Timezone/DST handling.
- Extensive testing.

## Milestone 10: Additional Applications

- Scrivener.
- Pages.
- Ulysses.
- Browser.
- LibreOffice.
- Obsidian.
- Generic adapters.

## Milestone 11: Advanced Analytics

- Historical comparisons.
- Productivity patterns.
- Reports.
- Year in Review.
- Advanced editing metrics.

## Milestone 12: Commercialization

Only after the product is stable:

- Entitlements.
- Pro features.
- Licensing.
- Distribution strategy.
- Optional cloud architecture.

---

# 50. Definition of Done for MVP

The MVP is complete when all of the following work reliably:

- [ ] Native macOS application.
- [ ] Menu bar interface.
- [ ] Background tracking independent of GUI.
- [ ] Launch at login.
- [ ] Manual sessions.
- [ ] Automatic sessions.
- [ ] Application filtering.
- [ ] Frontmost app detection.
- [ ] Keyboard activity detection without storing content.
- [ ] Inactivity timeout.
- [ ] Sleep/wake handling.
- [ ] Accessibility permission flow.
- [ ] Word Automation permission flow.
- [ ] File-access permission flow.
- [ ] Permission Center.
- [ ] Graceful degraded modes.
- [ ] Microsoft Word adapter.
- [ ] Word-count sampling.
- [ ] Project management.
- [ ] Document association.
- [ ] Session history.
- [ ] Daily statistics.
- [ ] Weekly statistics.
- [ ] Lifetime statistics.
- [ ] Goals.
- [ ] Streaks.
- [ ] Basic projections.
- [ ] Calendar history.
- [ ] Basic charts.
- [ ] CSV export.
- [ ] JSON export.
- [ ] Local database backup.
- [ ] Crash recovery.
- [ ] Timezone/DST correctness.
- [ ] Privacy protections.
- [ ] Unit tests.
- [ ] Integration tests.
- [ ] UI tests for critical flows.

---

# 51. Coding Standards for the AI

The coding AI must:

1. Inspect the existing project before modifying it.
2. Never delete or overwrite persistent data without explicit instruction.
3. Prefer migrations over destructive database changes.
4. Make one logical change at a time.
5. Run tests after each significant change.
6. Commit completed logical changes to Git and push them to the project's remote repository (`origin`, git@github.com:islonely/yakitori.git).
7. Never commit secrets.
8. Never log manuscript content.
9. Never add permissions that are not required.
10. Never introduce cloud dependencies into the local tracking path.
11. Keep UI code separate from tracking logic.
12. Keep application-specific logic inside adapters.
13. Avoid hard-coding Microsoft Word behavior into the generic tracker.
14. Document macOS permission requirements in the codebase.
15. Test permission-denied states, not only the happy path.
16. Prefer event-driven behavior over polling.
17. Avoid unnecessary background CPU usage.
18. Preserve backward compatibility when modifying the database.
19. Treat statistics as derived data.
20. Never claim precision that the underlying data cannot support.

---

# 52. First Coding Task

Start with **Milestone 1 only**.

Do not implement the entire application in one pass.

The first implementation should produce:

1. A compiling native macOS SwiftUI application.
2. A menu bar icon.
3. A basic popover.
4. A Dashboard placeholder.
5. A Settings placeholder.
6. Start/Pause/Stop controls with placeholder state.
7. Git repository initialized.
8. Test target configured.
9. `AGENTS.md` containing the non-negotiable rules.
10. Clear separation between UI and future tracking services.

After Milestone 1 is complete:

- Run the application.
- Run tests.
- Verify the menu bar behavior.
- Commit the changes.
- Then proceed to Milestone 2.

Do not jump ahead to Word integration before the persistence and permission architecture are in place.

---

# 52A. Social, Sharing and Gamification (local placeholder implemented)

The product owner wants, after 1.0:

- optional **public exposure** of a writer's statistics;
- multiple **leaderboards** (words, active time, streaks, per-period) that a
  writer can be placed on after finishing a session;
- **following** other writers and **comparing** statistics against them.

**Status:** the client side and leaderboard structure are implemented behind a
`SocialBackend` protocol, with a **local JSON placeholder** backend
(`~/Library/Application Support/Yakitori/community.json`). Publishing is opt-in;
only aggregate numbers are written. A "Show sample leaderboard entries" option
populates clearly-labelled placeholder profiles.

**Still required for real, online leaderboards:** a backend service — accounts,
a stats-ingestion API, leaderboard queries, and a follow graph. The client
already speaks the `CommunityData` shape, so a server can implement
`SocialBackend` (or a remote variant) without UI changes.

Privacy rules to preserve:

1. Statistics are private by default; publishing is opt-in and revocable.
2. Only aggregate numbers are shared — never documents, project names, paths, or
   manuscript text.
3. A privacy/security review before any network code ships.

# 53. Final Architectural Principle

The application should be thought of as:

```text
             ┌─────────────────────┐
             │     SwiftUI UI      │
             └──────────┬──────────┘
                        │
                  ViewModels
                        │
             ┌──────────▼──────────┐
             │      Services       │
             └──────────┬──────────┘
                        │
       ┌────────────────┼────────────────┐
       │                │                │
       ▼                ▼                ▼
 Tracking Engine   Statistics      Permission Manager
       │                │
       ▼                ▼
 Activity Events    Aggregates
       │                │
       └────────┬───────┘
                ▼
          Repository Layer
                │
                ▼
          Local Database

Application Integrations
        │
        ├── Word
        ├── Scrivener
        ├── Pages
        ├── Ulysses
        ├── Browser
        └── Generic
```

The tracker is the product.

Microsoft Word, Scrivener, and every other writing application are data sources.

The core tracking engine must remain independent of any single writing application.

**Build for correctness first; then reliability; then privacy; then resource efficiency; then native UX; then extensibility; then analytics; and monetization last.**
