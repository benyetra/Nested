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
