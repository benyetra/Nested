import Foundation
import NestCore
import SQLiteData

public enum StoreError: Error, Equatable, CustomStringConvertible {
  case noBaby
  case nothingRunning
  case notFound

  public var description: String {
    switch self {
    case .noBaby: "Add your baby in Nest first."
    case .nothingRunning: "No timer is running."
    case .notFound: "That entry no longer exists."
    }
  }
}

/// What happened in a write, for side effects (haptics, partner push) that should fire only
/// for local actions. Remote changes are observed through the database instead.
public enum StoreChange: Sendable, Hashable {
  case logged(Entry)
  case timerStarted(Entry)
  case timerStopped(Entry)
  case sideSwitched(Entry)
  case edited(Entry)
  case deleted(Entry)
  case alarmChanged(FeedAlarm?)
  case settingsChanged
}

/// Every write in the app goes through an `EventStore`; no view touches the database directly.
///
/// It is a protocol so the sync layer can be swapped (PRD risk table: Firestore fallback)
/// without touching UI. `LiveEventStore` is the SQLiteData implementation.
public protocol EventStore: Sendable {
  // Baby
  func baby() throws -> Baby?
  @discardableResult
  func createBaby(name: String, birthDate: Date?, feedingMode: FeedingMode, unit: VolumeUnit) throws -> Baby
  func updateBaby(_ baby: Baby) throws
  /// Deletes the baby and every entry (cascades, and syncs the deletion).
  func deleteAllData() throws

  // Logging
  @discardableResult
  func logBottle(
    amountMl: Double, contents: BottleContents, offeredMl: Double?, formulaBrand: String?,
    at date: Date, note: String, endSleep: Bool
  ) throws -> Entry
  @discardableResult
  func startNursing(side: Side?, at date: Date, endSleep: Bool) throws -> Entry
  @discardableResult
  func switchNursingSide(at date: Date) throws -> Entry
  @discardableResult
  func pauseNursing(at date: Date) throws -> Entry
  @discardableResult
  func resumeNursing(at date: Date) throws -> Entry
  @discardableResult
  func stopNursing(at date: Date, latchNote: String?) throws -> Entry
  @discardableResult
  func logNursing(
    leftSeconds: TimeInterval, rightSeconds: TimeInterval, endedOn: Side?, at date: Date,
    note: String
  ) throws -> Entry
  @discardableResult
  func startPump(at date: Date) throws -> Entry
  @discardableResult
  func stopPump(leftMl: Double, rightMl: Double, destination: PumpDestination?, at date: Date) throws -> Entry
  @discardableResult
  func logDiaper(
    kind: DiaperKind, stoolColor: StoolColor?, consistency: StoolConsistency?, size: DiaperSize?,
    rash: Bool, at date: Date, note: String
  ) throws -> Entry
  @discardableResult
  func startSleep(location: SleepLocation?, at date: Date) throws -> Entry
  @discardableResult
  func stopSleep(at date: Date) throws -> Entry
  @discardableResult
  func logNote(text: String, tag: NoteTag?, at date: Date) throws -> Entry
  /// Ends whichever timers are running (nursing, pump, sleep).
  @discardableResult
  func stopActiveTimers(at date: Date) throws -> [Entry]

  // Editing
  func save(_ entry: Entry) throws
  func delete(_ entry: Entry) throws
  /// Puts back a deleted entry exactly as it was (undo).
  func restore(_ entry: Entry) throws
  @discardableResult
  func duplicate(_ entry: Entry, at date: Date) throws -> Entry
  func revisions(of entryID: UUID) throws -> [EntryRevision]

  // Feed alarm
  func setFeedAlarm(fireAt: Date?, manual: Bool) throws
  func handleFeedAlarm() throws

  // Pediatrician questions
  @discardableResult
  func addQuestion(_ body: RichText) throws -> Question
  /// Saves new text and/or an answer. A non-empty answer checks the question off.
  func updateQuestion(id: UUID, body: RichText, answer: RichText) throws
  func setQuestionDone(id: UUID, done: Bool) throws
  func deleteQuestion(id: UUID) throws
  /// Puts a deleted question back (undo).
  func restoreQuestion(_ question: Question) throws

  // Photos
  /// Sets (or, with nil, removes) the photo for `Avatar.babySubject` / `Avatar.parentSubject(name)`.
  func setAvatar(subject: String, photo: Data?) throws

  // Devices
  func updateDevice(_ update: (inout DeviceToken) -> Void) throws

  // Reads
  func snapshot(now: Date) throws -> NestSnapshot
  func entries(from: Date, to: Date) throws -> [Entry]
  func history(since: Date) throws -> History

  // Import / export
  func exportCSV() throws -> String
  @discardableResult
  func importCSV(_ text: String) throws -> Int
}

extension EventStore {
  @discardableResult
  public func logBottle(amountMl: Double, contents: BottleContents, at date: Date = Date()) throws -> Entry {
    try logBottle(
      amountMl: amountMl, contents: contents, offeredMl: nil, formulaBrand: nil, at: date, note: "",
      endSleep: true)
  }

  @discardableResult
  public func logDiaper(kind: DiaperKind, at date: Date = Date()) throws -> Entry {
    try logDiaper(
      kind: kind, stoolColor: nil, consistency: nil, size: nil, rash: false, at: date, note: "")
  }
}

/// The SQLiteData-backed store.
public struct LiveEventStore: EventStore {
  public let database: any DatabaseWriter
  let owner: @Sendable () -> String
  /// This install's `DeviceToken` row id.
  let deviceID: UUID
  let now: @Sendable () -> Date
  let calendar: Calendar
  let onChange: @Sendable (StoreChange) -> Void

  public init(
    database: any DatabaseWriter,
    owner: @escaping @Sendable () -> String = { DevicePrefs.ownerName },
    deviceID: UUID = DevicePrefs.deviceID,
    now: @escaping @Sendable () -> Date = { Date() },
    calendar: Calendar = .current,
    onChange: @escaping @Sendable (StoreChange) -> Void = { _ in }
  ) {
    self.database = database
    self.owner = owner
    self.deviceID = deviceID
    self.now = now
    self.calendar = calendar
    self.onChange = onChange
  }

  var timeZone: String { calendar.timeZone.identifier }

  // MARK: Baby

  public func baby() throws -> Baby? {
    try database.read { db in try Self.currentBaby(db) }
  }

  static func currentBaby(_ db: Database) throws -> Baby? {
    if let id = DevicePrefs.babyID, let baby = try Baby.find(id).fetchOne(db) {
      return baby
    }
    return try Baby.order { $0.createdAt.asc() }.fetchOne(db)
  }

  func requireBaby(_ db: Database) throws -> Baby {
    guard let baby = try Self.currentBaby(db) else { throw StoreError.noBaby }
    return baby
  }

  public func createBaby(
    name: String, birthDate: Date?, feedingMode: FeedingMode, unit: VolumeUnit
  ) throws -> Baby {
    let baby = Baby(name: name, birthDate: birthDate, feedingMode: feedingMode, unit: unit, createdAt: now())
    try database.write { db in
      try Baby.insert { baby }.execute(db)
    }
    DevicePrefs.babyID = baby.id
    onChange(.settingsChanged)
    return baby
  }

  public func updateBaby(_ baby: Baby) throws {
    try database.write { db in
      try Baby.update(baby).execute(db)
    }
    onChange(.settingsChanged)
  }

  public func deleteAllData() throws {
    try database.write { db in
      guard let baby = try Self.currentBaby(db) else { return }
      try Baby.find(baby.id).delete().execute(db)
    }
    DevicePrefs.babyID = nil
    onChange(.settingsChanged)
  }

  // MARK: Feeds

  public func logBottle(
    amountMl: Double, contents: BottleContents, offeredMl: Double?, formulaBrand: String?,
    at date: Date, note: String, endSleep: Bool
  ) throws -> Entry {
    let stamp = now()
    let entry = try database.write { db in
      let baby = try requireBaby(db)
      if endSleep { try endRunningSleep(db, baby: baby, at: date) }
      let bottle = Bottle(
        id: UUID(), babyID: baby.id, startedAt: date, amountMl: amountMl, offeredMl: offeredMl,
        contents: contents, formulaBrand: formulaBrand, durationSeconds: nil, loggedBy: owner(),
        note: note, timeZone: timeZone, createdAt: stamp, editedAt: stamp)
      try Bottle.insert { bottle }.execute(db)
      if contents != .breastMilk, let brand = formulaBrand, !brand.isEmpty, brand != baby.formulaBrand {
        var updated = baby
        updated.formulaBrand = brand
        try Baby.update(updated).execute(db)
      }
      try autoArm(db, baby: baby, feedStart: date, feedEnd: nil)
      return Entry.bottle(bottle)
    }
    onChange(.logged(entry))
    return entry
  }

  public func startNursing(side: Side?, at date: Date, endSleep: Bool) throws -> Entry {
    let stamp = now()
    let (entry, started) = try database.write { db -> (Entry, Bool) in
      let baby = try requireBaby(db)
      if let running = try runningNursing(db, baby: baby) {
        return (running, false)
      }
      if endSleep { try endRunningSleep(db, baby: baby, at: date) }
      let chosen = try side ?? predictedSide(db, baby: baby)
      let session = NursingSession(
        id: UUID(), babyID: baby.id, startedAt: date, endedAt: nil, endedOnSide: nil, pausedAt: nil,
        pausedSeconds: 0, latchNote: "", loggedBy: owner(), note: "", timeZone: timeZone,
        createdAt: stamp, editedAt: stamp)
      let segment = NursingSegment(
        id: UUID(), sessionID: session.id, side: chosen, startedAt: date, endedAt: nil)
      try NursingSession.insert { session }.execute(db)
      try NursingSegment.insert { segment }.execute(db)
      try autoArm(db, baby: baby, feedStart: date, feedEnd: nil)
      return (Entry.nursing(session, segments: [segment]), true)
    }
    if started { onChange(.timerStarted(entry)) }
    return entry
  }

  public func switchNursingSide(at date: Date) throws -> Entry {
    let entry = try database.write { db in
      let baby = try requireBaby(db)
      guard case .nursing(var session, var segments)? = try runningNursing(db, baby: baby) else {
        throw StoreError.nothingRunning
      }
      let current = NursingMath.currentSide(segments) ?? .left
      if var open = NursingMath.openSegment(segments) {
        open.endedAt = max(date, open.startedAt)
        try NursingSegment.update(open).execute(db)
        segments = segments.map { $0.id == open.id ? open : $0 }
      }
      if let pausedAt = session.pausedAt {
        session.pausedSeconds += max(0, date.timeIntervalSince(pausedAt))
        session.pausedAt = nil
      }
      let next = NursingSegment(
        id: UUID(), sessionID: session.id, side: current.opposite, startedAt: date, endedAt: nil)
      try NursingSegment.insert { next }.execute(db)
      session.editedAt = now()
      try NursingSession.update(session).execute(db)
      return Entry.nursing(session, segments: segments + [next])
    }
    onChange(.sideSwitched(entry))
    return entry
  }

  public func pauseNursing(at date: Date) throws -> Entry {
    let entry = try database.write { db in
      let baby = try requireBaby(db)
      guard case .nursing(var session, var segments)? = try runningNursing(db, baby: baby) else {
        throw StoreError.nothingRunning
      }
      guard session.pausedAt == nil else { return Entry.nursing(session, segments: segments) }
      if var open = NursingMath.openSegment(segments) {
        open.endedAt = max(date, open.startedAt)
        try NursingSegment.update(open).execute(db)
        segments = segments.map { $0.id == open.id ? open : $0 }
      }
      session.pausedAt = date
      session.editedAt = now()
      try NursingSession.update(session).execute(db)
      return Entry.nursing(session, segments: segments)
    }
    onChange(.edited(entry))
    return entry
  }

  public func resumeNursing(at date: Date) throws -> Entry {
    let entry = try database.write { db in
      let baby = try requireBaby(db)
      guard case .nursing(var session, let segments)? = try runningNursing(db, baby: baby) else {
        throw StoreError.nothingRunning
      }
      guard let pausedAt = session.pausedAt else { return Entry.nursing(session, segments: segments) }
      session.pausedSeconds += max(0, date.timeIntervalSince(pausedAt))
      session.pausedAt = nil
      session.editedAt = now()
      let side = NursingMath.currentSide(segments) ?? .left
      let segment = NursingSegment(id: UUID(), sessionID: session.id, side: side, startedAt: date, endedAt: nil)
      try NursingSegment.insert { segment }.execute(db)
      try NursingSession.update(session).execute(db)
      return Entry.nursing(session, segments: segments + [segment])
    }
    onChange(.edited(entry))
    return entry
  }

  public func stopNursing(at date: Date, latchNote: String?) throws -> Entry {
    let entry = try database.write { db in
      let baby = try requireBaby(db)
      guard case .nursing(let session, let segments)? = try runningNursing(db, baby: baby) else {
        throw StoreError.nothingRunning
      }
      return try finishNursing(db, baby: baby, session: session, segments: segments, at: date, latchNote: latchNote)
    }
    onChange(.timerStopped(entry))
    return entry
  }

  func finishNursing(
    _ db: Database, baby: Baby, session: NursingSession, segments: [NursingSegment], at date: Date,
    latchNote: String?
  ) throws -> Entry {
    var session = session
    var segments = segments
    if var open = NursingMath.openSegment(segments) {
      open.endedAt = max(date, open.startedAt)
      try NursingSegment.update(open).execute(db)
      segments = segments.map { $0.id == open.id ? open : $0 }
    }
    if let pausedAt = session.pausedAt {
      session.pausedSeconds += max(0, date.timeIntervalSince(pausedAt))
      session.pausedAt = nil
    }
    session.endedAt = max(date, session.startedAt)
    session.endedOnSide = NursingMath.currentSide(segments)
    if let latchNote { session.latchNote = latchNote }
    session.editedAt = now()
    try NursingSession.update(session).execute(db)
    if baby.alarmMeasuredFrom == .feedEnd {
      try autoArm(db, baby: baby, feedStart: session.startedAt, feedEnd: session.endedAt)
    }
    return Entry.nursing(session, segments: segments)
  }

  public func logNursing(
    leftSeconds: TimeInterval, rightSeconds: TimeInterval, endedOn: Side?, at date: Date,
    note: String
  ) throws -> Entry {
    let stamp = now()
    let entry = try database.write { db in
      let baby = try requireBaby(db)
      let id = UUID()
      // Lay the sides out back to back, ending on `endedOn`.
      let order: [Side] = endedOn == .left ? [.right, .left] : [.left, .right]
      var cursor = date
      var segments: [NursingSegment] = []
      for side in order {
        let seconds = side == .left ? leftSeconds : rightSeconds
        guard seconds > 0 else { continue }
        let end = cursor.addingTimeInterval(seconds)
        segments.append(NursingSegment(id: UUID(), sessionID: id, side: side, startedAt: cursor, endedAt: end))
        cursor = end
      }
      let session = NursingSession(
        id: id, babyID: baby.id, startedAt: date, endedAt: cursor,
        endedOnSide: endedOn ?? segments.last?.side, pausedAt: nil, pausedSeconds: 0, latchNote: "",
        loggedBy: owner(), note: note, timeZone: timeZone, createdAt: stamp, editedAt: stamp)
      try NursingSession.insert { session }.execute(db)
      for segment in segments { try NursingSegment.insert { segment }.execute(db) }
      try autoArm(db, baby: baby, feedStart: date, feedEnd: cursor)
      return Entry.nursing(session, segments: segments)
    }
    onChange(.logged(entry))
    return entry
  }

  // MARK: Pump

  public func startPump(at date: Date) throws -> Entry {
    let stamp = now()
    let (entry, started) = try database.write { db -> (Entry, Bool) in
      let baby = try requireBaby(db)
      if let running = try PumpSession.where({ $0.babyID.eq(baby.id) && $0.endedAt.is(nil) }).fetchOne(db) {
        return (.pump(running), false)
      }
      let session = PumpSession(
        id: UUID(), babyID: baby.id, startedAt: date, endedAt: nil, leftMl: nil, rightMl: nil,
        destination: nil, loggedBy: owner(), note: "", timeZone: timeZone, createdAt: stamp, editedAt: stamp)
      try PumpSession.insert { session }.execute(db)
      return (.pump(session), true)
    }
    if started { onChange(.timerStarted(entry)) }
    return entry
  }

  public func stopPump(
    leftMl: Double, rightMl: Double, destination: PumpDestination?, at date: Date
  ) throws -> Entry {
    let entry = try database.write { db in
      let baby = try requireBaby(db)
      guard var session = try PumpSession.where({ $0.babyID.eq(baby.id) && $0.endedAt.is(nil) }).fetchOne(db)
      else { throw StoreError.nothingRunning }
      session.endedAt = max(date, session.startedAt)
      session.leftMl = leftMl
      session.rightMl = rightMl
      session.destination = destination
      session.editedAt = now()
      try PumpSession.update(session).execute(db)
      return Entry.pump(session)
    }
    onChange(.timerStopped(entry))
    return entry
  }

  // MARK: Diaper, sleep, note

  public func logDiaper(
    kind: DiaperKind, stoolColor: StoolColor?, consistency: StoolConsistency?, size: DiaperSize?,
    rash: Bool, at date: Date, note: String
  ) throws -> Entry {
    let stamp = now()
    let entry = try database.write { db in
      let baby = try requireBaby(db)
      let diaper = Diaper(
        id: UUID(), babyID: baby.id, occurredAt: date, kind: kind,
        stoolColor: kind.hasStool ? stoolColor : nil, consistency: kind.hasStool ? consistency : nil,
        size: size, rash: rash, loggedBy: owner(), note: note, timeZone: timeZone, createdAt: stamp,
        editedAt: stamp)
      try Diaper.insert { diaper }.execute(db)
      return Entry.diaper(diaper)
    }
    onChange(.logged(entry))
    return entry
  }

  public func startSleep(location: SleepLocation?, at date: Date) throws -> Entry {
    let stamp = now()
    let (entry, started) = try database.write { db -> (Entry, Bool) in
      let baby = try requireBaby(db)
      if let running = try SleepSession.where({ $0.babyID.eq(baby.id) && $0.endedAt.is(nil) }).fetchOne(db) {
        return (.sleep(running), false)
      }
      let sleep = SleepSession(
        id: UUID(), babyID: baby.id, startedAt: date, endedAt: nil, location: location,
        loggedBy: owner(), note: "", timeZone: timeZone, createdAt: stamp, editedAt: stamp)
      try SleepSession.insert { sleep }.execute(db)
      return (.sleep(sleep), true)
    }
    if started { onChange(.timerStarted(entry)) }
    return entry
  }

  public func stopSleep(at date: Date) throws -> Entry {
    let entry = try database.write { db in
      let baby = try requireBaby(db)
      guard let ended = try endRunningSleep(db, baby: baby, at: date) else {
        throw StoreError.nothingRunning
      }
      return Entry.sleep(ended)
    }
    onChange(.timerStopped(entry))
    return entry
  }

  @discardableResult
  func endRunningSleep(_ db: Database, baby: Baby, at date: Date) throws -> SleepSession? {
    guard var sleep = try SleepSession.where({ $0.babyID.eq(baby.id) && $0.endedAt.is(nil) }).fetchOne(db)
    else { return nil }
    sleep.endedAt = max(date, sleep.startedAt)
    sleep.editedAt = now()
    try SleepSession.update(sleep).execute(db)
    return sleep
  }

  public func logNote(text: String, tag: NoteTag?, at date: Date) throws -> Entry {
    let stamp = now()
    let entry = try database.write { db in
      let baby = try requireBaby(db)
      let note = BabyNote(
        id: UUID(), babyID: baby.id, occurredAt: date, tag: tag, text: text, loggedBy: owner(),
        timeZone: timeZone, createdAt: stamp, editedAt: stamp)
      try BabyNote.insert { note }.execute(db)
      return Entry.note(note)
    }
    onChange(.logged(entry))
    return entry
  }

  public func stopActiveTimers(at date: Date) throws -> [Entry] {
    let stopped = try database.write { db -> [Entry] in
      let baby = try requireBaby(db)
      var stopped: [Entry] = []
      if case .nursing(let session, let segments)? = try runningNursing(db, baby: baby) {
        stopped.append(try finishNursing(db, baby: baby, session: session, segments: segments, at: date, latchNote: nil))
      }
      if var pump = try PumpSession.where({ $0.babyID.eq(baby.id) && $0.endedAt.is(nil) }).fetchOne(db) {
        pump.endedAt = max(date, pump.startedAt)
        pump.editedAt = now()
        try PumpSession.update(pump).execute(db)
        stopped.append(.pump(pump))
      }
      if let sleep = try endRunningSleep(db, baby: baby, at: date) {
        stopped.append(.sleep(sleep))
      }
      return stopped
    }
    for entry in stopped { onChange(.timerStopped(entry)) }
    return stopped
  }

  // MARK: Editing

  public func save(_ entry: Entry) throws {
    let stamp = now()
    let me = owner()
    try database.write { db in
      guard let previous = try fetchEntry(db, id: entry.id, kind: entry.kind) else {
        throw StoreError.notFound
      }
      guard previous != entry else { return }
      let json = String(decoding: try JSONEncoder().encode(previous), as: UTF8.self)
      try EntryRevision.insert {
        EntryRevision(
          id: UUID(), babyID: entry.babyID, entryID: entry.id, kind: entry.kind, snapshot: json,
          editedBy: me, editedAt: stamp)
      }
      .execute(db)
      switch entry {
      case .bottle(var e):
        e.editedAt = stamp
        try Bottle.update(e).execute(db)
      case .nursing(var s, let segments):
        s.editedAt = stamp
        try NursingSession.update(s).execute(db)
        try NursingSegment.where { $0.sessionID.eq(s.id) }.delete().execute(db)
        for segment in segments { try NursingSegment.insert { segment }.execute(db) }
      case .pump(var e):
        e.editedAt = stamp
        try PumpSession.update(e).execute(db)
      case .diaper(var e):
        e.editedAt = stamp
        if !e.kind.hasStool {
          e.stoolColor = nil
          e.consistency = nil
        }
        try Diaper.update(e).execute(db)
      case .sleep(var e):
        e.editedAt = stamp
        try SleepSession.update(e).execute(db)
      case .note(var e):
        e.editedAt = stamp
        try BabyNote.update(e).execute(db)
      }
    }
    onChange(.edited(entry))
  }

  public func delete(_ entry: Entry) throws {
    try database.write { db in
      switch entry {
      case .bottle(let e): try Bottle.find(e.id).delete().execute(db)
      case .nursing(let e, _): try NursingSession.find(e.id).delete().execute(db)
      case .pump(let e): try PumpSession.find(e.id).delete().execute(db)
      case .diaper(let e): try Diaper.find(e.id).delete().execute(db)
      case .sleep(let e): try SleepSession.find(e.id).delete().execute(db)
      case .note(let e): try BabyNote.find(e.id).delete().execute(db)
      }
    }
    onChange(.deleted(entry))
  }

  public func restore(_ entry: Entry) throws {
    try database.write { db in
      switch entry {
      case .bottle(let e): try Bottle.insert { e }.execute(db)
      case .nursing(let s, let segments):
        try NursingSession.insert { s }.execute(db)
        for segment in segments { try NursingSegment.insert { segment }.execute(db) }
      case .pump(let e): try PumpSession.insert { e }.execute(db)
      case .diaper(let e): try Diaper.insert { e }.execute(db)
      case .sleep(let e): try SleepSession.insert { e }.execute(db)
      case .note(let e): try BabyNote.insert { e }.execute(db)
      }
    }
    onChange(.logged(entry))
  }

  public func duplicate(_ entry: Entry, at date: Date) throws -> Entry {
    let copy = entry.duplicated(at: date, by: owner(), now: now())
    try restore(copy)
    return copy
  }

  public func revisions(of entryID: UUID) throws -> [EntryRevision] {
    try database.read { db in
      try EntryRevision.where { $0.entryID.eq(entryID) }.order { $0.editedAt.desc() }.fetchAll(db)
    }
  }

  // MARK: Photos

  public func setAvatar(subject: String, photo: Data?) throws {
    let stamp = now()
    try database.write { db in
      let baby = try requireBaby(db)
      let existing = try Avatar.where { $0.babyID.eq(baby.id) && $0.subject.eq(subject) }.fetchAll(db)
      guard let photo, !photo.isEmpty else {
        for avatar in existing { try Avatar.find(avatar.id).delete().execute(db) }
        return
      }
      if var avatar = existing.first {
        avatar.photo = photo
        avatar.updatedAt = stamp
        try Avatar.update(avatar).execute(db)
        // A simultaneous first upload from two phones can leave twins; keep one.
        for extra in existing.dropFirst() { try Avatar.find(extra.id).delete().execute(db) }
      } else {
        try Avatar.insert {
          Avatar(id: UUID(), babyID: baby.id, subject: subject, photo: photo, updatedAt: stamp)
        }.execute(db)
      }
    }
  }

  public func avatars() throws -> [Avatar] {
    try database.read { db in try AvatarsRequest().fetch(db) }
  }

  // MARK: Questions

  public func addQuestion(_ body: RichText) throws -> Question {
    let stamp = now()
    return try database.write { db in
      let baby = try requireBaby(db)
      let question = Question(
        id: UUID(), babyID: baby.id, body: body.stored, askedBy: owner(), createdAt: stamp,
        editedAt: stamp)
      try Question.insert { question }.execute(db)
      return question
    }
  }

  public func updateQuestion(id: UUID, body: RichText, answer: RichText) throws {
    let stamp = now()
    try database.write { db in
      guard var question = try Question.find(id).fetchOne(db) else { throw StoreError.notFound }
      question.body = body.stored
      if question.answer != answer.stored {
        question.answer = answer.stored
        question.answeredBy = answer.isEmpty ? "" : owner()
        if !answer.isEmpty, !question.isDone {
          question.isDone = true
          question.doneAt = stamp
        }
      }
      question.editedAt = stamp
      try Question.update(question).execute(db)
    }
  }

  public func setQuestionDone(id: UUID, done: Bool) throws {
    let stamp = now()
    try database.write { db in
      guard var question = try Question.find(id).fetchOne(db) else { throw StoreError.notFound }
      question.isDone = done
      question.doneAt = done ? stamp : nil
      question.editedAt = stamp
      try Question.update(question).execute(db)
    }
  }

  public func questions() throws -> [Question] {
    try database.read { db in try QuestionsRequest().fetch(db) }
  }

  public func deleteQuestion(id: UUID) throws {
    try database.write { db in try Question.find(id).delete().execute(db) }
  }

  public func restoreQuestion(_ question: Question) throws {
    try database.write { db in try Question.upsert { question }.execute(db) }
  }

  // MARK: Feed alarm

  public func setFeedAlarm(fireAt: Date?, manual: Bool) throws {
    let alarm = try database.write { db in
      let baby = try requireBaby(db)
      return try upsertAlarm(db, baby: baby, fireAt: fireAt, manual: manual)
    }
    onChange(.alarmChanged(alarm))
  }

  public func handleFeedAlarm() throws {
    let alarm = try database.write { db -> FeedAlarm? in
      let baby = try requireBaby(db)
      guard var alarm = try FeedAlarm.find(baby.id).fetchOne(db) else { return nil }
      alarm.handledAt = now()
      alarm.handledBy = owner()
      try FeedAlarm.update(alarm).execute(db)
      return alarm
    }
    onChange(.alarmChanged(alarm))
  }

  @discardableResult
  func upsertAlarm(_ db: Database, baby: Baby, fireAt: Date?, manual: Bool) throws -> FeedAlarm {
    let alarm = FeedAlarm(
      babyID: baby.id, fireAt: fireAt, setBy: owner(), setAt: now(), isManual: manual,
      handledAt: nil, handledBy: nil)
    if try FeedAlarm.find(baby.id).fetchOne(db) != nil {
      try FeedAlarm.update(alarm).execute(db)
    } else {
      try FeedAlarm.insert { alarm }.execute(db)
    }
    return alarm
  }

  /// One alarm, always current: a new feed replaces whatever was pending.
  func autoArm(_ db: Database, baby: Baby, feedStart: Date, feedEnd: Date?) throws {
    let settings = baby.alarmSettings
    guard settings.autoArm != .off else { return }
    let fireAt = AlarmPlanner.autoArmFireDate(
      feedStartedAt: feedStart, feedEndedAt: feedEnd, settings: settings, night: baby.nightWindow,
      now: now(), calendar: calendar)
    // A backdated feed older than the latest one shouldn't move the alarm.
    if let latest = try latestFeedStart(db, baby: baby), latest > feedStart { return }
    try upsertAlarm(db, baby: baby, fireAt: fireAt, manual: false)
  }

  func latestFeedStart(_ db: Database, baby: Baby) throws -> Date? {
    let bottle = try Bottle.where { $0.babyID.eq(baby.id) }.order { $0.startedAt.desc() }
      .select(\.startedAt).fetchOne(db)
    let nursing = try NursingSession.where { $0.babyID.eq(baby.id) }.order { $0.startedAt.desc() }
      .select(\.startedAt).fetchOne(db)
    return [bottle, nursing].compactMap { $0 }.max()
  }

  // MARK: Devices

  public func updateDevice(_ update: (inout DeviceToken) -> Void) throws {
    try database.write { db in
      let baby = try requireBaby(db)
      let id = deviceID
      if var device = try DeviceToken.find(id).fetchOne(db) {
        let before = device
        update(&device)
        device.ownerName = owner()
        device.babyID = baby.id
        guard device != before else { return }
        device.updatedAt = now()
        try DeviceToken.update(device).execute(db)
      } else {
        var device = DeviceToken(
          id: id, babyID: baby.id, ownerName: owner(), pushToStartToken: nil, apnsToken: nil,
          activityPushToken: nil, activityEntryID: nil, alarmArmedFor: nil, alarmAuthorized: true,
          updatedAt: now())
        update(&device)
        try DeviceToken.insert { device }.execute(db)
      }
    }
  }

  // MARK: Reads

  func runningNursing(_ db: Database, baby: Baby) throws -> Entry? {
    guard
      let session = try NursingSession.where({ $0.babyID.eq(baby.id) && $0.endedAt.is(nil) })
        .order(by: { $0.startedAt.desc() }).fetchOne(db)
    else { return nil }
    let segments = try NursingSegment.where { $0.sessionID.eq(session.id) }
      .order { $0.startedAt.asc() }.fetchAll(db)
    return .nursing(session, segments: segments)
  }

  func predictedSide(_ db: Database, baby: Baby) throws -> Side {
    guard
      let last = try NursingSession.where({ $0.babyID.eq(baby.id) && $0.endedAt.isNot(nil) })
        .order(by: { $0.startedAt.desc() }).fetchOne(db)
    else { return .left }
    let segments = try NursingSegment.where { $0.sessionID.eq(last.id) }.fetchAll(db)
    let (l, r) = NursingMath.sideTotals(segments, now: now())
    return SidePredictor.nextSide(endedOn: last.endedOnSide, lastSessionDuration: l + r)
  }

  func fetchEntry(_ db: Database, id: UUID, kind: EventKind) throws -> Entry? {
    switch kind {
    case .bottle: return try Bottle.find(id).fetchOne(db).map(Entry.bottle)
    case .nursing:
      guard let s = try NursingSession.find(id).fetchOne(db) else { return nil }
      let segments = try NursingSegment.where { $0.sessionID.eq(id) }.order { $0.startedAt.asc() }.fetchAll(db)
      return .nursing(s, segments: segments)
    case .pump: return try PumpSession.find(id).fetchOne(db).map(Entry.pump)
    case .diaper: return try Diaper.find(id).fetchOne(db).map(Entry.diaper)
    case .sleep: return try SleepSession.find(id).fetchOne(db).map(Entry.sleep)
    case .note: return try BabyNote.find(id).fetchOne(db).map(Entry.note)
    }
  }

  public func snapshot(now date: Date) throws -> NestSnapshot {
    try database.read { db in
      try SnapshotBuilder.build(db, me: owner(), now: date, calendar: calendar)
    }
  }

  public func entries(from: Date, to: Date) throws -> [Entry] {
    try database.read { db in
      guard let baby = try Self.currentBaby(db) else { return [] }
      return try EntryQueries.entries(db, babyID: baby.id, from: from, to: to)
    }
  }

  public func history(since: Date) throws -> History {
    try database.read { db in
      guard let baby = try Self.currentBaby(db) else { return History() }
      return try EntryQueries.history(db, babyID: baby.id, since: since, now: now())
    }
  }

  // MARK: Import / export

  public func exportCSV() throws -> String {
    let all = try entries(from: .distantPast, to: .distantFuture)
    let rows = all.sorted { $0.date < $1.date }.map { EntryExport.row(for: $0, now: now()).fields }
    return CSV.encode(header: EntryRow.header, rows: rows)
  }

  public func importCSV(_ text: String) throws -> Int {
    let rows = try EntryRow.parse(csv: text)
    let stamp = now()
    let count = try database.write { db in
      let baby = try requireBaby(db)
      var count = 0
      for row in rows {
        let entry = EntryExport.entry(from: row, babyID: baby.id, fallbackOwner: owner(), now: stamp)
        // Skip rows already present (same type and start time), so re-importing is harmless.
        if try EntryQueries.exists(db, babyID: baby.id, kind: row.kind, at: row.startedAt) { continue }
        switch entry {
        case .bottle(let e): try Bottle.insert { e }.execute(db)
        case .nursing(let s, let segments):
          try NursingSession.insert { s }.execute(db)
          for segment in segments { try NursingSegment.insert { segment }.execute(db) }
        case .pump(let e): try PumpSession.insert { e }.execute(db)
        case .diaper(let e): try Diaper.insert { e }.execute(db)
        case .sleep(let e): try SleepSession.insert { e }.execute(db)
        case .note(let e): try BabyNote.insert { e }.execute(db)
        }
        count += 1
      }
      return count
    }
    onChange(.settingsChanged)
    return count
  }
}
