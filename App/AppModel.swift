import NestCore
import NestData
import SwiftUI

enum AppTab: Hashable {
  case now
  case timeline
  case trends
  case settings
}

/// A log sheet to present. `Identifiable` for `.sheet(item:)`.
struct LogRoute: Identifiable, Hashable {
  var kind: EventKind
  var id: EventKind { kind }
}

struct Toast: Identifiable {
  let id = UUID()
  var message: String
  var undo: (@MainActor () -> Void)?
}

/// A feed the user started while a sleep timer runs; confirmed with one tap.
struct PendingFeed: Identifiable {
  let id = UUID()
  var title: String
  var perform: @MainActor (_ endSleep: Bool) -> Void
}

/// App-wide UI state: sheet routing, undo toasts, haptic triggers, errors.
///
/// Views never write to the database themselves; they call `store` through `perform`, which
/// shows the 5-second undo toast (undo, not confirm) and fires haptics on the same frame.
@MainActor
@Observable
final class AppModel {
  let store: any EventStore
  var tab: AppTab = .now
  var route: LogRoute?
  var editing: Entry?
  var toast: Toast?
  var pendingFeed: PendingFeed?
  var errorMessage: String?
  var ownerName: String = DevicePrefs.ownerName

  // Haptic triggers, bumped on the frame the state changes.
  var successTick = 0
  var impactTick = 0
  var selectionTick = 0

  private var toastTask: Task<Void, Never>?

  init(store: any EventStore) {
    self.store = store
  }

  func open(_ kind: EventKind) {
    route = LogRoute(kind: kind)
  }

  func handle(url: URL) {
    if let kind = NestLink.kind(from: url) {
      tab = .now
      open(kind)
    } else if url == NestLink.trends {
      tab = .trends
    } else {
      tab = .now
    }
  }

  func setOwner(_ name: String) {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    DevicePrefs.ownerName = trimmed
    ownerName = trimmed
  }

  // MARK: Writes

  enum Undo {
    /// Undo by deleting what was just created (logs and timer starts).
    case deleteResult
    /// Undo by saving this earlier version back (timer stops, side switches, edits).
    case restoreVersion(Entry)
    /// Undo a deletion.
    case restoreDeleted(Entry)
    case none
  }

  enum Haptic {
    case success
    case impact
    case selection
  }

  /// Runs a store write, then shows the undo toast and fires haptics.
  @discardableResult
  func perform(
    _ message: String? = nil,
    haptic: Haptic = .success,
    undo: Undo = .deleteResult,
    _ action: () throws -> Entry?
  ) -> Entry? {
    do {
      let entry = try action()
      switch haptic {
      case .success: successTick += 1
      case .impact: impactTick += 1
      case .selection: selectionTick += 1
      }
      if let message {
        showToast(message, undo: undoAction(for: undo, result: entry))
      }
      return entry
    } catch {
      errorMessage = String(describing: error)
      return nil
    }
  }

  private func undoAction(for undo: Undo, result: Entry?) -> (@MainActor () -> Void)? {
    let store = store
    switch undo {
    case .deleteResult:
      guard let result else { return nil }
      return { try? store.delete(result) }
    case .restoreVersion(let earlier):
      return { try? store.save(earlier) }
    case .restoreDeleted(let entry):
      return { try? store.restore(entry) }
    case .none:
      return nil
    }
  }

  func showToast(_ message: String, undo: (@MainActor () -> Void)? = nil) {
    toastTask?.cancel()
    withAnimation(Motion.standard) { toast = Toast(message: message, undo: undo) }
    toastTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(5))
      guard !Task.isCancelled else { return }
      withAnimation(Motion.standard) { self?.toast = nil }
    }
  }

  func undoToast() {
    toast?.undo?()
    selectionTick += 1
    withAnimation(Motion.standard) { toast = nil }
  }

  func delete(_ entry: Entry, unit: VolumeUnit) {
    perform("Deleted \(entry.kind.title.lowercased())", haptic: .impact, undo: .restoreDeleted(entry)) {
      try store.delete(entry)
      return nil
    }
  }

  func duplicate(_ entry: Entry) {
    perform("Duplicated \(entry.kind.title.lowercased())") {
      try store.duplicate(entry, at: Date())
    }
  }

  func save(_ edited: Entry, original: Entry) {
    perform("Saved", haptic: .success, undo: .restoreVersion(original)) {
      try store.save(edited)
      return edited
    }
  }

  /// Starting a feed while she's asleep offers "End sleep and start feed?" as one tap.
  func startFeed(title: String, sleepRunning: Bool, _ start: @escaping @MainActor (_ endSleep: Bool) -> Void) {
    if sleepRunning {
      pendingFeed = PendingFeed(title: title, perform: start)
    } else {
      start(false)
    }
  }
}
