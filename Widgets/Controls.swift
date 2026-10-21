import AppIntents
import NestedCore
import NestedData
import SwiftUI
import WidgetKit

// Control Center controls. They can also be placed on the Lock Screen's bottom corners and
// the Action button. Nap and nursing are toggles showing elapsed time.

struct LogBottleControl: ControlWidget {
  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: "com.yetra.nest.control.bottle") {
      ControlWidgetButton(action: LogBottleIntent()) {
        Label("Repeat Bottle", systemImage: "waterbottle.fill")
      }
    }
    .displayName("Log Bottle")
    .description("Logs the usual supplemental bottle, in its usual amount and contents.")
  }
}

struct LogWetControl: ControlWidget {
  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: "com.yetra.nest.control.wet") {
      ControlWidgetButton(action: LogDiaperIntent(type: .wet)) {
        Label("Wet Diaper", systemImage: "drop.fill")
      }
    }
    .displayName("Wet Diaper")
  }
}

struct LogDirtyControl: ControlWidget {
  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: "com.yetra.nest.control.dirty") {
      ControlWidgetButton(action: LogDiaperIntent(type: .dirty)) {
        Label("Dirty Diaper", systemImage: "circle.fill")
      }
    }
    .displayName("Dirty Diaper")
  }
}

struct WakeUsControl: ControlWidget {
  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: "com.yetra.nest.control.alarm") {
      ControlWidgetButton(action: SetFeedAlarmIntent(hours: 3)) {
        Label("Wake Us in 3 h", systemImage: "alarm.fill")
      }
    }
    .displayName("Wake Us in 3 h")
    .description("Sets the feed alarm on both phones.")
  }
}

struct StopTimerControl: ControlWidget {
  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: "com.yetra.nest.control.stop") {
      ControlWidgetButton(action: StopActiveTimerIntent()) {
        Label("Stop Timer", systemImage: "stop.circle.fill")
      }
    }
    .displayName("Stop Timer")
  }
}

/// Whether a timer runs, and since when, for toggle labels.
struct TimerValue: Sendable {
  var isRunning: Bool
  var startedAt: Date?
}

/// The running timers for a control: the database, unless a write in the last few seconds is
/// newer than a read from this process can be trusted to see. Never throws; a control that can't
/// read shows the last known state instead of snapping back to "off".
private func currentTimers() -> (nursingStart: Date?, sleepStart: Date?) {
  let database = (try? SharedStore.store.snapshot(now: Date())).map {
    (nursingStart: $0.activeNursing?.session.startedAt, sleepStart: $0.activeSleep?.startedAt)
  }
  return TimerStateCache.resolve(cached: TimerStateCache.read(), database: database)
}

struct SleepValueProvider: ControlValueProvider {
  var previewValue: TimerValue { TimerValue(isRunning: false, startedAt: nil) }

  func currentValue() async throws -> TimerValue {
    let start = currentTimers().sleepStart
    return TimerValue(isRunning: start != nil, startedAt: start)
  }
}

struct NursingValueProvider: ControlValueProvider {
  var previewValue: TimerValue { TimerValue(isRunning: false, startedAt: nil) }

  func currentValue() async throws -> TimerValue {
    let start = currentTimers().nursingStart
    return TimerValue(isRunning: start != nil, startedAt: start)
  }
}

struct NapToggleControl: ControlWidget {
  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: "com.yetra.nest.control.nap", provider: SleepValueProvider()) { value in
      ControlWidgetToggle("Nap", isOn: value.isRunning, action: ToggleSleepIntent()) { isOn in
        if isOn, let start = value.startedAt {
          Label {
            Text(start, style: .timer)
          } icon: {
            Image(systemName: "moon.zzz.fill")
          }
        } else {
          Label("Awake", systemImage: "sun.max.fill")
        }
      }
      .tint(EventKind.sleep.color)
    }
    .displayName("Nap")
    .description("Starts or ends the sleep timer.")
  }
}

struct NursingToggleControl: ControlWidget {
  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: "com.yetra.nest.control.nursing", provider: NursingValueProvider()) { value in
      ControlWidgetToggle("Nursing", isOn: value.isRunning, action: ToggleNursingIntent()) { isOn in
        if isOn, let start = value.startedAt {
          Label {
            Text(start, style: .timer)
          } icon: {
            Image(systemName: "heart.fill")
          }
        } else {
          Label("Start", systemImage: "heart")
        }
      }
      .tint(EventKind.nursing.color)
    }
    .displayName("Nursing")
    .description("Starts nursing on the next side, or stops the running session.")
  }
}
