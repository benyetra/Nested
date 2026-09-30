import AppIntents
import NestedCore

// App Intents parameter types. Display representations must be literal so the App Intents
// metadata processor can read them at build time.

enum VolumeUnitOption: String, AppEnum {
  case ml
  case oz

  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Unit"
  static let caseDisplayRepresentations: [VolumeUnitOption: DisplayRepresentation] = [
    .ml: "millilitres",
    .oz: "ounces",
  ]

  var unit: VolumeUnit { self == .ml ? .ml : .oz }
}

enum BottleContentsOption: String, AppEnum {
  case breastMilk
  case formula
  case mixed

  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Bottle contents"
  static let caseDisplayRepresentations: [BottleContentsOption: DisplayRepresentation] = [
    .breastMilk: "breast milk",
    .formula: "formula",
    .mixed: "mixed",
  ]

  var contents: BottleContents { BottleContents(rawValue: rawValue) ?? .formula }
}

enum DiaperOption: String, AppEnum {
  case wet
  case dirty
  case mixed
  case dry

  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Diaper"
  static let caseDisplayRepresentations: [DiaperOption: DisplayRepresentation] = [
    .wet: DisplayRepresentation(title: "wet", image: .init(systemName: "drop")),
    .dirty: DisplayRepresentation(title: "dirty", image: .init(systemName: "circle.fill")),
    .mixed: DisplayRepresentation(title: "wet and dirty", image: .init(systemName: "drop.circle")),
    .dry: DisplayRepresentation(title: "dry", image: .init(systemName: "sun.max")),
  ]

  var kind: DiaperKind { DiaperKind(rawValue: rawValue) ?? .wet }
}

enum StoolColorOption: String, AppEnum {
  case black
  case darkGreen
  case green
  case mustardYellow
  case yellow
  case brown
  case orange
  case red
  case pale

  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Stool colour"
  static let caseDisplayRepresentations: [StoolColorOption: DisplayRepresentation] = [
    .black: "black",
    .darkGreen: "dark green",
    .green: "green",
    .mustardYellow: "mustard yellow",
    .yellow: "yellow",
    .brown: "brown",
    .orange: "orange",
    .red: "red",
    .pale: "white or pale gray",
  ]

  var color: StoolColor { StoolColor(rawValue: rawValue) ?? .yellow }
}

enum ConsistencyOption: String, AppEnum {
  case runny
  case seedy
  case pasty
  case formed
  case hard
  case mucousy

  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Consistency"
  static let caseDisplayRepresentations: [ConsistencyOption: DisplayRepresentation] = [
    .runny: "runny",
    .seedy: "seedy",
    .pasty: "pasty",
    .formed: "formed",
    .hard: "hard",
    .mucousy: "mucousy",
  ]

  var consistency: StoolConsistency { StoolConsistency(rawValue: rawValue) ?? .seedy }
}

enum SideOption: String, AppEnum {
  case auto
  case left
  case right

  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Side"
  static let caseDisplayRepresentations: [SideOption: DisplayRepresentation] = [
    .auto: "the next side",
    .left: "the left",
    .right: "the right",
  ]

  var side: Side? {
    switch self {
    case .auto: nil
    case .left: .left
    case .right: .right
    }
  }
}

enum SleepLocationOption: String, AppEnum {
  case crib
  case bassinet
  case arms
  case stroller
  case car

  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Sleep location"
  static let caseDisplayRepresentations: [SleepLocationOption: DisplayRepresentation] = [
    .crib: "crib",
    .bassinet: "bassinet",
    .arms: "arms",
    .stroller: "stroller",
    .car: "car",
  ]

  var location: SleepLocation { SleepLocation(rawValue: rawValue) ?? .crib }
}
