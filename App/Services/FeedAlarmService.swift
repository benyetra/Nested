import AlarmKit
import AppIntents
import NestCore
import NestData
import SwiftUI
import UserNotifications

/// AlarmKit metadata for the feed alarm (none needed beyond the type).
struct FeedAlarmMetadata: AlarmMetadata {}

/// Keeps this phone's single AlarmKit alarm in step with the shared `FeedAlarm` row.
///
/// Each phone schedules its own alarm from the shared record, so it rings even if the other
/// phone is offline at fire time. AlarmKit alarms break through silent mode and Focus and
/// forward to a paired Apple Watch.
@MainActor
@Observable
final class FeedAlarmService {
  static let shared = FeedAlarmService()

  private(set) var authorization: AlarmManager.AuthorizationState = AlarmManager.shared.authorizationState
  /// What this phone has armed, for the bedtime confirmation.
  private(set) var armedFor: Date?

  @ObservationIgnored private let manager = AlarmManager.shared
  @ObservationIgnored private let defaults = UserDefaults.standard

  private let idKey = "feedAlarm.scheduledID"
  private let fireKey = "feedAlarm.scheduledFireAt"
  private let fallbackID = "feed-alarm-fallback"

  var isDenied: Bool { authorization == .denied }

  private var scheduledID: UUID? {
    get { defaults.string(forKey: idKey).flatMap(UUID.init(uuidString:)) }
    set { defaults.set(newValue?.uuidString, forKey: idKey) }
  }

  private var scheduledFireAt: Date? {
    get { defaults.object(forKey: fireKey) as? Date }
    set { defaults.set(newValue, forKey: fireKey) }
  }

  init() {
    armedFor = scheduledFireAt.flatMap { $0 > Date() ? $0 : nil }
  }

  func requestAuthorization() async {
    if authorization == .notDetermined {
      authorization = (try? await manager.requestAuthorization()) ?? manager.authorizationState
    } else {
      authorization = manager.authorizationState
    }
  }

  /// Reschedules the local alarm whenever the shared row changes.
  func reconcile(_ snapshot: NestSnapshot, store: any EventStore) async {
    authorization = manager.authorizationState
    let now = Date()
    let desired: Date? = {
      guard
        let baby = snapshot.baby,
        let alarm = snapshot.pendingAlarm(now: now),
        let fireAt = alarm.fireAt,
        fireAt > now,
        AlarmPlanner.shouldRing(settings: baby.alarmSettings, me: snapshot.me, setBy: alarm.setBy)
      else { return nil }
      return fireAt
    }()

    // Stopped on the other phone: silence this one within seconds of the sync landing.
    if snapshot.feedAlarm?.handledAt != nil, let id = scheduledID {
      try? manager.stop(id: id)
    }

    if desired != scheduledFireAt || (desired != nil && scheduledID == nil) {
      cancelScheduled()
      if let desired, let baby = snapshot.baby {
        await schedule(at: desired, baby: baby, babyName: snapshot.babyName)
      }
    }

    let armed = scheduledFireAt.flatMap { $0 > now ? $0 : nil }
    armedFor = armed
    let authorized = authorization == .authorized
    try? store.updateDevice {
      $0.alarmArmedFor = armed
      $0.alarmAuthorized = authorized
    }
  }

  private func schedule(at fireAt: Date, baby: Baby, babyName: String) async {
    if authorization == .notDetermined { await requestAuthorization() }
    guard authorization == .authorized else {
      await scheduleFallbackNotification(at: fireAt, babyName: babyName)
      return
    }
    let id = UUID()
    let stop = AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.circle")
    let secondary: AlarmButton
    let secondaryIntent: any LiveActivityIntent
    switch baby.alarmSecondary {
    case .feedingNow:
      secondary = AlarmButton(text: "Feeding now", textColor: .white, systemImageName: "heart.fill")
      secondaryIntent = FeedingNowIntent(alarmID: id)
    case .snooze:
      secondary = AlarmButton(text: "Snooze 10 min", textColor: .white, systemImageName: "zzz")
      secondaryIntent = SnoozeFeedAlarmIntent(alarmID: id)
    }
    let alert = AlarmPresentation.Alert(
      title: "Time to feed \(babyName)",
      stopButton: stop,
      secondaryButton: secondary,
      secondaryButtonBehavior: .custom
    )
    let attributes = AlarmAttributes<FeedAlarmMetadata>(
      presentation: AlarmPresentation(alert: alert),
      metadata: FeedAlarmMetadata(),
      tintColor: EventKind.nursing.color
    )
    let configuration = AlarmManager.AlarmConfiguration<FeedAlarmMetadata>(
      schedule: .fixed(fireAt),
      attributes: attributes,
      stopIntent: StopFeedAlarmIntent(alarmID: id),
      secondaryIntent: secondaryIntent
    )
    do {
      _ = try await manager.schedule(id: id, configuration: configuration)
      scheduledID = id
      scheduledFireAt = fireAt
    } catch {
      await scheduleFallbackNotification(at: fireAt, babyName: babyName)
    }
  }

  private func cancelScheduled() {
    if let id = scheduledID {
      try? manager.cancel(id: id)
    }
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [fallbackID])
    scheduledID = nil
    scheduledFireAt = nil
  }

  /// When AlarmKit permission is denied: a time-sensitive notification, clearly labeled as
  /// not an alarm (it won't ring through silent mode).
  private func scheduleFallbackNotification(at fireAt: Date, babyName: String) async {
    let content = UNMutableNotificationContent()
    content.title = "Feed time for \(babyName)"
    content.body = "Notification only — Nest's alarm permission is off, so this won't ring on silent."
    content.sound = .default
    content.interruptionLevel = .timeSensitive
    content.categoryIdentifier = NotificationService.feedCategory
    let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireAt)
    let request = UNNotificationRequest(
      identifier: fallbackID, content: content,
      trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
    try? await UNUserNotificationCenter.current().add(request)
    scheduledID = nil
    scheduledFireAt = fireAt
  }
}
