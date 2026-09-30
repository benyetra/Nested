import Foundation

@testable import NestedCore

/// UTC Gregorian calendar so fixtures are independent of the machine's time zone.
let utc: Calendar = {
  var c = Calendar(identifier: .gregorian)
  c.timeZone = TimeZone(identifier: "UTC")!
  return c
}()

/// 2026-09-20 00:00 UTC plus the given hours/minutes.
func t(day: Int = 20, _ hour: Int, _ minute: Int = 0) -> Date {
  utc.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
}

func bottle(_ date: Date, _ ml: Double = 90) -> FeedRecord {
  FeedRecord(startedAt: date, kind: .bottle(amountMl: ml, contents: .formula))
}

/// Feeds every `hours` from `start` for `count` feeds.
func regularFeeds(from start: Date, every hours: Double, count: Int) -> [Date] {
  (0..<count).map { start.addingTimeInterval(Double($0) * hours * 3600) }
}
