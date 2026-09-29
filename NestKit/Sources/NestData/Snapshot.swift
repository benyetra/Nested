import Foundation
import NestCore
import SQLiteData

/// A running nursing session with its per-side segments.
public struct ActiveNursing: Hashable, Sendable {
  public var session: NursingSession
  public var segments: [NursingSegment]

  public init(session: NursingSession, segments: [NursingSegment]) {
    self.session = session
    self.segments = segments
  }

  public var currentSide: Side { NursingMath.currentSide(segments) ?? .left }
  public var isPaused: Bool { session.isPaused }
  /// Start of the open segment, for a live per-side timer.
  public var currentSegmentStart: Date? { NursingMath.openSegment(segments)?.startedAt }

  /// Seconds fed on each side, counting the open segment up to `now`.
  public func totals(now: Date) -> (left: TimeInterval, right: TimeInterval) {
    NursingMath.sideTotals(segments, now: now)
  }

  /// Anchor for a live total timer that excludes paused time:
  /// `Text(timerInterval: effectiveStart...)` shows elapsed feeding time.
  public func effectiveStart(now: Date) -> Date {
    let (l, r) = totals(now: now)
    return now.addingTimeInterval(-(l + r))
  }
}

/// Everything the Now screen, widgets, controls, Live Activities and Siri answers read.
public struct NestSnapshot: Hashable, Sendable {
  public var baby: Baby?
  public var me: String
  public var generatedAt: Date
  public var history: History

  public var lastFeed: FeedRecord?
  public var lastBottle: Bottle?
  public var lastDiaper: Diaper?
  public var lastSleep: SleepSession?

  public var activeNursing: ActiveNursing?
  public var activePump: PumpSession?
  public var activeSleep: SleepSession?

  public var feedPrediction: FeedPrediction?
  public var napPrediction: NapPrediction?
  public var nextSide: Side
  public var defaultBottleMl: Double?

  public var totals24h: RollingTotals
  public var todayFeeds: Int
  public var todayWet: Int
  public var todayDirty: Int

  public var feedAlarm: FeedAlarm?
  public var devices: [DeviceToken]

  public static let empty = NestSnapshot(
    baby: nil, me: "", generatedAt: .distantPast, history: History(), lastFeed: nil,
    lastBottle: nil, lastDiaper: nil, lastSleep: nil, activeNursing: nil, activePump: nil,
    activeSleep: nil, feedPrediction: nil, napPrediction: nil, nextSide: .left,
    defaultBottleMl: nil, totals24h: RollingTotals(), todayFeeds: 0, todayWet: 0, todayDirty: 0,
    feedAlarm: nil, devices: [])

  public var unit: VolumeUnit { baby?.unit ?? .ml }
  public var babyName: String {
    guard let name = baby?.name, !name.isEmpty else { return "Baby" }
    return name
  }

  public var hasRunningTimer: Bool {
    activeNursing != nil || activePump != nil || activeSleep != nil
  }

  /// Awake since the end of the last sleep; nil while asleep or with no sleep logged.
  public var awakeSince: Date? {
    activeSleep == nil ? lastSleep?.endedAt : nil
  }

  public var isNight: Bool {
    guard let baby else { return false }
    return baby.nightWindow.contains(generatedAt)
  }

  /// Contents for "repeat last bottle".
  public var defaultBottleContents: BottleContents { lastBottle?.contents ?? .formula }

  public func flags(now: Date, calendar: Calendar = .current) -> [HealthFlag] {
    guard let baby else { return [] }
    return HealthFlagEvaluator.evaluate(
      history: history, birthDate: baby.birthDate, now: now, thresholds: baby.flagThresholds,
      night: baby.nightWindow, calendar: calendar)
  }

  /// The alarm if one is armed and not handled.
  public func pendingAlarm(now: Date) -> FeedAlarm? {
    guard let feedAlarm, feedAlarm.isPending(now: now) else { return nil }
    return feedAlarm
  }

  public var otherDevices: [DeviceToken] {
    devices.filter { $0.ownerName != me }
  }
}

public enum SnapshotBuilder {
  /// Days of history loaded for predictions and flags.
  public static let historyDays = 14

  public static func build(_ db: Database, me: String, now: Date, calendar: Calendar) throws -> NestSnapshot {
    guard let baby = try LiveEventStore.currentBaby(db) else {
      var empty = NestSnapshot.empty
      empty.me = me
      empty.generatedAt = now
      return empty
    }
    let since = now.addingTimeInterval(-Double(historyDays) * 86_400)
    let history = try EntryQueries.history(db, babyID: baby.id, since: since, now: now)

    let lastBottle = try Bottle.where { $0.babyID.eq(baby.id) }.order { $0.startedAt.desc() }.fetchOne(db)
    let lastDiaper = try Diaper.where { $0.babyID.eq(baby.id) }.order { $0.occurredAt.desc() }.fetchOne(db)
    let lastSleep = try SleepSession.where { $0.babyID.eq(baby.id) && $0.endedAt.isNot(nil) }
      .order { $0.endedAt.desc() }.fetchOne(db)
    let activeSleep = try SleepSession.where { $0.babyID.eq(baby.id) && $0.endedAt.is(nil) }
      .order { $0.startedAt.desc() }.fetchOne(db)
    let activePump = try PumpSession.where { $0.babyID.eq(baby.id) && $0.endedAt.is(nil) }
      .order { $0.startedAt.desc() }.fetchOne(db)

    var activeNursing: ActiveNursing?
    if let session = try NursingSession.where({ $0.babyID.eq(baby.id) && $0.endedAt.is(nil) })
      .order(by: { $0.startedAt.desc() }).fetchOne(db)
    {
      let segments = try NursingSegment.where { $0.sessionID.eq(session.id) }
        .order { $0.startedAt.asc() }.fetchAll(db)
      activeNursing = ActiveNursing(session: session, segments: segments)
    }

    // Next side from the last finished session.
    var nextSide = Side.left
    if let last = try NursingSession.where({ $0.babyID.eq(baby.id) && $0.endedAt.isNot(nil) })
      .order(by: { $0.startedAt.desc() }).fetchOne(db)
    {
      let segments = try NursingSegment.where { $0.sessionID.eq(last.id) }.fetchAll(db)
      let (l, r) = NursingMath.sideTotals(segments, now: now)
      nextSide = SidePredictor.nextSide(endedOn: last.endedOnSide, lastSessionDuration: l + r)
    }

    let recentBottles = try Bottle.where { $0.babyID.eq(baby.id) }.order { $0.startedAt.desc() }
      .limit(5).fetchAll(db)
    let defaultBottle = BottlePredictor.defaultAmountMl(
      recentAmountsMl: recentBottles.reversed().map(\.amountMl), unit: baby.unit)

    let feedPrediction = FeedPredictor.predict(
      feedStarts: history.feeds.map(\.startedAt), now: now, calendar: calendar)
    let napPrediction = NapPredictor.predict(
      sleeps: history.sleeps,
      ageInDays: baby.birthDate.map { AgeMath.days(from: $0, to: now, calendar: calendar) } ?? 14,
      now: now,
      defaultOverride: baby.wakeWindowOverrideMinutes.map { TimeInterval($0 * 60) },
      calendar: calendar)

    let startOfToday = calendar.startOfDay(for: now)
    let today = RollingTotals.compute(history: history, since: startOfToday, now: now)

    let feedAlarm = try FeedAlarm.find(baby.id).fetchOne(db)
    let devices = try DeviceToken.where { $0.babyID.eq(baby.id) }.order { $0.ownerName.asc() }.fetchAll(db)

    return NestSnapshot(
      baby: baby,
      me: me,
      generatedAt: now,
      history: history,
      lastFeed: history.feeds.last,
      lastBottle: lastBottle,
      lastDiaper: lastDiaper,
      lastSleep: lastSleep,
      activeNursing: activeNursing,
      activePump: activePump,
      activeSleep: activeSleep,
      feedPrediction: feedPrediction,
      napPrediction: napPrediction,
      nextSide: nextSide,
      defaultBottleMl: defaultBottle,
      totals24h: RollingTotals.compute(history: history, since: now.addingTimeInterval(-86_400), now: now),
      todayFeeds: today.feeds,
      todayWet: today.wet,
      todayDirty: today.dirty,
      feedAlarm: feedAlarm,
      devices: devices
    )
  }
}
