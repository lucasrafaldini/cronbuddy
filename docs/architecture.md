# CronBuddy architecture

CronBuddy is two Swift targets: **CronBuddyCore**, a library with no UI that knows about schedules, cron, launchd and run history, and **CronBuddy**, the SwiftUI app on top. Everything that touches the operating system lives in the core and is covered by tests; the app is presentation and state.

```
┌──────────────────────────── CronBuddy.app (SwiftUI) ────────────────────────────┐
│  MenuBarExtra · main window · editor · settings          AppModel (@Observable)  │
└──────────────────────────────────────┬───────────────────────────────────────────┘
                                       │
┌──────────────────────────────── CronBuddyCore ───────────────────────────────────┐
│  Schedule ⇄ CronExpression    JobStore ─┬─ LaunchdBackend (plists, launchctl)     │
│  Job, JobAction, Templates              ├─ CrontabBackend (managed lines only)     │
│  ActionScript (one script per job)      └─ RunHistory (runs.jsonl + logs)          │
│  ScheduledRun / LegacyRun (run mode)                                              │
└──────────────────────────────────────────────────────────────────────────────────┘
```

## Decisions

### 1. Users describe schedules; the app speaks cron and launchd

People think "weekdays at 9 and 18:30", not `30 18 * * 1-5` plus `0 9 * * 1-5`. `Schedule` models intervals, hourly, daily (several times), weekly, monthly, at login and raw cron, and converts each to whatever the backend needs:

- **to cron**, grouping times that share a minute into one line (`0 9,18 * * *`) and splitting the rest;
- **to launchd**, expanding a cron expression into `StartCalendarInterval` entries, emitting both day fields separately when cron would OR them, and refusing expansions too large to be sane;
- **from cron**, recognizing structure in imported lines so `0 10,14,17 * * 1-5` shows up as "Weekdays at 10:00, 14:00 and 17:00".

The next-run preview uses the same parser, so what the editor promises is what the scheduler does. A leap-day expression and the OR semantics of day-of-month and day-of-week have their own tests.

### 2. launchd is the default

cron skips runs missed while the Mac sleeps; launchd runs them on wake. For a laptop that sleeps every night, that's the difference between a backup that happens and one that doesn't. cron stays available for people who want its exact semantics.

### 3. Every job is a script on disk

A job's action, whether a command, a script path, AppleScript or a Shortcut, is rendered into `actions/<id>.sh`, with environment variables exported first. cron and launchd only ever start CronBuddy with a job id. User text never has to be quoted into a crontab line or a plist, which is where scheduling tools usually break, and "Show Action Script in Finder" shows exactly what will run.

### 4. Jobs run through CronBuddy itself

macOS attributes a process's privacy permissions to its *responsible* process. A script started by cron or a bare launchd agent has none, so touching Documents or iCloud Drive fails. CronBuddy's own executable has a run mode (`--run-job <id>`): launchd starts it directly, and cron lines call `launchctl kickstart` on the job's agent, so cron keeps its timing while launchd does the launching. Either way CronBuddy is the responsible process, and one Full Disk Access grant covers every job.

The first version of this sent cron jobs through `open -a CronBuddy.app`. Testing on a real machine showed the flaw: LaunchServices then treated the headless run as the running app, and clicking CronBuddy during a run did nothing. Routing through launchd fixed it without giving up the single permission.

### 5. Run history is files the wrapper can append to

Each run appends one JSON line to `~/Library/Logs/CronBuddy/<id>/runs.jsonl` and writes its output to a log file beside it. The run mode, the app's Run Now and the 1.x compatibility path all write the same format. The app watches modification times every few seconds instead of keeping a database in sync, history survives reinstalls, and every log is a plain file that Console, `tail` or Finder can open. Old runs are pruned to a configurable count.

### 6. Running state is a marker with a pid

While a scheduled run is in progress, the run mode writes `.running` with its pid. The app shows a pulsing dot only if that pid is alive, so a crash can't leave a job "running" forever.

### 7. Never touch what you don't own

CronBuddy manages only crontab lines ending in `# cronbuddy:<id>` and launch agents with its label prefix. Everything else in your crontab is preserved byte for byte, apart from trailing blank lines, and the crontab is rewritten only when the managed section actually changes. On launch it reconciles: it reinstalls agents that drifted and removes orphaned ones.

### 8. Compatibility with 1.x is a feature, not an afterthought

1.x wrote crontab lines that launch the app with `--run '<command>' --name '<job>'`. Replacing the app would have silently broken them, so version 2 accepts that form, logs to the same place in the same format, and labels those lines in **Import from crontab** for a clean migration.

### 9. A testable core

`CronBuddyCore` is pure Swift with the system calls at the edges: `Shell.run`, `crontab`, `launchctl`. The 29 tests cover cron parsing and next dates, schedule conversion in all directions, crontab merging, launchd plists, action script rendering and quoting, run history and pruning, the run mode end to end, and 1.x compatibility, and every bundled template is validated against both backends.

## Design

- **The menu bar is the product.** Most of the time you only need to know what runs next and whether the last runs worked, so that's the whole popover: up next, then every job with a status dot and a one-line summary. Run and pause appear on hover.
- **Plain language everywhere.** Schedules read as sentences, errors say what to do ("cron can't repeat at this interval; use launchd"), and the editor's save button explains why it's disabled.
- **Status is color plus shape.** Green, red, grey and a pulsing ring for running, with labels for VoiceOver.
- **Themes carry typography, not just color.** Thoth and Paper set titles in a serif, Phosphor makes everything monospace, Nord uses rounded type. Text on the accent color has its own token, so gold and phosphor-green buttons stay readable.
- **Native first.** SwiftUI forms, tables, split views and sheets, so keyboard navigation, VoiceOver and system appearance work without extra code.

## Documentation screenshots

Debug builds accept `CRONBUDDY_HOME`, which points the app at a throwaway home folder and turns off every write to the real crontab and launchd, and `CRONBUDDY_SNAPSHOT_DIR`, which lets a script drive the UI and capture the app's own windows. Release builds contain neither.
