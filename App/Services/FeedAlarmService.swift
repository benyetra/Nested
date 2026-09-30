import AlarmKit
import AppIntents
import NestedCore
import NestedData
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
      authorization = await Self.requestAlarmAuthorization() ?? manager.authorizationState
    } else {
      authorization = manager.authorizationState
    }
  }

  /// Reschedules the local alarm whenever the shared row changes.
  func reconcile(_ snapshot: NestedSnapshot, store: any EventStore) async {
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
    let configuration = Self.makeConfiguration(id: id, fireAt: fireAt, baby: baby, babyName: babyName, isTest: false)
    do {
      try await Self.scheduleAlarm(id: id, configuration: configuration)
      scheduledID = id
      scheduledFireAt = fireAt
    } catch {
      await scheduleFallbackNotification(at: fireAt, babyName: babyName)
    }
  }

  /// The alarm exactly as it rings for real: same title, buttons, colour and sound. The test
  /// version differs only in what the buttons do, so trying it never logs a feed or touches the
  /// shared alarm.
  nonisolated private static func makeConfiguration(
    id: UUID, fireAt: Date, baby: Baby, babyName: String, isTest: Bool
  ) -> AlarmManager.AlarmConfiguration<FeedAlarmMetadata> {
    let stop = AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.circle")
    let secondary: AlarmButton
    let secondaryIntent: any LiveActivityIntent
    switch baby.alarmSecondary {
    case .feedingNow:
      secondary = AlarmButton(text: "Feeding now", textColor: .white, systemImageName: "heart.fill")
      secondaryIntent = isTest ? TestAlarmButtonIntent(alarmID: id, button: "Feeding now") : FeedingNowIntent(alarmID: id)
    case .snooze:
      secondary = AlarmButton(text: "Snooze 10 min", textColor: .white, systemImageName: "zzz")
      secondaryIntent = isTest ? TestAlarmButtonIntent(alarmID: id, button: "Snooze") : SnoozeFeedAlarmIntent(alarmID: id)
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
    let stopIntent: any LiveActivityIntent =
      isTest ? TestAlarmButtonIntent(alarmID: id, button: "Stop") : StopFeedAlarmIntent(alarmID: id)
    return AlarmManager.AlarmConfiguration<FeedAlarmMetadata>(
      schedule: .fixed(fireAt),
      attributes: attributes,
      stopIntent: stopIntent,
      secondaryIntent: secondaryIntent
    )
  }

  // MARK: Developer test

  /// Rings a real AlarmKit alarm on this phone after `seconds`, through the same code path as a
  /// feed alarm. Returns a message for the developer screen.
  func scheduleTestAlarm(after seconds: TimeInterval, baby: Baby, babyName: String) async -> String {
    if authorization == .notDetermined { await requestAuthorization() }
    authorization = manager.authorizationState
    guard authorization == .authorized else {
      return "Alarm permission is off, so a real alarm can't ring. Turn it on in Settings ▸ Nested, or tap Request permission."
    }
    let id = UUID()
    let fireAt = Date().addingTimeInterval(seconds)
    let configuration = Self.makeConfiguration(id: id, fireAt: fireAt, baby: baby, babyName: babyName, isTest: true)
    do {
      try await Self.scheduleAlarm(id: id, configuration: configuration)
      AlarmTestLog.remember(id)
      return "Alarm set for \(fireAt.formatted(date: .omitted, time: .standard))."
    } catch {
      return "AlarmKit refused to schedule it: \(error.localizedDescription)"
    }
  }

  /// The notification a parent gets if alarm permission is denied (it does not ring on silent).
  func scheduleTestFallback(after seconds: TimeInterval, babyName: String) async -> String {
    let center = UNUserNotificationCenter.current()
    let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    guard granted else { return "Notifications are off for Nested, so there's nothing to show." }
    await postFallback(identifier: "feed-alarm-test-fallback", at: Date().addingTimeInterval(seconds), babyName: babyName)
    return "Notification set for \(Date().addingTimeInterval(seconds).formatted(date: .omitted, time: .standard)). Lock the phone and flip the silent switch to hear what it does."
  }

  /// Cancels every test alarm this screen scheduled.
  func cancelTestAlarms() {
    for id in AlarmTestLog.ids { try? manager.cancel(id: id) }
    AlarmTestLog.clear()
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["feed-alarm-test-fallback"])
  }

  // AlarmManager isn't Sendable: its async calls run off the main actor on the shared
  // instance, so no main-actor-held reference is sent across isolation.
  nonisolated private static func requestAlarmAuthorization() async -> AlarmManager.AuthorizationState? {
    try? await AlarmManager.shared.requestAuthorization()
  }

  nonisolated private static func scheduleAlarm(
    id: UUID, configuration: sending AlarmManager.AlarmConfiguration<FeedAlarmMetadata>
  ) async throws {
    _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
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
    await postFallback(identifier: fallbackID, at: fireAt, babyName: babyName)
    scheduledID = nil
    scheduledFireAt = fireAt
  }

  private func postFallback(identifier: String, at fireAt: Date, babyName: String) async {
    let content = UNMutableNotificationContent()
    content.title = "Feed time for \(babyName)"
    content.body = "Notification only — Nested's alarm permission is off, so this won't ring on silent."
    content.sound = .default
    content.interruptionLevel = .timeSensitive
    content.categoryIdentifier = NotificationService.feedCategory
    let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireAt)
    let request = UNNotificationRequest(
      identifier: identifier, content: content,
      trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
    try? await UNUserNotificationCenter.current().add(request)
  }
}
