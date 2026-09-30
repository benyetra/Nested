import Foundation

/// Household settings for the night feed alarm (PRD "Night feed alarm").
public struct AlarmSettings: Hashable, Sendable, Codable {
  public var interval: TimeInterval
  public var measuredFrom: AlarmMeasuredFrom
  public var autoArm: AlarmAutoArm
  public var whoRings: AlarmWhoRings
  /// For `.onePhone`: the owner name of the phone that rings.
  public var ringOwner: String?
  public var secondaryButton: AlarmSecondaryButton

  public init(
    interval: TimeInterval = 3 * 3600,
    measuredFrom: AlarmMeasuredFrom = .feedStart,
    autoArm: AlarmAutoArm = .nightOnly,
    whoRings: AlarmWhoRings = .bothPhones,
    ringOwner: String? = nil,
    secondaryButton: AlarmSecondaryButton = .feedingNow
  ) {
    self.interval = interval
    self.measuredFrom = measuredFrom
    self.autoArm = autoArm
    self.whoRings = whoRings
    self.ringOwner = ringOwner
    self.secondaryButton = secondaryButton
  }

  public static let `default` = AlarmSettings()

  /// Allowed intervals: 1½–4 h in 15-minute steps.
  public static let intervalOptions: [TimeInterval] = stride(from: 90, through: 240, by: 15)
    .map { Double($0) * 60 }

  /// "Wake us in…" chips.
  public static let manualChips: [TimeInterval] = [2, 2.5, 3, 3.5].map { $0 * 3600 }
}

public enum AlarmPlanner {
  /// When a feed should arm the alarm, or nil if auto-arm doesn't apply.
  ///
  /// Measured start-to-start by default. `.nightOnly` arms when the feed happens inside the
  /// night window. Never returns a time in the past.
  public static func autoArmFireDate(
    feedStartedAt: Date,
    feedEndedAt: Date?,
    settings: AlarmSettings,
    night: DayWindow,
    now: Date,
    calendar: Calendar = .current
  ) -> Date? {
    switch settings.autoArm {
    case .off:
      return nil
    case .nightOnly:
      guard night.contains(feedStartedAt, calendar: calendar) else { return nil }
    case .allDay:
      break
    }
    let anchor: Date
    switch settings.measuredFrom {
    case .feedStart: anchor = feedStartedAt
    // A running nursing timer has no end yet: arm from now and re-arm when it stops.
    case .feedEnd: anchor = feedEndedAt ?? max(now, feedStartedAt)
    }
    let fireAt = anchor.addingTimeInterval(settings.interval)
    return fireAt > now ? fireAt : nil
  }

  /// Whether this phone should ring for an alarm set by `setBy`.
  ///
  /// `.alternate` is shift mode: the parent who did not log the feed takes the next one.
  public static func shouldRing(
    settings: AlarmSettings,
    me: String,
    setBy: String
  ) -> Bool {
    switch settings.whoRings {
    case .bothPhones: true
    case .onePhone: settings.ringOwner.map { $0 == me } ?? true
    case .alternate: setBy != me
    }
  }
}
