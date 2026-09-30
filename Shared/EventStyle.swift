import NestedCore
import SwiftUI

/// One semantic colour per event type, used on every surface: buttons, timeline, charts,
/// widgets and Live Activities.
extension EventKind {
  var color: Color {
    switch self {
    case .bottle: Color(red: 0.27, green: 0.56, blue: 0.98)  // blue
    case .nursing: Color(red: 0.69, green: 0.45, blue: 0.95)  // purple
    case .pump: Color(red: 0.19, green: 0.72, blue: 0.72)  // teal
    case .diaper: Color(red: 0.96, green: 0.68, blue: 0.20)  // amber
    case .sleep: Color(red: 0.42, green: 0.45, blue: 0.93)  // indigo
    case .note: Color(red: 0.60, green: 0.62, blue: 0.66)  // gray
    }
  }
}

extension StoolColor {
  var swatch: Color { Color(red: rgb.red, green: rgb.green, blue: rgb.blue) }
}

/// Red-shifted palette for night mode: no pure white, nothing bright.
enum NightPalette {
  /// Multiplied over the whole UI in night mode, so even system chrome turns dim red.
  static let multiply = Color(red: 1.0, green: 0.42, blue: 0.36)
  static let accent = Color(red: 0.86, green: 0.30, blue: 0.24)
}

extension Font {
  /// SF Pro Rounded for the big status numbers.
  static func status(_ style: Font.TextStyle = .title) -> Font {
    .system(style, design: .rounded).weight(.semibold)
  }
}

/// Deep links used by widgets and Lock Screen taps to open a log sheet.
enum NestedLink {
  static let scheme = "nested"

  static func log(_ kind: EventKind) -> URL {
    URL(string: "\(scheme)://log/\(kind.rawValue)")!
  }

  static let now = URL(string: "\(scheme)://now")!
  static let trends = URL(string: "\(scheme)://trends")!

  static func kind(from url: URL) -> EventKind? {
    guard url.scheme == scheme, url.host == "log" else { return nil }
    return EventKind(rawValue: url.lastPathComponent)
  }
}
