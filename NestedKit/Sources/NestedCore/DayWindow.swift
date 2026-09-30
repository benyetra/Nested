import Foundation

/// A daily window in local wall-clock minutes (0..<1440) that may wrap past midnight,
/// e.g. the night window 20:00–07:00.
public struct DayWindow: Hashable, Sendable, Codable {
  public var startMinutes: Int
  public var endMinutes: Int

  public init(startMinutes: Int, endMinutes: Int) {
    self.startMinutes = Self.normalize(startMinutes)
    self.endMinutes = Self.normalize(endMinutes)
  }

  /// PRD default night-mode window.
  public static let defaultNight = DayWindow(startMinutes: 20 * 60, endMinutes: 7 * 60)
  /// PRD prediction "day": 07:00–19:00.
  public static let predictionDay = DayWindow(startMinutes: 7 * 60, endMinutes: 19 * 60)

  public var wrapsMidnight: Bool { startMinutes > endMinutes }

  public func contains(minuteOfDay minute: Int) -> Bool {
    let minute = Self.normalize(minute)
    if startMinutes == endMinutes { return false }
    return wrapsMidnight
      ? (minute >= startMinutes || minute < endMinutes)
      : (minute >= startMinutes && minute < endMinutes)
  }

  public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
    contains(minuteOfDay: Self.minuteOfDay(date, calendar: calendar))
  }

  public static func minuteOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
    let parts = calendar.dateComponents([.hour, .minute], from: date)
    return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
  }

  /// "20:00–07:00"
  public var label: String {
    func hhmm(_ m: Int) -> String { String(format: "%02d:%02d", m / 60, m % 60) }
    return "\(hhmm(startMinutes))–\(hhmm(endMinutes))"
  }

  static func normalize(_ minute: Int) -> Int { ((minute % 1440) + 1440) % 1440 }
}
