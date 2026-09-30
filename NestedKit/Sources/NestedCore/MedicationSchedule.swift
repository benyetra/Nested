import Foundation

/// How often a medicine is taken.
public enum MedicationCadence: String, Codable, Sendable, CaseIterable, Hashable {
  /// At set times of day, every day ("8:00 AM and 8:00 PM").
  case fixedTimes
  /// A set number of hours after the last dose ("every 6 hours"). Each dose given moves the next.
  case everyHours
  /// No reminders; the log remembers when it was last given, and an optional minimum gap.
  case asNeeded

  public var title: String {
    switch self {
    case .fixedTimes: "At set times each day"
    case .everyHours: "Every few hours"
    case .asNeeded: "Only when needed"
    }
  }
}

/// The schedule part of a medicine, as plain values.
public struct MedicationPlan: Hashable, Sendable {
  public var cadence: MedicationCadence
  /// Minutes after midnight, for `.fixedTimes`.
  public var timesOfDay: [Int]
  /// Minutes between doses for `.everyHours`; the minimum gap for `.asNeeded` (0 for none).
  public var intervalMinutes: Int
  /// When the course begins. The first dose is due no earlier than this.
  public var startsAt: Date
  public var endsAt: Date?
  public var isActive: Bool

  public init(
    cadence: MedicationCadence, timesOfDay: [Int] = [], intervalMinutes: Int = 0, startsAt: Date,
    endsAt: Date? = nil, isActive: Bool = true
  ) {
    self.cadence = cadence
    self.timesOfDay = Array(Set(timesOfDay)).sorted()
    self.intervalMinutes = intervalMinutes
    self.startsAt = startsAt
    self.endsAt = endsAt
    self.isActive = isActive
  }
}

/// A logged dose: given (possibly for a particular due time) or deliberately skipped.
public struct DoseRecord: Hashable, Sendable {
  public var dueAt: Date?
  public var takenAt: Date
  public var skipped: Bool

  public init(dueAt: Date?, takenAt: Date, skipped: Bool = false) {
    self.dueAt = dueAt
    self.takenAt = takenAt
    self.skipped = skipped
  }
}

public enum MedicationStatus: Hashable, Sendable {
  case inactive
  /// Nothing to do until `Date`.
  case upcoming(Date)
  /// Due within the last hour.
  case due(since: Date)
  /// More than an hour past due (and less than six).
  case overdue(since: Date)
  /// As needed: when it was last given, and when the minimum gap ends (nil if not waiting).
  case asNeeded(lastGiven: Date?, okAfter: Date?)
  case finished
}

public enum MedicationSchedule {
  /// A dose this close to a due time counts for it.
  static let matchWindow: TimeInterval = 60
  /// Giving a dose within this long of a due time, before or after, settles that due time.
  public static let linkWindow: TimeInterval = 2 * 3600
  /// How long a due dose stays "due" before "overdue".
  public static let dueWindow: TimeInterval = 3600
  /// After this long, a missed dose stops asking for attention.
  public static let missedAfter: TimeInterval = 6 * 3600

  /// Every time the plan asks for a dose in `[from, to]` (ignoring what's been logged).
  public static func occurrences(
    plan: MedicationPlan, doses: [DoseRecord], from: Date, to: Date, calendar: Calendar = .current
  ) -> [Date] {
    guard plan.isActive, to >= from else { return [] }
    switch plan.cadence {
    case .asNeeded:
      return []
    case .fixedTimes:
      var result: [Date] = []
      var day = calendar.startOfDay(for: from)
      let lastDay = calendar.startOfDay(for: to)
      while day <= lastDay {
        for minutes in plan.timesOfDay {
          guard
            let due = calendar.date(byAdding: .minute, value: minutes, to: day),
            due >= from, due <= to, due >= plan.startsAt, due <= (plan.endsAt ?? .distantFuture)
          else { continue }
          result.append(due)
        }
        guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
        day = next
      }
      return result
    case .everyHours:
      guard plan.intervalMinutes > 0 else { return [] }
      let next: Date
      if let last = doses.map(\.takenAt).max() {
        next = last.addingTimeInterval(TimeInterval(plan.intervalMinutes * 60))
      } else {
        next = plan.startsAt
      }
      // Only the next dose is knowable: each one given moves the one after it.
      guard next <= (plan.endsAt ?? .distantFuture) else { return [] }
      return next >= from && next <= to ? [next] : []
    }
  }

  /// Whether a logged dose already covers a due time.
  public static func isHandled(_ due: Date, doses: [DoseRecord]) -> Bool {
    doses.contains { dose in
      if let dueAt = dose.dueAt { return abs(dueAt.timeIntervalSince(due)) < matchWindow }
      return abs(dose.takenAt.timeIntervalSince(due)) <= linkWindow
    }
  }

  /// Due times still waiting for a dose, from now on.
  public static func pending(
    plan: MedicationPlan, doses: [DoseRecord], from now: Date, within window: TimeInterval,
    calendar: Calendar = .current
  ) -> [Date] {
    occurrences(plan: plan, doses: doses, from: now, to: now.addingTimeInterval(window), calendar: calendar)
      .filter { !isHandled($0, doses: doses) }
  }

  /// The due time that a dose given at `takenAt` should settle: the nearest unhandled one within
  /// two hours either way. Nil if it's an extra dose.
  public static func dueToSettle(
    takenAt: Date, plan: MedicationPlan, doses: [DoseRecord], calendar: Calendar = .current
  ) -> Date? {
    occurrences(
      plan: plan, doses: doses, from: takenAt.addingTimeInterval(-linkWindow),
      to: takenAt.addingTimeInterval(linkWindow), calendar: calendar
    )
    .filter { !isHandled($0, doses: doses) }
    .min { abs($0.timeIntervalSince(takenAt)) < abs($1.timeIntervalSince(takenAt)) }
  }

  public static func status(
    plan: MedicationPlan, doses: [DoseRecord], now: Date, calendar: Calendar = .current
  ) -> MedicationStatus {
    guard plan.isActive else { return .inactive }
    if plan.cadence == .asNeeded {
      let last = doses.filter { !$0.skipped }.map(\.takenAt).max()
      let okAfter = last.flatMap { last -> Date? in
        let ends = last.addingTimeInterval(TimeInterval(plan.intervalMinutes * 60))
        return plan.intervalMinutes > 0 && ends > now ? ends : nil
      }
      return .asNeeded(lastGiven: last, okAfter: okAfter)
    }
    if let endsAt = plan.endsAt, now > endsAt.addingTimeInterval(missedAfter),
      pending(plan: plan, doses: doses, from: now, within: 86_400, calendar: calendar).isEmpty
    {
      return .finished
    }
    // A dose that has come due and is still unanswered, most recent first.
    let recent = occurrences(
      plan: plan, doses: doses, from: now.addingTimeInterval(-missedAfter), to: now, calendar: calendar
    )
    .filter { !isHandled($0, doses: doses) }
    if let due = recent.last {
      let late = now.timeIntervalSince(due)
      return late <= dueWindow ? .due(since: due) : .overdue(since: due)
    }
    let upcoming = pending(plan: plan, doses: doses, from: now, within: 14 * 86_400, calendar: calendar)
    if let next = upcoming.first { return .upcoming(next) }
    return plan.endsAt.map { now > $0 } == true ? .finished : .upcoming(now.addingTimeInterval(86_400))
  }

  // MARK: Wording

  /// "8:00 AM, 8:00 PM" for fixed times; "Every 6 hours"; "As needed".
  public static func cadenceSummary(_ plan: MedicationPlan, timeStyle: (Int) -> String) -> String {
    switch plan.cadence {
    case .fixedTimes:
      plan.timesOfDay.isEmpty ? "No times set" : "Daily at " + plan.timesOfDay.map(timeStyle).joined(separator: ", ")
    case .everyHours:
      plan.intervalMinutes % 60 == 0
        ? "Every \(plan.intervalMinutes / 60) hour\(plan.intervalMinutes == 60 ? "" : "s")"
        : "Every \(plan.intervalMinutes) min"
    case .asNeeded:
      plan.intervalMinutes > 0
        ? "As needed, at least \(plan.intervalMinutes / 60) h apart" : "As needed"
    }
  }
}
