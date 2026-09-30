import Foundation
import GRDB
import NestedCore
import SQLiteData

// The shared schema. `Baby` is the single shared root record; every other table has exactly
// one foreign key pointing back to it (directly, or through one parent), which is what
// SQLiteData needs to share children automatically with the partner's iCloud account.
//
// Sync rules (see SQLiteData "CloudKitSync"): UUID primary keys, no UNIQUE constraints,
// `NOT NULL ON CONFLICT REPLACE DEFAULT` on columns so older app versions can sync, and
// no reserved CloudKit field names. Table SQL is frozen once shipped: add migrations, never
// edit existing ones.

extension Side: QueryBindable {}
extension BottleContents: QueryBindable {}
extension DiaperKind: QueryBindable {}
extension StoolColor: QueryBindable {}
extension StoolConsistency: QueryBindable {}
extension DiaperSize: QueryBindable {}
extension SleepLocation: QueryBindable {}
extension NoteTag: QueryBindable {}
extension MedicationCadence: QueryBindable {}
extension PumpDestination: QueryBindable {}
extension FeedingMode: QueryBindable {}
extension VolumeUnit: QueryBindable {}
extension EventKind: QueryBindable {}
extension AlarmAutoArm: QueryBindable {}
extension AlarmMeasuredFrom: QueryBindable {}
extension AlarmWhoRings: QueryBindable {}
extension AlarmSecondaryButton: QueryBindable {}

@Table("babies")
public struct Baby: Identifiable, Hashable, Sendable, Codable {
  public let id: UUID
  public var name = ""
  public var birthDate: Date?
  public var feedingMode: FeedingMode = .mixed
  public var unit: VolumeUnit = .ml
  public var nightStartMinutes = 20 * 60
  public var nightEndMinutes = 7 * 60
  public var alarmIntervalMinutes = 180
  public var alarmMeasuredFrom: AlarmMeasuredFrom = .feedStart
  public var alarmAutoArm: AlarmAutoArm = .nightOnly
  public var alarmWhoRings: AlarmWhoRings = .bothPhones
  public var alarmRingOwner: String?
  public var alarmSecondary: AlarmSecondaryButton = .feedingNow
  public var flagsEnabled = true
  public var flagMinFeeds = 8
  public var flagMinWet = 5
  public var flagMaxGapDayMinutes = 180
  public var flagMaxGapNightMinutes = 240
  public var flagNotifications = false
  public var wakeWindowOverrideMinutes: Int?
  public var formulaBrand: String?
  public var createdAt: Date

  public init(
    id: UUID = UUID(),
    name: String,
    birthDate: Date?,
    feedingMode: FeedingMode = .mixed,
    unit: VolumeUnit = .ml,
    createdAt: Date = Date()
  ) {
    self.id = id
    self.name = name
    self.birthDate = birthDate
    self.feedingMode = feedingMode
    self.unit = unit
    self.createdAt = createdAt
  }

  public var nightWindow: DayWindow {
    get { DayWindow(startMinutes: nightStartMinutes, endMinutes: nightEndMinutes) }
    set {
      nightStartMinutes = newValue.startMinutes
      nightEndMinutes = newValue.endMinutes
    }
  }

  public var alarmSettings: AlarmSettings {
    get {
      AlarmSettings(
        interval: TimeInterval(alarmIntervalMinutes * 60),
        measuredFrom: alarmMeasuredFrom,
        autoArm: alarmAutoArm,
        whoRings: alarmWhoRings,
        ringOwner: alarmRingOwner,
        secondaryButton: alarmSecondary
      )
    }
    set {
      alarmIntervalMinutes = Int(newValue.interval / 60)
      alarmMeasuredFrom = newValue.measuredFrom
      alarmAutoArm = newValue.autoArm
      alarmWhoRings = newValue.whoRings
      alarmRingOwner = newValue.ringOwner
      alarmSecondary = newValue.secondaryButton
    }
  }

  public var flagThresholds: FlagThresholds {
    get {
      FlagThresholds(
        enabled: flagsEnabled,
        minFeedsPer24h: flagMinFeeds,
        minWetPer24h: flagMinWet,
        maxGapDay: TimeInterval(flagMaxGapDayMinutes * 60),
        maxGapNight: TimeInterval(flagMaxGapNightMinutes * 60)
      )
    }
    set {
      flagsEnabled = newValue.enabled
      flagMinFeeds = newValue.minFeedsPer24h
      flagMinWet = newValue.minWetPer24h
      flagMaxGapDayMinutes = Int(newValue.maxGapDay / 60)
      flagMaxGapNightMinutes = Int(newValue.maxGapNight / 60)
    }
  }
}

@Table("bottles")
public struct Bottle: Identifiable, Hashable, Sendable, Codable {
  public let id: UUID
  public var babyID: Baby.ID
  public var startedAt: Date
  /// Amount finished.
  public var amountMl: Double
  public var offeredMl: Double?
  public var contents: BottleContents = .formula
  public var formulaBrand: String?
  public var durationSeconds: Double?
  public var loggedBy = ""
  public var note = ""
  public var timeZone = ""
  public var createdAt: Date
  public var editedAt: Date
}

@Table("nursingSessions")
public struct NursingSession: Identifiable, Hashable, Sendable, Codable {
  public let id: UUID
  public var babyID: Baby.ID
  public var startedAt: Date
  /// nil while the timer is running.
  public var endedAt: Date?
  public var endedOnSide: Side?
  /// Set while paused; the open segment is closed at the same moment.
  public var pausedAt: Date?
  public var pausedSeconds: Double = 0
  public var latchNote = ""
  public var loggedBy = ""
  public var note = ""
  public var timeZone = ""
  public var createdAt: Date
  public var editedAt: Date

  public var isRunning: Bool { endedAt == nil }
  public var isPaused: Bool { pausedAt != nil }
}

@Table("nursingSegments")
public struct NursingSegment: Identifiable, Hashable, Sendable, Codable {
  public let id: UUID
  public var sessionID: NursingSession.ID
  public var side: Side
  public var startedAt: Date
  public var endedAt: Date?

  public func duration(now: Date) -> TimeInterval {
    Swift.max(0, (endedAt ?? now).timeIntervalSince(startedAt))
  }
}

@Table("pumpSessions")
public struct PumpSession: Identifiable, Hashable, Sendable, Codable {
  public let id: UUID
  public var babyID: Baby.ID
  public var startedAt: Date
  public var endedAt: Date?
  public var leftMl: Double?
  public var rightMl: Double?
  public var destination: PumpDestination?
  public var loggedBy = ""
  public var note = ""
  public var timeZone = ""
  public var createdAt: Date
  public var editedAt: Date

  public var isRunning: Bool { endedAt == nil }
  public var totalMl: Double { (leftMl ?? 0) + (rightMl ?? 0) }
}

@Table("diapers")
public struct Diaper: Identifiable, Hashable, Sendable, Codable {
  public let id: UUID
  public var babyID: Baby.ID
  public var occurredAt: Date
  public var kind: DiaperKind = .wet
  public var stoolColor: StoolColor?
  public var consistency: StoolConsistency?
  public var size: DiaperSize?
  public var rash = false
  public var loggedBy = ""
  public var note = ""
  public var timeZone = ""
  public var createdAt: Date
  public var editedAt: Date
}

@Table("sleeps")
public struct SleepSession: Identifiable, Hashable, Sendable, Codable {
  public let id: UUID
  public var babyID: Baby.ID
  public var startedAt: Date
  public var endedAt: Date?
  public var location: SleepLocation?
  public var loggedBy = ""
  public var note = ""
  public var timeZone = ""
  public var createdAt: Date
  public var editedAt: Date

  public var isRunning: Bool { endedAt == nil }
}

@Table("notes")
public struct BabyNote: Identifiable, Hashable, Sendable, Codable {
  public let id: UUID
  public var babyID: Baby.ID
  public var occurredAt: Date
  public var tag: NoteTag?
  public var text = ""
  public var loggedBy = ""
  public var timeZone = ""
  public var createdAt: Date
  public var editedAt: Date
}

/// A question to ask the pediatrician, and the answer written down at the appointment.
/// `body` and `answer` hold `RichText.stored` strings. `isDone` is the to-do checkbox.
@Table("questions")
public struct Question: Identifiable, Hashable, Sendable, Codable {
  public let id: UUID
  public var babyID: Baby.ID
  public var body = ""
  public var answer = ""
  public var isDone = false
  public var doneAt: Date?
  public var askedBy = ""
  public var answeredBy = ""
  public var createdAt: Date
  public var editedAt: Date
}

/// A small square JPEG for the baby or a parent. Kept in its own table so a photo change
/// doesn't rewrite (and re-sync) the `Baby` record. `subject` is `Avatar.babySubject` or
/// `Avatar.parentSubject(name)`; a parent's photo follows their name to the partner's phone.
@Table("avatars")
public struct Avatar: Identifiable, Hashable, Sendable, Codable {
  public let id: UUID
  public var babyID: Baby.ID
  public var subject = ""
  public var photo = Data()
  public var updatedAt: Date

  public static let babySubject = "baby"
  public static func parentSubject(_ name: String) -> String { "parent:\(name)" }
}

/// A medicine on a schedule, for the baby or a parent. Both phones schedule the same reminders
/// from these rows, so they go off at the same moment.
@Table("medications")
public struct Medication: Identifiable, Hashable, Sendable, Codable {
  public let id: UUID
  public var babyID: Baby.ID
  public var name = ""
  /// Free text: "1 mL", "400 IU", "half a tablet".
  public var dose = ""
  /// Who takes it: empty for the baby, otherwise a parent's name.
  public var forWho = ""
  public var cadence: MedicationCadence = .fixedTimes
  /// JSON array of minutes after midnight, for set-time schedules.
  public var timesOfDay = "[]"
  public var intervalMinutes = 0
  public var startsAt: Date
  public var endsAt: Date?
  public var notes = ""
  public var isActive = true
  public var createdBy = ""
  public var createdAt: Date
  public var editedAt: Date

  public var times: [Int] {
    get { (try? JSONDecoder().decode([Int].self, from: Data(timesOfDay.utf8))) ?? [] }
    set {
      let sorted = Array(Set(newValue)).sorted()
      timesOfDay = (try? JSONEncoder().encode(sorted)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }
  }

  public var plan: MedicationPlan {
    MedicationPlan(
      cadence: cadence, timesOfDay: times, intervalMinutes: intervalMinutes, startsAt: startsAt,
      endsAt: endsAt, isActive: isActive)
  }
}

/// One dose given (or skipped on purpose). `dueAt` ties it to the reminder it answers, so the
/// other phone stops asking.
@Table("medicationDoses")
public struct MedicationDose: Identifiable, Hashable, Sendable, Codable {
  public let id: UUID
  public var babyID: Baby.ID
  public var medicationID: Medication.ID
  public var dueAt: Date?
  public var takenAt: Date
  public var takenBy = ""
  public var skipped = false
  public var note = ""

  public var record: DoseRecord { DoseRecord(dueAt: dueAt, takenAt: takenAt, skipped: skipped) }
}

/// One row per installed device: Live Activity push tokens for the Worker, plus the
/// device's alarm-armed state for the bedtime confirmation.
@Table("deviceTokens")
public struct DeviceToken: Identifiable, Hashable, Sendable, Codable {
  public let id: UUID
  public var babyID: Baby.ID
  public var ownerName = ""
  public var pushToStartToken: String?
  public var apnsToken: String?
  public var activityPushToken: String?
  public var activityEntryID: UUID?
  public var alarmArmedFor: Date?
  public var alarmAuthorized = true
  public var updatedAt: Date
}

/// The single source of truth for the night feed alarm. The primary key is the baby, so
/// there is never more than one pending alarm; every phone reschedules its local AlarmKit
/// alarm whenever this row changes.
@Table("feedAlarms")
public struct FeedAlarm: Identifiable, Hashable, Sendable, Codable {
  @Column(primaryKey: true)
  public let babyID: Baby.ID
  /// nil when disarmed.
  public var fireAt: Date?
  public var setBy = ""
  public var setAt: Date
  public var isManual = false
  public var handledAt: Date?
  public var handledBy: String?

  public var id: Baby.ID { babyID }

  /// Armed and not yet handled.
  public func isPending(now: Date) -> Bool {
    guard let fireAt, handledAt == nil else { return false }
    return fireAt > now.addingTimeInterval(-15 * 60)
  }
}

/// Earlier versions of an edited entry, so a conflicting or mistaken edit is never lost.
@Table("entryRevisions")
public struct EntryRevision: Identifiable, Hashable, Sendable, Codable {
  public let id: UUID
  public var babyID: Baby.ID
  public var entryID: UUID
  public var kind: EventKind
  /// JSON of the entry before the edit.
  public var snapshot = ""
  public var editedBy = ""
  public var editedAt: Date
}

// MARK: - Migrations

public enum NestedSchema {
  /// Tables synchronized and shared through CloudKit, parents before children.
  public static let migrator: DatabaseMigrator = {
    var migrator = DatabaseMigrator()
    migrator.registerMigration("v1: create tables") { db in
      try #sql(
        """
        CREATE TABLE "babies" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "name" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "birthDate" TEXT,
          "feedingMode" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT 'mixed',
          "unit" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT 'ml',
          "nightStartMinutes" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 1200,
          "nightEndMinutes" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 420,
          "alarmIntervalMinutes" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 180,
          "alarmMeasuredFrom" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT 'feedStart',
          "alarmAutoArm" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT 'nightOnly',
          "alarmWhoRings" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT 'bothPhones',
          "alarmRingOwner" TEXT,
          "alarmSecondary" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT 'feedingNow',
          "flagsEnabled" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 1,
          "flagMinFeeds" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 8,
          "flagMinWet" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 5,
          "flagMaxGapDayMinutes" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 180,
          "flagMaxGapNightMinutes" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 240,
          "flagNotifications" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "wakeWindowOverrideMinutes" INTEGER,
          "formulaBrand" TEXT,
          "createdAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now'))
        ) STRICT
        """
      )
      .execute(db)

      try #sql(
        """
        CREATE TABLE "bottles" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "babyID" TEXT NOT NULL REFERENCES "babies"("id") ON DELETE CASCADE,
          "startedAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now')),
          "amountMl" REAL NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "offeredMl" REAL,
          "contents" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT 'formula',
          "formulaBrand" TEXT,
          "durationSeconds" REAL,
          "loggedBy" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "note" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "timeZone" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "createdAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now')),
          "editedAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now'))
        ) STRICT
        """
      )
      .execute(db)

      try #sql(
        """
        CREATE TABLE "nursingSessions" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "babyID" TEXT NOT NULL REFERENCES "babies"("id") ON DELETE CASCADE,
          "startedAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now')),
          "endedAt" TEXT,
          "endedOnSide" TEXT,
          "pausedAt" TEXT,
          "pausedSeconds" REAL NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "latchNote" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "loggedBy" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "note" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "timeZone" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "createdAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now')),
          "editedAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now'))
        ) STRICT
        """
      )
      .execute(db)

      try #sql(
        """
        CREATE TABLE "nursingSegments" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "sessionID" TEXT NOT NULL REFERENCES "nursingSessions"("id") ON DELETE CASCADE,
          "side" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT 'left',
          "startedAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now')),
          "endedAt" TEXT
        ) STRICT
        """
      )
      .execute(db)

      try #sql(
        """
        CREATE TABLE "pumpSessions" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "babyID" TEXT NOT NULL REFERENCES "babies"("id") ON DELETE CASCADE,
          "startedAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now')),
          "endedAt" TEXT,
          "leftMl" REAL,
          "rightMl" REAL,
          "destination" TEXT,
          "loggedBy" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "note" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "timeZone" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "createdAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now')),
          "editedAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now'))
        ) STRICT
        """
      )
      .execute(db)

      try #sql(
        """
        CREATE TABLE "diapers" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "babyID" TEXT NOT NULL REFERENCES "babies"("id") ON DELETE CASCADE,
          "occurredAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now')),
          "kind" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT 'wet',
          "stoolColor" TEXT,
          "consistency" TEXT,
          "size" TEXT,
          "rash" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "loggedBy" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "note" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "timeZone" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "createdAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now')),
          "editedAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now'))
        ) STRICT
        """
      )
      .execute(db)

      try #sql(
        """
        CREATE TABLE "sleeps" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "babyID" TEXT NOT NULL REFERENCES "babies"("id") ON DELETE CASCADE,
          "startedAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now')),
          "endedAt" TEXT,
          "location" TEXT,
          "loggedBy" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "note" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "timeZone" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "createdAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now')),
          "editedAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now'))
        ) STRICT
        """
      )
      .execute(db)

      try #sql(
        """
        CREATE TABLE "notes" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "babyID" TEXT NOT NULL REFERENCES "babies"("id") ON DELETE CASCADE,
          "occurredAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now')),
          "tag" TEXT,
          "text" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "loggedBy" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "timeZone" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "createdAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now')),
          "editedAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now'))
        ) STRICT
        """
      )
      .execute(db)

      try #sql(
        """
        CREATE TABLE "deviceTokens" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "babyID" TEXT NOT NULL REFERENCES "babies"("id") ON DELETE CASCADE,
          "ownerName" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "pushToStartToken" TEXT,
          "apnsToken" TEXT,
          "activityPushToken" TEXT,
          "activityEntryID" TEXT,
          "alarmArmedFor" TEXT,
          "alarmAuthorized" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 1,
          "updatedAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now'))
        ) STRICT
        """
      )
      .execute(db)

      try #sql(
        """
        CREATE TABLE "feedAlarms" (
          "babyID" TEXT PRIMARY KEY NOT NULL REFERENCES "babies"("id") ON DELETE CASCADE,
          "fireAt" TEXT,
          "setBy" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "setAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now')),
          "isManual" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "handledAt" TEXT,
          "handledBy" TEXT
        ) STRICT
        """
      )
      .execute(db)

      try #sql(
        """
        CREATE TABLE "entryRevisions" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "babyID" TEXT NOT NULL REFERENCES "babies"("id") ON DELETE CASCADE,
          "entryID" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "kind" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT 'note',
          "snapshot" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "editedBy" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "editedAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now'))
        ) STRICT
        """
      )
      .execute(db)
    }

    migrator.registerMigration("v1: indexes") { db in
      for (table, column) in [
        ("bottles", "babyID"), ("bottles", "startedAt"),
        ("nursingSessions", "babyID"), ("nursingSessions", "startedAt"),
        ("nursingSegments", "sessionID"),
        ("pumpSessions", "babyID"), ("pumpSessions", "startedAt"),
        ("diapers", "babyID"), ("diapers", "occurredAt"),
        ("sleeps", "babyID"), ("sleeps", "startedAt"),
        ("notes", "babyID"), ("notes", "occurredAt"),
        ("deviceTokens", "babyID"),
        ("entryRevisions", "babyID"), ("entryRevisions", "entryID"),
      ] {
        try db.execute(
          sql: """
            CREATE INDEX IF NOT EXISTS "idx_\(table)_\(column)" ON "\(table)"("\(column)")
            """)
      }
    }
    migrator.registerMigration("v2: questions") { db in
      try #sql(
        """
        CREATE TABLE "questions" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "babyID" TEXT NOT NULL REFERENCES "babies"("id") ON DELETE CASCADE,
          "body" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "answer" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "isDone" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "doneAt" TEXT,
          "askedBy" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "answeredBy" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "createdAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now')),
          "editedAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now'))
        ) STRICT
        """
      )
      .execute(db)
      try db.execute(
        sql: """
          CREATE INDEX IF NOT EXISTS "idx_questions_babyID" ON "questions"("babyID")
          """)
    }

    migrator.registerMigration("v3: avatars") { db in
      try #sql(
        """
        CREATE TABLE "avatars" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "babyID" TEXT NOT NULL REFERENCES "babies"("id") ON DELETE CASCADE,
          "subject" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "photo" BLOB NOT NULL ON CONFLICT REPLACE DEFAULT x'',
          "updatedAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now'))
        ) STRICT
        """
      )
      .execute(db)
      try db.execute(
        sql: """
          CREATE INDEX IF NOT EXISTS "idx_avatars_babyID" ON "avatars"("babyID")
          """)
    }

    migrator.registerMigration("v4: medications") { db in
      try #sql(
        """
        CREATE TABLE "medications" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "babyID" TEXT NOT NULL REFERENCES "babies"("id") ON DELETE CASCADE,
          "name" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "dose" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "forWho" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "cadence" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT 'fixedTimes',
          "timesOfDay" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '[]',
          "intervalMinutes" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "startsAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now')),
          "endsAt" TEXT,
          "notes" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "isActive" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 1,
          "createdBy" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "createdAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now')),
          "editedAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now'))
        ) STRICT
        """
      )
      .execute(db)
      try #sql(
        """
        CREATE TABLE "medicationDoses" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "babyID" TEXT NOT NULL REFERENCES "babies"("id") ON DELETE CASCADE,
          "medicationID" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "dueAt" TEXT,
          "takenAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now')),
          "takenBy" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "skipped" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "note" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT ''
        ) STRICT
        """
      )
      .execute(db)
      for (table, column) in [
        ("medications", "babyID"), ("medicationDoses", "babyID"),
        ("medicationDoses", "medicationID"), ("medicationDoses", "takenAt"),
      ] {
        try db.execute(
          sql: """
            CREATE INDEX IF NOT EXISTS "idx_\(table)_\(column)" ON "\(table)"("\(column)")
            """)
      }
    }

    return migrator
  }()

  /// Registers the functions the schema's defaults rely on.
  public static func prepare(_ db: Database) {
    db.add(
      function: GRDB.DatabaseFunction("uuid", argumentCount: 0, pure: false) { _ in
        UUID().uuidString.lowercased()
      })
  }

  /// Opens (or creates) and migrates the database at `url`. Pass nil for an in-memory
  /// database (tests, previews).
  public static func open(
    at url: URL?,
    configure: (inout Configuration) -> Void = { _ in }
  ) throws -> any DatabaseWriter {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    configuration.prepareDatabase { db in
      prepare(db)
    }
    configure(&configuration)
    let database: any DatabaseWriter
    if let url {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      database = try DatabasePool(path: url.path, configuration: configuration)
    } else {
      database = try DatabaseQueue(configuration: configuration)
    }
    try migrator.migrate(database)
    return database
  }
}
