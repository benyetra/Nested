import ActivityKit
import NestCore
import NestData
import SwiftUI

/// Mirrors running timers as Live Activities on this phone, and publishes this phone's
/// push tokens so the partner's phone can start/update/end activities here via the Worker.
@MainActor
final class LiveActivityService {
  static let shared = LiveActivityService()

  private var signatures: [UUID: String] = [:]
  private var observers: [Task<Void, Never>] = []
  private var activityTokenTasks: [String: Task<Void, Never>] = [:]

  func reconcile(_ snapshot: NestSnapshot) {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    let desired = NestTimerAttributes.running(in: snapshot)
    let desiredIDs = Set(desired.map(\.0.entryID))
    let activities = Activity<NestTimerAttributes>.activities

    for activity in activities where !desiredIDs.contains(activity.attributes.entryID) {
      signatures[activity.attributes.entryID] = nil
      Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    for (attributes, state) in desired {
      let signature = NestTimerAttributes.eventSignature(state)
      let content = ActivityContent(state: state, staleDate: nil, relevanceScore: 100)
      if let existing = activities.first(where: { $0.attributes.entryID == attributes.entryID }) {
        guard signatures[attributes.entryID] != signature else { continue }
        signatures[attributes.entryID] = signature
        Task { await existing.update(content) }
      } else {
        signatures[attributes.entryID] = signature
        _ = try? Activity.request(attributes: attributes, content: content, pushType: .token)
      }
    }
  }

  /// Tokens are refreshed on every launch (PRD risk: expired tokens).
  func startObservingTokens(store: any EventStore) {
    guard observers.isEmpty else { return }
    observers.append(
      Task {
        for await data in Activity<NestTimerAttributes>.pushToStartTokenUpdates {
          let token = data.hexString
          try? store.updateDevice { $0.pushToStartToken = token }
        }
      })
    observers.append(
      Task { [weak self] in
        for await activity in Activity<NestTimerAttributes>.activityUpdates {
          self?.observeToken(of: activity, store: store)
        }
      })
    for activity in Activity<NestTimerAttributes>.activities {
      observeToken(of: activity, store: store)
    }
  }

  private func observeToken(of activity: Activity<NestTimerAttributes>, store: any EventStore) {
    guard activityTokenTasks[activity.id] == nil else { return }
    let entryID = activity.attributes.entryID
    activityTokenTasks[activity.id] = Task {
      for await data in activity.pushTokenUpdates {
        let token = data.hexString
        try? store.updateDevice {
          $0.activityPushToken = token
          $0.activityEntryID = entryID
        }
      }
    }
  }
}

extension Data {
  var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
