import Foundation
import NestCore
import NestData
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
        try prepareDependencies {
          try $0.bootstrapNest(sync: .deferred)
        }
        @Dependency(\.defaultDatabase) var database
        let store = LiveEventStore(database: database) { _ in
          NestDatabase.postExternalWrite()
          SharedStore.reloadSurfaces()
        }
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
