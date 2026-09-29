# Nest — Newborn Tracker

A private, two-parent iOS app that logs every feed, diaper, nap and pump in under 3 seconds, syncs between both parents' phones through iCloud, and turns the history into predictions and trends. It's built from the *Newborn Tracker PRD*. (Repository: Nested; the app is called Nest.)

## Layout

| Path | What |
| --- | --- |
| `NestKit/Sources/NestCore` | Pure logic with no Apple-only frameworks: units, predictions, gentle flags, alarm rules, daily stats, CSV |
| `NestKit/Sources/NestData` | SQLiteData schema, migrations, `EventStore` (all writes), snapshot (all reads), CloudKit sync setup |
| `App/` | SwiftUI app: Now, Timeline, Trends, Settings, log sheets, and services (AlarmKit, ActivityKit, notifications, Worker push, Foundation Models summary, PDF report) |
| `Shared/` | Compiled into the app, widgets and watch: App Intents catalog, Live Activity attributes, process-wide store, widget timeline provider |
| `Widgets/` | Lock Screen and Home Screen widgets, Control Center controls, Live Activity / Dynamic Island |
| `Watch/`, `WatchWidgets/` | Apple Watch app and complications |
| `Tests/` | Swift Testing tests for every App Intent (hosted in the app) |
| `worker/` | Cloudflare Worker that sends APNs Live Activity and background pushes to the partner's phone |
| `project.yml` | XcodeGen spec |

## Build

```sh
brew install xcodegen
xcodegen generate
open Nest.xcodeproj
```

To run the logic tests without Xcode: `cd NestKit && swift test`. They also run on Linux; install `libsqlite3-dev` first.

## One-time Apple setup

Use the Apple Developer account for team `87A6J7UY87`.

1. **Identifiers.**
   - Register these App IDs:
     - `com.yetra.nest`
     - `com.yetra.nest.widgets`
     - `com.yetra.nest.watchkitapp`
     - `com.yetra.nest.watchkitapp.widgets`
   - Create the App Group `group.com.yetra.nest` and the iCloud container `iCloud.com.yetra.nest`.
   - Enable these for the targets that use them (see the `*.entitlements` files): App Groups, iCloud (CloudKit), Push Notifications, and Time Sensitive Notifications.
2. **CloudKit schema.** Run a development build once on a device so that SQLiteData creates the record types. Then use **Deploy Schema Changes to Production** in the CloudKit Console before TestFlight.
3. **Sharing.** Bennett creates the baby, then goes to Settings → Share with your partner and sends the invite in Messages. Yvette opens the link once.
4. **Worker** (optional, Phase 2). This lets a timer started on one phone appear on the other phone's Lock Screen even when Nest isn't running there. It also stops the partner's alarm within seconds. Setup is in `worker/README.md`. Then set `NEST_WORKER_URL` and `NEST_WORKER_KEY` in `project.yml`, or in Xcode Cloud environment variables.

## How the PRD maps to code

- **Log in one gesture.** Every action is an App Intent in `Shared/Intents/NestIntents.swift`. The same intents are used by:
  - Home Screen widget buttons
  - Control Center / Lock Screen controls
  - Siri phrases (`App/Intents/NestShortcuts.swift`)
  - Live Activity buttons
  - AlarmKit buttons
  - the Shortcuts app

  Write intents are `LiveActivityIntent`s compiled into both the app and the widget extension, so they run in the app process where the sync engine lives. If one runs in the extension anyway, the extension writes through a deferred sync engine and posts a Darwin notification, and the app uploads the change.
- **Shared instantly.**
  - Writes land in the local SQLite file first (App Group), then SQLiteData's `SyncEngine` syncs them to CloudKit and shares them with the partner through `CKShare`.
  - `SideEffects` watches the database, so remote and local changes alike reload widgets and controls, reschedule the alarm and reconcile Live Activities.
- **Timers survive everything.**
  - A running timer is a row with a nil `endedAt`, and all elapsed time is computed from stored times.
  - Nursing sides are `NursingSegment` rows, so pause and switch work from either phone.
- **Undo, not confirm.** Every write shows a 5-second undo toast (`AppModel.perform`). Delete-all is the only confirmation dialog.
- **Conflict rule.** Every edit writes the previous version to `entryRevisions`. The entry editor shows them under "Earlier versions".
- **Night feed alarm.**
  - Feeds auto-arm the single `feedAlarms` row, which is keyed by baby, so there's only ever one alarm (`EventStore.autoArm`).
  - Each phone schedules its own AlarmKit alarm from that row (`FeedAlarmService`) and reports its armed state for the bedtime confirmation.
  - Stop, Feeding now and Snooze update the shared row, and the partner's phone follows.
- **Predictions and flags.** `NestCore/Predictions.swift` and `HealthFlags.swift` are covered by fixture tests: regular pattern, cluster feeding, growth spurt, missing data.

## Deviations and known limits

- **Deployment target is iOS 26 / watchOS 26, not iOS 27.** Every framework the PRD relies on (AlarmKit, Foundation Models, Liquid Glass, controls) shipped in 26, and the app runs on iOS 27. Change `deploymentTarget` in `project.yml` to require 27.
- **Alarm sound.** AlarmKit doesn't expose a volume ramp, so the alarm uses the system alarm sound.
- **Snooze** is implemented as "move the shared alarm 10 minutes later", so both phones snooze together.
- **Only one phone** / **shift mode.**
  - With "Who rings: only one phone", the phone that rings is chosen by owner name.
  - Shift mode rings the parent who did *not* log the feed. It needs both phones set up.
- **LocalPrefs.** The PRD's private `LocalPrefs` table is App Group `UserDefaults` (`DevicePrefs`) instead, because it's per-device and never synced.
- **Design skills.** The `emilkowalski/skills` install from the PRD (`npx skills@latest add emilkowalski/skills`) is left for you to run in this repo.
