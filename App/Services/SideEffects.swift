import Combine
import NestCore
import NestData
import SQLiteData
import SwiftUI
import WidgetKit

/// Reacts to every database change — local writes and partner changes arriving through
/// CloudKit alike — by reloading widgets and controls, rescheduling the feed alarm,
/// reconciling Live Activities and posting notifications.
@MainActor
final class SideEffects {
  static let shared = SideEffects()

  @Fetch(SnapshotRequest()) private var snapshot = NestSnapshot.empty
  private var cancellable: AnyCancellable?
  private var store: (any EventStore)?
  private(set) var latest = NestSnapshot.empty

  func start(store: any EventStore) {
    self.store = store
    cancellable = $snapshot.publisher
      .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
      .sink { [weak self] snapshot in
        MainActor.assumeIsolated { self?.apply(snapshot) }
      }
    LiveActivityService.shared.startObservingTokens(store: store)
  }

  /// The owner name changed: rebuild the snapshot for the new "me".
  func reload(me: String) {
    Task { try? await $snapshot.load(SnapshotRequest(me: me)) }
  }

  func refresh() {
    guard let store, let snapshot = try? store.snapshot(now: Date()) else { return }
    apply(snapshot)
  }

  private func apply(_ snapshot: NestSnapshot) {
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
