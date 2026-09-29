import Foundation

// Predictions from the PRD's "Insights" section: plain statistics over the baby's own recent
// data, always a window, always saying what they are based on.

public enum Stats {
  public static func median(_ values: [Double]) -> Double? {
    quantile(values, 0.5)
  }

  /// Linear-interpolated quantile (type 7, same as numpy's default).
  public static func quantile(_ values: [Double], _ q: Double) -> Double? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let position = Double(sorted.count - 1) * min(max(q, 0), 1)
    let lower = Int(position.rounded(.down))
    let upper = Int(position.rounded(.up))
    let fraction = position - Double(lower)
    return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
  }
}

// MARK: - Next feed

public struct FeedPrediction: Hashable, Sendable {
  public var expected: Date
  public var earliest: Date
  public var latest: Date
  /// Number of intervals the estimate uses.
  public var basedOnCount: Int
  public var isNight: Bool

  /// "based on her last 12 night feeds"
  public var basis: String {
    "based on the last \(basedOnCount) \(isNight ? "night" : "daytime") feeds"
  }
}

public enum FeedPredictor {
  /// Feeds that start within this long of the previous one are treated as one feed
  /// (top-ups, switching from breast to bottle) so they don't drag the median down.
  public static let clusterGap: TimeInterval = 30 * 60
  public static let lookback: TimeInterval = 72 * 3600
  public static let minimumIntervals = 3

  /// Last feed start + median start-to-start interval over the last 72 h, split into day
  /// (07:00–19:00) and night; the window is the interquartile range.
  public static func predict(
    feedStarts: [Date],
    now: Date,
    calendar: Calendar = .current,
    day: DayWindow = .predictionDay
  ) -> FeedPrediction? {
    let starts = mergeClusters(
      feedStarts.filter { $0 <= now && $0 >= now.addingTimeInterval(-lookback) }.sorted()
    )
    guard let last = starts.last, starts.count >= 2 else { return nil }

    var dayIntervals: [Double] = []
    var nightIntervals: [Double] = []
    for (earlier, later) in zip(starts, starts.dropFirst()) {
      let interval = later.timeIntervalSince(earlier)
      if day.contains(earlier, calendar: calendar) {
        dayIntervals.append(interval)
      } else {
        nightIntervals.append(interval)
      }
    }

    let lastIsNight = !day.contains(last, calendar: calendar)
    var intervals = lastIsNight ? nightIntervals : dayIntervals
    if intervals.count < minimumIntervals {
      // Not enough of this period yet: fall back to every interval we have.
      intervals = dayIntervals + nightIntervals
    }
    guard
      let median = Stats.median(intervals),
      let q1 = Stats.quantile(intervals, 0.25),
      let q3 = Stats.quantile(intervals, 0.75)
    else { return nil }

    return FeedPrediction(
      expected: last.addingTimeInterval(median),
      earliest: last.addingTimeInterval(q1),
      latest: last.addingTimeInterval(q3),
      basedOnCount: intervals.count,
      isNight: lastIsNight
    )
  }

  static func mergeClusters(_ sortedStarts: [Date]) -> [Date] {
    var result: [Date] = []
    for start in sortedStarts {
      if let previous = result.last, start.timeIntervalSince(previous) < clusterGap { continue }
      result.append(start)
    }
    return result
  }
}

// MARK: - Nap window

public struct NapPrediction: Hashable, Sendable {
  public var awakeSince: Date
  public var opensAt: Date
  public var wakeWindow: TimeInterval
  /// 0...1 weight given to her own data (the rest is the age-based default).
  public var dataWeight: Double
  public var basedOnCount: Int

  public func progress(now: Date) -> Double {
    guard wakeWindow > 0 else { return 1 }
    return min(1, max(0, now.timeIntervalSince(awakeSince) / wakeWindow))
  }

  public var basis: String {
    if dataWeight >= 1 { return "based on her last \(basedOnCount) wake windows" }
    if dataWeight <= 0 { return "based on typical wake windows for her age" }
    return "blending her last \(basedOnCount) wake windows with her age's typical window"
  }
}

public enum NapPredictor {
  public static let lookbackDays = 5.0

  /// Typical newborn/infant wake windows by age, in minutes. Editable per baby in Settings.
  public static func ageDefaultWakeWindow(ageInDays: Int) -> TimeInterval {
    let minutes: Double
    switch ageInDays {
    case ..<28: minutes = 45
    case ..<56: minutes = 60
    case ..<90: minutes = 75
    case ..<120: minutes = 90
    case ..<180: minutes = 120
    case ..<270: minutes = 150
    case ..<365: minutes = 180
    default: minutes = 240
    }
    return minutes * 60
  }

  /// Last wake time + median wake window over the last 5 days, blended with the age
  /// default until 5 days of data exist: weight on her data = min(1, days of data ÷ 5).
  public static func predict(
    sleeps: [SleepRecord],
    ageInDays: Int,
    now: Date,
    defaultOverride: TimeInterval? = nil,
    calendar: Calendar = .current,
    day: DayWindow = .predictionDay
  ) -> NapPrediction? {
    let sorted = sleeps.sorted { $0.startedAt < $1.startedAt }
    // Asleep right now: no nap window to predict.
    if sorted.contains(where: { $0.endedAt == nil }) { return nil }
    guard let last = sorted.last, let awakeSince = last.endedAt else { return nil }

    let cutoff = now.addingTimeInterval(-lookbackDays * 86_400)
    let recent = sorted.filter { ($0.endedAt ?? now) >= cutoff }
    var windows: [Double] = []
    for (earlier, later) in zip(recent, recent.dropFirst()) {
      guard let wokeAt = earlier.endedAt, day.contains(wokeAt, calendar: calendar) else {
        continue
      }
      let window = later.startedAt.timeIntervalSince(wokeAt)
      // Ignore overlaps and implausible gaps (a missed log looks like a 7 h wake window).
      if window > 5 * 60 && window < 6 * 3600 { windows.append(window) }
    }

    let fallback = defaultOverride ?? ageDefaultWakeWindow(ageInDays: ageInDays)
    // "Days of data" is how long she has been tracked at all, not just the lookback.
    let daysOfData: Double
    if let first = sorted.first {
      daysOfData = max(0, now.timeIntervalSince(first.startedAt) / 86_400)
    } else {
      daysOfData = 0
    }
    let weight = windows.isEmpty ? 0 : min(1, daysOfData / lookbackDays)
    let own = Stats.median(windows) ?? fallback
    let blended = weight * own + (1 - weight) * fallback

    return NapPrediction(
      awakeSince: awakeSince,
      opensAt: awakeSince.addingTimeInterval(blended),
      wakeWindow: blended,
      dataWeight: weight,
      basedOnCount: windows.count
    )
  }
}

// MARK: - Night stretch

public struct NightStretch: Hashable, Sendable {
  /// Night keyed by the calendar day it started on.
  public var night: Date
  public var longest: TimeInterval
}

public struct NightStretchTrend: Hashable, Sendable {
  public var nights: [NightStretch]
  public var longestThisWeek: TimeInterval
  /// Mean longest stretch this week minus the previous week; nil without a previous week.
  public var changeFromLastWeek: TimeInterval?

  /// "Longest stretch 3 h 55 min, up 40 min this week"
  public var summary: String {
    var text = "Longest stretch \(Durations.format(longestThisWeek))"
    if let change = changeFromLastWeek, abs(change) >= 60 {
      text += ", \(change > 0 ? "up" : "down") \(Durations.format(abs(change))) this week"
    }
    return text
  }
}

public enum NightStretchAnalyzer {
  /// Longest sleep block per night for the last `nights` nights (a night is the night-mode
  /// window starting on that calendar day).
  public static func longestPerNight(
    sleeps: [SleepRecord],
    nights: Int,
    now: Date,
    window: DayWindow = .defaultNight,
    calendar: Calendar = .current
  ) -> [NightStretch] {
    let today = calendar.startOfDay(for: now)
    var result: [NightStretch] = []
    for offset in stride(from: nights, through: 1, by: -1) {
      guard
        let dayStart = calendar.date(byAdding: .day, value: -offset, to: today),
        let nightStart = calendar.date(byAdding: .minute, value: window.startMinutes, to: dayStart)
      else { continue }
      let lengthMinutes =
        window.wrapsMidnight
        ? (1440 - window.startMinutes + window.endMinutes)
        : (window.endMinutes - window.startMinutes)
      let nightEnd = nightStart.addingTimeInterval(Double(lengthMinutes) * 60)
      var longest: TimeInterval = 0
      for sleep in sleeps {
        let end = sleep.endedAt ?? now
        // A block counts for the night it overlaps; its full length is the stretch.
        if sleep.startedAt < nightEnd && end > nightStart {
          longest = max(longest, end.timeIntervalSince(sleep.startedAt))
        }
      }
      result.append(NightStretch(night: dayStart, longest: longest))
    }
    return result
  }

  public static func trend(
    sleeps: [SleepRecord],
    now: Date,
    window: DayWindow = .defaultNight,
    calendar: Calendar = .current
  ) -> NightStretchTrend? {
    let nights = longestPerNight(
      sleeps: sleeps, nights: 14, now: now, window: window, calendar: calendar)
    let thisWeek = nights.suffix(7).filter { $0.longest > 0 }
    let lastWeek = nights.prefix(7).filter { $0.longest > 0 }
    guard !thisWeek.isEmpty else { return nil }
    func mean(_ values: some Collection<NightStretch>) -> Double {
      values.map(\.longest).reduce(0, +) / Double(values.count)
    }
    return NightStretchTrend(
      nights: Array(nights.suffix(7)),
      longestThisWeek: thisWeek.map(\.longest).max() ?? 0,
      changeFromLastWeek: lastWeek.isEmpty ? nil : mean(thisWeek) - mean(lastWeek)
    )
  }
}

// MARK: - Next side

public enum SidePredictor {
  public static let shortSession: TimeInterval = 5 * 60

  /// Opposite of the side the last session ended on; if that session was under 5 min, the
  /// same side (she probably didn't empty it).
  public static func nextSide(endedOn: Side?, lastSessionDuration: TimeInterval?) -> Side {
    guard let endedOn else { return .left }
    if let duration = lastSessionDuration, duration < shortSession { return endedOn }
    return endedOn.opposite
  }
}

// MARK: - Bottle size

public enum BottlePredictor {
  /// Median finished amount of the last 5 bottles, rounded to the unit's display step.
  public static func defaultAmountMl(recentAmountsMl: [Double], unit: VolumeUnit) -> Double? {
    let lastFive = Array(recentAmountsMl.suffix(5)).filter { $0 > 0 }
    guard let median = Stats.median(lastFive) else { return nil }
    return Volume.roundedMl(median, unit: unit)
  }
}
