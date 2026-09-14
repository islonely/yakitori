# Writing Productivity & Author Analytics
## Product, UX, Architecture, and Technical Design Specification

**Platform:** macOS  
**Primary language:** Swift  
**UI:** SwiftUI  
**Storage:** Local SQLite / SwiftData or equivalent, with an abstraction layer so the storage engine can be changed later  
**Architecture:** Native macOS application + persistent background tracking service  
**Primary use case:** Writers who compose in Microsoft Word, Scrivener, or another writing application and want detailed writing-productivity and author-progress analytics without changing their writing environment.

---

# 1. Product Vision

Create a polished macOS application that automatically tracks a writer's writing activity and turns it into useful statistics.

The application should answer questions such as:

- How many words did I write today?
- How much time did I actually spend writing?
- What is my average daily output?
- What is my average session length?
- What days of the week am I most productive?
- What is my current writing streak?
- What is my longest streak?
- How many words have I written this year?
- How many words have I written in my lifetime?
- How much work have I put into a particular book?
- When did I start writing this book?
- How quickly am I progressing?
- How much time have I spent drafting versus editing?
- How many words did I add to a project?
- How many words did I remove?
- What is my net word-count change?
- When am I likely to finish?
- How does my current writing pace compare with previous projects?
- Which books have received the most work?
- Which days/times are most productive?
- How much writing have I done this week/month/year?
- What is my best writing day ever?
- What is my best writing session ever?
- How many words did I write during a particular year?
- How much time have I spent writing across my entire career?

The application should feel like a **fitness tracker for authors**.

The user writes normally in their preferred application. The tracker observes activity and produces analytics.

---

# 2. Core Design Principle

## Do not make the user change where they write.

The application should NOT require the user to write inside a proprietary editor.

For example:

> User writes a novel in Microsoft Word.

The tracker runs independently.

The user opens Word and writes normally.

The tracker detects:

1. Word is the active application.
2. The user is actively interacting with Word.
3. The active document/project.
4. Changes in the document's word count when possible.
5. The amount of time spent actively working.
6. The resulting statistics.

The same system should work with:

- Microsoft Word (exact word count)
- Apple Pages (exact word count)
- Scrivener, Ulysses, LibreOffice, Obsidian and browsers (focus/activity time
  only — no exact word count is available from these applications)

Word counts are only shown for applications that expose an **exact** count through
a supported macOS interface. The tracker never estimates word counts from
keystrokes. Applications without a count API are still useful for time tracking
but are labelled accordingly.

The application should therefore have an abstraction called something like:

`WritingApplicationAdapter`

rather than hard-coding Word into the core tracking system.

---

# 3. Product Philosophy

The product should have three layers.

## Layer 1 — Activity Tracking

"What am I doing right now?"

Examples:

- Microsoft Word is active.
- User has been typing for 12 minutes.
- Current document is `Naphtali.docx`.
- Current project is `Naphtali`.
- Current session has produced a net +842 words.

## Layer 2 — Productivity Analytics

"What does my writing behavior look like?"

Examples:

- 1,243 words today
- 2h 14m active writing time
- 18 sessions
- 11.4 words/minute
- 6-day streak
- best day: 4,821 words
- most productive weekday: Saturday

## Layer 3 — Author Analytics

"What have I accomplished as an author?"

Examples:

- 2,481,392 lifetime words
- 17 books/projects
- 3 completed novels
- 8 drafts
- 6,240 hours tracked
- 1,843,000 words written in fiction projects
- current project: 72% complete
- estimated completion: October 14

These layers should remain conceptually separate.

---

# 4. Application Structure

The application should consist of:

### Main GUI application

Responsible for:

- dashboards
- graphs
- charts
- projects
- settings
- reports
- goals
- history
- data management

### Background tracking service

Responsible for:

- monitoring active applications
- monitoring keyboard activity
- monitoring session state
- polling writing applications
- recording activity
- calculating incremental changes
- maintaining tracking even when the main GUI is closed

The background component should continue operating when the main application window is closed.

Ideally, the application should behave like a menu-bar utility.

Closing the main window must NOT stop tracking.

---

# 5. Menu Bar Application

The application should have a macOS menu-bar presence.

Example:

`✎  1,243 words today`

Clicking it opens a small popover containing:

- Today's words
- Current project
- Current session duration
- Current session word count
- Current streak
- Start/stop tracking
- Open Dashboard
- Pause Tracking
- Settings

Example:

```
┌───────────────────────────────┐
│ ✎ Writing Tracker             │
│                               │
│ Today                         │
│ 1,243 words                   │
│ 1h 42m active                 │
│                               │
│ Current Project               │
│ Naphtali                      │
│ +486 words this session       │
│                               │
│ 🔥 7 day streak               │
│                               │
│ [ Pause ]   [ Dashboard ]     │
└───────────────────────────────┘
```

The menu-bar interface should remain lightweight.

The full GUI is for analysis.

---

# 6. Tracking Modes

This is one of the most important features.

The user should be able to choose how tracking operates.

## Mode A — Manual Sessions

Recommended default for users who want strict writing tracking.

The user explicitly starts a writing session.

Example:

`Start Writing Session`

The tracker then records activity until:

- the user stops the session
- the user manually pauses
- optionally, the session automatically pauses after prolonged inactivity

This mode solves the problem of people using Word for non-writing activities.

For example:

A novelist uses Word for:

- writing
- email
- contracts
- letters
- invoices

Only explicitly started writing sessions count.

---

# 7. Mode B — Automatic Tracking

The tracker runs continuously.

It detects:

- active application
- user activity
- writing application
- document
- activity duration
- word-count changes

The user does not need to press Start.

This is appropriate for writers who primarily use Word/Scrivener/etc. for writing.

---

# 8. Mode C — Automatic Tracking With Application Filter

Recommended advanced mode.

The user specifies:

> Track activity automatically whenever these applications are active.

Example:

```
Writing Applications

☑ Microsoft Word
☑ Scrivener
☑ Ulysses
☐ Pages
☐ Obsidian
☐ Google Chrome
```

The user can therefore choose exactly which applications count.

This is preferable to assuming that every keyboard interaction is writing.

---

# 9. Application Selection

The user should be able to add an application through a native macOS application picker.

Example:

`+ Add Writing Application`

The user selects:

- Microsoft Word
- Scrivener
- Ulysses
- Pages
- etc.

The application should store:

- bundle identifier
- display name
- icon
- tracking status
- adapter type
- configuration

Example conceptual record:

```text
WritingApplication
    id
    name
    bundleIdentifier
    adapterType
    enabled
    automaticTrackingEnabled
    createdAt
```

Do not hard-code the application list into the database.

---

# 10. Application Adapters

The tracker should have an adapter architecture.

Example:

```text
WritingApplicationAdapter
    ├── WordAdapter               (exact word count)
    ├── PagesAdapter              (exact word count)
    ├── ScrivenerAdapter          (time only)
    ├── UlyssesAdapter            (time only)
    ├── BrowserDocumentAdapter    (time only)
    └── GenericApplicationAdapter (time only)

Only Word and Pages currently report word counts. Every other adapter reports
`wordCount: nil` and the UI states "Word count unavailable".
```

Each adapter can expose capabilities.

For example:

```text
ApplicationCapabilities

canDetectActiveDocument
canGetDocumentPath
canGetWordCount
canGetText
canDetectProject
canDetectChanges
canDetermineEditingActivity
```

Not every application will support every capability.

The generic adapter should still be capable of:

- detecting that the application is active
- tracking active time
- tracking keyboard activity
- associating activity with the application
- allowing the user to manually associate activity with a project

This means a new application does not have to have deep integration to be useful.

---

# 11. Microsoft Word Integration

Microsoft Word should receive a first-class adapter.

The implementation should investigate and use the most reliable native macOS mechanism available, potentially including:

- AppleScript / Microsoft Word scripting interface
- Accessibility APIs
- application metadata
- document paths
- Word's exposed document statistics

The system should attempt to retrieve:

- active document
- document path
- document title
- word count
- character count if available
- page count if available

The tracker should not assume that keyboard events alone are sufficient to determine word counts.

---

# 12. Keyboard Activity

The tracker may use macOS event monitoring to determine whether the user is actively interacting with the computer.

Important:

**Do NOT record the actual characters typed.**

The application only needs information such as:

```text
keyboard activity occurred
timestamp
event type
```

It should NOT store:

```text
"This is the actual text the user typed."
```

Privacy should be a major selling point.

The application should be able to say:

> "You typed/interacted for 27 minutes."

without knowing what the user wrote.

---

# 13. Accessibility Permission

Some functionality will require macOS Accessibility permission.

The onboarding experience should clearly explain why.

Example:

> **Accessibility Access**
>
> Writing Tracker needs permission to detect when you are actively working in your selected writing applications.
>
> We do not record the text you type.
>
> We only record activity timestamps and application/document statistics.

Provide a button:

`Open System Settings`

The application should detect whether permission has been granted.

---

# 14. Automation Permission

Some writing applications may require Automation permission.

For example, Word integration may need permission to communicate with Microsoft Word.

The application should detect missing permission and explain it.

Do not silently fail.

Instead show:

> Microsoft Word integration requires permission to communicate with Word.

with:

`Grant Permission`

or:

`How to Enable`

---

# 15. Session Detection

The tracking engine should distinguish between:

### Focus time

Time the writing application is the foreground application.

### Active time

Time during which the user is actually interacting.

### Writing time

Time during which the application believes the user is actively writing/editing.

These should not necessarily be the same.

Example:

User opens Word at 7:00 PM.

They read their manuscript for 10 minutes.

They type for 30 minutes.

They get coffee for 15 minutes.

They return and type for 20 minutes.

Statistics:

```text
Word focus time: 75 minutes
Active input time: 50 minutes
Writing time: approximately 50 minutes
```

This produces much better analytics than simply saying "Word was open for 75 minutes."

---

# 16. Inactivity Timeout

The user should configure the inactivity timeout.

Options:

- 30 seconds
- 1 minute
- 2 minutes
- 5 minutes
- 10 minutes
- 15 minutes
- Never

Default:

**5 minutes**

If there is no meaningful interaction for 5 minutes, active writing time pauses.

The session itself can remain open.

Example:

```text
Session started: 7:00 PM
Active: 7:00–7:38
Inactive: 7:38–7:51
Active: 7:51–8:30
```

Total session duration:

1h 30m

Active writing time:

1h 17m

---

# 17. Session Lifecycle

A session should have explicit states.

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

Potential transitions:

### Start

User manually starts session.

### Automatic start

Configured writing application becomes active and activity begins.

### Pause

Application loses focus or inactivity threshold is reached.

### Resume

Application becomes active and activity resumes.

### End

User ends session.

### Recording rule

A completed session is only saved when it represents real writing work. For
applications that report a word count, the session must have a non-zero net word
change; a session where the manuscript did not change is discarded (as is a
manual entry that adds no words). Time-only applications still record sessions
with meaningful active or focus time. Discarded sessions never reach the database
and never affect statistics.

---

# 18. Document Detection

The system should attempt to determine which document is being worked on.

For example:

```text
Microsoft Word
└── Naphtali.docx
```

The application should identify the document using the strongest available identifier.

Preferred order:

1. Stable document/file path
2. Document URL
3. Application-provided document identifier
4. Window/document title
5. Manual association

Avoid relying exclusively on window titles because filenames can change.

---

# 19. Projects / Books

The application needs a first-class concept of a **Project**.

A project may be:

- a novel
- novella
- short story
- screenplay
- nonfiction book
- article
- thesis
- dissertation
- blog
- research project

The product should not assume every user is a novelist.

However, the UI can use "Book" as an optional category.

Example:

```text
Projects

Naphtali
The Sequel
Short Stories
Blog
Other Writing
```

---

# 20. Project Fields

Suggested fields:

```text
Project
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

- Novel
- Novella
- Short Story
- Collection
- Screenplay
- Nonfiction
- Article
- Academic
- Other

Project statuses:

- Idea
- Planning
- Drafting
- Revising
- Editing
- Proofreading
- Complete
- Published
- Abandoned
- Archived

---

# 21. Project Association

There should be several ways to associate activity with a project.

### Automatic

The application recognizes the document.

### Folder-based

Example:

```text
Documents/Books/Naphtali/
```

Everything inside the folder can automatically belong to Naphtali.

### File-based

Specific files can be assigned.

### Manual

The user can assign an application/document to a project.

### Rules

Advanced users could create rules such as:

```text
If document path contains:
/Books/Naphtali/

assign to:
Naphtali
```

---

# 22. Project Word Count

Each project should maintain:

### Starting word count

The word count when tracking began.

### Current word count

Latest known manuscript word count.

### Net change

```text
current - starting
```

### Words added

Estimated cumulative words added.

### Words removed

Estimated cumulative words removed.

### Words worked

Gross amount of manuscript modification where reliable data exists.

This distinction is extremely important.

---

# 23. Gross vs Net Progress

Do not represent editing solely by net word count.

Example:

A writer edits a chapter:

```text
Words added: 1,842
Words removed: 613
Net change: +1,229
```

They did substantially more work than "+1,229 words" suggests.

The UI should therefore distinguish:

### Net manuscript change

`+1,229`

### Words added

`1,842`

### Words removed

`613`

### Words worked

Potentially:

`2,455`

depending on how reliably the system can calculate changes.

Where exact gross additions/deletions cannot be determined, label them as estimated rather than pretending they are exact.

---

# 24. Drafting vs Editing

The system should support writing phases.

Possible phases:

- Planning
- Drafting
- Revising
- Editing
- Proofreading
- Formatting

The user should be able to manually select the current phase.

Potentially, the application can later infer phase based on behavior.

For example:

High net positive word count:

> likely drafting

Large additions + deletions:

> likely revision

Mostly deletions:

> likely editing

However, automatic classification should be treated as an estimate.

---

# 25. Session Classification

Every session should have:

```text
sessionType
```

Possible values:

- Drafting
- Editing
- Revising
- Proofreading
- Research
- Planning
- Other
- Unknown

The user can select the session type when starting a session.

For example:

`Start Writing Session`

then:

```text
What are you working on?

Project: Naphtali

Activity:
○ Drafting
○ Revising
● Editing
○ Research
○ Other
```

The selection should be remembered.

---

# 26. Goals

The application should support multiple goals.

### Daily word goal

Example:

`1,000 words/day`

### Weekly word goal

`5,000 words/week`

### Monthly goal

`20,000 words/month`

### Project goal

`80,000 words`

### Deadline goal

`Finish by November 1`

### Time goal

`10 hours/week`

Users should be able to choose either word-based or time-based goals.

---

# 27. Goal Calculation

If a project has:

```text
Current words: 52,000
Target: 80,000
Remaining: 28,000
Deadline: 56 days
```

The application should calculate:

```text
Required average:
500 words/day
```

If the user's historical average is 850 words/day:

```text
Current pace:
850 words/day

Required pace:
500 words/day

Projected completion:
Ahead of schedule
```

This should be visualized.

---

# 28. Completion Projection

The application should estimate project completion.

Potential inputs:

- current word count
- target word count
- recent average words/day
- longer-term average
- scheduled writing days
- historical productivity
- deadline

Provide multiple projections:

### Recent pace

Based on last 7 days.

### Normal pace

Based on last 30 days.

### Historical pace

Based on all project activity.

Example:

```text
Projected Completion

7-day pace       Oct 18
30-day pace      Oct 24
Project average  Oct 31

Target deadline  Nov 15

You are currently ahead by ~15 days.
```

Avoid presenting projections as certainties.

---

# 29. Main Dashboard

The dashboard should be visually polished and data-rich.

Suggested layout:

```text
┌──────────────────────────────────────────────────────────────┐
│ Writing Tracker                              Today ▾         │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  TODAY                                                       │
│                                                              │
│  1,243              1h 42m             12.1                 │
│  WORDS              ACTIVE TIME         WPM                  │
│                                                              │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  DAILY OUTPUT                                                │
│                                                              │
│       ▂  ▄  ▆  ▃  █  ▇  ▅                                  │
│       M  T  W  T  F  S  S                                  │
│                                                              │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  CURRENT STREAK                                              │
│                                                              │
│  🔥 12 DAYS                                                  │
│  Longest: 47 days                                            │
│                                                              │
├────────────────────────────┬─────────────────────────────────┤
│ CURRENT PROJECT            │ GOAL                            │
│ Naphtali                   │ ███████████░░ 72%              │
│ 57,482 / 80,000            │ 22,518 remaining               │
│                            │                                 │
└────────────────────────────┴─────────────────────────────────┘
```

---

# 30. Dashboard Time Range

The dashboard should allow:

- Today
- Yesterday
- This week
- Last week
- This month
- Last month
- This year
- Last year
- All time
- Custom range

Charts should update accordingly.

---

# 31. Statistics Dashboard

Create a dedicated statistics page.

Categories:

## Output

- Words written
- Words added
- Words removed
- Net word change
- Average daily output
- Median daily output
- Maximum daily output

## Time

- Total active time
- Total session time
- Average session length
- Longest session
- Total writing days

## Pace

- Average WPM
- Best WPM
- Average words/hour
- Best words/hour

## Consistency

- Current streak
- Longest streak
- Writing days
- Missed days
- Average days/week

## Implemented chart set

- Daily words with 7-day and 30-day moving-average overlays
- Daily active time (area)
- Weekly and monthly totals
- Focus vs active time (stacked bars; the gap is reading/thinking time)
- Added vs removed words (diverging bars, labelled estimated)
- Day-of-week x hour heatmap (7x24)
- Radial 24-hour "writing clock"
- Session efficiency scatter (active minutes vs net words, coloured by type)
- Typing pace over time and typing pace distribution
- Session-type breakdown over time (stacked)
- Project mix over time (stacked area)
- Writing streak history (one bar per streak)
- Personal records (best day, session, pace, week, longest streak)
- Output by month (months x years grid)
- Career output by year and project type

## Typing pace

Typing pace (WPM) is **derived** from growth in the document's character count
(5 characters = 1 word) per active minute, not from keystrokes. Deletions and
modifier keys contribute nothing, so backspace and shift never inflate it.
Pasted text counts. It is available only for applications that expose a
character count (Word and Pages) and is always labelled estimated.

---

# 32. Lifetime Statistics

This should be one of the major selling points.

Example:

```text
LIFETIME

2,481,392
WORDS

1,834
WRITING DAYS

6,218
HOURS

1,492
SESSIONS

47
PROJECTS

18
COMPLETED PROJECTS
```

Additional lifetime statistics:

- first tracked writing day
- most productive year
- most productive month
- most productive day
- longest session
- highest words/day
- highest words/hour
- longest streak
- total projects
- completed projects
- average words/day
- average words/session

---

# 33. Lifetime Timeline

Provide a timeline showing writing activity across the entire history.

Example:

```text
2019     ▂▃▁▂▅
2020     ▄▆▇▃▅
2021     ▂▁▃▂▂
2022     ▅▆█▇▆
2023     ▇█▆█▇
2024     ▄▅▇█▇
2025     ▆▇█▆█
2026     ██████
```

Allow clicking a year to drill down.

---

# 34. Calendar Heatmap

Implement a GitHub-style contribution heatmap.

Each day represents writing activity.

Example:

```text
        Mon Tue Wed Thu Fri Sat Sun

Jan       ░   ▒   ▓   █   ░   ▓   ▒
Feb       ▓   █   █   ▒   ░   ░   ▓
Mar       █   █   ▓   ▓   ▒   █   █
```

Intensity should correspond to:

- words
- active minutes
- or sessions

Allow switching between these metrics.

Clicking a day opens detailed statistics.

Additional calendar views:

- A daily bar chart for the selected day's month.

---

# 35. Daily Detail View

Clicking a day should show:

```text
September 8, 2026

Words
1,843

Active time
2h 14m

Sessions
3

Projects
Naphtali — 1,521
Short Story — 322

Average WPM
13.7

First session
7:42 AM

Last session
10:18 PM
```

Below this:

### Sessions

```text
7:42–8:31
Naphtali
Drafting
+642 words

9:14–10:02
Naphtali
Editing
+411 net

9:47–10:18
Short Story
Drafting
+322
```

---

# 36. Project Dashboard

Every project should have its own dashboard.

Example:

```text
NAPHTALI

57,482 words

Target
80,000

72%

────────────────────────────

Started
June 3, 2026

Last activity
September 8, 2026

Total active time
112h 41m

Sessions
184

Writing days
71

Average/day
809 words

Average/session
312 words

Current pace
842 words/day

Projected completion
October 14
```

---

# 37. Project Graphs

Project pages should include:

### Word count over time

Line chart.

### Daily output

Bar chart.

### Cumulative progress

Area/line chart.

### Time spent

Bar chart.

### Draft vs editing

Stacked visualization.

### Words added vs removed

Positive/negative chart.

### Sessions

Timeline.

### Implemented project charts

- Cumulative progress with a pace projection cone (7-day, 30-day, lifetime)
- Burn-down of remaining words against the straight required-pace line
- Word-count history per document
- Milestone timeline (started, milestones hit, completed, projected completion)
- Daily output bars

---

# 38. Project Milestones

Allow milestones.

Examples:

```text
10,000 words       ✓
25,000 words       ✓
50,000 words       ✓
75,000 words       ○
80,000 words       ○
```

Also support custom milestones:

- Finish Chapter 10
- Finish first draft
- Send to editor
- Complete revision
- Publish

Milestones should have dates and completion status.

---

# 39. Writing Streaks

Define streak rules carefully.

Default:

A writing day is a day on which the user meets a minimum activity threshold.

Possible thresholds:

- 1 word
- 100 words
- 250 words
- 500 words
- custom

Do not automatically make a 1-word day count unless the user wants that.

Settings:

```text
Streak requirement:
○ Any writing
○ 100 words
● 250 words
○ 500 words
○ Custom
```

Also support scheduled days off.

---

# 40. Days Off

Writers should be able to designate days as:

- Rest day
- Vacation
- Sick day
- Holiday
- Scheduled day off

A scheduled day off should not break a streak.

Example:

```text
Writing schedule:
Mon–Fri

Saturday/Sunday:
Rest days
```

This is especially important for serious writers.

---

# 41. Writing Schedule

Allow users to define their normal schedule.

Example:

```text
Monday     ☑
Tuesday    ☑
Wednesday  ☑
Thursday   ☑
Friday     ☑
Saturday   ☐
Sunday     ☐
```

This enables better analytics.

Instead of:

> You wrote on 4 of 7 days.

the application can say:

> You wrote on 4 of 5 scheduled writing days.

---

# 42. Productivity Analysis

The application should eventually identify patterns.

Examples:

> Your average output is 23% higher on Saturdays.

> Your most productive hour is 8–9 PM.

> You average 1,120 words during sessions longer than one hour.

> Your editing sessions are typically 42 minutes.

> You have written 31% more words this year than last year.

This should be based strictly on sufficient data.

Do not produce misleading conclusions from tiny datasets.

---

# 43. Time-of-Day Analysis

Graph writing activity by hour.

Example:

```text
Words

2500 |                 █
2000 |             █   █
1500 |         █   █   █
1000 |     █   █   █   █
 500 | █   █   █   █   █
     └────────────────────
       8 10 12 2  4  6  8  10 PM
```

Also allow:

- words/hour
- active minutes/hour
- sessions/hour

---

# 44. Day-of-Week Analysis

Show:

```text
Monday      712 avg words
Tuesday     842
Wednesday   905
Thursday    1,021
Friday      1,180
Saturday    1,743
Sunday      634
```

This helps writers discover when they work best.

---

# 45. Writing Session History

A searchable session database.

Columns:

```text
Date
Project
Application
Type
Duration
Words Added
Words Removed
Net
WPM
```

Filters:

- project
- application
- session type
- date
- minimum duration
- word count

---

# 46. Session Detail

Clicking a session should show:

```text
September 8, 2026
7:42 PM – 8:31 PM

Project:
Naphtali

Application:
Microsoft Word

Type:
Drafting

Duration:
49 minutes

Active time:
43 minutes

Starting word count:
56,840

Ending word count:
57,482

Net change:
+642

Average:
14.9 words/minute
```

---

# 47. Editing Analytics

If reliable document snapshots/diffs can be obtained, expose:

```text
Added
1,842 words

Removed
613 words

Net
+1,229 words

Gross changes
2,455 words
```

This should be especially valuable to editors and revising authors.

If the system cannot reliably determine gross changes, don't fake precision.

---

# 48. Document Snapshots

Consider storing lightweight snapshots of document metadata rather than full document contents.

Preferred initial record:

```text
timestamp
projectID
documentID
wordCount
characterCount
pageCount
```

For advanced editing analysis, optionally store encrypted/local snapshots if technically feasible and explicitly enabled by the user.

Do NOT make full-text storage mandatory.

Privacy should remain the default.

---

# 49. Data Model

A possible conceptual schema:

```text
UserSettings

WritingApplication

Project

Document

Session

ActivityEvent

WordCountSnapshot

DailyAggregate

Goal

Milestone

WritingSchedule

Streak

ProjectPhase

Export
```

---

# 50. Session Model

Example:

```text
Session
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

---

# 51. Activity Event Model

Do not store individual keystrokes.

Store events such as:

```text
ActivityEvent
    timestamp
    applicationID
    eventType
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
```

Raw activity events can eventually be aggregated and compacted.

---

# 52. Aggregation

Do not calculate every dashboard statistic from millions of raw events every time.

Maintain aggregate tables.

For example:

```text
DailyAggregate

date
wordsAdded
wordsRemoved
netWords
activeSeconds
focusSeconds
sessionCount
writingDays
```

This makes dashboards fast.

The raw event history can remain available for recalculation.

---

# 53. Database Requirements

The database must be:

- local-first
- resilient
- transactional
- versioned
- migration-capable
- backed up/exportable

The user should never lose years of statistics because of an application update.

Database migrations must be carefully versioned.

---

# 54. Background Process

The tracker must continue working when the main GUI is closed.

Possible architecture:

```text
WritingTracker.app
        │
        ├── GUI
        │
        ├── Tracking Engine
        │
        └── Persistence
```

The tracking engine should ideally be implemented as a LaunchAgent/background service or equivalent macOS architecture appropriate to the chosen application packaging model.

The main GUI communicates with the background service through a local IPC mechanism.

Possible mechanisms:

- XPC
- local Unix socket
- distributed notification where appropriate
- shared local database

Prefer XPC if practical for a native macOS architecture.

---

# 55. Startup Behavior

Users should have:

`Launch at Login`

enabled by default or offered prominently during onboarding.

If enabled:

1. macOS starts the background component.
2. Tracking begins according to the user's selected tracking mode.
3. Main GUI does not need to be open.

Therefore:

> Closing the dashboard does not stop tracking.

---

# 56. Crash Recovery

The system must survive:

- app crashes
- computer restarts
- sleep/wake
- force quit
- application updates

When the computer resumes:

- close or reconcile stale sessions
- restore tracker state
- avoid creating phantom writing time

For example, if the Mac sleeps at 11:02 PM and wakes at 7:30 AM:

Do NOT record 8.5 hours of writing.

---

# 57. Computer Sleep Handling

Listen for system sleep/wake notifications.

When sleep occurs:

```text
pause active session
record sleep timestamp
```

On wake:

```text
resume eligibility
```

but do not automatically count time until activity resumes.

---

# 58. Multiple Monitors / Spaces

The system should track the frontmost application globally, regardless of:

- monitor
- Space
- full-screen mode

A writing application being visible on another monitor should not necessarily count unless it is considered active according to the chosen tracking mode.

---

# 59. Privacy

Privacy should be a major product feature.

Default behavior:

### Store

- application name
- document identifier/path
- timestamps
- activity state
- word counts
- session information
- project information
- statistics

### Do not store

- actual keystrokes
- passwords
- clipboard contents
- arbitrary screen contents
- screenshots
- document text

unless the user explicitly enables an advanced feature requiring it.

Marketing should eventually be able to say:

> **Your writing stays on your Mac.**

This could become a major differentiator.

---

# 60. Privacy Dashboard

Settings should include:

```text
Privacy

Keyboard content
Not recorded

Document text
Not recorded

Screenshots
Not recorded

Clipboard
Not recorded

Analytics
Local only
```

Advanced diagnostics should be opt-in.

---

# 61. Data Export

Users must be able to export their data.

Formats:

- CSV
- JSON
- possibly SQLite database backup

Export options:

```text
Export all data
Export sessions
Export project statistics
Export daily statistics
Export lifetime statistics
```

This is important for trust and future monetization.

---

# 62. Data Import

Eventually support importing data from other trackers.

Potentially:

- CSV
- JSON
- WordTracker-style exports
- Writing Tracker exports
- custom import

This could make switching to the product easier.

---

# 63. Backup

Offer:

### Automatic local backup

For example:

```text
~/Library/Application Support/WritingTracker/Backups/
```

Keep configurable historical backups.

Possible:

- 7 backups
- 30 backups
- 90 backups

Later, support optional cloud backup.

---

# 64. iCloud

Do NOT make iCloud a requirement for version 1.

Architecture should leave room for it.

Possible future functionality:

- iCloud database synchronization
- multiple Mac synchronization
- statistics backup
- project synchronization

However, synchronization must be designed carefully around conflicts.

---

# 65. Multi-Device Future

Long-term architecture should allow:

```text
Mac
 │
 ├── Local Tracker
 │
 └── Cloud Sync
       │
       ├── MacBook
       ├── iMac
       └── future iPad app
```

But version 1 should remain local-first.

---

# 66. Search

The application should have global search.

Search:

- projects
- documents
- sessions
- dates
- milestones

Example:

`Naphtali`

could show:

```text
Project: Naphtali

184 sessions
112h 41m
57,482 net words
71 writing days
```

---

# 67. Reports

Users should be able to generate reports.

Examples:

### Weekly Report

```text
September 1–7

Words: 8,421
Time: 7h 14m
Sessions: 14
Writing days: 6/7
Average/day: 1,403
Best day: Saturday — 2,841
```

### Monthly Report

More detailed.

### Yearly Report

Potentially beautiful, shareable author statistics.

---

# 68. Year in Review

This could eventually become a major feature.

Example:

# Your 2026 Writing Year

```text
382,491 words

427 hours

218 sessions

147 writing days

Longest streak:
42 days

Best day:
4,821 words

Most productive project:
Naphtali

Most productive month:
September
```

This should have an attractive visual presentation.

Potentially exportable as an image/PDF.

---

# 69. Author Dashboard

The top-level author dashboard should differ from the daily productivity dashboard.

Example:

```text
AUTHOR

Projects             18
Completed             6
Active                 3
Words         2,481,392
Writing time       6,218h

CURRENT PROJECT

Naphtali
57,482 / 80,000

CAREER OUTPUT

2024       182k
2025       341k
2026       428k
```

---

# 70. Project Library

Visual cards:

```text
┌──────────────────────┐
│ NAPHTALI             │
│ Novel                │
│                      │
│ 57,482 words         │
│ ███████████░ 72%     │
│                      │
│ Last active: Today   │
└──────────────────────┘
```

Projects should be sortable by:

- recent
- word count
- activity
- completion
- creation date
- alphabetical

---

# 71. Application Statistics

Eventually provide statistics by writing application.

Example:

```text
Microsoft Word
1,842,221 words
4,812h

Scrivener
612,481 words
1,201h

Ulysses
26,192 words
72h
```

This lets users understand their workflow.

---

# 72. Cross-Application Projects

A single project should support multiple applications.

Example:

```text
Naphtali

Microsoft Word
Main manuscript

Scrivener
Planning

Obsidian
Research

Google Docs
Beta-reader notes
```

All activity contributes to the same project where appropriate.

This is one of the strongest arguments for making the product application-independent.

---

# 73. Notes

Users should be able to add notes to sessions.

Example:

```text
Session note:

"Finished Chapter 23."
```

Notes can later appear on charts/timelines.

Potentially:

```text
September 8
+1,843 words

📌 Finished Chapter 23
```

---

# 74. Milestone Events

Users can mark important events.

Examples:

- Started project
- Finished chapter
- Finished draft
- Sent to editor
- Received edits
- Submitted manuscript
- Signed publishing contract
- Published

These can appear on the project timeline.

This transforms the product from a simple word counter into an **author history system**.

---

# 75. Project Timeline

Example:

```text
June 3
Project started

June 18
10,000 words

July 11
25,000 words

August 4
50,000 words

September 8
57,482 words

October 14
Projected completion
```

---

# 76. Comparison Mode

Allow users to compare projects.

Example:

| Statistic | Naphtali | Sequel |
|---|---:|---:|
| Words | 57,482 | 31,201 |
| Active time | 112h | 67h |
| Sessions | 184 | 103 |
| Avg/day | 809 | 743 |
| Avg/session | 312 | 303 |

Also allow comparing:

- years
- months
- projects
- drafting vs editing

---

# 77. Historical Comparison

Examples:

> You wrote 18% more words this month than the same month last year.

> Your average session is 12 minutes longer than it was in 2025.

> Your current project is progressing 14% faster than your previous novel.

These comparisons should be opt-in or presented unobtrusively.

---

# 78. Achievements

Achievements should be optional.

Examples:

- First 1,000 words
- 10,000 lifetime words
- 100,000 lifetime words
- 1 million words
- 100 writing days
- 30-day streak
- 100 sessions
- First completed project

Do not make the product feel childish unless the user enables a gamification mode.

---

# 78A. Social Sharing, Leaderboards and Following

Writers can optionally:

- **Publish** a snapshot of their statistics (words, active time, streaks, and
  similar aggregates) — private by default, opt-in, and revocable.
- Be placed on **leaderboards** after finishing a session, across several kinds
  (daily/weekly/monthly words, active time, streaks, project progress).
- **Follow** other writers and **compare** their statistics against their own.

**Status:** implemented locally behind a `SocialBackend` protocol with a JSON
placeholder (`community.json`), plus a Community screen and opt-in sharing
controls. Only aggregate numbers are written — never documents, project names,
paths, or manuscript text.

**Online version requires a backend** (identity, stats ingestion, leaderboard
queries, follow graph). The client already uses the `CommunityData` shape, so a
server can provide a remote `SocialBackend` without UI changes. A dedicated
privacy screen explains what is tracked, how AppleScript is used, and what
permission prompts may appear.

# 79. Widgets

Potential macOS widgets:

### Today

```text
1,243 words
Goal: 1,500
```

### Streak

```text
🔥 12 days
```

### Current Project

```text
Naphtali
72%
```

### Weekly Output

Mini chart.

### Lifetime

```text
2.48M words
```

Widgets should be considered after the core tracker is stable.

---

# 80. Notifications

Notifications should be configurable.

Examples:

> You've reached your 1,000-word goal.

> You're 500 words away from today's goal.

> Your writing streak is at risk.

> You completed 10 hours of writing this week.

Users should be able to disable all notifications.

Do not create nagging behavior by default.

---

# 81. Goals vs Streaks

Do not conflate them.

A streak answers:

> "Have I been consistently writing?"

A goal answers:

> "Did I accomplish what I planned?"

Someone could have:

- 30-day streak
- but repeatedly miss a 2,000-word goal

Both statistics should remain independent.

---

# 82. Dashboard Customization

Eventually allow users to rearrange dashboard cards.

Cards:

- Today
- Weekly output
- Monthly output
- Current project
- Goal
- Streak
- Lifetime
- Recent sessions
- Productivity graph
- Calendar
- Project progress

Users should be able to hide cards they don't care about.

---

# 83. Themes

Support:

- System
- Light
- Dark

Potential future themes:

- Default
- Minimal
- Professional
- Cyberpunk / neon

The default should be polished and restrained.

Avoid making the UI look like a novelty application.

---

# 84. Charts

Use native macOS charting technology where appropriate, likely Swift Charts.

Implemented chart types:

- Bar, line, area and stacked bar
- Scatter (point) and diverging bar (added vs removed)
- Heatmap (calendar, 7x24 day/hour, months x years)
- Radial 24-hour "writing clock"
- Progress rings and goal gauges
- Projection cone and burn-down
- Milestone timeline

Charts support:

- date ranges (statistics and dashboard ranges)
- click / drill-down (calendar day detail)
- annotations and tooltips where useful

---

# 84A. Additional Analytics Visualizations

Ten further visualizations answer questions the earlier charts do not. They are
computed by a dedicated `AnalyticsService` (Core) and rendered with Swift Charts
on the Statistics and Project screens. None infer word counts from keystrokes;
all reuse the existing definitions of net word change, active time, and daily
aggregates.

Shared implementation notes:

- **Architecture**: `AnalyticsService` -> result models (`AnalyticsModels`) ->
  chart views (`UI/Charts/AnalyticsCharts.swift`). Views do not compute.
- **Filters**: calculators accept the existing `SessionFilter` (date range,
  project, application, session type). The Statistics screen applies its date
  range; project-scoped charts apply the project.
- **Exact vs estimated**: gross words worked is derived from the existing
  added/removed aggregation and is always labelled estimated; net manuscript
  change comes from document word counts.
- **Empty states**: each card shows an explicit message instead of an empty chart.
- **Accessibility**: every card exposes an accessibility summary (measure, range,
  key values, sample sizes).
- **Performance**: goal history precomputes daily statistics once instead of
  querying per period.

## 1. Session Duration (histogram)

- **Purpose**: reveal the spread of session lengths, not just their average.
- **Metric**: completed session duration in minutes.
- **Calculation**: sessions in range with duration > 0; evenly spaced bins
  (about 6 to 15); mean, median, P25, P75, min, max.
- **Visualization**: histogram with a median/mean marker legend and stats row.
- **Filters**: date range, project, application, session type.
- **Data quality**: duration is wall clock (ended minus started); zero and
  negative durations are excluded. Distinct from active time.
- **Empty**: "No completed sessions with a valid duration yet."
- **Caveat**: duration is not active time; a long session may contain idle
  stretches.

## 2. Daily Output Distribution (histogram)

- **Purpose**: show what a typical writing day looks like.
- **Metric**: net words (default), or gross words worked, per writing day.
- **Calculation**: writing days in range (days with at least one session);
  evenly spaced bins; mean/median/P25/P75/min/max. Negative and zero-net days are
  kept.
- **Visualization**: histogram with a metric picker and a stats row.
- **Filters**: date range.
- **Data quality**: gross worked is estimated (derived from added + removed where
  exact edits are unavailable).
- **Empty**: "No writing days in this range."
- **Caveat**: empty calendar days are excluded so they do not distort the shape.

## 3. Productivity by Session Length (dot plot)

- **Purpose**: describe how efficiency changes as sessions get longer.
- **Metric**: net words per active hour.
- **Calculation**: sessions with active time > 0 grouped into fixed duration
  bands; per band median and P25-P75; bands with fewer than 3 sessions withheld.
- **Visualization**: dot plot with interquartile range bars and sample counts.
- **Filters**: date range, project, application, session type.
- **Data quality**: net over active time; never keystrokes.
- **Empty**: "Not enough sessions in any duration band yet."
- **Caveat**: medians are shown because productivity has heavy outliers; longer
  is not inherently better.

## 4. Goal Performance (time series)

- **Purpose**: show how consistently goals are actually met.
- **Metric**: attainment = actual / target x 100 for each completed period.
- **Calculation**: one representative goal per period type; completed
  daily/weekly/monthly periods from the goal start (capped at the first tracked
  day) up to but excluding the current incomplete period; met/missed, success
  rate, median/average attainment, longest consecutive success run.
- **Visualization**: line and points coloured Met/Close/Missed, a 100% reference
  line, and summary statistics.
- **Filters**: period type; the date range does not truncate goal history.
- **Data quality**: periods before tracking began are not counted as failures.
- **Empty**: "No completed <period> goal periods yet."
- **Caveat**: only one goal per period type is charted; a completed period with no
  activity counts as missed.

## 5. Project Velocity (time series)

- **Purpose**: show how fast a project progresses, and whether speed changes.
- **Metric**: net words per day or per week for a single project.
- **Calculation**: project sessions grouped by day/week, gaps filled between first
  and last activity; rolling average over 7 days (daily) or 4 weeks (weekly).
- **Visualization**: bars for raw output plus a rolling-average line, omitted when
  there is too little data.
- **Filters**: project (chart lives on the project screen); optional date range.
- **Data quality**: net manuscript change only; unrelated projects excluded.
- **Empty**: "Not enough project activity in this range."
- **Caveat**: research sessions can add active time without manuscript words.

## 6. Writing Cadence (histogram)

- **Purpose**: measure how long you typically go between writing sessions.
- **Metric**: time from the end of one session to the start of the next.
- **Calculation**: sessions sorted chronologically; the first session has no gap;
  fixed bins from under 15 minutes to 7+ days; median/mean/P25/P75/min/max.
- **Visualization**: histogram with a stats row.
- **Filters**: date range, project, application, session type.
- **Data quality**: overlapping sessions are ignored rather than counted as a
  zero-minute gap.
- **Empty**: "Need at least two sessions to measure gaps."
- **Caveat**: cadence measures spacing, not preferred clock time.

## 7. Project Effort by Phase (100% stacked horizontal bar)

- **Purpose**: show where a project's effort goes across writing phases.
- **Metric**: active time per session type.
- **Calculation**: active seconds summed per session type, normalized to 100% per
  project.
- **Visualization**: 100% stacked horizontal bars, one per project; comparison
  mode renders multiple projects with shared colours.
- **Filters**: project (single, or the two compared in Reports).
- **Data quality**: active time is the denominator, not net words; unknown types
  are retained.
- **Empty**: "No active time recorded for these projects."
- **Caveat**: proportions are descriptive and do not rank phases by value.

## 8. Cumulative Lifetime Output (cumulative line)

- **Purpose**: a career trajectory of total output over recorded time.
- **Metric**: cumulative net manuscript words (default), or gross words worked.
- **Calculation**: daily aggregates in date order; running total that does not
  reset at project boundaries and may decrease on negative-net days.
- **Visualization**: line and area.
- **Filters**: metric toggle; lifetime scope (no date truncation).
- **Data quality**: gross worked is estimated.
- **Empty**: "No writing history yet."
- **Caveat**: project-scoped cumulative progress already exists on the project
  screen; this chart is intentionally lifetime-scoped.

## 9. Output Variability (rolling line)

- **Purpose**: measure consistency rather than average output.
- **Metric**: rolling coefficient of variation (standard deviation / mean) over a
  7-writing-day window; falls back to standard deviation when the mean is zero.
- **Calculation**: writing days only, in date order; rolling window statistics.
- **Visualization**: line and area.
- **Filters**: date range.
- **Data quality**: writing days only, never calendar days.
- **Empty**: "Need at least 7 writing days for this window."
- **Caveat**: a lower value means steadier output, not better writing.

## 10. Productivity by Work Type (dot plot)

- **Purpose**: compare productivity characteristics across types of work.
- **Metric**: median net words per active hour per session type.
- **Calculation**: sessions with active time grouped by type; median, mean,
  P25-P75, sample count; categories with fewer than 3 sessions withheld.
- **Visualization**: dot plot with interquartile range bars and sample counts.
- **Filters**: date range, project, application, session type.
- **Data quality**: net over active time.
- **Empty**: "Not enough sessions of any type yet."
- **Caveat**: descriptive only. Research and proofreading legitimately produce few
  or no manuscript words; this is not a ranking of work quality.

Implementation status: all ten are implemented in `AnalyticsService` with unit
tests, on the Statistics screen (and the Project screen for velocity and effort
by phase, plus Reports comparison for effort by phase).

---

# 85. Accessibility

The GUI should support:

- Dynamic Type
- VoiceOver
- keyboard navigation
- high contrast
- reduced motion

Do not rely solely on color to communicate statistics.

---

# 86. Localization

Do not hard-code user-facing strings throughout the codebase.

Use localization infrastructure from the beginning.

Initial language:

English.

Future:

- Spanish
- French
- German
- Japanese
- etc.

---

# 87. Architecture

Recommended conceptual architecture:

```text
┌─────────────────────────────────────────────┐
│                 SwiftUI GUI                 │
├─────────────────────────────────────────────┤
│             Application Services            │
│                                             │
│ DashboardService                            │
│ ProjectService                              │
│ StatisticsService                           │
│ GoalService                                 │
│ ReportService                               │
├─────────────────────────────────────────────┤
│             Tracking Engine                 │
│                                             │
│ Focus Monitor                               │
│ Activity Monitor                            │
│ Session Manager                             │
│ Application Detector                        │
│ Document Detector                           │
│ Word Count Monitor                          │
├─────────────────────────────────────────────┤
│          Application Adapters               │
│                                             │
│ WordAdapter                                  │
│ ScrivenerAdapter                             │
│ GenericAdapter                               │
├─────────────────────────────────────────────┤
│                 Data Layer                  │
│                                             │
│ Repository                                  │
│ SQLite                                      │
│ Migrations                                  │
│ Backup                                      │
└─────────────────────────────────────────────┘
```

---

# 88. Dependency Rules

The GUI should never directly manipulate the database.

Use services/repositories.

For example:

```text
SwiftUI View
    ↓
ViewModel
    ↓
Service
    ↓
Repository
    ↓
Database
```

This will make the application much easier to maintain.

---

# 89. Tracking Engine Separation

The tracking engine should be completely independent of the GUI.

It should be possible to run:

```text
TrackingEngine
```

without:

```text
Dashboard
```

This is essential because the application must continue tracking after the GUI is closed.

---

# 90. Event-Driven Design

Prefer event-driven architecture where possible.

Events:

```text
ApplicationBecameActive
ApplicationBecameInactive
KeyboardActivityDetected
DocumentChanged
WordCountChanged
SystemDidSleep
SystemDidWake
SessionStarted
SessionPaused
SessionEnded
```

The session manager consumes these events.

---

# 91. Word Count Polling

Do not poll excessively.

Potential approach:

- when writing app becomes active: sample immediately
- while active: sample periodically
- increase interval during inactivity
- sample at session end
- sample when document changes

Potential interval:

1–5 seconds while actively writing, depending on performance and integration capabilities.

Optimize later based on profiling.

---

# 92. Word Count Delta

Suppose:

```text
10:00 — 50,000 words
10:05 — 50,342 words
10:10 — 50,891 words
```

The system can calculate:

```text
+342
+549
```

Total net:

`+891`

This provides much more reliable statistics than estimating words from keystrokes.

---

# 93. Handling Deletions

Example:

```text
50,000
49,600
```

Net:

`-400`

The system should record:

```text
netWordChange = -400
```

Do not call this "words written."

Instead call it:

**Net word change**

The daily dashboard should distinguish:

```text
Words added
1,200

Words removed
400

Net
+800
```

where exact added/removed figures are available.

---

# 94. Clipboard / Paste Handling

The system must account for pasted text.

If the document jumps:

```text
10,000 → 15,000
```

do not assume the user typed 5,000 words.

The system should simply recognize:

```text
document net change: +5,000
```

unless a more sophisticated diff system can determine the actual operation.

---

# 95. Undo / Redo

Word count can change:

```text
20,000
20,500
20,000
```

This should not create:

```text
+500 words written
```

followed by another arbitrary statistic.

The underlying event history should preserve the changes.

Analytics can then distinguish:

- gross additions
- gross deletions
- net change

where possible.

---

# 96. Formatting Activity

Formatting should not count as writing.

For example:

- bolding text
- changing fonts
- changing margins
- applying headings

may trigger activity events.

The application should track time/activity but should not claim those actions produced words.

This reinforces the importance of separating:

**Active time**

from

**Word output**

---

# 97. Research Time

Potential future feature:

Allow applications to be classified as:

- Writing
- Research
- Communication
- Other

Example:

```text
Microsoft Word → Writing
Safari → Research
Obsidian → Research
Discord → Other
```

Then a project could eventually show:

```text
Writing time       112h
Research time       38h
Total project time 150h
```

This should be optional and probably not part of the earliest MVP.

---

# 98. Application Categories

Allow:

```text
Writing Application
Research Application
Other Application
```

But do not automatically track every application without explicit user configuration.

---

# 99. Manual Activity Entry

Users should be able to manually add activity.

Example:

> I wrote 1,500 words on paper today.

The user can enter:

```text
Date:
September 8

Project:
Naphtali

Words:
1,500

Time:
2 hours

Type:
Drafting
```

This prevents the product from becoming useless when writers sometimes work:

- on paper
- on another computer
- while traveling
- offline
- using an unsupported editor

---

# 100. Manual Corrections

Users should be able to correct incorrect tracking.

For example:

```text
Session:
2h 13m

Correct duration:
1h 42m
```

Or:

```text
Assign this session to:
Naphtali
```

Corrections should be logged rather than silently destroying raw data.

---

# 101. Data Integrity

Every calculated statistic should be reproducible from underlying records.

Avoid storing only final numbers.

For example, do not merely store:

```text
Lifetime words = 2,481,392
```

without enough underlying data to reconstruct it.

Store daily/project/session information from which the number can be recalculated.

---

# 102. Statistics Engine

Create a dedicated statistics engine.

Example:

```text
StatisticsService

calculateDailyStats()
calculateWeeklyStats()
calculateMonthlyStats()
calculateYearlyStats()
calculateLifetimeStats()
calculateProjectStats()
calculateStreak()
calculateAverage()
calculateProjection()
calculateProductivityPatterns()
```

The statistics engine should have unit tests.

---

# 103. Time Zones

Store timestamps in a reliable canonical format.

Display according to the user's local timezone.

Be careful around:

- daylight saving time
- travel
- midnight
- computer timezone changes

A writing session spanning midnight must be split correctly for daily statistics.

---

# 104. Midnight Handling

Example:

```text
11:58 PM → 12:12 AM
```

The session is continuous, but daily statistics should show:

```text
September 8:
2 minutes

September 9:
12 minutes
```

The underlying session may remain one session.

---

# 105. Week Definitions

Allow the user to select:

- Sunday-start week
- Monday-start week

This affects weekly reports.

---

# 106. Fiscal / Calendar Year

Default to calendar year.

Potential future support for custom reporting years.

---

# 107. Performance

The tracker should have extremely low overhead.

Target:

- negligible CPU while idle
- minimal memory footprint
- no noticeable impact on Word/Scrivener
- no noticeable keyboard/input latency

The tracking engine must never block the main thread.

---

# 108. Offline First

Version 1 should work completely offline.

No account should be required.

No internet connection should be required to:

- track
- view statistics
- create projects
- export data

This is another strong privacy/product advantage.

---

# 109. Account System

Do NOT require an account for local functionality.

Potential future account:

- optional cloud synchronization
- subscription management
- cross-device sync
- backups
- licensing

The local application should remain useful without an account.

---

# 110. Monetization Architecture

Although monetization is not the immediate priority, the architecture should not make future monetization painful.

Potential model:

## Free

- local tracking
- basic statistics
- limited projects
- basic dashboard
- daily/weekly history

## Pro

- unlimited projects
- lifetime analytics
- advanced charts
- editing analytics
- projections
- reports
- advanced application integrations
- data exports
- advanced productivity analysis
- custom goals
- historical comparisons

## Future Cloud / Premium

- cross-device sync
- cloud backups
- account
- mobile app
- web dashboard

Do not artificially cripple the fundamental tracking engine just to create a paywall.

---

# 111. Licensing Architecture

Separate:

```text
Core tracking engine
```

from:

```text
Entitlement system
```

The application should be able to determine:

```text
Entitlement.free
Entitlement.pro
Entitlement.cloud
```

without scattering subscription checks throughout the codebase.

Use feature gates:

```text
Feature.lifetimeAnalytics
Feature.advancedCharts
Feature.cloudSync
Feature.unlimitedProjects
Feature.advancedIntegrations
```

---

# 112. Monetization Recommendation

Long-term, a **one-time purchase or reasonably priced subscription** should be considered carefully.

This is a utility that primarily stores local data and does not necessarily require expensive cloud infrastructure.

A possible model:

### Free

Basic tracker.

### Pro — one-time purchase

Unlock advanced analytics and unlimited projects.

### Optional Cloud subscription

Only users who want:

- synchronization
- cloud backups
- cross-device access

pay recurring costs.

This could be much more attractive to privacy-conscious writers than forcing everyone into a subscription.

The architecture should support either model without committing to one now.

---

# 113. Store Distribution

The application should eventually be capable of distribution through:

- Mac App Store
- direct download from developer website

Do not assume Mac App Store distribution is the only route.

The tracking functionality involving Accessibility and Automation permissions should be investigated against Apple's current sandbox, signing, entitlement, and review requirements before choosing the final distribution strategy.

For early development, prioritize functionality and local testing.

---

# 114. Licensing / Activation

If commercialized, separate licensing from tracking.

Potential architecture:

```text
LicenseManager
    ↓
EntitlementManager
    ↓
FeatureFlags
```

Never make tracking depend on a remote server being reachable.

A temporary internet outage should not stop a writer's statistics.

---

# 115. Telemetry

Default:

**No behavioral telemetry.**

If commercialized, optional anonymous diagnostics could be offered.

Example:

```text
☐ Help improve Writing Tracker by sending anonymous diagnostics
```

Never silently upload:

- document names
- document paths
- writing content
- keyboard activity
- project names

---

# 116. Onboarding

First launch should be simple.

## Step 1

Welcome.

> Track your writing without changing where you write.

## Step 2

Choose writing applications.

```text
☑ Microsoft Word
☐ Scrivener
☐ Pages
☐ Ulysses
```

## Step 3

Choose tracking mode.

```text
● Automatic
○ Manual sessions
○ Automatic with application filtering
```

## Step 4

Grant permissions.

Explain Accessibility/Automation permissions.

## Step 5

Create first project.

```text
Project name:
[________________]

Target word count:
[________]

Deadline:
[________]
```

## Step 6

Done.

> Writing Tracker is ready.

---

# 117. First-Run Privacy Message

The product should explicitly communicate:

> Writing Tracker does not need to know what you are writing.
>
> It tracks activity, timing, applications, documents, and word-count changes so you can understand your writing habits.
>
> Your manuscript stays on your Mac.

This should be a major part of the product identity.

---

# 118. Settings

Settings sections:

### General

- Launch at login
- Menu bar icon
- Start at launch
- Appearance

### Tracking

- Tracking mode
- Inactivity timeout
- Active application behavior
- Session rules
- Global start/stop hotkey (configurable, optional)

### Applications

- Writing applications
- Application adapters
- Application categories

### Projects

- Automatic project assignment
- Folder rules

### Goals

- Daily goal
- Weekly goal
- Streak threshold

### Notifications

- Goals
- Streaks
- Milestones

### Privacy

- Data collection
- Diagnostics
- Keyboard recording status

### Data

- Export
- Import
- Backup
- Reset statistics

### Account

Future.

---

# 119. Reset / Delete Data

The user must have full control.

Options:

```text
Delete session history
Delete project
Delete all statistics
Factory reset
```

Dangerous operations should require confirmation.

Potentially allow exporting first.

---

# 120. Visual Design

The application should look like a serious professional productivity application.

Design goals:

- clean
- modern
- information-dense
- readable
- native macOS
- polished charts
- subtle animations
- excellent dark mode

Do not make it look like a spreadsheet.

Do not make every statistic a giant number.

Use hierarchy.

---

# 121. Navigation

Recommended sidebar:

```text
Dashboard

Statistics
Calendar
Sessions

Projects
    All Projects
    Active
    Completed

Goals

Reports

Achievements

Settings
```

Potentially:

```text
Author
```

at the top.

---

# 122. Dashboard Navigation

The dashboard should be the default page.

A user should be able to answer:

> "How am I doing today?"

within two seconds.

---

# 123. Project Navigation

The project page should answer:

> "How is this book progressing?"

within two seconds.

---

# 124. Lifetime Navigation

The lifetime page should answer:

> "What have I accomplished as a writer?"

within two seconds.

These are the three core experiences.

---

# 125. MVP Definition

Do NOT attempt to build everything above in version 1.

The first functional milestone should be:

### MVP

1. Native macOS application.
2. Menu bar application.
3. Background tracking.
4. Launch at login.
5. Application selection.
6. Manual sessions.
7. Automatic sessions.
8. Frontmost application detection.
9. Keyboard activity detection without storing typed content.
10. Basic Word integration.
11. Word-count sampling.
12. Projects.
13. Session history.
14. Daily statistics.
15. Weekly statistics.
16. Lifetime statistics.
17. Basic charts.
18. Calendar history.
19. Goals.
20. Streaks.
21. Data export.
22. Local SQLite persistence.
23. Sleep/wake handling.
24. Privacy controls.

That alone would be a genuinely useful product.

---

# 126. Version 1.1

Add:

- better Word integration
- Scrivener integration
- project folder rules
- project dashboards
- advanced charts
- editing statistics
- milestones
- notes
- reports

---

# 127. Version 1.5

Add:

- More **exact word-count** integrations where a supported interface exists
- Time-only tracking polish for Scrivener, Ulysses, LibreOffice, Obsidian and browsers
- generic application adapters (time only)
- productivity pattern analysis
- project comparisons
- year-in-review
- widgets
- advanced projections

---

# 128. Version 2

Potentially:

- cloud synchronization
- optional account
- iCloud
- cross-device support
- web dashboard
- mobile companion
- advanced author analytics
- shareable reports
- commercial licensing

---

# 129. Future AI Features

AI should NOT be required for the core product.

But it could eventually provide useful analysis.

For example:

> "Analyze my writing habits from the last 90 days."

Possible response:

> You tend to write most frequently between 7 PM and 10 PM. Your output is highest on Saturdays, but your average session is longest on Thursdays. Your current 30-day pace is approximately 18% above your historical average.

AI should analyze the statistics, not necessarily the manuscript.

This maintains the privacy-first positioning.

---

# 130. AI Project Forecasting

Future AI could analyze:

- historical pace
- project type
- writing schedule
- deadline
- previous projects

and provide:

> At your current pace, you are likely to reach your target between October 12 and October 21.

Again, this should be clearly labeled as a projection.

---

# 131. AI Writing Coach

Potential future optional feature:

> "You have written 8,421 words this week, which is 12% above your normal weekly average."

or:

> "You have had three consecutive weeks of declining writing time."

This should be motivational rather than judgmental.

---

# 132. Important Product Rule

Do not make the product shame writers.

Avoid language like:

> You failed your goal.

Prefer:

> Goal: 72% complete

or:

> You wrote 4,200 of your 6,000-word weekly target.

The product should feel encouraging.

---

# 133. Technical Testing

The application must have extensive automated tests around the tracking engine.

Especially test:

- application focus changes
- inactivity
- sleep/wake
- midnight
- timezone changes
- daylight saving
- negative word changes
- pasted text
- undo
- redo
- document switching
- Word closing
- computer restart
- duplicate events
- crash recovery
- multiple projects
- sessions spanning midnight

Statistics calculations should have deterministic unit tests.

---

# 134. Privacy Testing

Verify that:

- actual keystrokes are never persisted
- clipboard contents are never persisted
- screenshots are never captured
- document contents are not uploaded
- analytics remain local
- permissions are clearly communicated

---

# 135. Logging

Development logs may include:

```text
Word became active
Document changed
Word count changed 10,421 → 10,487
Session paused
```

Never log:

```text
actual text typed
```

Production logging should be minimal.

Provide a diagnostic export that strips sensitive data.

---

# 136. Error Handling

If Word integration fails:

Do not stop tracking.

Fall back to:

```text
Application activity tracking
```

If document word count cannot be obtained:

```text
Words:
Unavailable

Active time:
42m
```

The system should degrade gracefully.

---

# 137. Generic Application Fallback

Even without a dedicated adapter, the tracker should still be able to say:

```text
User was actively working in:
MyWritingApp

Time:
1h 23m
```

The user could manually enter:

```text
Words:
1,203
```

This allows the product to support obscure writing applications.

---

# 138. Core Product Differentiator

The primary differentiator should be:

> **Detailed writing analytics without forcing writers into a proprietary writing application.**

Competitors may offer:

- writing editors
- timers
- manual word counters

This product instead offers:

**A tracking layer that sits on top of the writer's existing workflow.**

---

# 139. Secondary Differentiator

Privacy.

Positioning:

> Your manuscript is yours. We track your writing, not what you write.

---

# 140. Third Differentiator

Author-level historical analytics.

A normal productivity timer might tell someone:

> You wrote for 2 hours today.

This application should eventually be able to say:

> You have spent 6,218 hours writing across 47 projects and produced 2.48 million words.

That is a fundamentally different product.

---

# 141. Product Naming Concept

The working project name can be temporary.

The final name should communicate something along the lines of:

- writing
- author
- words
- productivity
- tracking
- progress
- analytics

Do not let naming constrain the architecture.

---

# 142. Development Priorities

When making implementation decisions, prioritize:

1. Data correctness
2. Tracking reliability
3. Privacy
4. Low resource usage
5. Native macOS experience
6. Extensibility
7. Visual polish
8. Advanced analytics
9. Monetization

Never sacrifice data integrity for a flashy feature.

---

# 143. Critical Architectural Requirement

The tracking engine must be independent of any particular editor.

Do NOT build:

```text
WordTracker
```

with Scrivener support added later.

Build:

```text
WritingTracker
```

with:

```text
WordAdapter
ScrivenerAdapter
...
```

This distinction should be enforced throughout the codebase.

---

# 144. Critical Analytics Requirement

Never confuse:

```text
words typed
```

with:

```text
net manuscript change
```

and never confuse either with:

```text
active writing time
```

These are three different measurements.

The database and UI should preserve that distinction.

---

# 145. Critical Background Requirement

Closing the window must not stop tracking.

The tracking process must remain alive independently of the dashboard.

This should be treated as a core architectural requirement rather than a later enhancement.

---

# 146. Critical Privacy Requirement

The application should never need to record the actual content of keyboard input.

Use keyboard events only as signals that activity occurred.

The system should store timestamps and activity metadata rather than keystroke contents.

---

# 147. Suggested Initial Development Sequence

Build in this order:

### Phase 1 — Foundation

- Swift project
- SwiftUI shell
- menu bar app
- database
- settings
- logging
- migrations

### Phase 2 — Activity Detection

- frontmost application detection
- application selection
- keyboard activity detection
- Accessibility permission flow
- session state machine

### Phase 3 — Persistence

- sessions
- activity events
- daily aggregates
- crash recovery
- sleep/wake

### Phase 4 — Word Integration

- Word adapter
- document detection
- word count retrieval
- project association

### Phase 5 — Statistics

- daily
- weekly
- monthly
- yearly
- lifetime
- streaks
- averages

### Phase 6 — GUI

- dashboard
- charts
- calendar
- session history
- statistics pages

### Phase 7 — Projects

- project library
- project dashboard
- goals
- milestones
- projections

### Phase 8 — Advanced Analytics

- editing analytics
- productivity patterns
- comparisons
- reports

### Phase 9 — Additional Editors

- Scrivener
- Pages
- Ulysses
- generic adapters

### Phase 10 — Commercialization

- licensing abstraction
- entitlement system
- optional account
- cloud architecture
- payment integration
- distribution

---

# 148. Coding AI Instructions

When implementing this project:

### Do

- Keep tracking and GUI separate.
- Use protocols for application adapters.
- Use dependency injection where useful.
- Keep database access behind repositories.
- Write tests for statistics.
- Write tests for session state transitions.
- Use async/background processing where appropriate.
- Keep the UI responsive.
- Treat privacy as a first-class concern.
- Document macOS permission requirements.
- Make migrations reversible where practical.
- Commit changes in small logical Git commits.

### Do not

- hard-code Microsoft Word into the tracking engine
- store actual keystrokes
- make the dashboard responsible for tracking
- require the GUI to remain open
- require internet connectivity for local tracking
- assume word count changes equal typed words
- destroy historical records when recalculating statistics
- build subscription logic directly into individual views
- make cloud services mandatory for core functionality

---

# 149. Definition of Success

The first version is successful if I can:

1. Install the application.
2. Grant the necessary macOS permissions.
3. Select Microsoft Word as a writing application.
4. Start a writing session manually.
5. Write in Word normally.
6. Close the Writing Tracker dashboard.
7. Continue writing.
8. Have the background process continue tracking.
9. Stop the writing session.
10. Reopen the dashboard.
11. See the session recorded.
12. See today's word count.
13. See active writing time.
14. See my current streak.
15. See the project associated with the session.
16. See historical daily activity.
17. See charts.
18. See lifetime totals.
19. Export the data.
20. Restart the Mac and have tracking continue automatically if enabled.

---

# 150. Ultimate Product Vision

The finished product should feel like this:

> **Strava / Apple Fitness for authors.**

Not a writing application.

Not merely a timer.

Not merely a word counter.

It should become the author's permanent historical record of their writing life.

A writer should eventually be able to open the application ten years from now and see:

```text
YOUR WRITING LIFE

47 projects
18 completed
2,481,392 words
6,218 hours
1,834 writing days

Longest streak
143 days

Best writing day
8,421 words

Most productive year
2026

Most productive project
Naphtali

Favorite writing time
7–10 PM

Average session
47 minutes
```

And then drill all the way down to:

```text
September 8, 2026
7:42 PM

Naphtali
Microsoft Word
Drafting

49 minutes
+642 words
14.9 WPM
```

That historical continuity is the long-term value of the product.

The user should be able to use it for years without changing writing applications, while the tracker quietly builds an increasingly valuable record of their work.