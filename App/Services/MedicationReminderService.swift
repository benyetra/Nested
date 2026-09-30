import NestedCore
import NestedData
import SwiftUI
import UserNotifications

/// Turns the shared medicine list into reminders on this phone.
///
/// Both phones run this against the same synced rows, so they schedule the same reminders for the
/// same clock times and go off together, even if one is offline. A dose logged on either phone
/// clears the reminder on the other when the sync lands.
@MainActor
final class MedicationReminderService {
  static let shared = MedicationReminderService()

  static let category = "MED_REMINDER"
  nonisolated static let idPrefix = "med-"
  nonisolated static let given = "MED_GIVEN"
  nonisolated static let snooze = "MED_SNOOZE"
  nonisolated static let skip = "MED_SKIP"

  /// Reminders are planned this far ahead; the app tops them up whenever it runs or a sync lands.
  static let planningWindow: TimeInterval = 72 * 3600
  /// iOS keeps 64 pending notifications per app; leave room for feed reminders.
  static let maxPending = 48
  /// If a dose is still unanswered this long after it's due, remind again.
  static let followUp: TimeInterval = 15 * 60

  private let center = UNUserNotificationCenter.current()
  private let scheduledKey = "med.reminders.scheduled"
  private let signatureKey = "med.reminders.signature"

  struct Planned: Hashable {
    var id: String
    var fireAt: Date
    var title: String
    var body: String
    var medicationID: UUID
    var dueAt: Date
  }

  static func identifier(medicationID: UUID, dueAt: Date, followUp: Bool) -> String {
    "\(idPrefix)\(followUp ? "again" : "due")-\(medicationID.uuidString)-\(Int(dueAt.timeIntervalSince1970))"
  }

  nonisolated static func snoozeIdentifier(medicationID: String, due: TimeInterval) -> String {
    "\(idPrefix)snooze-\(medicationID)-\(Int(due))"
  }

  // MARK: Planning (pure)

  static func plan(snapshot: NestedSnapshot, now: Date, calendar: Calendar = .current) -> [Planned] {
    var items: [Planned] = []
    for medication in snapshot.medications where medication.isActive && medication.cadence != .asNeeded {
      let doses = snapshot.medicationDoses.filter { $0.medicationID == medication.id }.map(\.record)
      let who = medication.forWho.isEmpty ? snapshot.babyName : medication.forWho
      let detail = [who, medication.name, medication.dose].filter { !$0.isEmpty }.joined(separator: " · ")

      func add(due: Date, fireAt: Date, isFollowUp: Bool) {
        guard fireAt > now else { return }
        items.append(
          Planned(
            id: identifier(medicationID: medication.id, dueAt: due, followUp: isFollowUp), fireAt: fireAt,
            title: isFollowUp ? "Still due: medicine" : "Medicine time", body: detail,
            medicationID: medication.id, dueAt: due))
      }

      for due in MedicationSchedule.pending(
        plan: medication.plan, doses: doses, from: now, within: planningWindow, calendar: calendar)
      {
        add(due: due, fireAt: due, isFollowUp: false)
        add(due: due, fireAt: due.addingTimeInterval(followUp), isFollowUp: true)
      }
      // Came due a moment ago and unanswered: its follow-up is still ahead.
      for due in MedicationSchedule.occurrences(
        plan: medication.plan, doses: doses, from: now.addingTimeInterval(-followUp), to: now, calendar: calendar
      ) where !MedicationSchedule.isHandled(due, doses: doses) {
        add(due: due, fireAt: due.addingTimeInterval(followUp), isFollowUp: true)
      }
    }
    return Array(items.sorted { $0.fireAt < $1.fireAt }.prefix(maxPending))
  }

  // MARK: Reconcile

  func reconcile(_ snapshot: NestedSnapshot, now: Date = Date()) {
    clearHandled(snapshot)

    let planned = Self.plan(snapshot: snapshot, now: now)
    let signature = planned.map { "\($0.id)|\($0.title)|\($0.body)|\(Int($0.fireAt.timeIntervalSince1970))" }
      .joined(separator: "\n")
    let defaults = UserDefaults.standard
    guard signature != defaults.string(forKey: signatureKey) else { return }

    center.removePendingNotificationRequests(withIdentifiers: defaults.stringArray(forKey: scheduledKey) ?? [])
    for item in planned {
      let content = UNMutableNotificationContent()
      content.title = item.title
      content.body = item.body
      content.sound = .default
      content.interruptionLevel = .timeSensitive
      content.categoryIdentifier = Self.category
      content.threadIdentifier = item.medicationID.uuidString
      content.userInfo = [
        "medicationID": item.medicationID.uuidString, "dueAt": item.dueAt.timeIntervalSince1970,
      ]
      let components = Calendar.current.dateComponents(
        [.year, .month, .day, .hour, .minute, .second], from: item.fireAt)
      center.add(
        UNNotificationRequest(
          identifier: item.id, content: content,
          trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
    }
    defaults.set(planned.map(\.id), forKey: scheduledKey)
    defaults.set(signature, forKey: signatureKey)
  }

  /// Takes down reminders, delivered or waiting, for doses either phone has already logged, and
  /// for medicines that were paused or deleted.
  private func clearHandled(_ snapshot: NestedSnapshot) {
    var pending: [String] = []
    for dose in snapshot.medicationDoses {
      guard let due = dose.dueAt else { continue }
      pending.append(Self.snoozeIdentifier(medicationID: dose.medicationID.uuidString, due: due.timeIntervalSince1970))
    }
    center.removePendingNotificationRequests(withIdentifiers: pending)

    let medications = Dictionary(uniqueKeysWithValues: snapshot.medications.map { ($0.id.uuidString, $0) })
    let doses = snapshot.medicationDoses
    Task {
      let delivered = await Self.deliveredReminders()
      var stale: [String] = []
      for reminder in delivered {
        guard let medication = medications[reminder.medicationID], medication.isActive else {
          stale.append(reminder.id)
          continue
        }
        let records = doses.filter { $0.medicationID == medication.id }.map(\.record)
        if MedicationSchedule.isHandled(Date(timeIntervalSince1970: reminder.due), doses: records) {
          stale.append(reminder.id)
        }
      }
      if !stale.isEmpty { center.removeDeliveredNotifications(withIdentifiers: stale) }
    }
  }

  private nonisolated static func deliveredReminders() async -> [(id: String, medicationID: String, due: TimeInterval)] {
    await withCheckedContinuation { continuation in
      UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
        let found = notifications.compactMap { notification -> (id: String, medicationID: String, due: TimeInterval)? in
          let request = notification.request
          guard
            request.identifier.hasPrefix(MedicationReminderService.idPrefix),
            let medicationID = request.content.userInfo["medicationID"] as? String,
            let due = request.content.userInfo["dueAt"] as? Double
          else { return nil }
          return (request.identifier, medicationID, due)
        }
        continuation.resume(returning: found)
      }
    }
  }
}
