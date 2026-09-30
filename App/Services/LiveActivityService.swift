import ActivityKit
import NestedCore
import NestedData
import SwiftUI

/// Mirrors running timers as Live Activities on this phone, and publishes this phone's
/// push tokens so the partner's phone can start/update/end activities here via the Worker.
///
/// `Activity` isn't Sendable, so async work on an activity happens in nonisolated helpers
/// that look it up by ID rather than sending a main-actor reference across isolation.
@MainActor
final class LiveActivityService {
  static let shared = LiveActivityService()

  private var signatures: [UUID: String] = [:]
  private var observers: [Task<Void, Never>] = []
  private var observedActivityIDs: Set<String> = []

  func reconcile(_ snapshot: NestedSnapshot) {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    let desired = NestedTimerAttributes.running(in: snapshot)
    let desiredIDs = Set(desired.map(\.0.entryID))
    let activities = Activity<NestedTimerAttributes>.activities

    for activity in activities where !desiredIDs.contains(activity.attributes.entryID) {
      signatures[activity.attributes.entryID] = nil
      let id = activity.id
      Task { await Self.end(activityID: id) }
    }

    for (attributes, state) in desired {
      let signature = NestedTimerAttributes.eventSignature(state)
      if let existing = activities.first(where: { $0.attributes.entryID == attributes.entryID }) {
        guard signatures[attributes.entryID] != signature else { continue }
        signatures[attributes.entryID] = signature
        let id = existing.id
        Task { await Self.update(activityID: id, state: state) }
      } else {
        signatures[attributes.entryID] = signature
        let content = ActivityContent(state: state, staleDate: nil, relevanceScore: 100)
        _ = try? Activity.request(attributes: attributes, content: content, pushType: .token)
      }
    }
  }

  nonisolated private static func end(activityID: String) async {
    for activity in Activity<NestedTimerAttributes>.activities where activity.id == activityID {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
  }

  nonisolated private static func update(activityID: String, state: NestedTimerAttributes.ContentState) async {
    for activity in Activity<NestedTimerAttributes>.activities where activity.id == activityID {
      await activity.update(ActivityContent(state: state, staleDate: nil, relevanceScore: 100))
    }
  }

  /// Tokens are refreshed on every launch (PRD risk: expired tokens).
  func startObservingTokens(store: any EventStore) {
    guard observers.isEmpty else { return }
    observers.append(
      Task.detached {
        for await data in Activity<NestedTimerAttributes>.pushToStartTokenUpdates {
          let token = data.hexString
          try? store.updateDevice { $0.pushToStartToken = token }
        }
      })
    observers.append(
      Task.detached {
        for await activity in Activity<NestedTimerAttributes>.activityUpdates {
          let id = activity.id
          await LiveActivityService.shared.observeToken(activityID: id, store: store)
        }
      })
    for activity in Activity<NestedTimerAttributes>.activities {
      observeToken(activityID: activity.id, store: store)
    }
  }

  private func observeToken(activityID: String, store: any EventStore) {
    guard observedActivityIDs.insert(activityID).inserted else { return }
    Task.detached { await Self.forwardTokens(activityID: activityID, store: store) }
  }

  nonisolated private static func forwardTokens(activityID: String, store: any EventStore) async {
    guard let activity = Activity<NestedTimerAttributes>.activities.first(where: { $0.id == activityID }) else {
      return
    }
    let entryID = activity.attributes.entryID
    for await data in activity.pushTokenUpdates {
      let token = data.hexString
      try? store.updateDevice {
        $0.activityPushToken = token
        $0.activityEntryID = entryID
      }
    }
  }
}

extension Data {
  var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
