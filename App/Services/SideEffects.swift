import Combine
import NestedCore
import NestedData
import SQLiteData
import SwiftUI
import WidgetKit

/// Reacts to every database change — local writes and partner changes arriving through
/// CloudKit alike — by reloading widgets and controls, rescheduling the feed alarm,
/// reconciling Live Activities and posting notifications.
///
/// It also owns the app's one database observation of the snapshot. Every screen reads
/// `snapshot` from here instead of running its own `@Fetch`, so a write triggers one
/// query instead of one per open tab.
@MainActor
@Observable
final class SideEffects {
  static let shared = SideEffects()

  @ObservationIgnored @Fetch(SnapshotRequest(), animation: Motion.standard) private var fetched = NestedSnapshot.empty
  @ObservationIgnored private var cancellable: AnyCancellable?
  @ObservationIgnored private var store: (any EventStore)?
  @ObservationIgnored private(set) var latest = NestedSnapshot.empty

  var snapshot: NestedSnapshot { fetched }

  func start(store: any EventStore) {
    self.store = store
    cancellable = $fetched.publisher
      // `generatedAt` changes on every fetch; only real changes should touch widgets,
      // alarms and Live Activities.
      .removeDuplicates(by: Self.isSameContent)
      .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
      .sink { [weak self] snapshot in
        MainActor.assumeIsolated { self?.apply(snapshot) }
      }
    LiveActivityService.shared.startObservingTokens(store: store)
  }

  /// Runs on the database's thread, so it must not be main-actor isolated (a closure written
  /// inline here would inherit that isolation and trap at runtime).
  nonisolated private static func isSameContent(_ old: NestedSnapshot, _ new: NestedSnapshot) -> Bool {
    var old = old
    old.generatedAt = new.generatedAt
    return old == new
  }

  /// The owner name changed: rebuild the snapshot for the new "me".
  func reload(me: String) {
    Task { try? await $fetched.load(SnapshotRequest(me: me)) }
  }

  func refresh() {
    guard let store else { return }
    // Build off the main thread; the read can wait behind a sync write.
    Task {
      let built = await Task.detached { try? store.snapshot(now: Date()) }.value
      if let built { apply(built) }
    }
  }

  private func apply(_ snapshot: NestedSnapshot) {
    latest = snapshot
    SharedStore.reloadSurfaces()
    guard let store, snapshot.baby != nil else { return }
    LiveActivityService.shared.reconcile(snapshot)
    NotificationService.shared.reconcile(snapshot)
    Task { await FeedAlarmService.shared.reconcile(snapshot, store: store) }
  }

  /// Local writes only: things the partner can't observe until sync lands.
  func handle(_ change: StoreChange) {
    PartnerPushService.shared.handle(change, snapshot: latest)
  }
}
