import ActivityKit
import AppIntents
import NestCore
import SwiftUI
import WidgetKit

/// Running nursing, pumping or sleep timer on the Lock Screen and in the Dynamic Island.
/// Elapsed time is drawn from the stored start, so it's right on both phones.
struct TimerLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: NestTimerAttributes.self) { context in
      LockScreenActivityView(context: context)
        .padding()
        .activityBackgroundTint(context.attributes.kind.color.opacity(0.25))
        .widgetURL(NestLink.log(context.attributes.kind))
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Label(title(context), systemImage: context.attributes.kind.symbol)
            .font(.headline)
            .foregroundStyle(context.attributes.kind.color)
        }
        DynamicIslandExpandedRegion(.trailing) {
          TotalTimer(state: context.state)
            .font(.title2.weight(.semibold))
            .frame(maxWidth: 110, alignment: .trailing)
        }
        DynamicIslandExpandedRegion(.bottom) {
          ActivityButtons(context: context)
        }
      } compactLeading: {
        HStack(spacing: 2) {
          Image(systemName: context.attributes.kind.symbol)
          if let side = context.state.side { Text(side.initial).fontWeight(.bold) }
        }
        .foregroundStyle(context.attributes.kind.color)
      } compactTrailing: {
        TotalTimer(state: context.state)
          .frame(maxWidth: 56)
      } minimal: {
        Image(systemName: context.attributes.kind.symbol)
          .foregroundStyle(context.attributes.kind.color)
      }
      .widgetURL(NestLink.log(context.attributes.kind))
    }
  }

  private func title(_ context: ActivityViewContext<NestTimerAttributes>) -> String {
    switch context.attributes.kind {
    case .nursing: context.state.isPaused ? "Paused" : (context.state.side?.title ?? "Nursing")
    case .pump: "Pumping"
    default: "Asleep"
    }
  }
}

private struct TotalTimer: View {
  let state: NestTimerAttributes.ContentState

  var body: some View {
    Group {
      if state.isPaused, let elapsed = state.pausedElapsed {
        Text(Durations.clock(elapsed))
      } else {
        Text(timerInterval: state.timerStart...Date.distantFuture, countsDown: false)
      }
    }
    .monospacedDigit()
    .multilineTextAlignment(.trailing)
  }
}

private struct LockScreenActivityView: View {
  let context: ActivityViewContext<NestTimerAttributes>

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Label(headline, systemImage: context.attributes.kind.symbol)
          .font(.headline)
          .foregroundStyle(context.attributes.kind.color)
        Spacer()
        TotalTimer(state: context.state)
          .font(.title.weight(.semibold))
      }
      if context.attributes.kind == .nursing {
        SideIndicator(state: context.state)
      }
      ActivityButtons(context: context)
      Text("Started by \(context.state.loggedBy.isEmpty ? "someone" : context.state.loggedBy)")
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
  }

  private var headline: String {
    switch context.attributes.kind {
    case .nursing: "\(context.attributes.babyName) · nursing"
    case .pump: "Pumping"
    default: "\(context.attributes.babyName) is asleep"
    }
  }
}

/// L | R with the current side highlighted.
private struct SideIndicator: View {
  let state: NestTimerAttributes.ContentState

  var body: some View {
    HStack(spacing: 6) {
      ForEach(Side.allCases, id: \.self) { side in
        let current = state.side == side
        HStack {
          Text(side.initial).fontWeight(.bold)
          Spacer()
          if current, !state.isPaused, let start = state.sideStart {
            Text(timerInterval: start...Date.distantFuture, countsDown: false).monospacedDigit()
          } else {
            Text(Durations.clock(side == .left ? state.leftSeconds : state.rightSeconds)).monospacedDigit()
          }
        }
        .font(.subheadline)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
          RoundedRectangle(cornerRadius: 10)
            .fill(current ? EventKind.nursing.color.opacity(0.45) : Color.secondary.opacity(0.15)))
      }
    }
  }
}

private struct ActivityButtons: View {
  let context: ActivityViewContext<NestTimerAttributes>

  var body: some View {
    HStack(spacing: 8) {
      switch context.attributes.kind {
      case .nursing:
        Button(intent: SwitchSideIntent()) {
          Label("Switch", systemImage: "arrow.left.arrow.right").frame(maxWidth: .infinity)
        }
        Button(intent: PauseNursingIntent()) {
          Label(context.state.isPaused ? "Resume" : "Pause", systemImage: context.state.isPaused ? "play.fill" : "pause.fill")
            .frame(maxWidth: .infinity)
        }
        Button(intent: StopNursingIntent()) {
          Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity)
        }
      case .sleep:
        Button(intent: EndSleepIntent()) {
          Label("Awake", systemImage: "sun.max.fill").frame(maxWidth: .infinity)
        }
      default:
        Link(destination: NestLink.log(.pump)) {
          Label("Stop and enter volume", systemImage: "stop.fill").frame(maxWidth: .infinity)
        }
      }
    }
    .font(.subheadline.weight(.semibold))
    .buttonStyle(.bordered)
    .tint(context.attributes.kind.color)
  }
}
