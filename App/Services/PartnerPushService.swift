import Foundation
import NestedCore
import NestedData

/// Calls the Cloudflare Worker (worker/src/index.js), which holds the APNs key, so a timer
/// started on one phone appears on the other phone's Lock Screen even when Nested isn't running
/// there, and a stopped alarm stops on both phones within seconds.
///
/// Configure `NestedWorkerURL` and `NestedWorkerKey` in project.yml. When unset, the partner still
/// sees running timers through sync, in widgets and in the app.
@MainActor
final class PartnerPushService {
  static let shared = PartnerPushService()

  private let endpoint: URL?
  private let key: String
  private let encoder = JSONEncoder()

  init(bundle: Bundle = .main) {
    let url = (bundle.object(forInfoDictionaryKey: "NestedWorkerURL") as? String) ?? ""
    endpoint = url.isEmpty ? nil : URL(string: url)
    key = (bundle.object(forInfoDictionaryKey: "NestedWorkerKey") as? String) ?? ""
  }

  var isConfigured: Bool { endpoint != nil && !key.isEmpty }

  func handle(_ change: StoreChange, snapshot: NestedSnapshot) {
    guard isConfigured else { return }
    let partners = snapshot.otherDevices
    guard !partners.isEmpty else { return }

    switch change {
    case .timerStarted(let entry):
      guard let payload = liveActivity(for: entry, snapshot: snapshot) else { return }
      for device in partners {
        guard let token = device.pushToStartToken else { continue }
        send([
          "type": "liveactivity", "event": "start", "token": token,
          "attributesType": "NestedTimerAttributes", "attributes": payload.attributes,
          "contentState": payload.state,
          "alert": ["title": "\(snapshot.me) started \(entry.kind.title.lowercased())",
                    "body": entry.title(unit: snapshot.unit)],
        ])
      }
    case .sideSwitched(let entry), .edited(let entry):
      guard entry.isRunning, let payload = liveActivity(for: entry, snapshot: snapshot) else { return }
      for device in partners where device.activityEntryID == entry.id {
        guard let token = device.activityPushToken else { continue }
        send(["type": "liveactivity", "event": "update", "token": token, "contentState": payload.state])
      }
    case .timerStopped(let entry), .deleted(let entry):
      for device in partners where device.activityEntryID == entry.id {
        guard let token = device.activityPushToken else { continue }
        let state = liveActivity(for: entry, snapshot: snapshot)?.state ?? [:]
        send(["type": "liveactivity", "event": "end", "token": token, "contentState": state])
      }
    case .alarmChanged(let alarm):
      // Stop / snooze / re-arm: wake the partner's app so it reschedules immediately.
      _ = alarm
      for device in partners {
        guard let token = device.apnsToken else { continue }
        send(["type": "background", "token": token])
      }
    case .logged, .settingsChanged:
      break
    }
  }

  private func liveActivity(
    for entry: Entry, snapshot: NestedSnapshot
  ) -> (attributes: [String: Any], state: [String: Any])? {
    let now = Date()
    let state: NestedTimerAttributes.ContentState
    switch entry {
    case .nursing(let session, let segments):
      let active = ActiveNursing(session: session, segments: segments)
      let (l, r) = active.totals(now: now)
      state = .init(
        timerStart: active.effectiveStart(now: now), sideStart: active.currentSegmentStart,
        side: active.currentSide, isPaused: active.isPaused, pausedElapsed: active.isPaused ? l + r : nil,
        leftSeconds: l, rightSeconds: r, loggedBy: session.loggedBy)
    case .pump(let p):
      state = .init(
        timerStart: p.startedAt, sideStart: nil, side: nil, isPaused: false, pausedElapsed: nil,
        leftSeconds: 0, rightSeconds: 0, loggedBy: p.loggedBy)
    case .sleep(let s):
      state = .init(
        timerStart: s.startedAt, sideStart: nil, side: nil, isPaused: false, pausedElapsed: nil,
        leftSeconds: 0, rightSeconds: 0, loggedBy: s.loggedBy)
    default:
      return nil
    }
    let attributes = NestedTimerAttributes(entryID: entry.id, kind: entry.kind, babyName: snapshot.babyName)
    // Encode with ActivityKit's own JSON conventions (default JSONEncoder date strategy).
    guard
      let stateObject = try? JSONSerialization.jsonObject(with: encoder.encode(state)) as? [String: Any],
      let attributesObject = try? JSONSerialization.jsonObject(with: encoder.encode(attributes)) as? [String: Any]
    else { return nil }
    return (attributesObject, stateObject)
  }

  private func send(_ body: [String: Any]) {
    guard let endpoint, let data = try? JSONSerialization.data(withJSONObject: body) else { return }
    var request = URLRequest(url: endpoint.appendingPathComponent("push"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    request.httpBody = data
    request.timeoutInterval = 10
    Task.detached {
      _ = try? await URLSession.shared.data(for: request)
    }
  }
}
