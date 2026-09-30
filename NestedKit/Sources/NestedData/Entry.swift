import Foundation
import NestedCore

/// Any loggable entry, used by the Timeline, edit sheets and undo.
public enum Entry: Hashable, Sendable, Identifiable, Codable {
  case bottle(Bottle)
  case nursing(NursingSession, segments: [NursingSegment])
  case pump(PumpSession)
  case diaper(Diaper)
  case sleep(SleepSession)
  case note(BabyNote)

  public var id: UUID {
    switch self {
    case .bottle(let e): e.id
    case .nursing(let e, _): e.id
    case .pump(let e): e.id
    case .diaper(let e): e.id
    case .sleep(let e): e.id
    case .note(let e): e.id
    }
  }

  public var kind: EventKind {
    switch self {
    case .bottle: .bottle
    case .nursing: .nursing
    case .pump: .pump
    case .diaper: .diaper
    case .sleep: .sleep
    case .note: .note
    }
  }

  public var babyID: Baby.ID {
    switch self {
    case .bottle(let e): e.babyID
    case .nursing(let e, _): e.babyID
    case .pump(let e): e.babyID
    case .diaper(let e): e.babyID
    case .sleep(let e): e.babyID
    case .note(let e): e.babyID
    }
  }

  /// When it happened (start for timers).
  public var date: Date {
    get {
      switch self {
      case .bottle(let e): e.startedAt
      case .nursing(let e, _): e.startedAt
      case .pump(let e): e.startedAt
      case .diaper(let e): e.occurredAt
      case .sleep(let e): e.startedAt
      case .note(let e): e.occurredAt
      }
    }
  }

  public var endDate: Date? {
    switch self {
    case .nursing(let e, _): e.endedAt
    case .pump(let e): e.endedAt
    case .sleep(let e): e.endedAt
    case .bottle(let e): e.durationSeconds.map { e.startedAt.addingTimeInterval($0) }
    case .diaper, .note: nil
    }
  }

  public var isRunning: Bool {
    switch self {
    case .nursing(let e, _): e.isRunning
    case .pump(let e): e.isRunning
    case .sleep(let e): e.isRunning
    default: false
    }
  }

  public var loggedBy: String {
    switch self {
    case .bottle(let e): e.loggedBy
    case .nursing(let e, _): e.loggedBy
    case .pump(let e): e.loggedBy
    case .diaper(let e): e.loggedBy
    case .sleep(let e): e.loggedBy
    case .note(let e): e.loggedBy
    }
  }

  public var note: String {
    switch self {
    case .bottle(let e): e.note
    case .nursing(let e, _): e.note
    case .pump(let e): e.note
    case .diaper(let e): e.note
    case .sleep(let e): e.note
    case .note(let e): e.text
    }
  }

  /// One-line description for the Timeline and exports.
  public func title(unit: VolumeUnit, now: Date = Date()) -> String {
    switch self {
    case .bottle(let b):
      return "\(Volume.format(ml: b.amountMl, unit: unit)) \(b.contents.title.lowercased())"
    case .nursing(let s, let segments):
      let (left, right) = NursingMath.sideTotals(segments, now: now)
      var parts: [String] = []
      if left > 0 { parts.append("L \(Durations.format(left))") }
      if right > 0 { parts.append("R \(Durations.format(right))") }
      if s.isRunning { return "Nursing now" + (parts.isEmpty ? "" : " · " + parts.joined(separator: " · ")) }
      return parts.isEmpty ? "Nursed" : parts.joined(separator: " · ")
    case .pump(let p):
      if p.isRunning { return "Pumping now" }
      let dest = p.destination.map { " · \($0.title)" } ?? ""
      return "\(Volume.format(ml: p.totalMl, unit: unit)) pumped\(dest)"
    case .diaper(let d):
      var text = d.kind.title
      if let color = d.stoolColor { text += " · \(color.title.lowercased())" }
      if d.rash { text += " · rash" }
      return text
    case .sleep(let s):
      if s.isRunning { return "Asleep" }
      let length = s.endedAt.map { Durations.format($0.timeIntervalSince(s.startedAt)) } ?? ""
      let place = s.location.map { " · \($0.title)" } ?? ""
      return "Slept \(length)\(place)"
    case .note(let n):
      let tag = n.tag.map { "\($0.title): " } ?? ""
      return tag + n.text
    }
  }

  /// Copy of this entry with fresh identifiers, moved to `date`. Used by long-press duplicate.
  public func duplicated(at date: Date, by owner: String, now: Date) -> Entry {
    let offset = date.timeIntervalSince(self.date)
    func shift(_ d: Date?) -> Date? { d.map { $0.addingTimeInterval(offset) } }
    switch self {
    case .bottle(var e):
      e = Bottle(
        id: UUID(), babyID: e.babyID, startedAt: date, amountMl: e.amountMl, offeredMl: e.offeredMl,
        contents: e.contents, formulaBrand: e.formulaBrand, durationSeconds: e.durationSeconds,
        loggedBy: owner, note: e.note, timeZone: TimeZone.current.identifier, createdAt: now,
        editedAt: now)
      return .bottle(e)
    case .nursing(let s, let segments):
      let id = UUID()
      let session = NursingSession(
        id: id, babyID: s.babyID, startedAt: date, endedAt: shift(s.endedAt) ?? date,
        endedOnSide: s.endedOnSide, pausedAt: nil, pausedSeconds: s.pausedSeconds,
        latchNote: s.latchNote, loggedBy: owner, note: s.note,
        timeZone: TimeZone.current.identifier, createdAt: now, editedAt: now)
      let copies = segments.map {
        NursingSegment(
          id: UUID(), sessionID: id, side: $0.side, startedAt: $0.startedAt.addingTimeInterval(offset),
          endedAt: shift($0.endedAt) ?? date)
      }
      return .nursing(session, segments: copies)
    case .pump(let p):
      return .pump(
        PumpSession(
          id: UUID(), babyID: p.babyID, startedAt: date, endedAt: shift(p.endedAt) ?? date,
          leftMl: p.leftMl, rightMl: p.rightMl, destination: p.destination, loggedBy: owner,
          note: p.note, timeZone: TimeZone.current.identifier, createdAt: now, editedAt: now))
    case .diaper(let d):
      return .diaper(
        Diaper(
          id: UUID(), babyID: d.babyID, occurredAt: date, kind: d.kind, stoolColor: d.stoolColor,
          consistency: d.consistency, size: d.size, rash: d.rash, loggedBy: owner, note: d.note,
          timeZone: TimeZone.current.identifier, createdAt: now, editedAt: now))
    case .sleep(let s):
      return .sleep(
        SleepSession(
          id: UUID(), babyID: s.babyID, startedAt: date, endedAt: shift(s.endedAt) ?? date,
          location: s.location, loggedBy: owner, note: s.note,
          timeZone: TimeZone.current.identifier, createdAt: now, editedAt: now))
    case .note(let n):
      return .note(
        BabyNote(
          id: UUID(), babyID: n.babyID, occurredAt: date, tag: n.tag, text: n.text,
          loggedBy: owner, timeZone: TimeZone.current.identifier, createdAt: now, editedAt: now))
    }
  }
}

public enum NursingMath {
  public static func sideTotals(
    _ segments: [NursingSegment],
    now: Date
  ) -> (left: TimeInterval, right: TimeInterval) {
    var left: TimeInterval = 0
    var right: TimeInterval = 0
    for segment in segments {
      switch segment.side {
      case .left: left += segment.duration(now: now)
      case .right: right += segment.duration(now: now)
      }
    }
    return (left, right)
  }

  /// The side currently (or most recently) being fed on.
  public static func currentSide(_ segments: [NursingSegment]) -> Side? {
    segments.max { $0.startedAt < $1.startedAt }?.side
  }

  public static func openSegment(_ segments: [NursingSegment]) -> NursingSegment? {
    segments.first { $0.endedAt == nil }
  }
}
