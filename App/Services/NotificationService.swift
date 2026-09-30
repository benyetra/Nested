import NestedCore
import NestedData
import SwiftUI
import UserNotifications

/// Optional predicted-feed reminders and gentle-flag notifications, with actionable buttons.
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
  static let shared = NotificationService()

  static let feedCategory = "FEED_REMINDER"
  static let flagCategory = "HEALTH_FLAG"
  static let feedReminderKey = "feedReminders"

  private enum Action {
    static let logBottle = "LOG_BOTTLE"
    static let startNursing = "START_NURSING"
    static let snooze = "SNOOZE_15"
  }

  private let center = UNUserNotificationCenter.current()
  private let reminderID = "predicted-feed"
  private var notifiedFlags: Set<String> {
    get { Set(UserDefaults.standard.stringArray(forKey: "notifiedFlags") ?? []) }
    set { UserDefaults.standard.set(Array(newValue.suffix(50)), forKey: "notifiedFlags") }
  }

  var feedRemindersEnabled: Bool {
    UserDefaults.standard.bool(forKey: Self.feedReminderKey)
  }

  func configure() {
    center.delegate = self
    let logBottle = UNNotificationAction(identifier: Action.logBottle, title: "Log bottle", options: [])
    let startNursing = UNNotificationAction(identifier: Action.startNursing, title: "Start nursing", options: [])
    let snooze = UNNotificationAction(identifier: Action.snooze, title: "Snooze 15 min", options: [])
    center.setNotificationCategories([
      UNNotificationCategory(
        identifier: Self.feedCategory, actions: [logBottle, startNursing, snooze], intentIdentifiers: []),
      UNNotificationCategory(identifier: Self.flagCategory, actions: [], intentIdentifiers: []),
    ])
  }

  func requestAuthorization() async {
    _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
  }

  func reconcile(_ snapshot: NestedSnapshot) {
    scheduleFeedReminder(snapshot)
    postFlags(snapshot)
  }

  private func scheduleFeedReminder(_ snapshot: NestedSnapshot) {
    center.removePendingNotificationRequests(withIdentifiers: [reminderID])
    guard feedRemindersEnabled, let prediction = snapshot.feedPrediction, snapshot.activeNursing == nil
    else { return }
    let fireAt = prediction.earliest
    guard fireAt > Date() else { return }
    let content = UNMutableNotificationContent()
    content.title = "Feed window opening"
    content.body = "Next feed ~\(fireAt.formatted(date: .omitted, time: .shortened)) (\(prediction.basis))."
    content.categoryIdentifier = Self.feedCategory
    content.interruptionLevel = .timeSensitive
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, fireAt.timeIntervalSinceNow), repeats: false)
    center.add(UNNotificationRequest(identifier: reminderID, content: content, trigger: trigger))
  }

  private func postFlags(_ snapshot: NestedSnapshot) {
    guard let baby = snapshot.baby, baby.flagNotifications else { return }
    let now = Date()
    let day = now.formatted(.iso8601.year().month().day())
    var notified = notifiedFlags
    for flag in snapshot.flags(now: now) {
      let key = "\(day)-\(flag.kind.rawValue)"
      guard !notified.contains(key) else { continue }
      notified.insert(key)
      let content = UNMutableNotificationContent()
      content.title = flag.title
      content.body = flag.detail
      content.categoryIdentifier = Self.flagCategory
      center.add(UNNotificationRequest(identifier: key, content: content, trigger: nil))
    }
    notifiedFlags = notified
  }

  // MARK: Delegate

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .sound, .list]
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    let action = response.actionIdentifier
    await MainActor.run {
      guard let store = try? SharedStore.store else { return }
      switch action {
      case Action.logBottle:
        let snapshot = try? store.snapshot(now: Date())
        _ = try? store.logBottle(
          amountMl: snapshot?.defaultBottleMl ?? 90, contents: snapshot?.defaultBottleContents ?? .formula,
          offeredMl: nil, formulaBrand: snapshot?.baby?.formulaBrand, at: Date(), note: "", endSleep: true)
      case Action.startNursing:
        _ = try? store.startNursing(side: nil, at: Date(), endSleep: true)
      case Action.snooze:
        let content = UNMutableNotificationContent()
        content.title = "Feed reminder"
        content.body = "Snoozed 15 minutes ago."
        content.categoryIdentifier = Self.feedCategory
        content.interruptionLevel = .timeSensitive
        UNUserNotificationCenter.current().add(
          UNNotificationRequest(
            identifier: "snoozed-feed", content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 15 * 60, repeats: false)))
      default:
        break
      }
    }
  }
}
