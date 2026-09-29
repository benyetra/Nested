import Foundation

/// A breast side for nursing and pumping.
public enum Side: String, Codable, Sendable, CaseIterable, Hashable {
  case left
  case right

  public var opposite: Side { self == .left ? .right : .left }
  public var title: String { self == .left ? "Left" : "Right" }
  public var initial: String { self == .left ? "L" : "R" }
}

public enum BottleContents: String, Codable, Sendable, CaseIterable, Hashable {
  case breastMilk
  case formula
  case mixed

  public var title: String {
    switch self {
    case .breastMilk: "Breast milk"
    case .formula: "Formula"
    case .mixed: "Mixed"
    }
  }
}

public enum DiaperKind: String, Codable, Sendable, CaseIterable, Hashable {
  case wet
  case dirty
  case mixed
  case dry

  public var title: String {
    switch self {
    case .wet: "Wet"
    case .dirty: "Dirty"
    case .mixed: "Wet + dirty"
    case .dry: "Dry"
    }
  }

  /// Counts toward the wet-diaper total.
  public var isWet: Bool { self == .wet || self == .mixed }
  /// Counts toward the dirty-diaper total.
  public var isDirty: Bool { self == .dirty || self == .mixed }
  /// Stool fields only apply when there is stool.
  public var hasStool: Bool { isDirty }
}

/// Stool colour swatches from the PRD's palette, in display order.
public enum StoolColor: String, Codable, Sendable, CaseIterable, Hashable {
  case black
  case darkGreen
  case green
  case mustardYellow
  case yellow
  case brown
  case orange
  case red
  case pale

  public var title: String {
    switch self {
    case .black: "Black"
    case .darkGreen: "Dark green"
    case .green: "Green"
    case .mustardYellow: "Mustard"
    case .yellow: "Yellow"
    case .brown: "Brown"
    case .orange: "Orange"
    case .red: "Red"
    case .pale: "White / pale gray"
    }
  }

  /// sRGB swatch, 0...1 components. Kept in Core so every surface draws the same colour.
  public var rgb: (red: Double, green: Double, blue: Double) {
    switch self {
    case .black: (0.10, 0.09, 0.08)
    case .darkGreen: (0.20, 0.30, 0.13)
    case .green: (0.40, 0.55, 0.20)
    case .mustardYellow: (0.83, 0.65, 0.16)
    case .yellow: (0.95, 0.83, 0.30)
    case .brown: (0.47, 0.31, 0.17)
    case .orange: (0.91, 0.52, 0.18)
    case .red: (0.78, 0.15, 0.15)
    case .pale: (0.86, 0.86, 0.83)
    }
  }

  /// Red, white/pale gray, and black after the first week are worth raising with the
  /// pediatrician (AAP / HealthyChildren.org). Meconium is expected in the first days.
  public func isWorthACall(ageInDays: Int?) -> Bool {
    switch self {
    case .red, .pale: true
    case .black: (ageInDays ?? 8) > 7
    default: false
    }
  }
}

public enum StoolConsistency: String, Codable, Sendable, CaseIterable, Hashable {
  case runny
  case seedy
  case pasty
  case formed
  case hard
  case mucousy

  public var title: String {
    switch self {
    case .runny: "Runny"
    case .seedy: "Seedy"
    case .pasty: "Pasty"
    case .formed: "Formed"
    case .hard: "Hard"
    case .mucousy: "Mucousy"
    }
  }
}

public enum DiaperSize: String, Codable, Sendable, CaseIterable, Hashable {
  case small
  case medium
  case large

  public var title: String {
    switch self {
    case .small: "S"
    case .medium: "M"
    case .large: "L"
    }
  }
}

public enum SleepLocation: String, Codable, Sendable, CaseIterable, Hashable {
  case crib
  case bassinet
  case arms
  case stroller
  case car

  public var title: String {
    switch self {
    case .crib: "Crib"
    case .bassinet: "Bassinet"
    case .arms: "Arms"
    case .stroller: "Stroller"
    case .car: "Car"
    }
  }
}

public enum NoteTag: String, Codable, Sendable, CaseIterable, Hashable {
  case spitUp
  case fussy
  case medicine
  case temperature

  public var title: String {
    switch self {
    case .spitUp: "Spit-up"
    case .fussy: "Fussy"
    case .medicine: "Medicine"
    case .temperature: "Temperature"
    }
  }
}

public enum PumpDestination: String, Codable, Sendable, CaseIterable, Hashable {
  case fedNow
  case fridge
  case freezer

  public var title: String {
    switch self {
    case .fedNow: "Fed now"
    case .fridge: "Fridge"
    case .freezer: "Freezer"
    }
  }
}

public enum FeedingMode: String, Codable, Sendable, CaseIterable, Hashable {
  case nursing
  case bottle
  case mixed

  public var title: String {
    switch self {
    case .nursing: "Nursing"
    case .bottle: "Bottle"
    case .mixed: "Nursing + bottle"
    }
  }
}

public enum VolumeUnit: String, Codable, Sendable, CaseIterable, Hashable {
  case ml
  case oz

  public var title: String { self == .ml ? "ml" : "oz" }
}

/// Every loggable event type. Colour and symbol live in the app's design layer.
public enum EventKind: String, Codable, Sendable, CaseIterable, Hashable {
  case bottle
  case nursing
  case pump
  case diaper
  case sleep
  case note

  public var title: String {
    switch self {
    case .bottle: "Bottle"
    case .nursing: "Nursing"
    case .pump: "Pump"
    case .diaper: "Diaper"
    case .sleep: "Sleep"
    case .note: "Note"
    }
  }

  /// SF Symbol name used on every surface.
  public var symbol: String {
    switch self {
    case .bottle: "waterbottle.fill"
    case .nursing: "heart.fill"
    case .pump: "drop.halffull"
    case .diaper: "drop.fill"
    case .sleep: "moon.zzz.fill"
    case .note: "note.text"
    }
  }

  public var isTimer: Bool { self == .nursing || self == .pump || self == .sleep }
}

public enum AlarmAutoArm: String, Codable, Sendable, CaseIterable, Hashable {
  case nightOnly
  case allDay
  case off

  public var title: String {
    switch self {
    case .nightOnly: "Night only"
    case .allDay: "All day"
    case .off: "Off"
    }
  }
}

public enum AlarmMeasuredFrom: String, Codable, Sendable, CaseIterable, Hashable {
  case feedStart
  case feedEnd

  public var title: String { self == .feedStart ? "Feed start" : "Feed end" }
}

public enum AlarmWhoRings: String, Codable, Sendable, CaseIterable, Hashable {
  case bothPhones
  case onePhone
  case alternate

  public var title: String {
    switch self {
    case .bothPhones: "Both phones"
    case .onePhone: "Only one phone"
    case .alternate: "Alternate (shift mode)"
    }
  }
}

public enum AlarmSecondaryButton: String, Codable, Sendable, CaseIterable, Hashable {
  case feedingNow
  case snooze

  public var title: String { self == .feedingNow ? "Feeding now" : "Snooze 10 min" }
}

public enum NightModeSetting: String, Codable, Sendable, CaseIterable, Hashable {
  case automatic
  case alwaysOn
  case off

  public var title: String {
    switch self {
    case .automatic: "On a schedule"
    case .alwaysOn: "Always"
    case .off: "Off"
    }
  }
}
