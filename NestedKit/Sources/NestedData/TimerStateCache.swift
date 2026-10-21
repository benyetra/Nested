import Foundation

/// The running timers as last known, kept in the App Group's defaults so a Lock Screen control
/// can show the right state at once. Reading the database from a widget process can be slow or
/// fail, and a control that guesses "off" looks like the tap did nothing.
public enum TimerStateCache {
  public struct State: Codable, Equatable, Sendable {
    public var nursingStart: Date?
    public var sleepStart: Date?
    public var updatedAt: Date
  }

  private static let key = "timerStateCache"

  public static func write(nursingStart: Date?, sleepStart: Date?, now: Date = Date()) {
    let state = State(nursingStart: nursingStart, sleepStart: sleepStart, updatedAt: now)
    if let data = try? JSONEncoder().encode(state) { DevicePrefs.defaults.set(data, forKey: key) }
  }

  public static func read() -> State? {
    guard let data = DevicePrefs.defaults.data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(State.self, from: data)
  }

  /// What a control should show. A write in the last few seconds is newer than anything a
  /// database read from another process can be trusted to have seen yet; otherwise the database
  /// wins, and the cache stands in only if the database can't be read.
  public static func resolve(
    cached: State?, database: (nursingStart: Date?, sleepStart: Date?)?, now: Date = Date(),
    freshFor: TimeInterval = 10
  ) -> (nursingStart: Date?, sleepStart: Date?) {
    if let cached, now.timeIntervalSince(cached.updatedAt) <= freshFor {
      return (cached.nursingStart, cached.sleepStart)
    }
    if let database { return database }
    if let cached { return (cached.nursingStart, cached.sleepStart) }
    return (nil, nil)
  }
}
