import Foundation
import Testing

@testable import NestedCore

@Suite("Units")
struct VolumeTests {
  @Test func roundingAndFormatting() {
    #expect(Volume.format(ml: 88.7, unit: .ml) == "90 ml")
    #expect(Volume.format(ml: 88.7, unit: .oz) == "3 oz")
    #expect(Volume.format(ml: 81, unit: .oz) == "2.75 oz")
    #expect(Volume.displayValue(ml: 29.57, unit: .oz) == 1)
    #expect(Volume.spoken(ml: 29.57, unit: .oz) == "1 ounce")
  }

  @Test("Switching units never changes stored ml")
  func switchingIsDisplayOnly() {
    let stored = 120.0
    _ = Volume.format(ml: stored, unit: .oz)
    #expect(Volume.format(ml: stored, unit: .ml) == "120 ml")
    #expect(Volume.ml(from: 4, unit: .oz) == 4 * 29.57)
  }
}

@Suite("Durations and windows")
struct FormattingTests {
  @Test func durations() {
    #expect(Durations.format(14 * 60) == "14 min")
    #expect(Durations.format(130 * 60) == "2 h 10 min")
    #expect(Durations.compact(112 * 60) == "1h 52m")
    #expect(Durations.spoken(130 * 60) == "2 hours 10 minutes")
    #expect(Durations.clock(3 * 60 + 7) == "03:07")
  }

  @Test func nightWindowWrapsMidnight() {
    let night = DayWindow.defaultNight
    #expect(night.contains(minuteOfDay: 23 * 60))
    #expect(night.contains(minuteOfDay: 2 * 60))
    #expect(!night.contains(minuteOfDay: 7 * 60))
    #expect(!night.contains(minuteOfDay: 12 * 60))
    #expect(night.contains(t(22), calendar: utc))
  }
}

@Suite("Health flags")
struct HealthFlagTests {
  let birth = t(day: 1, 0)

  @Test("Stool colours: red, pale always; black only after day 7")
  func stoolBanner() {
    #expect(StoolColor.red.isWorthACall(ageInDays: 2))
    #expect(StoolColor.pale.isWorthACall(ageInDays: 2))
    #expect(!StoolColor.black.isWorthACall(ageInDays: 3))
    #expect(StoolColor.black.isWorthACall(ageInDays: 8))
    #expect(!StoolColor.mustardYellow.isWorthACall(ageInDays: 20))
  }

  @Test("Few feeds and few wet diapers after day 5")
  func counts() {
    let now = t(day: 20, 12)
    let history = History(
      feeds: regularFeeds(from: t(day: 19, 0), every: 4, count: 9).map { bottle($0) },
      diapers: [
        DiaperRecord(occurredAt: t(day: 19, 1), kind: .wet),
        DiaperRecord(occurredAt: t(day: 20, 1), kind: .wet),
      ]
    )
    let flags = HealthFlagEvaluator.evaluate(
      history: history, birthDate: birth, now: now, thresholds: .default, calendar: utc)
    #expect(flags.map(\.kind).contains(.fewFeeds))
    #expect(flags.map(\.kind).contains(.fewWetDiapers))
    #expect(flags.allSatisfy { !$0.detail.localizedCaseInsensitiveContains("has ") })
  }

  @Test("No count flags on the first day of data")
  func firstDay() {
    let history = History(feeds: [bottle(t(day: 20, 10))])
    let flags = HealthFlagEvaluator.evaluate(
      history: history, birthDate: birth, now: t(day: 20, 11), thresholds: .default, calendar: utc)
    #expect(flags.isEmpty)
  }

  @Test("Gap limit is 4 h at night, 3 h by day")
  func gap() {
    let dayHistory = History(feeds: [bottle(t(day: 20, 9))])
    let dayFlags = HealthFlagEvaluator.evaluate(
      history: dayHistory, birthDate: birth, now: t(day: 20, 12, 30), thresholds: .default,
      calendar: utc)
    #expect(dayFlags.map(\.kind) == [.longGap])

    let nightHistory = History(feeds: [bottle(t(day: 20, 22))])
    let nightFlags = HealthFlagEvaluator.evaluate(
      history: nightHistory, birthDate: birth, now: t(day: 21, 1, 30), thresholds: .default,
      calendar: utc)
    #expect(nightFlags.isEmpty)
  }

  @Test("Disabled thresholds produce nothing")
  func disabled() {
    var thresholds = FlagThresholds.default
    thresholds.enabled = false
    let history = History(diapers: [DiaperRecord(occurredAt: t(10), kind: .dirty, stoolColor: .red)])
    #expect(
      HealthFlagEvaluator.evaluate(
        history: history, birthDate: birth, now: t(11), thresholds: thresholds, calendar: utc
      ).isEmpty)
  }

  @Test("Red stool raises the call banner")
  func redStool() {
    let history = History(diapers: [DiaperRecord(occurredAt: t(10), kind: .dirty, stoolColor: .red)])
    let flags = HealthFlagEvaluator.evaluate(
      history: history, birthDate: birth, now: t(11), thresholds: .default, calendar: utc)
    #expect(flags.first?.kind == .stoolColor)
    #expect(flags.first?.detail == "Worth a call to your pediatrician.")
  }
}

@Suite("Night feed alarm rules")
struct AlarmPlannerTests {
  let night = DayWindow.defaultNight

  @Test("A feed at 11:40pm arms 2:40am")
  func arms() {
    let fire = AlarmPlanner.autoArmFireDate(
      feedStartedAt: t(23, 40), feedEndedAt: nil, settings: .default, night: night,
      now: t(23, 45), calendar: utc)
    #expect(fire == t(day: 21, 2, 40))
  }

  @Test("Daytime feeds don't auto-arm in night-only mode, but do in all-day")
  func daytime() {
    #expect(
      AlarmPlanner.autoArmFireDate(
        feedStartedAt: t(13), feedEndedAt: nil, settings: .default, night: night, now: t(13),
        calendar: utc) == nil)
    var allDay = AlarmSettings.default
    allDay.autoArm = .allDay
    #expect(
      AlarmPlanner.autoArmFireDate(
        feedStartedAt: t(13), feedEndedAt: nil, settings: allDay, night: night, now: t(13),
        calendar: utc) == t(16))
  }

  @Test("Measured from feed end")
  func fromEnd() {
    var settings = AlarmSettings.default
    settings.measuredFrom = .feedEnd
    #expect(
      AlarmPlanner.autoArmFireDate(
        feedStartedAt: t(23), feedEndedAt: t(23, 30), settings: settings, night: night,
        now: t(23, 31), calendar: utc) == t(day: 21, 2, 30))
  }

  @Test("Off never arms, past times never arm")
  func offAndPast() {
    var off = AlarmSettings.default
    off.autoArm = .off
    #expect(
      AlarmPlanner.autoArmFireDate(
        feedStartedAt: t(23), feedEndedAt: nil, settings: off, night: night, now: t(23),
        calendar: utc) == nil)
    #expect(
      AlarmPlanner.autoArmFireDate(
        feedStartedAt: t(day: 19, 23), feedEndedAt: nil, settings: .default, night: night,
        now: t(day: 20, 5), calendar: utc) == nil)
  }

  @Test("Who rings")
  func whoRings() {
    var s = AlarmSettings.default
    #expect(AlarmPlanner.shouldRing(settings: s, me: "Bennett", setBy: "Bennett"))
    s.whoRings = .onePhone
    s.ringOwner = "Yvette"
    #expect(!AlarmPlanner.shouldRing(settings: s, me: "Bennett", setBy: "Bennett"))
    #expect(AlarmPlanner.shouldRing(settings: s, me: "Yvette", setBy: "Bennett"))
    s.whoRings = .alternate
    #expect(!AlarmPlanner.shouldRing(settings: s, me: "Bennett", setBy: "Bennett"))
    #expect(AlarmPlanner.shouldRing(settings: s, me: "Yvette", setBy: "Bennett"))
  }

  @Test func intervalOptions() {
    #expect(AlarmSettings.intervalOptions.first == TimeInterval(90 * 60))
    #expect(AlarmSettings.intervalOptions.last == TimeInterval(4 * 3600))
    #expect(AlarmSettings.intervalOptions.count == 11)
  }
}

@Suite("Daily stats")
struct DailyStatsTests {
  @Test("Sleep across midnight is split between days")
  func sleepSplit() {
    let history = History(
      feeds: [bottle(t(day: 19, 10), 90), bottle(t(day: 20, 10), 120)],
      sleeps: [SleepRecord(startedAt: t(day: 19, 23), endedAt: t(day: 20, 2))],
      diapers: [DiaperRecord(occurredAt: t(day: 20, 8), kind: .mixed, stoolColor: .yellow)]
    )
    let days = DailyStatsBuilder.build(history: history, days: 2, now: t(day: 20, 12), calendar: utc)
    #expect(days.count == 2)
    #expect(days[0].sleepTotal == 3600)
    #expect(days[1].sleepTotal == 2 * 3600)
    #expect(days[1].longestSleep == 3 * 3600)
    #expect(days[0].bottleMl == 90)
    #expect(days[1].wetCount == 1 && days[1].dirtyCount == 1)
    #expect(days[1].stoolColors == [.yellow])
  }

  @Test func rollingTotals() {
    let history = History(
      feeds: [bottle(t(day: 19, 11)), bottle(t(day: 20, 1)), bottle(t(day: 20, 1, 10))],
      diapers: [DiaperRecord(occurredAt: t(day: 20, 2), kind: .wet)]
    )
    let totals = RollingTotals.compute(history: history, since: t(day: 19, 12), now: t(day: 20, 12))
    #expect(totals.feeds == 1)  // the two 1am feeds are one cluster
    #expect(totals.bottleMl == 180)
    #expect(totals.wet == 1)
  }

  @Test func stash() {
    let history = History(
      feeds: [FeedRecord(startedAt: t(12), kind: .bottle(amountMl: 60, contents: .breastMilk))],
      pumps: [
        PumpRecord(startedAt: t(8), endedAt: t(8, 20), leftMl: 50, rightMl: 50, destination: .fridge),
        PumpRecord(startedAt: t(9), endedAt: t(9, 20), leftMl: 100, rightMl: 0, destination: .freezer),
      ]
    )
    let stash = StashInventory.compute(history: history, now: t(13))
    #expect(stash.fridgeMl == 40)
    #expect(stash.freezerMl == 100)
  }
}

@Suite("CSV")
struct CSVTests {
  @Test func escaping() {
    let text = CSV.encode(header: ["a", "b"], rows: [["x, y", "say \"hi\"\nthere"]])
    #expect(CSV.parse(text) == [["a", "b"], ["x, y", "say \"hi\"\nthere"]])
  }

  @Test("Export rows round-trip through import")
  func roundTrip() throws {
    var bottleRow = EntryRow(kind: .bottle, startedAt: t(10), note: "Took it, slowly", loggedBy: "Bennett")
    bottleRow.amountMl = 90
    bottleRow.contents = .formula
    var diaperRow = EntryRow(kind: .diaper, startedAt: t(11), loggedBy: "Yvette")
    diaperRow.diaper = .dirty
    diaperRow.stoolColor = .mustardYellow
    diaperRow.rash = true
    let csv = CSV.encode(header: EntryRow.header, rows: [bottleRow.fields, diaperRow.fields])
    let parsed = try EntryRow.parse(csv: csv)
    #expect(parsed == [bottleRow, diaperRow])
  }

  @Test func importErrors() {
    #expect(throws: EntryRow.ImportError.missingHeader) { try EntryRow.parse(csv: "x,y\n1,2\n") }
    #expect(throws: EntryRow.ImportError.self) {
      try EntryRow.parse(csv: "type,started_at\nbottle,2026-09-20T10:00:00Z\n")
    }
  }
}

@Suite("Answers")
struct AnswerTests {
  @Test func lastFeedSpoken() {
    let feed = FeedRecord(
      startedAt: t(10), endedAt: t(10, 14),
      kind: .nursing(leftSeconds: 14 * 60, rightSeconds: 0, endedOnSide: .left))
    let text = Answers.lastFeed(feed, babyName: "Maddie", unit: .oz, now: t(12, 10))
    #expect(text == "Maddie ate 2 hours 10 minutes ago, left side, 14 minutes.")
    #expect(Answers.feedSummary(bottle(t(1), 90), unit: .ml) == "90 ml formula")
  }
}


@Suite("Report day ranges")
struct ReportRangeTests {
  private func days(_ counts: [(feeds: Int, wet: Int)]) -> [DayStats] {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let start = cal.date(from: DateComponents(year: 2026, month: 9, day: 20))!
    return counts.enumerated().map { offset, c in
      var day = DayStats(day: cal.date(byAdding: .day, value: offset, to: start)!)
      day.feedCount = c.feeds
      day.wetCount = c.wet
      return day
    }
  }

  private var utc: Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal
  }

  @Test("Days before birth are dropped; with no birth date, leading empty days are")
  func trimming() {
    // Sep 20…Sep 29; born on Sep 25.
    let stats = days([(0, 0), (0, 0), (0, 0), (0, 0), (0, 0), (1, 2), (7, 3), (11, 1), (8, 1), (8, 2)])
    let birth = utc.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 14))!
    #expect(DailyStatsBuilder.trimmed(stats, birth: birth, calendar: utc).count == 5)
    #expect(DailyStatsBuilder.trimmed(stats, birth: nil, calendar: utc).count == 5)
    #expect(DailyStatsBuilder.trimmed(days([(0, 0), (0, 0)]), birth: nil, calendar: utc).count == 1)
    #expect(DailyStatsBuilder.trimmed([], birth: nil, calendar: utc).isEmpty)
  }

  @Test("Averages skip today and the partial birth day")
  func averages() throws {
    let stats = days([(1, 2), (7, 3), (11, 1), (8, 1), (8, 2)])  // Sep 20…24; born Sep 20
    let birth = utc.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 9))!
    let avg = try #require(DailyStatsBuilder.averages(stats, birth: birth, calendar: utc))
    #expect(avg.days == 3)  // Sep 21, 22, 23
    let expectedFeeds: Double = 26.0 / 3.0
    #expect(abs(avg.feeds - expectedFeeds) < 0.0001)
    #expect(DailyStatsBuilder.averages(Array(stats.prefix(2)), birth: birth, calendar: utc) == nil)
  }
}

@Suite("Trend summaries")
struct TrendSummaryTests {
  private var utc: Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal
  }

  @Test("Whole days leave out today and the birth day")
  func wholeDays() {
    let start = utc.date(from: DateComponents(year: 2026, month: 9, day: 25))!
    let stats = (0..<5).map { DayStats(day: utc.date(byAdding: .day, value: $0, to: start)!) }
    let birth = utc.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 13))!
    let whole = DailyStatsBuilder.wholeDays(stats, birth: birth, calendar: utc)
    #expect(whole.count == 3)
    #expect(whole.first?.day == utc.date(byAdding: .day, value: 1, to: start))
  }

  @Test("The wet-diaper guide rises through day 4, then stays at six")
  func guide() {
    #expect([1, 2, 3, 4, 5, 6, 12].map { NewbornGuide.minimumWetDiapers(dayOfLife: $0) } == [1, 2, 3, 4, 6, 6, 6])
    let birth = utc.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 13))!
    let day3 = utc.date(from: DateComponents(year: 2026, month: 9, day: 27))!
    #expect(NewbornGuide.dayOfLife(birth, birth: birth, calendar: utc) == 1)
    #expect(NewbornGuide.dayOfLife(day3, birth: birth, calendar: utc) == 3)
  }

  @Test("The weekly digest speaks of nursing first and bottles as the top-up")
  func digest() throws {
    var a = DayStats(day: Date(timeIntervalSince1970: 0))
    a.feedCount = 9
    a.bottleCount = 1
    a.bottleMl = 35
    a.nursingLeft = 40 * 60
    a.nursingRight = 60 * 60
    var b = a
    b.day = Date(timeIntervalSince1970: 86_400)
    let digest = try #require(WeeklyDigest.compute(days: [a, b], stretch: nil))
    #expect(digest.nursingPerDay == 8 && digest.bottlesPerDay == 1)
    let facts = digest.facts(babyName: "Maddie", unit: .ml)
    #expect(facts[0].contains("9.0 times"))
    #expect(facts[1].contains("Most feeds were nursing"))
    #expect(facts[2].contains("top-up"))
    let none = try #require(WeeklyDigest.compute(days: [DayStats(day: Date())], stretch: nil))
    #expect(!none.facts(babyName: "Maddie", unit: .ml).joined().contains("top-up"))
  }
}

@Suite("Medication schedules")
struct MedicationScheduleTests {
  private var utc: Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal
  }

  private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    utc.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
  }

  private var twiceDaily: MedicationPlan {
    MedicationPlan(cadence: .fixedTimes, timesOfDay: [20 * 60, 8 * 60], startsAt: at(1, 0))
  }

  @Test("Fixed times list each day's doses in order, within the window")
  func fixedTimes() {
    let due = MedicationSchedule.occurrences(plan: twiceDaily, doses: [], from: at(3, 9), to: at(5, 9), calendar: utc)
    #expect(due == [at(3, 20), at(4, 8), at(4, 20), at(5, 8)])
  }

  @Test("A course only runs between its start and end")
  func bounds() {
    var plan = twiceDaily
    plan.startsAt = at(3, 12)
    plan.endsAt = at(4, 12)
    let due = MedicationSchedule.occurrences(plan: plan, doses: [], from: at(3, 0), to: at(6, 0), calendar: utc)
    #expect(due == [at(3, 20), at(4, 8)])
    plan.isActive = false
    #expect(MedicationSchedule.occurrences(plan: plan, doses: [], from: at(3, 0), to: at(6, 0), calendar: utc).isEmpty)
  }

  @Test("A logged dose settles its due time, whichever phone logged it")
  func handled() {
    let doses = [DoseRecord(dueAt: at(3, 20), takenAt: at(3, 20, 7))]
    let pending = MedicationSchedule.pending(plan: twiceDaily, doses: doses, from: at(3, 19), within: 14 * 3600, calendar: utc)
    #expect(pending == [at(4, 8)])
    // An unlinked dose given near a due time also settles it.
    let loose = [DoseRecord(dueAt: nil, takenAt: at(4, 7, 30))]
    #expect(MedicationSchedule.isHandled(at(4, 8), doses: loose))
    #expect(!MedicationSchedule.isHandled(at(4, 20), doses: loose))
  }

  @Test("A dose given near a due time is linked to it; an extra dose is not")
  func linking() {
    #expect(MedicationSchedule.dueToSettle(takenAt: at(4, 9), plan: twiceDaily, doses: [], calendar: utc) == at(4, 8))
    #expect(MedicationSchedule.dueToSettle(takenAt: at(4, 14), plan: twiceDaily, doses: [], calendar: utc) == nil)
  }

  @Test("Every-N-hours counts from the last dose, and only the next one is known")
  func rolling() {
    let plan = MedicationPlan(cadence: .everyHours, intervalMinutes: 360, startsAt: at(3, 6))
    #expect(MedicationSchedule.pending(plan: plan, doses: [], from: at(3, 0), within: 86_400, calendar: utc) == [at(3, 6)])
    let doses = [DoseRecord(dueAt: at(3, 6), takenAt: at(3, 6, 40))]
    #expect(MedicationSchedule.pending(plan: plan, doses: doses, from: at(3, 7), within: 86_400, calendar: utc) == [at(3, 12, 40)])
  }

  @Test("Status: upcoming, due, overdue, then given")
  func status() {
    let upcoming = MedicationSchedule.status(plan: twiceDaily, doses: [], now: at(4, 7), calendar: utc)
    #expect(upcoming == .upcoming(at(4, 8)))
    #expect(MedicationSchedule.status(plan: twiceDaily, doses: [], now: at(4, 8, 20), calendar: utc) == .due(since: at(4, 8)))
    #expect(MedicationSchedule.status(plan: twiceDaily, doses: [], now: at(4, 10), calendar: utc) == .overdue(since: at(4, 8)))
    let given = [DoseRecord(dueAt: at(4, 8), takenAt: at(4, 8, 5))]
    #expect(MedicationSchedule.status(plan: twiceDaily, doses: given, now: at(4, 10), calendar: utc) == .upcoming(at(4, 20)))
    // Six hours past, a missed dose stops nagging.
    #expect(MedicationSchedule.status(plan: twiceDaily, doses: [], now: at(4, 15), calendar: utc) == .upcoming(at(4, 20)))
  }

  @Test("As-needed medicines wait out their minimum gap")
  func asNeeded() {
    let plan = MedicationPlan(cadence: .asNeeded, intervalMinutes: 360, startsAt: at(1, 0))
    let doses = [DoseRecord(dueAt: nil, takenAt: at(4, 9))]
    #expect(MedicationSchedule.status(plan: plan, doses: doses, now: at(4, 11), calendar: utc) == .asNeeded(lastGiven: at(4, 9), okAfter: at(4, 15)))
    #expect(MedicationSchedule.status(plan: plan, doses: doses, now: at(4, 16), calendar: utc) == .asNeeded(lastGiven: at(4, 9), okAfter: nil))
    #expect(MedicationSchedule.status(plan: plan, doses: [], now: at(4, 16), calendar: utc) == .asNeeded(lastGiven: nil, okAfter: nil))
  }

  @Test("Cadence wording")
  func wording() {
    let style: (Int) -> String = { "\($0 / 60):\(String(format: "%02d", $0 % 60))" }
    #expect(MedicationSchedule.cadenceSummary(twiceDaily, timeStyle: style) == "Daily at 8:00, 20:00")
    #expect(MedicationSchedule.cadenceSummary(MedicationPlan(cadence: .everyHours, intervalMinutes: 360, startsAt: at(1, 0)), timeStyle: style) == "Every 6 hours")
    #expect(MedicationSchedule.cadenceSummary(MedicationPlan(cadence: .asNeeded, startsAt: at(1, 0)), timeStyle: style) == "As needed")
  }
}
