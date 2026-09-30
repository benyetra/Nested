import AppIntents
import Foundation
import NestedCore
import NestedData
import Testing

@testable import Nested

/// Every intent runs the same code path from widgets, controls, Siri and the Watch; these run
/// each one against an in-memory database.
@MainActor
@Suite("App Intents", .serialized)
struct IntentTests {
  let store: LiveEventStore

  init() throws {
    store = LiveEventStore(database: try NestedDatabase.openInMemory(), owner: { "Bennett" })
    SharedStore.configure(store)
    var baby = try store.createBaby(
      name: "Maddie", birthDate: Date().addingTimeInterval(-20 * 86_400), feedingMode: .mixed, unit: .ml)
    // Keep auto-arm out of the alarm assertions (it depends on the time of day).
    baby.alarmAutoArm = .off
    try store.updateBaby(baby)
  }

  private var snapshot: NestedSnapshot { get throws { try store.snapshot(now: Date()) } }

  @Test func logBottleWithAmount() async throws {
    var intent = LogBottleIntent()
    intent.amount = 3
    intent.unit = .oz
    intent.contents = .formula
    _ = try await intent.perform()
    let bottle = try #require(try snapshot.lastBottle)
    #expect(abs(bottle.amountMl - 3 * Volume.mlPerOunce) < 0.01)
    #expect(bottle.contents == .formula)
    #expect(bottle.loggedBy == "Bennett")
  }

  @Test("Log bottle without an amount repeats the usual bottle")
  func logBottleRepeat() async throws {
    try store.logBottle(amountMl: 120, contents: .breastMilk, at: Date().addingTimeInterval(-3 * 3600))
    _ = try await LogBottleIntent().perform()
    let bottle = try #require(try snapshot.lastBottle)
    #expect(bottle.amountMl == 120)
    #expect(bottle.contents == .breastMilk)
  }

  @Test func logDiaper() async throws {
    var intent = LogDiaperIntent(type: .dirty)
    intent.color = .mustardYellow
    intent.consistency = .seedy
    _ = try await intent.perform()
    let diaper = try #require(try snapshot.lastDiaper)
    #expect(diaper.kind == .dirty)
    #expect(diaper.stoolColor == .mustardYellow)
    #expect(diaper.consistency == .seedy)
  }

  @Test("Nursing: start on the next side, switch, pause, stop")
  func nursing() async throws {
    try store.logNursing(leftSeconds: 900, rightSeconds: 0, endedOn: .left, at: Date().addingTimeInterval(-3 * 3600), note: "")
    _ = try await StartNursingIntent().perform()
    #expect(try snapshot.activeNursing?.currentSide == .right)
    _ = try await SwitchSideIntent().perform()
    #expect(try snapshot.activeNursing?.currentSide == .left)
    _ = try await PauseNursingIntent().perform()
    #expect(try snapshot.activeNursing?.isPaused == true)
    _ = try await PauseNursingIntent().perform()
    #expect(try snapshot.activeNursing?.isPaused == false)
    _ = try await StopNursingIntent().perform()
    #expect(try snapshot.activeNursing == nil)
  }

  @Test("Sleep start/end and the control toggle")
  func sleep() async throws {
    var start = StartSleepIntent()
    start.location = .bassinet
    _ = try await start.perform()
    #expect(try snapshot.activeSleep?.location == .bassinet)
    _ = try await EndSleepIntent().perform()
    #expect(try snapshot.activeSleep == nil)

    var toggle = ToggleSleepIntent()
    toggle.value = true
    _ = try await toggle.perform()
    #expect(try snapshot.activeSleep != nil)
    toggle.value = false
    _ = try await toggle.perform()
    #expect(try snapshot.activeSleep == nil)
  }

  @Test func nursingToggle() async throws {
    var toggle = ToggleNursingIntent()
    toggle.value = true
    _ = try await toggle.perform()
    #expect(try snapshot.activeNursing != nil)
    toggle.value = false
    _ = try await toggle.perform()
    #expect(try snapshot.activeNursing == nil)
  }

  @Test func pump() async throws {
    _ = try await StartPumpIntent().perform()
    #expect(try snapshot.activePump != nil)
    var end = EndPumpIntent()
    end.left = 60
    end.right = 50
    end.unit = .ml
    _ = try await end.perform()
    #expect(try snapshot.activePump == nil)
    #expect(try snapshot.history.pumps.last?.totalMl == 110)
  }

  @Test func stopActiveTimer() async throws {
    try store.startSleep(location: nil, at: Date())
    try store.startPump(at: Date())
    _ = try await StopActiveTimerIntent().perform()
    #expect(try !snapshot.hasRunningTimer)
  }

  @Test func note() async throws {
    var intent = LogNoteIntent()
    intent.text = "Spit up"
    _ = try await intent.perform()
    let entries = try store.entries(from: .distantPast, to: .distantFuture)
    #expect(entries.contains { $0.kind == .note && $0.note == "Spit up" })
  }

  @Test("Questions answer from the data")
  func questions() async throws {
    let noData = try await LastFeedQueryIntent().perform()
    _ = noData
    try store.logNursing(leftSeconds: 14 * 60, rightSeconds: 0, endedOn: .left, at: Date().addingTimeInterval(-2 * 3600), note: "")
    let snap = try snapshot
    let answer = Answers.lastFeed(snap.lastFeed, babyName: snap.babyName, unit: snap.unit, now: Date())
    #expect(answer.contains("left side"))
    _ = try await NextFeedQueryIntent().perform()
  }

  @Test("Feed alarm: set, snooze, feeding now, stop")
  func feedAlarm() async throws {
    _ = try await SetFeedAlarmIntent(hours: 3).perform()
    let alarm = try #require(try snapshot.feedAlarm)
    #expect(alarm.isManual)
    #expect(abs((alarm.fireAt ?? .distantPast).timeIntervalSinceNow - 3 * 3600) < 60)

    _ = try await SnoozeFeedAlarmIntent(alarmID: UUID()).perform()
    #expect(abs((try snapshot.feedAlarm?.fireAt ?? .distantPast).timeIntervalSinceNow - 600) < 60)

    _ = try await FeedingNowIntent(alarmID: UUID()).perform()
    #expect(try snapshot.feedAlarm?.handledAt != nil)
    #expect(try snapshot.activeNursing != nil)

    _ = try await StopFeedAlarmIntent(alarmID: UUID()).perform()
    #expect(try snapshot.feedAlarm?.handledBy == "Bennett")
  }
}
