import Foundation
import NestedCore
import NestedData
import SQLiteData
#if canImport(WidgetKit)
  import WidgetKit
#endif

/// The process-wide `EventStore`.
///
/// The app configures it at launch with its live sync engine. Extensions (widgets, controls,
/// intents running out of process) open the same App Group database lazily with a deferred
/// sync engine: their writes are recorded as pending CloudKit changes and the app uploads
/// them as soon as it hears the external-write notification.
enum SharedStore {
  nonisolated(unsafe) private static var configured: (any EventStore)?
  private static let lock = NSLock()

  static func configure(_ store: any EventStore) {
    lock.withLock { configured = store }
  }

  static var store: any EventStore {
    get throws {
      try lock.withLock {
        if let configured { return configured }
        let database = NestedBootstrap.run(sync: .deferred)
        let store = LiveEventStore(database: database, onChange: { _ in
          NestedDatabase.postExternalWrite()
          SharedStore.reloadSurfaces()
        })
        configured = store
        return store
      }
    }
  }

  /// Widgets and controls reload on every write, local or synced.
  static func reloadSurfaces() {
    #if canImport(WidgetKit)
      WidgetCenter.shared.reloadAllTimelines()
      #if os(iOS)
        ControlCenter.shared.reloadAllControls()
      #endif
    #endif
  }
}

/// Opens the database and sync engine for a process without ever crashing on a setup
/// problem (missing App Group or iCloud capability). Problems are collected so the app can
/// explain them instead.
enum NestedBootstrap {
  nonisolated(unsafe) private(set) static var syncEngine: SyncEngine?
  nonisolated(unsafe) private(set) static var problems: [String] = []

  static func run(sync: NestedSyncMode, delegate: (any SyncEngineDelegate)? = nil) -> any DatabaseWriter {
    var problems: [String] = []
    if NestedDatabase.fileURL == nil {
      problems.append(
        "The App Group \(DevicePrefs.appGroup) isn't available, so entries are kept in memory only "
          + "and widgets can't see them. Add the App Groups capability in Signing & Capabilities.")
    }
    let database: any DatabaseWriter
    do {
      database = try NestedDatabase.openShared()
    } catch {
      problems.append("Couldn't open the database: \(error.localizedDescription)")
      database = try! NestedDatabase.openInMemory()
    }
    if sync != .none {
      do {
        syncEngine = try NestedDatabase.makeSyncEngine(
          for: database, startImmediately: sync == .live, delegate: delegate)
      } catch {
        problems.append(
          "iCloud sync is off (\(error)). Check the iCloud capability with CloudKit and the "
            + "container \(NestedDatabase.containerIdentifier), and that this device is signed in to iCloud.")
      }
    }
    let engine = syncEngine
    prepareDependencies {
      $0.defaultDatabase = database
      if let engine { $0.defaultSyncEngine = engine }
    }
    self.problems = problems
    return database
  }
}
