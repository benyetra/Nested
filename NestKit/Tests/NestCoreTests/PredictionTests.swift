import Foundation
import Testing

@testable import NestCore

@Suite("Next feed prediction")
struct FeedPredictionTests {
  @Test("Regular 3 h pattern predicts 3 h after the last feed with a tight window")
  func regular() throws {
    let starts = regularFeeds(from: t(day: 18, 0), every: 3, count: 24)
    let last = starts.last!
    let now = last.addingTimeInterval(30 * 60)
    let prediction = try #require(FeedPredictor.predict(feedStarts: starts, now: now, calendar: utc))
    #expect(prediction.expected == last.addingTimeInterval(3 * 3600))
    #expect(prediction.earliest == prediction.expected)
    #expect(prediction.latest == prediction.expected)
  }

  @Test("Night and day intervals are kept separate")
  func dayNightSplit() throws {
    // Daytime feeds every 2 h (07–19), night feeds every 4 h.
    var starts: [Date] = []
    for day in 18...19 {
      starts += regularFeeds(from: t(day: day, 7), every: 2, count: 7)  // 7..19
      starts += [t(day: day, 23), t(day: day + 1, 3)]
    }
    // Last feed at 03:00 on the 20th (night).
    let now = t(day: 20, 3, 10)
    let prediction = try #require(FeedPredictor.predict(feedStarts: starts, now: now, calendar: utc))
    #expect(prediction.isNight)
    #expect(prediction.expected == t(day: 20, 7))

    // A daytime last feed predicts ~2 h.
    let dayStarts = starts.filter { $0 <= t(day: 19, 13) }
    let dayPrediction = try #require(
      FeedPredictor.predict(feedStarts: dayStarts, now: t(day: 19, 13, 5), calendar: utc))
    #expect(!dayPrediction.isNight)
    #expect(dayPrediction.expected == t(day: 19, 15))
  }

  @Test("Cluster feeding: starts within 30 min merge into one feed")
  func clusterFeeding() throws {
    var starts = regularFeeds(from: t(day: 19, 8), every: 3, count: 6)
    // Evening cluster: 3 extra top-ups 15 min after each of the last three feeds.
    starts += starts.suffix(3).map { $0.addingTimeInterval(15 * 60) }
    let now = t(day: 19, 23, 30)
    let prediction = try #require(FeedPredictor.predict(feedStarts: starts, now: now, calendar: utc))
    #expect(prediction.expected == t(day: 20, 2))
  }

  @Test("Growth spurt: shorter recent intervals widen the window")
  func growthSpurt() throws {
    var starts = regularFeeds(from: t(day: 18, 7), every: 3, count: 5)  // 7..19
    starts += regularFeeds(from: t(day: 19, 7), every: 1.5, count: 8)  // 7..17:30
    let now = t(day: 19, 18)
    let prediction = try #require(FeedPredictor.predict(feedStarts: starts, now: now, calendar: utc))
    // Mostly 1.5 h recent intervals: the median follows them, the window stretches later.
    #expect(prediction.earliest <= prediction.expected)
    #expect(prediction.latest > prediction.expected)
    let hours = prediction.expected.timeIntervalSince(t(day: 19, 17, 30)) / 3600
    #expect(hours >= 1.5 && hours <= 3)
  }

  @Test("Missing data: fewer than two feeds gives no prediction")
  func missingData() {
    #expect(FeedPredictor.predict(feedStarts: [], now: t(12), calendar: utc) == nil)
    #expect(FeedPredictor.predict(feedStarts: [t(10)], now: t(12), calendar: utc) == nil)
  }

  @Test("Feeds older than 72 h are ignored")
  func lookback() {
    let old = regularFeeds(from: t(day: 10, 0), every: 3, count: 10)
    #expect(FeedPredictor.predict(feedStarts: old, now: t(day: 20, 0), calendar: utc) == nil)
  }

  @Test("Quantiles interpolate linearly")
  func quantiles() {
    #expect(Stats.median([1, 2, 3, 4]) == 2.5)
    #expect(Stats.quantile([1, 2, 3, 4, 5], 0.25) == 2)
    #expect(Stats.quantile([10], 0.75) == 10)
  }
}

@Suite("Nap window")
struct NapPredictionTests {
  @Test("No sleep data uses the age default")
  func ageDefault() throws {
    let sleeps = [SleepRecord(startedAt: t(9), endedAt: t(10))]
    let p = try #require(NapPredictor.predict(sleeps: sleeps, ageInDays: 10, now: t(10, 5), calendar: utc))
    #expect(p.dataWeight == 0)
    #expect(p.opensAt == t(10, 45))
  }

  @Test("Five days of data uses her own median fully")
  func ownData() throws {
    var sleeps: [SleepRecord] = []
    for day in 15...20 {
      // Wake windows of 90 min: sleep 9–10, 11:30–12:30, 14–15.
      sleeps += [
        SleepRecord(startedAt: t(day: day, 9), endedAt: t(day: day, 10)),
        SleepRecord(startedAt: t(day: day, 11, 30), endedAt: t(day: day, 12, 30)),
        SleepRecord(startedAt: t(day: day, 14), endedAt: t(day: day, 15)),
      ]
    }
    let p = try #require(
      NapPredictor.predict(sleeps: sleeps, ageInDays: 10, now: t(day: 20, 15, 10), calendar: utc))
    #expect(p.dataWeight == 1)
    #expect(p.wakeWindow == 90 * 60)
    #expect(p.opensAt == t(day: 20, 16, 30))
  }

  @Test("Blending: weight = days of data ÷ 5")
  func blending() throws {
    // 2.5 days of data with 105-min windows; age default 45 min.
    let sleeps = [
      SleepRecord(startedAt: t(day: 18, 12), endedAt: t(day: 18, 13)),
      SleepRecord(startedAt: t(day: 18, 14, 45), endedAt: t(day: 18, 15, 30)),
      SleepRecord(startedAt: t(day: 20, 9), endedAt: t(day: 20, 10)),
    ]
    let now = t(day: 20, 24)  // 2.5 days after the first sleep
    let p = try #require(NapPredictor.predict(sleeps: sleeps, ageInDays: 10, now: now, calendar: utc))
    #expect(abs(p.dataWeight - 0.5) < 0.001)
    #expect(abs(p.wakeWindow - (0.5 * 105 + 0.5 * 45) * 60) < 1)
  }

  @Test("Asleep now: no nap window")
  func asleep() {
    let sleeps = [SleepRecord(startedAt: t(9))]
    #expect(NapPredictor.predict(sleeps: sleeps, ageInDays: 10, now: t(10), calendar: utc) == nil)
  }
}

@Suite("Next side, bottle size, night stretch")
struct SmallPredictionTests {
  @Test func nextSide() {
    #expect(SidePredictor.nextSide(endedOn: nil, lastSessionDuration: nil) == .left)
    #expect(SidePredictor.nextSide(endedOn: .left, lastSessionDuration: 900) == .right)
    #expect(SidePredictor.nextSide(endedOn: .left, lastSessionDuration: 120) == .left)
  }

  @Test func bottleSize() {
    #expect(BottlePredictor.defaultAmountMl(recentAmountsMl: [], unit: .ml) == nil)
    #expect(BottlePredictor.defaultAmountMl(recentAmountsMl: [60, 90, 88, 92, 120, 30], unit: .ml) == 90)
    let oz = BottlePredictor.defaultAmountMl(recentAmountsMl: [88, 90, 89], unit: .oz)!
    #expect(Volume.displayValue(ml: oz, unit: .oz) == 3)
  }

  @Test func nightStretchTrend() throws {
    var sleeps: [SleepRecord] = []
    // Previous week: 3 h longest; this week: 4 h longest.
    for day in 6...12 {
      sleeps.append(SleepRecord(startedAt: t(day: day, 22), endedAt: t(day: day, 25)))
    }
    for day in 13...19 {
      sleeps.append(SleepRecord(startedAt: t(day: day, 22), endedAt: t(day: day, 26)))
    }
    let trend = try #require(NightStretchAnalyzer.trend(sleeps: sleeps, now: t(day: 20, 12), calendar: utc))
    #expect(trend.longestThisWeek == 4 * 3600)
    #expect(trend.changeFromLastWeek == 3600)
    #expect(trend.summary == "Longest stretch 4 h, up 1 h this week")
  }
}


@Suite("Feed prediction phases")
struct FeedPhaseTests {
  private let prediction = FeedPrediction(
    expected: Date(timeIntervalSince1970: 10_000), earliest: Date(timeIntervalSince1970: 9_000),
    latest: Date(timeIntervalSince1970: 11_000), basedOnCount: 12, isNight: false)
  private let style: (Date) -> String = { "t\(Int($0.timeIntervalSince1970))" }

  @Test("Upcoming, due and overdue never show a passed time")
  func phases() {
    #expect(prediction.phase(at: Date(timeIntervalSince1970: 8_000)) == .upcoming)
    #expect(prediction.phase(at: Date(timeIntervalSince1970: 9_000)) == .due)
    #expect(prediction.phase(at: Date(timeIntervalSince1970: 11_000)) == .due)
    #expect(prediction.phase(at: Date(timeIntervalSince1970: 11_001)) == .overdue)

    #expect(prediction.shortLabel(now: Date(timeIntervalSince1970: 8_000), timeStyle: style) == "Next feed ~t10000")
    #expect(prediction.shortLabel(now: Date(timeIntervalSince1970: 10_000), timeStyle: style) == "Feed due now")
    #expect(prediction.shortLabel(now: Date(timeIntervalSince1970: 20_000), timeStyle: style) == "Feed overdue")
  }

  @Test("Spoken answers say overdue instead of a past time")
  func spoken() {
    let late = Answers.nextFeed(prediction, babyName: "Maddie", now: Date(timeIntervalSince1970: 20_000), timeStyle: style)
    #expect(late.contains("overdue") && !late.hasPrefix("Next feed around"))
    let early = Answers.nextFeed(prediction, babyName: "Maddie", now: Date(timeIntervalSince1970: 1), timeStyle: style)
    #expect(early.hasPrefix("Next feed around t10000"))
  }
}
