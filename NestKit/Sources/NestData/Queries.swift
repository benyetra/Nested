import Foundation
import NestCore
import SQLiteData

/// Read helpers shared by the store, the snapshot and fetch requests.
public enum EntryQueries {
  public static func entries(_ db: Database, babyID: Baby.ID, from: Date, to: Date) throws -> [Entry] {
    var result: [Entry] = []
    result += try Bottle.where { $0.babyID.eq(babyID) && $0.startedAt.gte(from) && $0.startedAt.lte(to) }
      .fetchAll(db).map(Entry.bottle)

    let sessions = try NursingSession
      .where { $0.babyID.eq(babyID) && $0.startedAt.gte(from) && $0.startedAt.lte(to) }
      .fetchAll(db)
    let segments = try segmentsBySession(db, sessionIDs: sessions.map(\.id))
    result += sessions.map { Entry.nursing($0, segments: segments[$0.id] ?? []) }

    result += try PumpSession.where { $0.babyID.eq(babyID) && $0.startedAt.gte(from) && $0.startedAt.lte(to) }
      .fetchAll(db).map(Entry.pump)
    result += try Diaper.where { $0.babyID.eq(babyID) && $0.occurredAt.gte(from) && $0.occurredAt.lte(to) }
      .fetchAll(db).map(Entry.diaper)
    result += try SleepSession.where { $0.babyID.eq(babyID) && $0.startedAt.gte(from) && $0.startedAt.lte(to) }
      .fetchAll(db).map(Entry.sleep)
    result += try BabyNote.where { $0.babyID.eq(babyID) && $0.occurredAt.gte(from) && $0.occurredAt.lte(to) }
      .fetchAll(db).map(Entry.note)
    return result.sorted { $0.date > $1.date }
  }

  static func segmentsBySession(_ db: Database, sessionIDs: [UUID]) throws -> [UUID: [NursingSegment]] {
    guard !sessionIDs.isEmpty else { return [:] }
    let all = try NursingSegment.where { $0.sessionID.in(sessionIDs) }
      .order { $0.startedAt.asc() }.fetchAll(db)
    return Dictionary(grouping: all, by: \.sessionID)
  }

  /// Everything since `since`, plus any timer still running from before it.
  public static func history(_ db: Database, babyID: Baby.ID, since: Date, now: Date) throws -> History {
    let bottles = try Bottle.where { $0.babyID.eq(babyID) && $0.startedAt.gte(since) }.fetchAll(db)
    let sessions = try NursingSession
      .where { $0.babyID.eq(babyID) && ($0.startedAt.gte(since) || $0.endedAt.is(nil)) }
      .fetchAll(db)
    let segments = try segmentsBySession(db, sessionIDs: sessions.map(\.id))
    let sleeps = try SleepSession
      .where { $0.babyID.eq(babyID) && ($0.startedAt.gte(since) || $0.endedAt.is(nil)) }
      .fetchAll(db)
    let diapers = try Diaper.where { $0.babyID.eq(babyID) && $0.occurredAt.gte(since) }.fetchAll(db)
    let pumps = try PumpSession.where { $0.babyID.eq(babyID) && $0.startedAt.gte(since) }.fetchAll(db)

    var feeds = bottles.map { bottle in
      let start = bottle.startedAt
      return FeedRecord(
        startedAt: start,
        endedAt: bottle.durationSeconds.map(start.addingTimeInterval),
        kind: .bottle(amountMl: bottle.amountMl, contents: bottle.contents))
    }
    feeds += sessions.map { session in
      let (l, r) = NursingMath.sideTotals(segments[session.id] ?? [], now: now)
      return FeedRecord(
        startedAt: session.startedAt, endedAt: session.endedAt,
        kind: .nursing(leftSeconds: l, rightSeconds: r, endedOnSide: session.endedOnSide))
    }
    return History(
      feeds: feeds,
      sleeps: sleeps.map { SleepRecord(startedAt: $0.startedAt, endedAt: $0.endedAt) },
      diapers: diapers.map { DiaperRecord(occurredAt: $0.occurredAt, kind: $0.kind, stoolColor: $0.stoolColor) },
      pumps: pumps.map {
        PumpRecord(
          startedAt: $0.startedAt, endedAt: $0.endedAt, leftMl: $0.leftMl ?? 0, rightMl: $0.rightMl ?? 0,
          destination: $0.destination)
      }
    )
  }

  static func exists(_ db: Database, babyID: Baby.ID, kind: EventKind, at date: Date) throws -> Bool {
    let lower = date.addingTimeInterval(-1)
    let upper = date.addingTimeInterval(1)
    switch kind {
    case .bottle:
      return try Bottle.where { $0.babyID.eq(babyID) && $0.startedAt.gte(lower) && $0.startedAt.lte(upper) }
        .fetchCount(db) > 0
    case .nursing:
      return try NursingSession.where { $0.babyID.eq(babyID) && $0.startedAt.gte(lower) && $0.startedAt.lte(upper) }
        .fetchCount(db) > 0
    case .pump:
      return try PumpSession.where { $0.babyID.eq(babyID) && $0.startedAt.gte(lower) && $0.startedAt.lte(upper) }
        .fetchCount(db) > 0
    case .diaper:
      return try Diaper.where { $0.babyID.eq(babyID) && $0.occurredAt.gte(lower) && $0.occurredAt.lte(upper) }
        .fetchCount(db) > 0
    case .sleep:
      return try SleepSession.where { $0.babyID.eq(babyID) && $0.startedAt.gte(lower) && $0.startedAt.lte(upper) }
        .fetchCount(db) > 0
    case .note:
      return try BabyNote.where { $0.babyID.eq(babyID) && $0.occurredAt.gte(lower) && $0.occurredAt.lte(upper) }
        .fetchCount(db) > 0
    }
  }
}

/// Maps entries to and from the CSV row format.
public enum EntryExport {
  public static func row(for entry: Entry, now: Date) -> EntryRow {
    var row = EntryRow(kind: entry.kind, startedAt: entry.date, note: entry.note, loggedBy: entry.loggedBy)
    switch entry {
    case .bottle(let b):
      row.amountMl = b.amountMl
      row.offeredMl = b.offeredMl
      row.contents = b.contents
      row.formulaBrand = b.formulaBrand
      row.endedAt = entry.endDate
      row.timeZone = b.timeZone
    case .nursing(let s, let segments):
      let (l, r) = NursingMath.sideTotals(segments, now: now)
      row.endedAt = s.endedAt
      row.leftSeconds = l
      row.rightSeconds = r
      row.endedOnSide = s.endedOnSide
      row.timeZone = s.timeZone
    case .pump(let p):
      row.endedAt = p.endedAt
      row.leftMl = p.leftMl
      row.rightMl = p.rightMl
      row.destination = p.destination
      row.timeZone = p.timeZone
    case .diaper(let d):
      row.diaper = d.kind
      row.stoolColor = d.stoolColor
      row.consistency = d.consistency
      row.size = d.size
      row.rash = d.rash
      row.timeZone = d.timeZone
    case .sleep(let s):
      row.endedAt = s.endedAt
      row.location = s.location
      row.timeZone = s.timeZone
    case .note(let n):
      row.tag = n.tag
      row.timeZone = n.timeZone
    }
    if row.timeZone?.isEmpty == true { row.timeZone = nil }
    return row
  }

  public static func entry(from row: EntryRow, babyID: Baby.ID, fallbackOwner: String, now: Date) -> Entry {
    let owner = row.loggedBy.isEmpty ? fallbackOwner : row.loggedBy
    let tz = row.timeZone ?? TimeZone.current.identifier
    switch row.kind {
    case .bottle:
      return .bottle(
        Bottle(
          id: UUID(), babyID: babyID, startedAt: row.startedAt, amountMl: row.amountMl ?? 0,
          offeredMl: row.offeredMl, contents: row.contents ?? .formula, formulaBrand: row.formulaBrand,
          durationSeconds: row.endedAt.map { $0.timeIntervalSince(row.startedAt) }, loggedBy: owner,
          note: row.note, timeZone: tz, createdAt: now, editedAt: now))
    case .nursing:
      let id = UUID()
      var segments: [NursingSegment] = []
      var cursor = row.startedAt
      let order: [Side] = row.endedOnSide == .left ? [.right, .left] : [.left, .right]
      for side in order {
        let seconds = (side == .left ? row.leftSeconds : row.rightSeconds) ?? 0
        guard seconds > 0 else { continue }
        let end = cursor.addingTimeInterval(seconds)
        segments.append(NursingSegment(id: UUID(), sessionID: id, side: side, startedAt: cursor, endedAt: end))
        cursor = end
      }
      return .nursing(
        NursingSession(
          id: id, babyID: babyID, startedAt: row.startedAt, endedAt: row.endedAt ?? cursor,
          endedOnSide: row.endedOnSide ?? segments.last?.side, pausedAt: nil, pausedSeconds: 0,
          latchNote: "", loggedBy: owner, note: row.note, timeZone: tz, createdAt: now, editedAt: now),
        segments: segments)
    case .pump:
      return .pump(
        PumpSession(
          id: UUID(), babyID: babyID, startedAt: row.startedAt, endedAt: row.endedAt ?? row.startedAt,
          leftMl: row.leftMl, rightMl: row.rightMl, destination: row.destination, loggedBy: owner,
          note: row.note, timeZone: tz, createdAt: now, editedAt: now))
    case .diaper:
      return .diaper(
        Diaper(
          id: UUID(), babyID: babyID, occurredAt: row.startedAt, kind: row.diaper ?? .wet,
          stoolColor: row.stoolColor, consistency: row.consistency, size: row.size,
          rash: row.rash ?? false, loggedBy: owner, note: row.note, timeZone: tz, createdAt: now,
          editedAt: now))
    case .sleep:
      return .sleep(
        SleepSession(
          id: UUID(), babyID: babyID, startedAt: row.startedAt, endedAt: row.endedAt ?? row.startedAt,
          location: row.location, loggedBy: owner, note: row.note, timeZone: tz, createdAt: now,
          editedAt: now))
    case .note:
      return .note(
        BabyNote(
          id: UUID(), babyID: babyID, occurredAt: row.startedAt, tag: row.tag, text: row.note,
          loggedBy: owner, timeZone: tz, createdAt: now, editedAt: now))
    }
  }
}

// MARK: - Fetch requests for SwiftUI

/// Everything the Now screen, widgets and intents need, rebuilt whenever the database changes
/// (local writes and partner changes arriving through sync alike).
public struct SnapshotRequest: FetchKeyRequest {
  public var me: String
  public init(me: String = DevicePrefs.ownerName) { self.me = me }
  public func fetch(_ db: Database) throws -> NestSnapshot {
    try SnapshotBuilder.build(db, me: me, now: Date(), calendar: .current)
  }
}

/// Timeline entries for the last `days` days, newest first.
public struct TimelineRequest: FetchKeyRequest {
  public var days: Int
  public init(days: Int) { self.days = days }
  public func fetch(_ db: Database) throws -> [Entry] {
    guard let baby = try LiveEventStore.currentBaby(db) else { return [] }
    let from = Calendar.current.date(byAdding: .day, value: -days, to: Calendar.current.startOfDay(for: Date()))
      ?? .distantPast
    return try EntryQueries.entries(db, babyID: baby.id, from: from, to: .distantFuture)
  }
}

/// History for the trend charts.
public struct TrendsRequest: FetchKeyRequest {
  public struct Value: Sendable, Hashable {
    public var baby: Baby?
    public var history: History
    public var notes: [BabyNote]
    public init(baby: Baby? = nil, history: History = History(), notes: [BabyNote] = []) {
      self.baby = baby
      self.history = history
      self.notes = notes
    }
  }

  public var days: Int
  public init(days: Int) { self.days = days }
  public func fetch(_ db: Database) throws -> Value {
    guard let baby = try LiveEventStore.currentBaby(db) else { return Value() }
    // Two extra weeks so week-over-week comparisons have a baseline.
    let since = Calendar.current.date(
      byAdding: .day, value: -(days + 14), to: Calendar.current.startOfDay(for: Date())) ?? .distantPast
    let notes = try BabyNote.where { $0.babyID.eq(baby.id) && $0.occurredAt.gte(since) }
      .order { $0.occurredAt.desc() }.fetchAll(db)
    return Value(
      baby: baby, history: try EntryQueries.history(db, babyID: baby.id, since: since, now: Date()),
      notes: notes)
  }
}

/// Earlier versions of one entry, newest first.
public struct RevisionsRequest: FetchKeyRequest {
  public var entryID: UUID
  public init(entryID: UUID) { self.entryID = entryID }
  public func fetch(_ db: Database) throws -> [EntryRevision] {
    try EntryRevision.where { $0.entryID.eq(entryID) }.order { $0.editedAt.desc() }.fetchAll(db)
  }
}

/// Open questions first (oldest first, so they read in the order they were thought of),
/// then answered ones, most recently answered first.
public struct QuestionsRequest: FetchKeyRequest {
  public init() {}
  public func fetch(_ db: Database) throws -> [Question] {
    guard let baby = try LiveEventStore.currentBaby(db) else { return [] }
    let all = try Question.where { $0.babyID.eq(baby.id) }.fetchAll(db)
    let open = all.filter { !$0.isDone }.sorted { $0.createdAt < $1.createdAt }
    let done = all.filter(\.isDone).sorted { ($0.doneAt ?? $0.editedAt) > ($1.doneAt ?? $1.editedAt) }
    return open + done
  }
}

/// Photos for the baby and parents. Newest wins if a subject somehow has two.
public struct AvatarsRequest: FetchKeyRequest {
  public init() {}
  public func fetch(_ db: Database) throws -> [Avatar] {
    guard let baby = try LiveEventStore.currentBaby(db) else { return [] }
    return try Avatar.where { $0.babyID.eq(baby.id) }.order { $0.updatedAt.desc() }.fetchAll(db)
  }
}
