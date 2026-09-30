import AlarmKit
import NestedCore
import NestedData
import SwiftUI

/// Developer tools for trying the feed alarm exactly as it will happen at 3 a.m.: a real
/// AlarmKit alarm with the real sound, volume, silent-switch and Focus behaviour.
struct DeveloperAlarmView: View {
  @Environment(AppModel.self) private var model
  private var snapshot: NestedSnapshot { SideEffects.shared.snapshot }
  private let alarms = FeedAlarmService.shared

  @State private var delay: TimeInterval = 15
  @State private var message: String?
  @State private var live: [String] = []
  @State private var lastAction = AlarmTestLog.lastAction
  @State private var confirmingBothPhones = false

  private let delays: [(String, TimeInterval)] = [("15 sec", 15), ("30 sec", 30), ("1 min", 60), ("2 min", 120)]

  var body: some View {
    Form {
      Section {
        LabeledContent("Alarm permission", value: permissionText)
        if alarms.authorization == .notDetermined || alarms.authorization == .denied {
          Button("Request permission") { Task { await alarms.requestAuthorization() } }
        }
        if let baby = snapshot.baby {
          LabeledContent("Second button", value: baby.alarmSecondary == .snooze ? "Snooze 10 min" : "Feeding now")
        }
      } header: {
        Text("Status")
      } footer: {
        Text("These are the settings the real alarm uses. Change them in Settings ▸ Feed alarm.")
      }

      Section {
        Picker("Ring in", selection: $delay) {
          ForEach(delays, id: \.1) { Text($0.0).tag($0.1) }
        }
        .pickerStyle(.segmented)
        Button("Ring this phone", systemImage: "alarm.waves.left.and.right") { ringThisPhone() }
          .disabled(snapshot.baby == nil)
        if let message {
          Text(message).font(.footnote).foregroundStyle(.secondary)
        }
      } header: {
        Text("Test on this phone")
      } footer: {
        Text("A real alarm, the same as the feed alarm. Lock the phone, flip the silent switch, turn on a Focus, or lower the ringer volume first, then see what you hear. Its buttons only stop the test.")
      }

      Section {
        Button("Test the whole thing on both phones", systemImage: "iphone.gen3.radiowaves.left.and.right") {
          confirmingBothPhones = true
        }
        .disabled(snapshot.baby == nil)
      } footer: {
        Text("Sets the real shared alarm, so the sync and the partner's phone are tested too. Stop or “Feeding now” act for real, and Feeding now starts a nursing timer.")
      }

      Section {
        Button("Ring the no-permission fallback notification") { ringFallback() }
      } footer: {
        Text("What you'd get if alarm permission is denied: an ordinary time-sensitive notification. It does not ring on silent.")
      }

      Section("On this phone now") {
        if live.isEmpty {
          Text("No alarms scheduled").foregroundStyle(.secondary)
        }
        ForEach(live, id: \.self) { Text($0).font(.footnote.monospaced()) }
        if let lastAction {
          LabeledContent("Last button", value: lastAction)
        }
        Button("Cancel test alarms", role: .destructive) {
          alarms.cancelTestAlarms()
          message = "Test alarms cancelled."
        }
      }

      Section("Check") {
        Label("Silent switch and Focus shouldn't matter. It should still ring.", systemImage: "bell.slash")
        Label("Volume follows Settings ▸ Sounds & Haptics ▸ Ringer and Alerts. If that's all the way down, you won't hear it.", systemImage: "speaker.wave.2")
        Label("There is no gradual volume ramp; iOS rings at full alarm volume.", systemImage: "waveform")
      }
      .font(.footnote)
    }
    .nestedListBackground()
    .navigationTitle("Alarm test")
    .navigationBarTitleDisplayMode(.inline)
    .task { await watchAlarms() }
    .confirmationDialog(
      "Ring both phones?", isPresented: $confirmingBothPhones, titleVisibility: .visible
    ) {
      Button("Set the real alarm for \(Int(delay)) seconds from now") { ringBothPhones() }
    } message: {
      Text("Your partner's phone will ring too.")
    }
  }

  private var permissionText: String {
    switch alarms.authorization {
    case .authorized: "Allowed"
    case .denied: "Denied"
    case .notDetermined: "Not asked yet"
    @unknown default: "Unknown"
    }
  }

  private func ringThisPhone() {
    guard let baby = snapshot.baby else { return }
    let seconds = delay
    let name = snapshot.babyName
    Task { message = await alarms.scheduleTestAlarm(after: seconds, baby: baby, babyName: name) }
  }

  private func ringFallback() {
    let seconds = delay
    let name = snapshot.babyName
    Task { message = await alarms.scheduleTestFallback(after: seconds, babyName: name) }
  }

  private func ringBothPhones() {
    let fireAt = Date().addingTimeInterval(delay)
    model.perform("Alarm set for both phones", haptic: .success, undo: .none) {
      try model.store.setFeedAlarm(fireAt: fireAt, manual: true)
      return nil
    }
  }

  /// Follows the system's alarm list so the screen shows the real state (scheduled, alerting).
  private func watchAlarms() async {
    let updates = Self.alarmDescriptions()
    for await lines in updates {
      live = lines
      lastAction = AlarmTestLog.lastAction
    }
  }

  private nonisolated static func alarmDescriptions() -> AsyncStream<[String]> {
    AsyncStream { continuation in
      let task = Task.detached {
        for await alarms in AlarmManager.shared.alarmUpdates {
          continuation.yield(
            alarms.map { "\($0.id.uuidString.prefix(8)) · \(String(describing: $0.state))" })
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}
