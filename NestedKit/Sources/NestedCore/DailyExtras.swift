import Foundation

/// Per-day measures that need the raw event times rather than totals.
public struct DayExtras: Hashable, Sendable, Identifiable {
  public var day: Date
  /// Mean time between feed clusters that started on this day; 0 with fewer than two.
  public var averageFeedGap: TimeInterval = 0
  public var longestFeedGap: TimeInterval = 0
  public var nightSleep: TimeInterval = 0
  public var daySleep: TimeInterval = 0

  public var id: Date { day }
  public init(day: Date) { self.day = day }
}

public enum DailyExtrasBuilder {
  /// One entry per given day start, in the same order.
  public static func build(
    history: History,
    days: [Date],
    now: Date,
    night: DayWindow = .defaultNight,
    calendar: Calendar = .current
  ) -> [DayExtras] {
    guard !days.isEmpty else { return [] }
    var byDay = Dictionary(uniqueKeysWithValues: days.map { ($0, DayExtras(day: $0)) })

    // Gaps between feeds, credited to the day the earlier feed started.
    let starts = FeedPredictor.mergeClusters(history.feeds.map(\.startedAt).sorted())
    var gaps: [Date: [TimeInterval]] = [:]
    for (a, b) in zip(starts, starts.dropFirst()) {
      let day = calendar.startOfDay(for: a)
      if byDay[day] != nil { gaps[day, default: []].append(b.timeIntervalSince(a)) }
    }
    for (day, values) in gaps {
      byDay[day]!.longestFeedGap = values.max() ?? 0
      byDay[day]!.averageFeedGap = values.reduce(0, +) / Double(values.count)
    }

    // Sleep split into five-minute slices, each counted as night or day by its start time.
    let slice: TimeInterval = 300
    for sleep in history.sleeps {
      let end = min(sleep.endedAt ?? now, now)
      var cursor = sleep.startedAt
      while cursor < end {
        let next = min(end, cursor.addingTimeInterval(slice))
        let day = calendar.startOfDay(for: cursor)
        if byDay[day] != nil {
          let length = next.timeIntervalSince(cursor)
          if night.contains(cursor, calendar: calendar) {
            byDay[day]!.nightSleep += length
          } else {
            byDay[day]!.daySleep += length
          }
        }
        cursor = next
      }
    }
    return days.compactMap { byDay[$0] }
  }
}
