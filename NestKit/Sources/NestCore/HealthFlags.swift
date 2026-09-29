import Foundation

/// Editable thresholds for the "gentle flags". Defaults are AAP starting points
/// (HealthyChildren.org); parents can change or disable each.
public struct FlagThresholds: Hashable, Sendable, Codable {
  public var enabled: Bool
  public var minFeedsPer24h: Int
  public var minWetPer24h: Int
  public var maxGapDay: TimeInterval
  public var maxGapNight: TimeInterval

  public init(
    enabled: Bool = true,
    minFeedsPer24h: Int = 8,
    minWetPer24h: Int = 5,
    maxGapDay: TimeInterval = 3 * 3600,
    maxGapNight: TimeInterval = 4 * 3600
  ) {
    self.enabled = enabled
    self.minFeedsPer24h = minFeedsPer24h
    self.minWetPer24h = minWetPer24h
    self.maxGapDay = maxGapDay
    self.maxGapNight = maxGapNight
  }

  public static let `default` = FlagThresholds()
}

/// A pattern worth asking the pediatrician about. Wording is fixed and never diagnoses.
public struct HealthFlag: Hashable, Sendable, Identifiable {
  public enum Kind: String, Hashable, Sendable {
    case fewFeeds
    case fewWetDiapers
    case longGap
    case stoolColor
  }

  public var kind: Kind
  public var title: String
  public var detail: String
  public var id: Kind { kind }

  public static let callPediatrician = "Worth a call to your pediatrician."
}

public enum HealthFlagEvaluator {
  public static func evaluate(
    history: History,
    birthDate: Date?,
    now: Date,
    thresholds: FlagThresholds,
    night: DayWindow = .defaultNight,
    calendar: Calendar = .current
  ) -> [HealthFlag] {
    guard thresholds.enabled else { return [] }
    var flags: [HealthFlag] = []
    let dayAgo = now.addingTimeInterval(-86_400)
    let ageInDays = birthDate.map { AgeMath.days(from: $0, to: now, calendar: calendar) }

    // Only judge 24 h totals once there is 24 h of history, so day one doesn't nag.
    let earliest = [
      history.feeds.first?.startedAt,
      history.diapers.first?.occurredAt,
      history.sleeps.first?.startedAt,
    ].compactMap { $0 }.min()
    let hasFullDay = earliest.map { $0 <= dayAgo } ?? false

    if hasFullDay {
      let feeds = FeedPredictor.mergeClusters(
        history.feeds.map(\.startedAt).filter { $0 > dayAgo && $0 <= now }.sorted()
      ).count
      if feeds < thresholds.minFeedsPer24h {
        flags.append(
          HealthFlag(
            kind: .fewFeeds,
            title: "\(feeds) feed\(feeds == 1 ? "" : "s") in the last 24 h",
            detail: "Fewer than \(thresholds.minFeedsPer24h). \(HealthFlag.callPediatrician)"
          ))
      }

      if (ageInDays ?? 6) > 5 {
        let wet = history.diapers.filter { $0.occurredAt > dayAgo && $0.kind.isWet }.count
        if wet < thresholds.minWetPer24h {
          flags.append(
            HealthFlag(
              kind: .fewWetDiapers,
              title: "\(wet) wet diaper\(wet == 1 ? "" : "s") in the last 24 h",
              detail: "Fewer than \(thresholds.minWetPer24h). \(HealthFlag.callPediatrician)"
            ))
        }
      }
    }

    if let lastFeed = history.feeds.last?.startedAt {
      let gap = now.timeIntervalSince(lastFeed)
      let limit = night.contains(now, calendar: calendar) ? thresholds.maxGapNight : thresholds.maxGapDay
      if gap > limit {
        flags.append(
          HealthFlag(
            kind: .longGap,
            title: "\(Durations.format(gap)) since the last feed",
            detail: "Longer than your \(Durations.format(limit)) limit."
          ))
      }
    }

    // Stool colours in the last 48 h.
    let recentStools = history.diapers.filter {
      $0.occurredAt > now.addingTimeInterval(-2 * 86_400)
    }
    let flagged = recentStools.last { diaper in
      guard let color = diaper.stoolColor else { return false }
      let ageThen = birthDate.map {
        AgeMath.days(from: $0, to: diaper.occurredAt, calendar: calendar)
      }
      return color.isWorthACall(ageInDays: ageThen)
    }
    if let color = flagged?.stoolColor {
      flags.append(
        HealthFlag(
          kind: .stoolColor,
          title: "\(color.title) stool logged",
          detail: HealthFlag.callPediatrician
        ))
    }

    return flags
  }
}

public enum AgeMath {
  /// Whole days since birth, where the birth day is day 0.
  public static func days(from birth: Date, to date: Date, calendar: Calendar = .current) -> Int {
    let start = calendar.startOfDay(for: birth)
    let end = calendar.startOfDay(for: date)
    return max(0, calendar.dateComponents([.day], from: start, to: end).day ?? 0)
  }

  /// "Day 12", "3 weeks", "2 months"
  public static func label(birth: Date, now: Date, calendar: Calendar = .current) -> String {
    let days = Self.days(from: birth, to: now, calendar: calendar)
    if days < 14 { return "Day \(days)" }
    if days < 56 { return "\(days / 7) weeks" }
    let months = calendar.dateComponents([.month], from: birth, to: now).month ?? 0
    return "\(months) month\(months == 1 ? "" : "s")"
  }
}
