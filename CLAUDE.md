# Nest — rules for changes

- **The spec.** The Newborn Tracker PRD is the spec. Paste the relevant section into each plan, and update the doc when a decision changes.
- **Writes.** Every write goes through `EventStore` (`NestKit/Sources/NestData/EventStore.swift`). No view or intent touches the database directly. Reads use `SnapshotRequest`, `TimelineRequest` or `TrendsRequest`.
- **Logic location.** Pure logic belongs in `NestCore`, with Swift Testing tests. It must stay free of Apple-only frameworks so `swift test` runs on Linux.
- **Timers.** Elapsed time always comes from stored `startedAt`/`endedAt`. Never count time in memory.
- **Schema.** Table SQL is frozen once shipped. Add a new migration instead of editing one. Keep the sync rules:
  - UUID primary keys
  - no `UNIQUE` constraints
  - `NOT NULL ON CONFLICT REPLACE DEFAULT` on new columns
  - one foreign key per table, pointing back to `babies`
- **Intents.** Every App Intent has a test in `Tests/IntentTests.swift`. Write intents are `NestWriteIntent` (`LiveActivityIntent` on iOS).
- **Motion.** Motion follows `Motion` in `App/Design/Design.swift`:
  - 0.35 s / 1.0 by default
  - 0.3 s / 0.8 for sheets
  - 0.4 s / 0.8 for side switches
  - a 200 ms cross-fade under Reduce Motion
- **Colour.** Each event type has one colour (`EventKind.color`), used on every surface.
- **Dependencies.** Don't add a dependency without asking. SQLiteData is pinned to an exact version.
- **After editing.** Run `cd NestKit && swift test`, then `xcodegen generate` (regenerates the committed `Nest.xcodeproj`; commit it with the change) and build the `Nest` scheme. Entitlements are defined in `project.yml`, not edited by hand.
