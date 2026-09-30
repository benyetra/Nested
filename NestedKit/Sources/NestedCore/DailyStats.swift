import Foundation

/// Per-day totals that feed every trend chart and the pediatrician report.
public struct DayStats: Hashable, Sendable, Identifiable {
  public var day: Date
  public var feedCount = 0
  public var bottleCount = 0
  public var bottleMl = 0.0
  public var nursingLeft: TimeInterval = 0
  public var nursingRight: TimeInterval = 0
  public var sleepTotal: TimeInterval = 0
  public var longestSleep: TimeInterval = 0
  public var wetCount = 0
  public var dirtyCount = 0
  public var pumpMl = 0.0
  public var stoolColors: [StoolColor] = []

  public var id: Date { day }

  public init(day: Date) { self.day = day }
}

public enum StatsRange: String, CaseIterable, Sendable, Hashable, Identifiable {
  case day = "24h"
  case week = "7d"
  case twoWeeks = "14d"
  case month = "30d"

  public var id: String { rawValue }
  public var days: Int {
    switch self {
    case .day: 1
    case .week: 7
    case .twoWeeks: 14
    case .month: 30
    }
  }
}

public enum DailyStatsBuilder {
  /// Totals for each calendar day from `days - 1` days ago through today. Sleep and
  /// nursing that cross midnight are split across the days they cover.
  public static func build(
    history: History,
    days: Int,
    now: Date,
    calendar: Calendar = .current
  ) -> [DayStats] {
    let today = calendar.startOfDay(for: now)
    let dayStarts: [Date] = (0..<max(1, days)).reversed().compactMap {
      calendar.date(byAdding: .day, value: -$0, to: today)
    }
    var byDay = Dictionary(uniqueKeysWithValues: dayStarts.map { ($0, DayStats(day: $0)) })

    func key(_ date: Date) -> Date? {
      let start = calendar.startOfDay(for: date)
      return byDay[start] == nil ? nil : start
    }

    for feed in history.feeds {
      guard let day = key(feed.startedAt) else { continue }
      byDay[day]!.feedCount += 1
      switch feed.kind {
      case .bottle(let ml, _):
        byDay[day]!.bottleCount += 1
        byDay[day]!.bottleMl += ml
      case .nursing(let left, let right, _):
        byDay[day]!.nursingLeft += left
        byDay[day]!.nursingRight += right
      }
    }

    for sleep in history.sleeps {
      let end = sleep.endedAt ?? now
      var cursor = sleep.startedAt
      while cursor < end {
        let dayStart = calendar.startOfDay(for: cursor)
        guard let next = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }
        let segmentEnd = min(end, next)
        if byDay[dayStart] != nil {
          byDay[dayStart]!.sleepTotal += segmentEnd.timeIntervalSince(cursor)
        }
        cursor = segmentEnd
      }
      // The longest stretch is credited whole to the day it ended on.
      if let day = key(end) {
        byDay[day]!.longestSleep = max(byDay[day]!.longestSleep, end.timeIntervalSince(sleep.startedAt))
      }
    }

    for diaper in history.diapers {
      guard let day = key(diaper.occurredAt) else { continue }
      if diaper.kind.isWet { byDay[day]!.wetCount += 1 }
      if diaper.kind.isDirty { byDay[day]!.dirtyCount += 1 }
      if let color = diaper.stoolColor { byDay[day]!.stoolColors.append(color) }
    }

    for pump in history.pumps where pump.endedAt != nil {
      guard let day = key(pump.startedAt) else { continue }
      byDay[day]!.pumpMl += pump.totalMl
    }

    return dayStarts.compactMap { byDay[$0] }
  }
}

/// Totals over a rolling window ending now (the Now screen's "last 24 h", the report).
public struct RollingTotals: Hashable, Sendable {
  public var feeds = 0
  public var bottleMl = 0.0
  public var nursing: TimeInterval = 0
  public var sleep: TimeInterval = 0
  public var wet = 0
  public var dirty = 0
  public var pumpMl = 0.0

  public init() {}

  public static func compute(history: History, since: Date, now: Date) -> RollingTotals {
    var totals = RollingTotals()
    let feeds = history.feeds.filter { $0.startedAt >= since && $0.startedAt <= now }
    totals.feeds = FeedPredictor.mergeClusters(feeds.map(\.startedAt)).count
    for feed in feeds {
      switch feed.kind {
      case .bottle(let ml, _): totals.bottleMl += ml
      case .nursing(let l, let r, _): totals.nursing += l + r
      }
    }
    for sleep in history.sleeps {
      let start = max(sleep.startedAt, since)
      let end = min(sleep.endedAt ?? now, now)
      if end > start { totals.sleep += end.timeIntervalSince(start) }
    }
    for diaper in history.diapers where diaper.occurredAt >= since && diaper.occurredAt <= now {
      if diaper.kind.isWet { totals.wet += 1 }
      if diaper.kind.isDirty { totals.dirty += 1 }
    }
    for pump in history.pumps where pump.startedAt >= since && pump.endedAt != nil {
      totals.pumpMl += pump.totalMl
    }
    return totals
  }
}

/// Pumped-milk stash: what went to the fridge/freezer, less what was fed from bottles of
/// breast milk since. A rough running inventory, never negative.
public struct StashInventory: Hashable, Sendable {
  public var fridgeMl: Double
  public var freezerMl: Double

  public static func compute(history: History, now: Date) -> StashInventory {
    // Fridge milk is good for about 4 days; count only recent fridge pumps.
    let fridgeCutoff = now.addingTimeInterval(-4 * 86_400)
    var fridge = history.pumps
      .filter { $0.destination == .fridge && $0.startedAt >= fridgeCutoff }
      .reduce(0) { $0 + $1.totalMl }
    var freezer = history.pumps
      .filter { $0.destination == .freezer }
      .reduce(0) { $0 + $1.totalMl }
    let fedFromStash = history.feeds
      .filter { $0.startedAt >= fridgeCutoff }
      .reduce(0.0) { total, feed in
        if case .bottle(let ml, let contents) = feed.kind, contents == .breastMilk {
          return total + ml
        }
        return total
      }
    let fromFridge = min(fridge, fedFromStash)
    fridge -= fromFridge
    freezer = max(0, freezer - (fedFromStash - fromFridge))
    return StashInventory(fridgeMl: fridge, freezerMl: freezer)
  }
}


/// Averages over whole days, for the report footer.
public struct DayAverages: Hashable, Sendable {
  public var days: Int
  public var feeds: Double
  public var bottleMl: Double
  public var nursing: TimeInterval
  public var sleep: TimeInterval
  public var wet: Double
  public var dirty: Double
}

extension DailyStatsBuilder {
  static func isEmpty(_ day: DayStats) -> Bool {
    day.feedCount == 0 && day.sleepTotal == 0 && day.wetCount == 0 && day.dirtyCount == 0
  }

  /// Drops the days before the baby was born (or, with no birth date, the empty days before the
  /// first entry) so a report doesn't open with rows of zeros. Always keeps at least today.
  public static func trimmed(_ stats: [DayStats], birth: Date?, calendar: Calendar = .current) -> [DayStats] {
    guard !stats.isEmpty else { return stats }
    let first: Int?
    if let birth {
      let birthDay = calendar.startOfDay(for: birth)
      first = stats.firstIndex { $0.day >= birthDay }
    } else {
      first = stats.firstIndex { !isEmpty($0) }
    }
    return Array(stats[(first ?? stats.count - 1)...])
  }

  /// Average per day over whole days only: today is still in progress and the birth day is
  /// partial, so neither counts. Nil until there are two whole days.
  public static func averages(_ stats: [DayStats], birth: Date?, calendar: Calendar = .current) -> DayAverages? {
    var whole = Array(stats.dropLast())
    if let birth, let first = whole.first, calendar.isDate(first.day, inSameDayAs: birth) {
      whole.removeFirst()
    }
    guard whole.count >= 2 else { return nil }
    let n = Double(whole.count)
    return DayAverages(
      days: whole.count,
      feeds: Double(whole.map(\.feedCount).reduce(0, +)) / n,
      bottleMl: whole.map(\.bottleMl).reduce(0, +) / n,
      nursing: whole.map { $0.nursingLeft + $0.nursingRight }.reduce(0, +) / n,
      sleep: whole.map(\.sleepTotal).reduce(0, +) / n,
      wet: Double(whole.map(\.wetCount).reduce(0, +)) / n,
      dirty: Double(whole.map(\.dirtyCount).reduce(0, +)) / n)
  }
}
