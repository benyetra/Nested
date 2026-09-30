import AppIntents
import Foundation
import NestedCore
import NestedData

// The shared action catalog (PRD "Quick-capture surfaces"). Every surface — widgets, controls,
// Siri, Spotlight, the Action button, Live Activities, alarms — runs these same intents.
//
// Write intents conform to `LiveActivityIntent` and are compiled into both the app and the
// widget extension, so the system runs them in the app's process where the sync engine lives
// and the change reaches the partner without opening the app.

#if os(iOS)
  typealias NestedWriteIntent = LiveActivityIntent
#else
  typealias NestedWriteIntent = AppIntent
#endif

extension IntentDialog {
  init(text: String) { self.init(stringLiteral: text) }
}

enum IntentText {
  static func time(_ date: Date) -> String {
    date.formatted(date: .omitted, time: .shortened)
  }
}

// MARK: - Bottle

struct LogBottleIntent: NestedWriteIntent {
  static let title: LocalizedStringResource = "Log Bottle"
  static let description = IntentDescription(
    "Logs a bottle. Without an amount, repeats the usual amount and contents.")
  static let openAppWhenRun = false

  @Parameter(title: "Amount")
  var amount: Double?

  @Parameter(title: "Unit")
  var unit: VolumeUnitOption?

  @Parameter(title: "Contents")
  var contents: BottleContentsOption?

  init() {}

  init(amountMl: Double?, contents: BottleContents?) {
    self.amount = amountMl
    self.unit = .ml
    self.contents = contents.flatMap { BottleContentsOption(rawValue: $0.rawValue) }
  }

  static var parameterSummary: some ParameterSummary {
    Summary("Log \(\.$amount) \(\.$unit) of \(\.$contents)")
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let store = try SharedStore.store
    let snapshot = try store.snapshot(now: Date())
    let displayUnit = snapshot.unit
    let ml: Double
    if let amount {
      ml = Volume.ml(from: amount, unit: unit?.unit ?? displayUnit)
    } else {
      ml = snapshot.defaultBottleMl ?? Volume.roundedMl(90, unit: displayUnit)
    }
    let chosen = contents?.contents ?? snapshot.defaultBottleContents
    try store.logBottle(
      amountMl: ml, contents: chosen, offeredMl: nil, formulaBrand: snapshot.baby?.formulaBrand,
      at: Date(), note: "", endSleep: true)
    return .result(
      dialog: IntentDialog(text: "Logged \(Volume.format(ml: ml, unit: displayUnit)) \(chosen.title.lowercased())"))
  }
}

// MARK: - Diaper

struct LogDiaperIntent: NestedWriteIntent {
  static let title: LocalizedStringResource = "Log Diaper"
  static let description = IntentDescription("Logs a diaper change.")
  static let openAppWhenRun = false

  @Parameter(title: "Type", default: .wet)
  var type: DiaperOption

  @Parameter(title: "Stool colour")
  var color: StoolColorOption?

  @Parameter(title: "Consistency")
  var consistency: ConsistencyOption?

  init() {}

  init(type: DiaperKind) {
    self.type = DiaperOption(rawValue: type.rawValue) ?? .wet
  }

  static var parameterSummary: some ParameterSummary {
    Summary("Log a \(\.$type) diaper") {
      \.$color
      \.$consistency
    }
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let store = try SharedStore.store
    try store.logDiaper(
      kind: type.kind, stoolColor: color?.color, consistency: consistency?.consistency, size: nil,
      rash: false, at: Date(), note: "")
    var text = "Logged a \(type.kind.title.lowercased()) diaper"
    let ageInDays = try store.baby()?.birthDate.map { AgeMath.days(from: $0, to: Date()) }
    if let color, color.color.isWorthACall(ageInDays: ageInDays) {
      text += ". \(color.color.title) stool: \(HealthFlag.callPediatrician.lowercased())"
    }
    return .result(dialog: IntentDialog(text: text))
  }
}

// MARK: - Nursing

struct StartNursingIntent: NestedWriteIntent {
  static let title: LocalizedStringResource = "Start Nursing"
  static let description = IntentDescription(
    "Starts a nursing timer, on the side opposite the last one unless you choose.")
  static let openAppWhenRun = false

  @Parameter(title: "Side", default: .auto)
  var side: SideOption

  init() {}
  init(side: Side?) { self.side = side.flatMap { SideOption(rawValue: $0.rawValue) } ?? .auto }

  static var parameterSummary: some ParameterSummary {
    Summary("Start nursing on \(\.$side)")
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let entry = try SharedStore.store.startNursing(side: side.side, at: Date(), endSleep: true)
    guard case .nursing(_, let segments) = entry else { return .result(dialog: "Started nursing") }
    let current = NursingMath.currentSide(segments) ?? .left
    return .result(dialog: IntentDialog(text: "Nursing on the \(current.title.lowercased())"))
  }
}

struct SwitchSideIntent: NestedWriteIntent {
  static let title: LocalizedStringResource = "Switch Nursing Side"
  static let description = IntentDescription("Closes the current side and starts the other.")
  static let openAppWhenRun = false

  init() {}

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let entry = try SharedStore.store.switchNursingSide(at: Date())
    guard case .nursing(_, let segments) = entry, let side = NursingMath.currentSide(segments) else {
      return .result(dialog: "Switched sides")
    }
    return .result(dialog: IntentDialog(text: "Switched to the \(side.title.lowercased())"))
  }
}

struct PauseNursingIntent: NestedWriteIntent {
  static let title: LocalizedStringResource = "Pause or Resume Nursing"
  static let openAppWhenRun = false

  init() {}

  @MainActor
  func perform() async throws -> some IntentResult {
    let store = try SharedStore.store
    if try store.snapshot(now: Date()).activeNursing?.isPaused == true {
      try store.resumeNursing(at: Date())
    } else {
      try store.pauseNursing(at: Date())
    }
    return .result()
  }
}

struct StopNursingIntent: NestedWriteIntent {
  static let title: LocalizedStringResource = "Stop Nursing"
  static let openAppWhenRun = false

  init() {}

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let entry = try SharedStore.store.stopNursing(at: Date(), latchNote: nil)
    return .result(dialog: IntentDialog(text: entry.title(unit: .ml)))
  }
}

// MARK: - Sleep

struct StartSleepIntent: NestedWriteIntent {
  static let title: LocalizedStringResource = "Start Sleep"
  static let description = IntentDescription("Starts a sleep timer.")
  static let openAppWhenRun = false

  @Parameter(title: "Location")
  var location: SleepLocationOption?

  init() {}

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    try SharedStore.store.startSleep(location: location?.location, at: Date())
    return .result(dialog: "Sleep timer started")
  }
}

struct EndSleepIntent: NestedWriteIntent {
  static let title: LocalizedStringResource = "End Sleep"
  static let description = IntentDescription("Ends the running sleep timer.")
  static let openAppWhenRun = false

  init() {}

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let entry = try SharedStore.store.stopSleep(at: Date())
    return .result(dialog: IntentDialog(text: entry.title(unit: .ml)))
  }
}

// MARK: - Pump

struct StartPumpIntent: NestedWriteIntent {
  static let title: LocalizedStringResource = "Start Pumping"
  static let openAppWhenRun = false

  init() {}

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    try SharedStore.store.startPump(at: Date())
    return .result(dialog: "Pumping timer started")
  }
}

struct EndPumpIntent: NestedWriteIntent {
  static let title: LocalizedStringResource = "End Pumping"
  static let openAppWhenRun = false

  @Parameter(title: "Left volume")
  var left: Double?

  @Parameter(title: "Right volume")
  var right: Double?

  @Parameter(title: "Unit")
  var unit: VolumeUnitOption?

  init() {}

  static var parameterSummary: some ParameterSummary {
    Summary("End pumping with \(\.$left) left and \(\.$right) right, in \(\.$unit)")
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let store = try SharedStore.store
    let displayUnit = try store.baby()?.unit ?? .ml
    let u = unit?.unit ?? displayUnit
    let leftMl = Volume.ml(from: left ?? 0, unit: u)
    let rightMl = Volume.ml(from: right ?? 0, unit: u)
    try store.stopPump(leftMl: leftMl, rightMl: rightMl, destination: nil, at: Date())
    return .result(
      dialog: IntentDialog(text: "Logged \(Volume.format(ml: leftMl + rightMl, unit: displayUnit)) pumped"))
  }
}

// MARK: - Any timer

struct StopActiveTimerIntent: NestedWriteIntent {
  static let title: LocalizedStringResource = "Stop Timer"
  static let description = IntentDescription("Ends whichever nursing, pumping or sleep timer is running.")
  static let openAppWhenRun = false

  init() {}

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let stopped = try SharedStore.store.stopActiveTimers(at: Date())
    guard !stopped.isEmpty else { return .result(dialog: "No timer is running") }
    return .result(dialog: IntentDialog(text: "Stopped " + stopped.map { $0.kind.title.lowercased() }.joined(separator: " and ")))
  }
}

// MARK: - Note

struct LogNoteIntent: NestedWriteIntent {
  static let title: LocalizedStringResource = "Log Note"
  static let openAppWhenRun = false

  @Parameter(title: "Note")
  var text: String

  init() {}

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    try SharedStore.store.logNote(text: text, tag: nil, at: Date())
    return .result(dialog: "Noted")
  }
}

// MARK: - Questions

struct LastFeedQueryIntent: AppIntent {
  static let title: LocalizedStringResource = "When Did She Last Eat?"
  static let description = IntentDescription("Says how long ago the last feed was, and which side or how much.")
  static let openAppWhenRun = false

  init() {}

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
    let snapshot = try SharedStore.store.snapshot(now: Date())
    let answer = Answers.lastFeed(snapshot.lastFeed, babyName: snapshot.babyName, unit: snapshot.unit, now: Date())
    return .result(value: answer, dialog: IntentDialog(text: answer))
  }
}

struct NextFeedQueryIntent: AppIntent {
  static let title: LocalizedStringResource = "When Is the Next Feed?"
  static let description = IntentDescription("Predicts the next feed from her recent pattern.")
  static let openAppWhenRun = false

  init() {}

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
    let snapshot = try SharedStore.store.snapshot(now: Date())
    let answer = Answers.nextFeed(snapshot.feedPrediction, babyName: snapshot.babyName, timeStyle: IntentText.time)
    return .result(value: answer, dialog: IntentDialog(text: answer))
  }
}

// MARK: - Feed alarm

struct SetFeedAlarmIntent: NestedWriteIntent {
  static let title: LocalizedStringResource = "Wake Us In…"
  static let description = IntentDescription("Sets the feed alarm on both phones.")
  static let openAppWhenRun = false

  @Parameter(title: "Hours", default: 3)
  var hours: Double

  init() {}
  init(hours: Double) { self.hours = hours }

  static var parameterSummary: some ParameterSummary {
    Summary("Wake us in \(\.$hours) hours")
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let fireAt = Date().addingTimeInterval(min(max(hours, 0.25), 8) * 3600)
    try SharedStore.store.setFeedAlarm(fireAt: fireAt, manual: true)
    return .result(dialog: IntentDialog(text: "Alarm set for \(IntentText.time(fireAt)) on both phones"))
  }
}

/// AlarmKit's stop button: marks the alarm handled so the partner's phone stops too.
struct StopFeedAlarmIntent: NestedWriteIntent {
  static let title: LocalizedStringResource = "Stop Feed Alarm"
  static let openAppWhenRun = false
  static let isDiscoverable = false

  @Parameter(title: "Alarm ID")
  var alarmID: String

  init() {}
  init(alarmID: UUID) { self.alarmID = alarmID.uuidString }

  @MainActor
  func perform() async throws -> some IntentResult {
    try SharedStore.store.handleFeedAlarm()
    return .result()
  }
}

/// AlarmKit's secondary button, "Feeding now": stops both alarms and starts a nursing timer on
/// the predicted side (bottle households get the bottle sheet instead).
struct FeedingNowIntent: NestedWriteIntent {
  static let title: LocalizedStringResource = "Feeding Now"
  static let openAppWhenRun = false
  static let isDiscoverable = false

  @Parameter(title: "Alarm ID")
  var alarmID: String

  init() {}
  init(alarmID: UUID) { self.alarmID = alarmID.uuidString }

  @MainActor
  func perform() async throws -> some IntentResult {
    let store = try SharedStore.store
    try store.handleFeedAlarm()
    if try store.baby()?.feedingMode != .bottle {
      try store.startNursing(side: nil, at: Date(), endSleep: true)
    }
    return .result()
  }
}

/// Optional secondary button: moves the shared alarm 10 minutes later on both phones.
struct SnoozeFeedAlarmIntent: NestedWriteIntent {
  static let title: LocalizedStringResource = "Snooze Feed Alarm"
  static let openAppWhenRun = false
  static let isDiscoverable = false

  @Parameter(title: "Alarm ID")
  var alarmID: String

  init() {}
  init(alarmID: UUID) { self.alarmID = alarmID.uuidString }

  @MainActor
  func perform() async throws -> some IntentResult {
    try SharedStore.store.setFeedAlarm(fireAt: Date().addingTimeInterval(10 * 60), manual: true)
    return .result()
  }
}

// MARK: - Control toggles

struct ToggleSleepIntent: SetValueIntent, NestedWriteIntent {
  static let title: LocalizedStringResource = "Nap"
  static let openAppWhenRun = false
  static let isDiscoverable = false

  @Parameter(title: "Asleep")
  var value: Bool

  init() {}

  @MainActor
  func perform() async throws -> some IntentResult {
    let store = try SharedStore.store
    if value {
      try store.startSleep(location: nil, at: Date())
    } else if try store.snapshot(now: Date()).activeSleep != nil {
      try store.stopSleep(at: Date())
    }
    return .result()
  }
}

struct ToggleNursingIntent: SetValueIntent, NestedWriteIntent {
  static let title: LocalizedStringResource = "Nursing"
  static let openAppWhenRun = false
  static let isDiscoverable = false

  @Parameter(title: "Nursing")
  var value: Bool

  init() {}

  @MainActor
  func perform() async throws -> some IntentResult {
    let store = try SharedStore.store
    if value {
      try store.startNursing(side: nil, at: Date(), endSleep: true)
    } else if try store.snapshot(now: Date()).activeNursing != nil {
      try store.stopNursing(at: Date(), latchNote: nil)
    }
    return .result()
  }
}
