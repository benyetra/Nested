import AlarmKit
import AppIntents
import Foundation

/// Which test alarms this phone scheduled and what the last button press did, kept in the app's
/// defaults so the developer screen can show them after the alarm intents run.
enum AlarmTestLog {
  private static let idsKey = "dev.alarmTest.ids"
  private static let lastKey = "dev.alarmTest.lastAction"

  static var ids: [UUID] {
    (UserDefaults.standard.stringArray(forKey: idsKey) ?? []).compactMap(UUID.init(uuidString:))
  }

  static func remember(_ id: UUID) {
    UserDefaults.standard.set(Array((ids + [id]).suffix(20)).map(\.uuidString), forKey: idsKey)
  }

  static func clear() {
    UserDefaults.standard.removeObject(forKey: idsKey)
  }

  static var lastAction: String? { UserDefaults.standard.string(forKey: lastKey) }

  static func record(_ button: String) {
    let time = Date().formatted(date: .omitted, time: .standard)
    UserDefaults.standard.set("\(button) button pressed at \(time)", forKey: lastKey)
  }
}

/// Every button on a test alarm: dismisses that alarm and notes which button it was. It never
/// changes the shared alarm, logs a feed or reaches the partner's phone.
struct TestAlarmButtonIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "Test Alarm Button"
  static let openAppWhenRun = false
  static let isDiscoverable = false

  @Parameter(title: "Alarm ID")
  var alarmID: String

  @Parameter(title: "Button")
  var button: String

  init() {}
  init(alarmID: UUID, button: String) {
    self.alarmID = alarmID.uuidString
    self.button = button
  }

  func perform() async throws -> some IntentResult {
    AlarmTestLog.record(button)
    if let id = UUID(uuidString: alarmID) {
      try? AlarmManager.shared.stop(id: id)
    }
    return .result()
  }
}
