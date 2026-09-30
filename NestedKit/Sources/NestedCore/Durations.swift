import Foundation

/// Text for elapsed time. Live-ticking text on screen uses `Text(date, style:)`; these
/// are for fixed values (durations of finished entries, spoken answers, exports).
public enum Durations {
  /// "14 min", "2 h 10 min", "45 s".
  public static func format(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds.rounded()))
    if total < 60 { return "\(total) s" }
    let minutes = total / 60
    if minutes < 60 { return "\(minutes) min" }
    let hours = minutes / 60
    let rest = minutes % 60
    return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
  }

  /// "1h 52m", "14m" — for Lock Screen inline widgets.
  public static func compact(_ seconds: TimeInterval) -> String {
    let minutes = max(0, Int(seconds / 60))
    if minutes < 60 { return "\(minutes)m" }
    let rest = minutes % 60
    return rest == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(rest)m"
  }

  /// "2 hours 10 minutes" — for Siri.
  public static func spoken(_ seconds: TimeInterval) -> String {
    let minutes = max(0, Int((seconds / 60).rounded()))
    if minutes < 1 { return "less than a minute" }
    let hours = minutes / 60
    let rest = minutes % 60
    func unit(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
    if hours == 0 { return unit(rest, "minute") }
    if rest == 0 { return unit(hours, "hour") }
    return "\(unit(hours, "hour")) \(unit(rest, "minute"))"
  }

  /// "03:07" / "1:02:09" — monospaced timer readout for fixed durations.
  public static func clock(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds))
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    return h > 0
      ? String(format: "%d:%02d:%02d", h, m, s)
      : String(format: "%02d:%02d", m, s)
  }
}
