import Foundation
import NestedCore
import SQLiteData
import Testing

@testable import NestedData

/// A mutable clock the store reads, so tests control "now".
final class TestClock: @unchecked Sendable {
  var now: Date
  init(_ now: Date) { self.now = now }
  func advance(minutes: Double) { now = now.addingTimeInterval(minutes * 60) }
}

let utc: Calendar = {
  var c = Calendar(identifier: .gregorian)
  c.timeZone = TimeZone(identifier: "UTC")!
  return c
}()

func t(day: Int = 20, _ hour: Int, _ minute: Int = 0) -> Date {
  utc.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
}

/// Store over an in-memory database with a named owner and controllable clock.
func makeStore(
  owner: String = "Bennett",
  clock: TestClock,
  database: (any DatabaseWriter)? = nil
) throws -> LiveEventStore {
  DevicePrefs.defaults = UserDefaults(suiteName: "nested-tests-\(UUID().uuidString)")!
  let db = try database ?? NestedDatabase.openInMemory()
  return LiveEventStore(database: db, owner: { owner }, now: { clock.now }, calendar: utc)
}

@Suite("EventStore", .serialized)
struct EventStoreTests {
  @Test("Each event type can be created, edited, deleted and restored")
  func crudAllTypes() throws {
    let clock = TestClock(t(10))
    let store = try makeStore(clock: clock)
    try store.createBaby(name: "Maddie", birthDate: t(day: 1, 0), feedingMode: .mixed, unit: .ml)

    var created: [Entry] = []
    created.append(try store.logBottle(amountMl: 90, contents: .formula, at: t(9)))
    created.append(
      try store.logNursing(leftSeconds: 600, rightSeconds: 300, endedOn: .right, at: t(8), note: ""))
    _ = try store.startPump(at: t(7))
    created.append(try store.stopPump(leftMl: 40, rightMl: 50, destination: .fridge, at: t(7, 20)))
    created.append(try store.logDiaper(kind: .dirty, stoolColor: .yellow, consistency: .seedy, size: .medium, rash: false, at: t(6), note: ""))
    _ = try store.startSleep(location: .crib, at: t(4))
    created.append(try store.stopSleep(at: t(5)))
    created.append(try store.logNote(text: "Spit up after feed", tag: .spitUp, at: t(9, 30)))

    #expect(try store.entries(from: .distantPast, to: .distantFuture).count == 6)
    #expect(Set(created.map(\.kind)) == Set(EventKind.allCases))

    // Edit each.
    for entry in created {
      var edited = entry
      switch edited {
      case .bottle(var e): e.amountMl = 120; edited = .bottle(e)
      case .nursing(var s, let seg): s.note = "good latch"; edited = .nursing(s, segments: seg)
      case .pump(var e): e.leftMl = 60; edited = .pump(e)
      case .diaper(var e): e.kind = .wet; edited = .diaper(e)
      case .sleep(var e): e.location = .arms; edited = .sleep(e)
      case .note(var e): e.text = "Big spit up"; edited = .note(e)
      }
      try store.save(edited)
      #expect(try store.revisions(of: entry.id).count == 1)
    }
    let afterEdit = try store.entries(from: .distantPast, to: .distantFuture)
    #expect(afterEdit.contains { if case .bottle(let b) = $0 { b.amountMl == 120 } else { false } })
    // Editing a diaper to wet drops stool fields.
    #expect(afterEdit.contains { if case .diaper(let d) = $0 { d.kind == .wet && d.stoolColor == nil } else { false } })

    // Delete and undo each.
    for entry in afterEdit {
      try store.delete(entry)
      #expect(try store.entries(from: .distantPast, to: .distantFuture).count == 5)
      try store.restore(entry)
      #expect(try store.entries(from: .distantPast, to: .distantFuture).count == 6)
    }
    let restored = try store.entries(from: .distantPast, to: .distantFuture)
    #expect(restored == afterEdit)
  }

  @Test("Nursing timer: auto side, switch, pause, stop; elapsed from stored times")
  func nursingTimer() throws {
    let clock = TestClock(t(10))
    let store = try makeStore(clock: clock)
    try store.createBaby(name: "Maddie", birthDate: nil, feedingMode: .nursing, unit: .ml)

    // Previous session ended on the left after 15 min -> start on the right.
    try store.logNursing(leftSeconds: 900, rightSeconds: 0, endedOn: .left, at: t(7), note: "")
    let started = try store.startNursing(side: nil, at: t(10), endSleep: true)
    guard case .nursing(let session, let segments) = started else { Issue.record(); return }
    #expect(segments.map(\.side) == [.right])

    // Starting again returns the running session instead of a second one.
    let again = try store.startNursing(side: .left, at: t(10, 1), endSleep: true)
    #expect(again.id == session.id)

    clock.now = t(10, 8)
    try store.switchNursingSide(at: t(10, 8))
    clock.now = t(10, 12)
    try store.pauseNursing(at: t(10, 12))
    clock.now = t(10, 20)
    try store.resumeNursing(at: t(10, 20))
    clock.now = t(10, 23)
    let stopped = try store.stopNursing(at: t(10, 23), latchNote: nil)
    guard case .nursing(let done, let doneSegments) = stopped else { Issue.record(); return }
    let (l, r) = NursingMath.sideTotals(doneSegments, now: clock.now)
    #expect(r == 8 * 60)
    #expect(l == 7 * 60)  // 4 min before pause + 3 after
    #expect(done.pausedSeconds == 8 * 60)
    #expect(done.endedOnSide == .left)

    let snapshot = try store.snapshot(now: t(10, 30))
    #expect(snapshot.activeNursing == nil)
    #expect(snapshot.nextSide == .right)
  }

  @Test("Timers survive: a session started by one parent is stopped by the other")
  func crossDeviceStop() throws {
    let clock = TestClock(t(10))
    let db = try NestedDatabase.openInMemory()
    let yvette = try makeStore(owner: "Yvette", clock: clock, database: db)
    try yvette.createBaby(name: "Maddie", birthDate: nil, feedingMode: .nursing, unit: .oz)
    try yvette.startNursing(side: .left, at: t(10), endSleep: true)

    // A different store (another process / after relaunch) sees and stops the same timer.
    clock.now = t(10, 14)
    let bennett = LiveEventStore(database: db, owner: { "Bennett" }, now: { clock.now }, calendar: utc)
    #expect(try bennett.snapshot(now: clock.now).activeNursing != nil)
    let stopped = try bennett.stopNursing(at: clock.now, latchNote: nil)
    guard case .nursing(let s, let seg) = stopped else { Issue.record(); return }
    #expect(s.loggedBy == "Yvette")
    #expect(NursingMath.sideTotals(seg, now: clock.now).left == 14 * 60)
  }

  @Test("Only one sleep timer; starting a feed can end sleep")
  func sleepAndFeed() throws {
    let clock = TestClock(t(10))
    let store = try makeStore(clock: clock)
    try store.createBaby(name: "Maddie", birthDate: nil, feedingMode: .bottle, unit: .ml)
    let first = try store.startSleep(location: nil, at: t(9))
    let second = try store.startSleep(location: .crib, at: t(9, 30))
    #expect(first.id == second.id)

    try store.logBottle(amountMl: 90, contents: .formula, offeredMl: nil, formulaBrand: nil, at: t(10), note: "", endSleep: true)
    let snapshot = try store.snapshot(now: t(10, 1))
    #expect(snapshot.activeSleep == nil)
    #expect(snapshot.awakeSince == t(10))
    #expect(snapshot.lastSleep?.endedAt == t(10))
  }

  @Test("Stop active timers ends everything running")
  func stopAll() throws {
    let clock = TestClock(t(10))
    let store = try makeStore(clock: clock)
    try store.createBaby(name: "Maddie", birthDate: nil, feedingMode: .mixed, unit: .ml)
    try store.startSleep(location: nil, at: t(9))
    try store.startPump(at: t(9, 10))
    try store.startNursing(side: .left, at: t(9, 20), endSleep: false)
    let stopped = try store.stopActiveTimers(at: t(10))
    #expect(stopped.count == 3)
    #expect(try !store.snapshot(now: t(10)).hasRunningTimer)
    #expect(throws: StoreError.nothingRunning) { try store.stopSleep(at: t(10)) }
  }

  @Test("Duplicate copies an entry to a new time with a new id")
  func duplicate() throws {
    let clock = TestClock(t(10))
    let store = try makeStore(clock: clock)
    try store.createBaby(name: "Maddie", birthDate: nil, feedingMode: .mixed, unit: .ml)
    let entry = try store.logNursing(leftSeconds: 300, rightSeconds: 600, endedOn: .right, at: t(8), note: "")
    let copy = try store.duplicate(entry, at: t(10))
    #expect(copy.id != entry.id)
    #expect(copy.date == t(10))
    #expect(try store.entries(from: .distantPast, to: .distantFuture).count == 2)
    guard case .nursing(_, let segments) = copy else { Issue.record(); return }
    #expect(NursingMath.sideTotals(segments, now: t(11)) == (300, 600))
  }

  @Test("Switching units changes no stored data")
  func unitSwitch() throws {
    let clock = TestClock(t(10))
    let store = try makeStore(clock: clock)
    var baby = try store.createBaby(name: "Maddie", birthDate: nil, feedingMode: .bottle, unit: .ml)
    try store.logBottle(amountMl: 88.71, contents: .breastMilk, at: t(9))
    let before = try store.entries(from: .distantPast, to: .distantFuture)
    baby.unit = .oz
    try store.updateBaby(baby)
    let after = try store.entries(from: .distantPast, to: .distantFuture)
    #expect(before == after)
    #expect(after.first?.title(unit: .oz) == "3 oz breast milk")
    #expect(after.first?.title(unit: .ml) == "90 ml breast milk")
  }
}

@Suite("Feed alarm", .serialized)
struct FeedAlarmStoreTests {
  @Test("11:40pm feed arms 2:40am; 1:15am feed moves it to 4:15am")
  func armAndReplace() throws {
    let clock = TestClock(t(23, 40))
    let store = try makeStore(clock: clock)
    try store.createBaby(name: "Maddie", birthDate: nil, feedingMode: .nursing, unit: .ml)
    try store.startNursing(side: nil, at: t(23, 40), endSleep: true)
    #expect(try store.snapshot(now: clock.now).feedAlarm?.fireAt == t(day: 21, 2, 40))

    clock.now = t(23, 55)
    try store.stopNursing(at: clock.now, latchNote: nil)
    clock.now = t(day: 21, 1, 15)
    try store.logBottle(amountMl: 60, contents: .breastMilk, at: t(day: 21, 1, 15))
    let alarm = try #require(try store.snapshot(now: clock.now).feedAlarm)
    #expect(alarm.fireAt == t(day: 21, 4, 15))
    #expect(alarm.handledAt == nil)
    #expect(alarm.setBy == "Bennett")
  }

  @Test("Backdated feeds older than the latest don't move the alarm")
  func backdated() throws {
    let clock = TestClock(t(23, 40))
    let store = try makeStore(clock: clock)
    try store.createBaby(name: "Maddie", birthDate: nil, feedingMode: .bottle, unit: .ml)
    try store.logBottle(amountMl: 90, contents: .formula, at: t(23, 30))
    try store.logBottle(amountMl: 30, contents: .formula, at: t(22))
    #expect(try store.snapshot(now: clock.now).feedAlarm?.fireAt == t(day: 21, 2, 30))
  }

  @Test("Manual alarm, handling, and daytime feeds clearing a pending alarm")
  func manualAndHandled() throws {
    let clock = TestClock(t(21))
    let store = try makeStore(clock: clock)
    try store.createBaby(name: "Maddie", birthDate: nil, feedingMode: .bottle, unit: .ml)
    try store.setFeedAlarm(fireAt: t(23, 30), manual: true)
    var snapshot = try store.snapshot(now: clock.now)
    #expect(snapshot.pendingAlarm(now: clock.now)?.isManual == true)

    try store.handleFeedAlarm()
    snapshot = try store.snapshot(now: clock.now)
    #expect(snapshot.pendingAlarm(now: clock.now) == nil)
    #expect(snapshot.feedAlarm?.handledBy == "Bennett")

    // Night feed arms; a daytime feed replaces it with nothing.
    clock.now = t(day: 21, 5)
    try store.logBottle(amountMl: 90, contents: .formula, at: clock.now)
    #expect(try store.snapshot(now: clock.now).pendingAlarm(now: clock.now)?.fireAt == t(day: 21, 8))
    clock.now = t(day: 21, 7, 30)
    try store.logBottle(amountMl: 90, contents: .formula, at: clock.now)
    #expect(try store.snapshot(now: clock.now).pendingAlarm(now: clock.now) == nil)
  }
}

@Suite("Snapshot, devices, import/export", .serialized)
struct SnapshotTests {
  @Test("Snapshot predictions and totals")
  func snapshot() throws {
    let clock = TestClock(t(day: 20, 11))
    let store = try makeStore(clock: clock)
    try store.createBaby(name: "Maddie", birthDate: t(day: 1, 0), feedingMode: .bottle, unit: .ml)
    for i in 0..<12 {
      try store.logBottle(amountMl: 90, contents: .formula, at: t(day: 19, 0).addingTimeInterval(Double(i) * 3 * 3600))
    }
    try store.logDiaper(kind: .wet, at: t(day: 20, 10, 30))
    let snapshot = try store.snapshot(now: clock.now)
    #expect(snapshot.babyName == "Maddie")
    #expect(snapshot.defaultBottleMl == 90)
    #expect(snapshot.feedPrediction?.expected == t(day: 20, 12))
    #expect(snapshot.todayWet == 1)
    #expect(snapshot.lastDiaper?.kind == .wet)
    #expect(snapshot.flags(now: clock.now, calendar: utc).map(\.kind) == [.fewWetDiapers])
  }

  @Test("Device rows record push tokens and alarm state")
  func devices() throws {
    let clock = TestClock(t(10))
    let store = try makeStore(owner: "Yvette", clock: clock)
    try store.createBaby(name: "Maddie", birthDate: nil, feedingMode: .mixed, unit: .ml)
    try store.updateDevice { $0.pushToStartToken = "abc" }
    try store.updateDevice { $0.alarmArmedFor = t(13) }
    let snapshot = try store.snapshot(now: clock.now)
    #expect(snapshot.devices.count == 1)
    #expect(snapshot.devices.first?.pushToStartToken == "abc")
    #expect(snapshot.devices.first?.alarmArmedFor == t(13))
    #expect(snapshot.devices.first?.ownerName == "Yvette")
  }

  @Test("CSV export imports into a fresh database with nothing lost; re-import is a no-op")
  func csvRoundTrip() throws {
    let clock = TestClock(t(12))
    let store = try makeStore(clock: clock)
    try store.createBaby(name: "Maddie", birthDate: nil, feedingMode: .mixed, unit: .ml)
    try store.logBottle(amountMl: 90, contents: .formula, at: t(9))
    try store.logNursing(leftSeconds: 600, rightSeconds: 300, endedOn: .right, at: t(8), note: "a, b")
    try store.logDiaper(kind: .dirty, stoolColor: .mustardYellow, consistency: .seedy, size: nil, rash: true, at: t(7), note: "")
    try store.startSleep(location: .bassinet, at: t(5))
    try store.stopSleep(at: t(6))
    try store.logNote(text: "37.8°C", tag: .temperature, at: t(10))
    let csv = try store.exportCSV()

    let other = try makeStore(owner: "Yvette", clock: clock)
    try other.createBaby(name: "Maddie", birthDate: nil, feedingMode: .mixed, unit: .ml)
    #expect(try other.importCSV(csv) == 5)
    #expect(try other.importCSV(csv) == 0)
    let imported = try other.entries(from: .distantPast, to: .distantFuture)
    let original = try store.entries(from: .distantPast, to: .distantFuture)
    #expect(imported.map { $0.title(unit: .ml) } == original.map { $0.title(unit: .ml) })
    #expect(imported.map(\.loggedBy) == original.map(\.loggedBy))
  }

  @Test("Writes without a baby fail clearly")
  func noBaby() throws {
    let store = try makeStore(clock: TestClock(t(10)))
    #expect(throws: StoreError.noBaby) { try store.logDiaper(kind: .wet) }
  }
}

@Suite("Delete all", .serialized)
struct DeleteAllTests {
  @Test("Deleting all data cascades to every entry")
  func deleteAll() throws {
    let clock = TestClock(t(10))
    let store = try makeStore(clock: clock)
    try store.createBaby(name: "Maddie", birthDate: nil, feedingMode: .mixed, unit: .ml)
    try store.logBottle(amountMl: 90, contents: .formula, at: t(9))
    try store.logNursing(leftSeconds: 60, rightSeconds: 60, endedOn: .left, at: t(8), note: "")
    try store.setFeedAlarm(fireAt: t(12), manual: true)
    try store.deleteAllData()
    #expect(try store.baby() == nil)
    #expect(try store.database.read { db in try NursingSegment.all.fetchCount(db) } == 0)
    #expect(try store.database.read { db in try FeedAlarm.all.fetchCount(db) } == 0)
  }
}


@Suite("Questions", .serialized)
struct QuestionTests {
  @Test("Add, answer, toggle, restore and delete")
  func lifecycle() throws {
    let clock = TestClock(t(10))
    let store = try makeStore(clock: clock)
    try store.createBaby(name: "Maddie", birthDate: nil, feedingMode: .mixed, unit: .ml)

    let q = try store.addQuestion(RichText(runs: [RichRun("Is this "), RichRun("spit up", bold: true), RichRun(" normal?")]))
    #expect(RichText(stored: q.body).plain == "Is this spit up normal?")
    #expect(q.askedBy == "Bennett" && !q.isDone)

    clock.advance(minutes: 5)
    try store.setQuestionDone(id: q.id, done: true)
    try store.setQuestionDone(id: q.id, done: false)

    try store.updateQuestion(id: q.id, body: RichText(stored: q.body), answer: RichText(plain: "Totally normal"))
    let updated = try #require(store.questions().first)
    #expect(updated.isDone && updated.doneAt != nil)
    #expect(RichText(stored: updated.answer).plain == "Totally normal")

    try store.deleteQuestion(id: q.id)
    #expect(try store.questions().isEmpty)
    try store.restoreQuestion(updated)
    #expect(try store.questions().count == 1)
  }

  @Test("Rich text round-trips and merges runs; plain strings still read")
  func richText() {
    let text = RichText(runs: [RichRun("a"), RichRun("b"), RichRun("c", bold: true), RichRun("")])
    #expect(text.runs.count == 2)
    #expect(RichText(stored: text.stored) == text)
    #expect(RichText(stored: "just words").plain == "just words")
    #expect(RichText(stored: "[not json").plain == "[not json")
    #expect(RichText(plain: "  \n").isEmpty)
    #expect(RichText().stored == "")
  }
}


@Suite("Avatars", .serialized)
struct AvatarTests {
  @Test("Set, replace and remove a photo per subject")
  func lifecycle() throws {
    let clock = TestClock(t(10))
    let store = try makeStore(clock: clock)
    try store.createBaby(name: "Maddie", birthDate: nil, feedingMode: .mixed, unit: .ml)

    try store.setAvatar(subject: Avatar.babySubject, photo: Data([1, 2, 3]))
    try store.setAvatar(subject: Avatar.parentSubject("Yvette"), photo: Data([9]))
    clock.advance(minutes: 1)
    try store.setAvatar(subject: Avatar.babySubject, photo: Data([4, 5]))

    let all = try store.avatars()
    #expect(all.count == 2)
    #expect(all.first { $0.subject == Avatar.babySubject }?.photo == Data([4, 5]))

    try store.setAvatar(subject: Avatar.babySubject, photo: nil)
    #expect(try store.avatars().map(\.subject) == [Avatar.parentSubject("Yvette")])
  }
}

@Suite("Medications", .serialized)
struct MedicationStoreTests {
  private func makeMedication(_ store: LiveEventStore, at start: Date) throws -> Medication {
    var medication = try store.draftMedication()
    medication.name = "Vitamin D"
    medication.dose = "1 mL"
    medication.cadence = .fixedTimes
    medication.times = [20 * 60, 8 * 60]
    medication.startsAt = start
    try store.saveMedication(medication)
    return medication
  }

  @Test("Saved medicines keep their times, sorted, and show in the snapshot with their doses")
  func saveAndSnapshot() throws {
    let clock = TestClock(t(day: 3, 7))
    let store = try makeStore(clock: clock)
    try store.createBaby(name: "Maddie", birthDate: nil, feedingMode: .mixed, unit: .ml)
    let saved = try makeMedication(store, at: t(day: 1, 0))

    let loaded = try #require(store.medications().first)
    #expect(loaded.id == saved.id && loaded.times == [8 * 60, 20 * 60] && loaded.dose == "1 mL")

    try store.logDose(medicationID: saved.id, dueAt: nil, at: t(day: 3, 8, 5), skipped: false)
    let snapshot = try store.snapshot(now: clock.now)
    #expect(snapshot.medications.count == 1)
    #expect(snapshot.medicationDoses.count == 1)
  }

  @Test("Giving a dose settles the nearest due time; both parents tapping is one dose")
  func bothParentsTap() throws {
    let clock = TestClock(t(day: 3, 8, 10))
    let store = try makeStore(clock: clock)
    try store.createBaby(name: "Maddie", birthDate: nil, feedingMode: .mixed, unit: .ml)
    let medication = try makeMedication(store, at: t(day: 1, 0))
    let due = t(day: 3, 8)

    let first = try store.logDose(medicationID: medication.id, dueAt: due, at: t(day: 3, 8, 10), skipped: false)
    // The partner's phone, a few seconds later, answering the same reminder.
    let second = try store.logDose(medicationID: medication.id, dueAt: due, at: t(day: 3, 8, 11), skipped: false)
    #expect(first.id == second.id)
    #expect(try store.doses(since: .distantPast).count == 1)

    // A repeat tap from the app a moment later is the same dose.
    let repeatTap = try store.logDose(medicationID: medication.id, dueAt: nil, at: t(day: 3, 8, 11), skipped: false)
    #expect(repeatTap.id == first.id)

    // Ten minutes later is a real extra dose, which the app warns about before logging.
    let extra = try store.logDose(medicationID: medication.id, dueAt: nil, at: t(day: 3, 8, 20), skipped: false)
    #expect(extra.id != first.id && extra.dueAt == nil)

    // The evening dose settles the evening due time.
    let evening = try store.logDose(medicationID: medication.id, dueAt: nil, at: t(day: 3, 20, 5), skipped: false)
    #expect(evening.dueAt == t(day: 3, 20))
    #expect(try store.doses(since: .distantPast).count == 3)
  }

  @Test("A skipped dose is recorded and an extra dose has no due time")
  func skippedAndExtra() throws {
    let clock = TestClock(t(day: 3, 12))
    let store = try makeStore(clock: clock)
    try store.createBaby(name: "Maddie", birthDate: nil, feedingMode: .mixed, unit: .ml)
    let medication = try makeMedication(store, at: t(day: 1, 0))

    let skipped = try store.logDose(medicationID: medication.id, dueAt: t(day: 3, 8), at: t(day: 3, 9), skipped: true)
    #expect(skipped.skipped && skipped.dueAt == t(day: 3, 8))
    let extra = try store.logDose(medicationID: medication.id, dueAt: nil, at: t(day: 3, 14), skipped: false)
    #expect(extra.dueAt == nil)
  }

  @Test("Deleting a medicine deletes its doses; deleting the baby's data removes everything")
  func deleting() throws {
    let clock = TestClock(t(day: 3, 12))
    let store = try makeStore(clock: clock)
    try store.createBaby(name: "Maddie", birthDate: nil, feedingMode: .mixed, unit: .ml)
    let medication = try makeMedication(store, at: t(day: 1, 0))
    let dose = try store.logDose(medicationID: medication.id, dueAt: nil, at: t(day: 3, 8, 5), skipped: false)

    try store.deleteDose(id: dose.id)
    #expect(try store.doses(since: .distantPast).isEmpty)
    try store.logDose(medicationID: medication.id, dueAt: nil, at: t(day: 3, 8, 5), skipped: false)
    try store.deleteMedication(id: medication.id)
    #expect(try store.medications().isEmpty && (try store.doses(since: .distantPast)).isEmpty)
  }
}
