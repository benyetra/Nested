import Foundation

/// Spoken and short-form text shared by Siri, widgets and the Now screen.
public enum Answers {
  /// "She ate 2 hours 10 minutes ago, left side, 14 minutes."
  public static func lastFeed(
    _ feed: FeedRecord?,
    babyName: String,
    unit: VolumeUnit,
    now: Date
  ) -> String {
    guard let feed else { return "There are no feeds logged for \(babyName) yet." }
    let ago = Durations.spoken(now.timeIntervalSince(feed.startedAt))
    switch feed.kind {
    case .bottle(let ml, let contents):
      return "\(babyName) had \(Volume.spoken(ml: ml, unit: unit)) of \(contents.title.lowercased()) \(ago) ago."
    case .nursing(let left, let right, let endedOn):
      if feed.endedAt == nil {
        return "\(babyName) is nursing now, started \(ago) ago."
      }
      let side = endedOn.map { ", \($0.title.lowercased()) side" } ?? ""
      return "\(babyName) ate \(ago) ago\(side), \(Durations.spoken(left + right))."
    }
  }

  /// "Next feed around 2:40 AM, between 2:15 and 3:05."
  public static func nextFeed(
    _ prediction: FeedPrediction?,
    babyName: String,
    now: Date = Date(),
    timeStyle: (Date) -> String
  ) -> String {
    guard let prediction else {
      return "I need a few more feeds for \(babyName) before I can predict the next one."
    }
    switch prediction.phase(at: now) {
    case .due:
      return "\(babyName)'s next feed is due now. I expected it around \(timeStyle(prediction.expected)), \(prediction.basis)."
    case .overdue:
      return "\(babyName)'s next feed is overdue. I expected it around \(timeStyle(prediction.expected)), \(prediction.basis)."
    case .upcoming:
      break
    }
    return
      "Next feed around \(timeStyle(prediction.expected)), between \(timeStyle(prediction.earliest)) and \(timeStyle(prediction.latest)), \(prediction.basis)."
  }

  /// Short label for a feed: "90 ml formula", "Nursed 14 min · L".
  public static func feedSummary(_ feed: FeedRecord, unit: VolumeUnit) -> String {
    switch feed.kind {
    case .bottle(let ml, let contents):
      return "\(Volume.format(ml: ml, unit: unit)) \(contents.title.lowercased())"
    case .nursing(let left, let right, let endedOn):
      let side = endedOn.map { " · \($0.initial)" } ?? ""
      return "Nursed \(Durations.format(left + right))\(side)"
    }
  }
}

/// Numbers for the weekly summary card. Computed in code; the on-device model only phrases
/// them (see the app's SummaryService). `fallbackText` is used when no model is available.
public struct WeeklyDigest: Hashable, Sendable, Codable {
  public var feedsPerDay: Double
  public var nursingPerDay: Double
  public var nursingSecondsPerDay: TimeInterval
  public var bottlesPerDay: Double
  public var bottleMlPerDay: Double
  public var sleepPerDay: TimeInterval
  public var longestStretch: TimeInterval
  public var longestStretchChange: TimeInterval?
  public var wetPerDay: Double
  public var dirtyPerDay: Double

  /// Averages the last seven of the given days. Pass whole days (see `DailyStatsBuilder.wholeDays`).
  public static func compute(days: [DayStats], stretch: NightStretchTrend?) -> WeeklyDigest? {
    let week = days.suffix(7)
    guard !week.isEmpty else { return nil }
    let n = Double(week.count)
    let bottles = week.map(\.bottleCount).reduce(0, +)
    let feeds = week.map(\.feedCount).reduce(0, +)
    return WeeklyDigest(
      feedsPerDay: Double(feeds) / n,
      nursingPerDay: Double(max(0, feeds - bottles)) / n,
      nursingSecondsPerDay: week.map { $0.nursingLeft + $0.nursingRight }.reduce(0, +) / n,
      bottlesPerDay: Double(bottles) / n,
      bottleMlPerDay: week.map(\.bottleMl).reduce(0, +) / n,
      sleepPerDay: week.map(\.sleepTotal).reduce(0, +) / n,
      longestStretch: stretch?.longestThisWeek ?? week.map(\.longestSleep).max() ?? 0,
      longestStretchChange: stretch?.changeFromLastWeek,
      wetPerDay: Double(week.map(\.wetCount).reduce(0, +)) / n,
      dirtyPerDay: Double(week.map(\.dirtyCount).reduce(0, +)) / n
    )
  }

  /// A plain-language list of the facts, given to the model and used as the fallback.
  public func facts(babyName: String, unit: VolumeUnit) -> [String] {
    var facts = ["\(babyName) fed about \(String(format: "%.1f", feedsPerDay)) times a day."]
    if nursingSecondsPerDay > 0 {
      facts.append(
        "Most feeds were nursing: about \(String(format: "%.1f", nursingPerDay)) sessions and \(Durations.format(nursingSecondsPerDay)) a day in total."
      )
    }
    if bottlesPerDay > 0 {
      facts.append(
        "Bottles were the top-up: about \(String(format: "%.1f", bottlesPerDay)) a day, \(Volume.format(ml: bottleMlPerDay, unit: unit)) in total."
      )
    }
    facts += [
      "She slept about \(Durations.format(sleepPerDay)) a day.",
      "Her longest sleep stretch was \(Durations.format(longestStretch)).",
      String(format: "She had about %.1f wet and %.1f dirty diapers a day.", wetPerDay, dirtyPerDay),
    ]
    if let change = longestStretchChange, abs(change) >= 60 {
      facts.append(
        "The longest stretch is \(change > 0 ? "up" : "down") \(Durations.format(abs(change))) from last week."
      )
    }
    return facts
  }

  public func fallbackText(babyName: String, unit: VolumeUnit) -> String {
    let f = facts(babyName: babyName, unit: unit)
    return f.prefix(3).joined(separator: " ")
  }
}
