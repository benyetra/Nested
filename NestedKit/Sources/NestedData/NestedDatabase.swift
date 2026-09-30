import Foundation
import NestedCore
import SQLiteData

#if canImport(CloudKit)
  import CloudKit
#endif

/// Opening the shared database and wiring CloudKit sync.
///
/// The SQLite file lives in the App Group container so the app, widgets, controls, intents and
/// Live Activities all read the same data.
public enum NestedDatabase {
  public static let containerIdentifier = "iCloud.com.yetra.nest"
  /// Posted (Darwin notification) by extensions after they write, so the app's sync engine
  /// uploads the change without waiting for the next launch.
  public static let externalWriteNotification = "com.yetra.nest.external-write"

  public static var fileURL: URL? {
    #if canImport(Darwin)
      FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: DevicePrefs.appGroup)?
        // The folder keeps its original name: renaming it would orphan the existing database.
        .appendingPathComponent("Nest", isDirectory: true)
        .appendingPathComponent("nest.sqlite")
    #else
      nil
    #endif
  }

  /// Opens the shared on-disk database with the CloudKit metadatabase attached.
  public static func openShared() throws -> any DatabaseWriter {
    try NestedSchema.open(at: fileURL) { configuration in
      // Release file locks when suspended: required for SQLite in a shared container.
      configuration.observesSuspensionNotifications = true
      #if canImport(CloudKit)
        configuration.prepareDatabase { db in
          try db.attachMetadatabase(containerIdentifier: containerIdentifier)
        }
      #endif
    }
  }

  /// Opens an in-memory database, for previews and tests.
  public static func openInMemory() throws -> any DatabaseWriter {
    try NestedSchema.open(at: nil)
  }

  #if canImport(CloudKit)
    /// Every synchronized table. `Baby` is the shared root; the rest follow it into the
    /// partner's iCloud account through their single foreign key.
    public static func makeSyncEngine(
      for database: any DatabaseWriter,
      startImmediately: Bool = true,
      delegate: (any SyncEngineDelegate)? = nil
    ) throws -> SyncEngine {
      try SyncEngine(
        for: database,
        tables: Baby.self,
        Bottle.self,
        NursingSession.self,
        NursingSegment.self,
        PumpSession.self,
        Diaper.self,
        SleepSession.self,
        BabyNote.self,
        DeviceToken.self,
        FeedAlarm.self,
        EntryRevision.self,
        Question.self,
        Avatar.self,
        Medication.self,
        MedicationDose.self,
        containerIdentifier: containerIdentifier,
        startImmediately: startImmediately,
        delegate: delegate
      )
    }
  #endif

  /// Tells the app process that an extension wrote to the database.
  public static func postExternalWrite() {
    #if canImport(Darwin)
      CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFNotificationName(externalWriteNotification as CFString), nil, nil, true)
    #endif
  }
}

#if canImport(CloudKit)
  extension DependencyValues {
    /// Prepares the database (and optionally the sync engine) for a process.
    ///
    /// - The app runs the sync engine.
    /// - Extensions pass `sync: .deferred`: they install the sync triggers so their writes are
    ///   recorded as pending changes, and the app uploads them when it next starts syncing.
    public mutating func bootstrapNested(
      sync: NestedSyncMode,
      delegate: (any SyncEngineDelegate)? = nil
    ) throws {
      defaultDatabase = try NestedDatabase.openShared()
      switch sync {
      case .live:
        defaultSyncEngine = try NestedDatabase.makeSyncEngine(for: defaultDatabase, delegate: delegate)
      case .deferred:
        defaultSyncEngine = try NestedDatabase.makeSyncEngine(
          for: defaultDatabase, startImmediately: false, delegate: delegate)
      case .none:
        break
      }
    }
  }

  public enum NestedSyncMode: Sendable {
    case live
    case deferred
    case none
  }
#endif
