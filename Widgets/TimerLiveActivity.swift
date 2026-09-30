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
        // A deep, nearly opaque shade of the timer's colour: white text stays readable on
        // any wallpaper. Colour on colour (the old tint) washed out.
        .activityBackgroundTint(context.attributes.kind.color.mix(with: .black, by: 0.55))
        .activitySystemActionForegroundColor(.white)
        .widgetURL(NestLink.log(context.attributes.kind))
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Label {
            Text(title(context)).foregroundStyle(.white)
          } icon: {
            Image(systemName: context.attributes.kind.symbol).foregroundStyle(context.attributes.kind.color)
          }
          .font(.headline)
        }
        DynamicIslandExpandedRegion(.trailing) {
          TotalTimer(state: context.state)
            .font(.title2.weight(.semibold))
            .foregroundStyle(.white)
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
        Label {
          Text(headline).foregroundStyle(.white)
        } icon: {
          Image(systemName: context.attributes.kind.symbol)
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(Circle().fill(context.attributes.kind.color))
        }
        .font(.headline)
        Spacer()
        TotalTimer(state: context.state)
          .font(.title.weight(.semibold))
          .foregroundStyle(.white)
      }
      if context.attributes.kind == .nursing {
        SideIndicator(state: context.state)
      }
      ActivityButtons(context: context)
      Text("Started by \(context.state.loggedBy.isEmpty ? "someone" : context.state.loggedBy)")
        .font(.caption)
        .foregroundStyle(.white.opacity(0.8))
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
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
          RoundedRectangle(cornerRadius: 10)
            .fill(current ? EventKind.nursing.color : Color.white.opacity(0.16)))
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
    // White on a dark shade reads on the lock screen and the black Dynamic Island alike.
    .tint(.white)
    .foregroundStyle(.white)
  }
}
