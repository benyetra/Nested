import Foundation

/// A day's sleep and feeding targets by age, written by the parents (for example from a sleep
/// book or the pediatrician's advice). Nested ships only a generic starting point; the numbers
/// are theirs to set per stage.
public struct SleepPlan: Codable, Hashable, Sendable {
  public struct Stage: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    /// First week of age this stage applies from, counted from the due date if she was early.
    public var fromWeek: Int
    /// Morning wake-up, in minutes after midnight.
    public var wakeMinute: Int
    /// Start of night sleep; nil leaves bedtime unscheduled.
    public var bedMinute: Int?
    /// Nap start times, in minutes after midnight.
    public var napMinutes: [Int]
    /// Target length of each nap in minutes; 0 for none set.
    public var napLength: Int
    /// Longest she should be awake between sleeps, in minutes; 0 for none set.
    public var wakeWindow: Int
    /// Feed interval in minutes through the day; 0 for none set.
    public var feedEvery: Int

    public init(
      id: UUID = UUID(), fromWeek: Int, wakeMinute: Int = 7 * 60, bedMinute: Int? = nil,
      napMinutes: [Int] = [], napLength: Int = 0, wakeWindow: Int = 0, feedEvery: Int = 0
    ) {
      self.id = id
      self.fromWeek = fromWeek
      self.wakeMinute = wakeMinute
      self.bedMinute = bedMinute
      self.napMinutes = napMinutes.sorted()
      self.napLength = napLength
      self.wakeWindow = wakeWindow
      self.feedEvery = feedEvery
    }

    public var title: String { "From week \(fromWeek)" }
  }

  public var enabled: Bool
  public var stages: [Stage]

  public init(enabled: Bool = true, stages: [Stage]) {
    self.enabled = enabled
    self.stages = stages.sorted { $0.fromWeek < $1.fromWeek }
  }

  public func stage(ageWeeks: Int) -> Stage? {
    stages.last { $0.fromWeek <= ageWeeks } ?? stages.first
  }

  /// Generic age-based guidance to edit from. Not any particular book's schedule.
  public static var starter: SleepPlan {
    func h(_ hour: Int, _ minute: Int = 0) -> Int { hour * 60 + minute }
    return SleepPlan(
      enabled: false,
      stages: [
        Stage(fromWeek: 0, wakeMinute: h(7), napMinutes: [], napLength: 0, wakeWindow: 60, feedEvery: 180),
        Stage(fromWeek: 6, wakeMinute: h(7), bedMinute: h(20), napMinutes: [h(9), h(11, 30), h(14), h(16, 30)],
          napLength: 90, wakeWindow: 90, feedEvery: 180),
        Stage(fromWeek: 13, wakeMinute: h(7), bedMinute: h(19, 30), napMinutes: [h(9, 15), h(12), h(15, 15)],
          napLength: 90, wakeWindow: 120, feedEvery: 210),
        Stage(fromWeek: 26, wakeMinute: h(7), bedMinute: h(19), napMinutes: [h(9, 30), h(13, 30)],
          napLength: 90, wakeWindow: 150, feedEvery: 240),
      ])
  }
}

/// One point on today's plan.
public struct PlanSlot: Hashable, Sendable, Identifiable {
  public enum Kind: String, Hashable, Sendable { case wake, feed, nap, bed }
  public enum Status: Hashable, Sendable {
    /// Happened, near the planned time.
    case done
    /// The planned time is now (a little before to a little after).
    case due
    case upcoming
    /// The time passed with nothing logged.
    case missed
  }

  public var kind: Kind
  public var at: Date
  public var status: Status
  /// When it actually happened, if it did.
  public var actual: Date?
  /// Minutes to aim for (nap length), when set.
  public var targetMinutes: Int?
  public var id: String { "\(kind.rawValue).\(Int(at.timeIntervalSince1970))" }
}

public enum SleepPlanner {
  /// How far from the planned time still counts as on time.
  public static let tolerance: TimeInterval = 45 * 60

  /// Today's slots in time order, each marked from what has been logged.
  public static func today(
    plan: SleepPlan, ageDays: Int, now: Date, history: History, calendar: Calendar = .current
  ) -> [PlanSlot] {
    guard plan.enabled, let stage = plan.stage(ageWeeks: max(0, ageDays) / 7) else { return [] }
    let start = calendar.startOfDay(for: now)
    func time(_ minute: Int) -> Date { start.addingTimeInterval(Double(minute) * 60) }

    func status(planned: Date, actual: Date?, tolerance: TimeInterval) -> PlanSlot.Status {
      if actual != nil { return .done }
      if now > planned.addingTimeInterval(tolerance) { return .missed }
      if now >= planned.addingTimeInterval(-15 * 60) { return .due }
      return .upcoming
    }

    var slots: [PlanSlot] = []
    // Morning wake: the first sleep that ended today.
    let wakeAt = time(stage.wakeMinute)
    let actualWake = history.sleeps.compactMap(\.endedAt).filter { $0 >= start && $0 < start.addingTimeInterval(86_400) }.min()
    slots.append(
      PlanSlot(kind: .wake, at: wakeAt, status: status(planned: wakeAt, actual: actualWake, tolerance: 90 * 60), actual: actualWake))

    // Feeds from wake to bedtime (or 10 pm).
    if stage.feedEvery > 0 {
      let end = time(stage.bedMinute ?? 22 * 60)
      var cursor = wakeAt.addingTimeInterval(Double(stage.feedEvery) * 60)
      while cursor <= end {
        let actual = history.feeds.map(\.startedAt).first { abs($0.timeIntervalSince(cursor)) <= 40 * 60 }
        slots.append(PlanSlot(kind: .feed, at: cursor, status: status(planned: cursor, actual: actual, tolerance: 40 * 60), actual: actual))
        cursor = cursor.addingTimeInterval(Double(stage.feedEvery) * 60)
      }
    }

    // Naps.
    for minute in stage.napMinutes {
      let planned = time(minute)
      let actual = history.sleeps.map(\.startedAt).first { abs($0.timeIntervalSince(planned)) <= tolerance }
      slots.append(
        PlanSlot(
          kind: .nap, at: planned, status: status(planned: planned, actual: actual, tolerance: tolerance), actual: actual,
          targetMinutes: stage.napLength > 0 ? stage.napLength : nil))
    }

    // Bedtime.
    if let bed = stage.bedMinute {
      let planned = time(bed)
      let actual = history.sleeps.map(\.startedAt).first { abs($0.timeIntervalSince(planned)) <= 75 * 60 }
      slots.append(PlanSlot(kind: .bed, at: planned, status: status(planned: planned, actual: actual, tolerance: 75 * 60), actual: actual))
    }
    return slots.sorted { ($0.at, $0.kind.rawValue) < ($1.at, $1.kind.rawValue) }
  }

  /// The next thing to do: the first slot that is due or still ahead.
  public static func next(_ slots: [PlanSlot]) -> PlanSlot? {
    slots.first { $0.status == .due || $0.status == .upcoming }
  }

  /// When the running nap should end to stay on plan: its planned length from when it started.
  public static func napEnd(
    plan: SleepPlan, ageDays: Int, sleepStarted: Date, calendar: Calendar = .current
  ) -> Date? {
    guard plan.enabled, let stage = plan.stage(ageWeeks: max(0, ageDays) / 7), stage.napLength > 0
    else { return nil }
    let minute = calendar.component(.hour, from: sleepStarted) * 60 + calendar.component(.minute, from: sleepStarted)
    // Only a daytime nap: between the morning wake and a bit before bedtime.
    let bed = stage.bedMinute ?? 20 * 60
    guard minute >= stage.wakeMinute - 30, minute < bed - 30 else { return nil }
    return sleepStarted.addingTimeInterval(Double(stage.napLength) * 60)
  }

  // MARK: Adherence

  /// How the last week lined up with the plan: naps on time, how long they run, bedtime drift.
  public static func insights(
    plan: SleepPlan, birth: Date?, due: Date? = nil, history: History, now: Date,
    calendar: Calendar = .current
  ) -> [Insight] {
    guard plan.enabled, let birth else { return [] }
    var onTime = 0, planned = 0
    var overruns: [Double] = []
    var bedDrift: [Double] = []
    for offset in 1...7 {
      guard let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: now)) else { continue }
      let noon = day.addingTimeInterval(12 * 3600)
      let ageDays = DevelopmentGuide.ageDays(birth: birth, due: due, now: noon, calendar: calendar)
      guard ageDays >= 0, let stage = plan.stage(ageWeeks: ageDays / 7) else { continue }
      let sleeps = history.sleeps.filter { $0.startedAt >= day && $0.startedAt < day.addingTimeInterval(86_400) }
      guard !sleeps.isEmpty else { continue }  // an unlogged day says nothing
      for minute in stage.napMinutes {
        let target = day.addingTimeInterval(Double(minute) * 60)
        planned += 1
        if let match = sleeps.first(where: { abs($0.startedAt.timeIntervalSince(target)) <= tolerance }) {
          onTime += 1
          if stage.napLength > 0, let end = match.endedAt {
            overruns.append(end.timeIntervalSince(match.startedAt) / 60 - Double(stage.napLength))
          }
        }
      }
      if let bed = stage.bedMinute {
        let target = day.addingTimeInterval(Double(bed) * 60)
        if let match = sleeps.first(where: { abs($0.startedAt.timeIntervalSince(target)) <= 90 * 60 }) {
          bedDrift.append(match.startedAt.timeIntervalSince(target) / 60)
        }
      }
    }
    var out: [Insight] = []
    if planned >= 6 {
      let share = Double(onTime) / Double(planned)
      let text = "\(onTime) of \(planned) planned naps started within 45 minutes of plan this past week."
      if share >= 0.75 {
        out.append(
          Insight(
            id: "plan.naps", severity: .good, topic: .sleep, title: "Naps are following the plan", detail: text,
            metric: "\(Int((share * 100).rounded()))%"))
      } else if share < 0.4 {
        out.append(
          Insight(
            id: "plan.naps", severity: .notice, topic: .sleep, title: "Naps are drifting from the plan",
            detail: text + " Her wake windows may be running longer or shorter than the plan expects.",
            metric: "\(Int((share * 100).rounded()))%"))
      }
    }
    if overruns.count >= 4 {
      let mean = overruns.reduce(0, +) / Double(overruns.count)
      if mean >= 20 {
        out.append(
          Insight(
            id: "plan.napLong", severity: .notice, topic: .sleep, title: "Naps are running long",
            detail: "Naps averaged about \(Int(mean.rounded())) minutes over the plan's length this past week.",
            metric: "+\(Int(mean.rounded())) min"))
      } else if mean <= -25 {
        out.append(
          Insight(
            id: "plan.napShort", severity: .notice, topic: .sleep, title: "Naps are running short",
            detail: "Naps averaged about \(Int((-mean).rounded())) minutes under the plan's length this past week.",
            metric: "\(Int(mean.rounded())) min"))
      }
    }
    if bedDrift.count >= 4 {
      let mean = bedDrift.reduce(0, +) / Double(bedDrift.count)
      if abs(mean) >= 25 {
        out.append(
          Insight(
            id: "plan.bed", severity: .info, topic: .sleep,
            title: mean > 0 ? "Bedtime is running late" : "Bedtime is running early",
            detail: "Night sleep has started about \(Int(abs(mean).rounded())) minutes \(mean > 0 ? "after" : "before") the plan's bedtime on average.",
            metric: "\(mean > 0 ? "+" : "−")\(Int(abs(mean).rounded())) min"))
      }
    }
    return out
  }
}
