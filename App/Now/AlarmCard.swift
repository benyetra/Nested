import NestCore
import NestData
import SwiftUI

/// Bedtime confirmation for the night feed alarm, plus the "Wake us in…" chips.
struct AlarmCard: View {
  @Environment(AppModel.self) private var model
  @Environment(\.openURL) private var openURL
  let snapshot: NestSnapshot
  let now: Date

  private var alarmService: FeedAlarmService { .shared }

  var body: some View {
    Card(tint: EventKind.nursing.color) {
      VStack(alignment: .leading, spacing: 10) {
        if alarmService.isDenied {
          permissionBanner
        }
        if let alarm = snapshot.pendingAlarm(now: now), let fireAt = alarm.fireAt {
          armedView(alarm: alarm, fireAt: fireAt)
        } else {
          Label("No feed alarm set", systemImage: "alarm")
            .font(.subheadline.weight(.semibold))
          if snapshot.baby?.alarmAutoArm == .nightOnly {
            Text("Logging a feed after \(snapshot.baby?.nightWindow.label.prefix(5) ?? "20:00") sets one automatically.")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        }
        wakeChips
      }
    }
  }

  private var permissionBanner: some View {
    Button {
      if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    } label: {
      Label {
        VStack(alignment: .leading, spacing: 2) {
          Text("The alarm won't ring").font(.subheadline.weight(.semibold))
          Text("Alarm permission is off, so you'll get a notification instead — it won't sound on silent. Tap to open Settings.")
            .font(.footnote)
            .multilineTextAlignment(.leading)
        }
      } icon: {
        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
      }
    }
    .buttonStyle(.plain)
  }

  private func armedView(alarm: FeedAlarm, fireAt: Date) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline) {
        Label("Alarm \(fireAt.formatted(date: .omitted, time: .shortened))", systemImage: "alarm.fill")
          .font(.headline)
          .monospacedDigit()
        Spacer()
        Button("Turn off", role: .destructive) {
          model.perform("Alarm off", haptic: .selection, undo: .none) {
            try model.store.setFeedAlarm(fireAt: nil, manual: true)
            return nil
          }
        }
        .font(.subheadline)
      }
      Text("in \(Text(fireAt, style: .relative)) · \(alarm.isManual ? "set" : "auto-set") by \(alarm.setBy.isEmpty ? "you" : alarm.setBy)")
        .font(.footnote)
        .foregroundStyle(.secondary)
      ForEach(deviceRows(fireAt: fireAt, setBy: alarm.setBy), id: \.name) { row in
        Label {
          Text("\(row.name): \(row.status)")
        } icon: {
          Image(systemName: row.ok ? "checkmark.circle.fill" : "exclamationmark.circle")
            .foregroundStyle(row.ok ? .green : .orange)
        }
        .font(.footnote)
      }
    }
    .accessibilityElement(children: .combine)
  }

  private struct DeviceRow {
    var name: String
    var status: String
    var ok: Bool
  }

  private func deviceRows(fireAt: Date, setBy: String) -> [DeviceRow] {
    guard let baby = snapshot.baby else { return [] }
    // (owner, armed-for, alarm permission) for every phone, this one from live state.
    var phones = snapshot.devices
      .filter { $0.ownerName != snapshot.me }
      .map { (name: $0.ownerName, armedFor: $0.alarmArmedFor, authorized: $0.alarmAuthorized) }
    phones.insert((name: snapshot.me, armedFor: alarmService.armedFor, authorized: !alarmService.isDenied), at: 0)
    return phones.map { phone in
      let name = phone.name.isEmpty ? "Unnamed phone" : phone.name
      if !AlarmPlanner.shouldRing(settings: baby.alarmSettings, me: phone.name, setBy: setBy) {
        return DeviceRow(name: name, status: "won't ring (by your settings)", ok: true)
      }
      if let armedAt = phone.armedFor, abs(armedAt.timeIntervalSince(fireAt)) < 60 {
        return DeviceRow(name: name, status: phone.authorized ? "armed" : "notification only", ok: phone.authorized)
      }
      return DeviceRow(name: name, status: "not confirmed yet — is it on and charged?", ok: false)
    }
  }

  private var wakeChips: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Wake us in…").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
      HStack(spacing: 8) {
        ForEach(AlarmSettings.manualChips, id: \.self) { interval in
          Chip(title: chipTitle(interval), tint: EventKind.nursing.color) {
            let fireAt = Date().addingTimeInterval(interval)
            model.perform(
              "Alarm set for \(fireAt.formatted(date: .omitted, time: .shortened))", haptic: .selection, undo: .none
            ) {
              try model.store.setFeedAlarm(fireAt: fireAt, manual: true)
              return nil
            }
          }
        }
      }
    }
  }

  private func chipTitle(_ interval: TimeInterval) -> String {
    let hours = interval / 3600
    return hours == hours.rounded() ? "\(Int(hours)) h" : "\(Int(hours))½ h"
  }
}
