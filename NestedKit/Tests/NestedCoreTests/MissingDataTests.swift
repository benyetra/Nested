import Foundation
import Testing

@testable import NestedCore

@Suite("Missing data")
struct MissingDataTests {
  let now = t(day: 20, 12)

  func feed(_ date: Date) -> FeedRecord {
    FeedRecord(
      startedAt: date, endedAt: date.addingTimeInterval(900),
      kind: .nursing(leftSeconds: 600, rightSeconds: 300, endedOnSide: .right))
  }

  /// Feeds every three hours for a week, with `skip` hours removed.
  func steady(skipping skip: Set<Int> = []) -> [FeedRecord] {
    var out: [FeedRecord] = []
    for offset in 0..<(7 * 8) {
      let date = now.addingTimeInterval(-Double(offset) * 3 * 3600 - 3600)
      let hoursAgo = Int(now.timeIntervalSince(date) / 3600)
      if skip.contains(hoursAgo) { continue }
      out.append(feed(date))
    }
    return out
  }

  @Test("A regular log has nothing missing")
  func regular() {
    let found = MissingDataDetector.suggestions(history: History(feeds: steady()), now: now, calendar: utcCalendar)
    #expect(found.isEmpty)
  }

  @Test("A skipped feed is suggested halfway through the gap, with the usual nursing times")
  func skippedFeed() {
    // Feeds were at 1, 4, 7, 10 ... hours ago; drop the one 7 h ago.
    let found = MissingDataDetector.suggestions(history: History(feeds: steady(skipping: [7])), now: now, calendar: utcCalendar)
    #expect(found.count == 1)
    guard let one = found.first else { return }
    #expect(one.isFeed)
    #expect(one.at == now.addingTimeInterval(-7 * 3600))
    #expect(one.guess == .nursing(leftSeconds: 600, rightSeconds: 300))
  }

  @Test("A long sleep across the gap explains it")
  func sleepExplainsGap() {
    let sleep = SleepRecord(startedAt: now.addingTimeInterval(-10 * 3600), endedAt: now.addingTimeInterval(-4.2 * 3600))
    let found = MissingDataDetector.suggestions(
      history: History(feeds: steady(skipping: [7]), sleeps: [sleep]), now: now, calendar: utcCalendar)
    #expect(found.isEmpty)
  }

  @Test("Dismissed suggestions stay dismissed")
  func dismissed() {
    let history = History(feeds: steady(skipping: [7]))
    let first = MissingDataDetector.suggestions(history: history, now: now, calendar: utcCalendar)
    let again = MissingDataDetector.suggestions(
      history: history, now: now, dismissed: Set(first.map(\.id)), calendar: utcCalendar)
    #expect(again.isEmpty)
  }

  @Test("Too little history makes no guesses")
  func sparse() {
    let found = MissingDataDetector.suggestions(
      history: History(feeds: [feed(now.addingTimeInterval(-20_000)), feed(now.addingTimeInterval(-3600))]), now: now,
      calendar: utcCalendar)
    #expect(found.isEmpty)
  }
}

private let utcCalendar: Calendar = {
  var c = Calendar(identifier: .gregorian)
  c.timeZone = TimeZone(identifier: "UTC")!
  return c
}()
