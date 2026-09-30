import Foundation

/// Volumes are always stored in millilitres; this converts and rounds for display.
///
/// PRD: 1 oz = 29.57 ml, displayed rounded to 5 ml or 0.25 oz. Switching units never
/// touches stored data.
public enum Volume {
  public static let mlPerOunce = 29.57

  public static func ounces(fromMl ml: Double) -> Double { ml / mlPerOunce }
  public static func ml(fromOunces oz: Double) -> Double { oz * mlPerOunce }

  /// Converts a value typed in `unit` to stored millilitres.
  public static func ml(from value: Double, unit: VolumeUnit) -> Double {
    unit == .ml ? value : ml(fromOunces: value)
  }

  /// Converts stored millilitres to `unit` and rounds to that unit's display step.
  public static func displayValue(ml: Double, unit: VolumeUnit) -> Double {
    switch unit {
    case .ml: (ml / 5).rounded() * 5
    case .oz: (ounces(fromMl: ml) / 0.25).rounded() * 0.25
    }
  }

  /// Picker step for the unit.
  public static func step(for unit: VolumeUnit) -> Double { unit == .ml ? 5 : 0.25 }

  /// Rounds a stored millilitre amount so it lands exactly on a display step of `unit`.
  /// Used for defaults, so "repeat last bottle" shows a clean number.
  public static func roundedMl(_ ml: Double, unit: VolumeUnit) -> Double {
    Volume.ml(from: displayValue(ml: ml, unit: unit), unit: unit)
  }

  /// "90 ml", "3 oz", "2.75 oz".
  public static func format(ml: Double, unit: VolumeUnit) -> String {
    let value = displayValue(ml: ml, unit: unit)
    return "\(formatNumber(value)) \(unit.title)"
  }

  /// Spoken form: "90 millilitres", "3 ounces".
  public static func spoken(ml: Double, unit: VolumeUnit) -> String {
    let value = displayValue(ml: ml, unit: unit)
    let word: String
    switch unit {
    case .ml: word = "ml"
    case .oz: word = value == 1 ? "ounce" : "ounces"
    }
    return "\(formatNumber(value)) \(word)"
  }

  static func formatNumber(_ value: Double) -> String {
    if value == value.rounded() { return String(Int(value)) }
    var text = String(format: "%.2f", value)
    while text.hasSuffix("0") { text.removeLast() }
    return text
  }
}
