import AppIntents
import NestedCore
import NestedData
import SwiftUI
import WidgetKit

// MARK: - Lock Screen

struct LockScreenWidget: Widget {
  let kind = "com.yetra.nest.lockscreen"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: StatusProvider()) { entry in
      LockScreenView(entry: entry)
        .containerBackground(.clear, for: .widget)
    }
    .configurationDisplayName("Last fed")
    .description("Time since the last feed, the next side and awake time. Tap to start nursing.")
    .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
  }
}

private struct LockScreenView: View {
  @Environment(\.widgetFamily) private var family
  let entry: StatusEntry

  var body: some View {
    Group {
      switch family {
      case .accessoryCircular: FeedRingView(snapshot: entry.snapshot, now: entry.date)
      case .accessoryInline: StatusInlineView(snapshot: entry.snapshot)
      default: StatusRectangularView(snapshot: entry.snapshot)
      }
    }
    // Nursing is the main feed, so a tap opens it (the bottle is a button away in the app).
    .widgetURL(NestedLink.log(.nursing))
  }
}

// MARK: - Home Screen

struct HomeWidget: Widget {
  let kind = "com.yetra.nest.home"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: StatusProvider()) { entry in
      HomeWidgetView(entry: entry)
        .containerBackground(.fill.tertiary, for: .widget)
    }
    .configurationDisplayName("Nested")
    .description("Last fed and next feed; the medium and large sizes log with one tap.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

private struct HomeWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: StatusEntry

  private var snapshot: NestedSnapshot { entry.snapshot }

  var body: some View {
    switch family {
    case .systemSmall: small
    case .systemLarge: large
    default: medium
    }
  }

  private var timeStyle: (Date) -> String { { $0.formatted(date: .omitted, time: .shortened) } }
  private var lastFeedKind: EventKind { snapshot.lastFeed?.eventKind ?? .nursing }

  // Nursing is how she's mainly fed, so it leads: the last-fed tile says how, the biggest
  // button is Nurse on the next side, and the bottle is the smaller supplement button.

  private var small: some View {
    VStack(alignment: .leading, spacing: 4) {
      if let nursing = snapshot.activeNursing {
        nursingTile(nursing, big: true)
      } else {
        lastFedTile(big: true)
      }
      Spacer(minLength: 0)
      if snapshot.activeNursing == nil, let prediction = snapshot.feedPrediction {
        Text(prediction.shortLabel(now: entry.date, timeStyle: timeStyle))
          .font(.caption2.weight(.medium))
          .foregroundStyle(.secondary)
      }
      nurseButton(prominent: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .widgetURL(NestedLink.now)
  }

  private var medium: some View {
    VStack(spacing: 10) {
      HStack(alignment: .top) {
        if let nursing = snapshot.activeNursing {
          nursingTile(nursing, big: false)
        } else {
          lastFedTile(big: false)
        }
        if let sleep = snapshot.activeSleep {
          tile(.sleep, "Asleep", date: sleep.startedAt)
        } else {
          tile(.sleep, "Awake", date: snapshot.awakeSince)
        }
        tile(.diaper, "Diaper", date: snapshot.lastDiaper?.occurredAt)
      }
      HStack(spacing: 6) {
        nurseButton(prominent: true)
        if snapshot.activeNursing != nil {
          IntentButton(intent: SwitchSideIntent(), title: "Switch", symbol: "arrow.left.arrow.right", kind: .nursing)
        } else {
          IntentButton(intent: LogBottleIntent(), title: "Bottle", symbol: "waterbottle.fill", kind: .bottle)
        }
        IntentButton(intent: LogDiaperIntent(type: .wet), title: "Wet", symbol: "drop.fill", kind: .diaper)
        IntentButton(intent: LogDiaperIntent(type: .dirty), title: "Dirty", symbol: "circle.fill", kind: .diaper)
        if snapshot.activeSleep != nil {
          IntentButton(intent: EndSleepIntent(), title: "Wake", symbol: "sun.max.fill", kind: .sleep)
        } else {
          IntentButton(intent: StartSleepIntent(), title: "Sleep", symbol: "moon.zzz.fill", kind: .sleep)
        }
      }
    }
  }

  private var large: some View {
    let split = snapshot.feedSplit(since: Calendar.current.startOfDay(for: entry.date))
    return VStack(alignment: .leading, spacing: 12) {
      medium
      Divider()
      Text("Today").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
      DayStrip(history: snapshot.history, day: entry.date)
        .frame(height: 26)
      HStack {
        count("\(split.nursed)", "nursed", .nursing)
        count(
          split.bottles > 0 ? Volume.format(ml: split.bottleMl, unit: snapshot.unit) : "0",
          split.bottles == 1 ? "1 bottle" : "\(split.bottles) bottles", .bottle)
        count("\(snapshot.todayWet)", "wet", .diaper)
        count("\(snapshot.todayDirty)", "dirty", .diaper)
        count(Durations.compact(snapshot.totals24h.sleep), "sleep/24h", .sleep)
      }
      if let prediction = snapshot.feedPrediction {
        Text(
          prediction.phase(at: entry.date) == .upcoming
            ? "Next feed ~\(timeStyle(prediction.expected)) (\(timeStyle(prediction.earliest))–\(timeStyle(prediction.latest)))"
            : prediction.shortLabel(now: entry.date, timeStyle: timeStyle)
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }
  }

  /// Last feed, with how (side and time, or bottle amount). The icon and colour follow the type.
  private func lastFedTile(big: Bool) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Label("Last fed", systemImage: lastFeedKind.symbol)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(lastFeedKind.color)
      if let feed = snapshot.lastFeed {
        Text(feed.startedAt, style: .relative)
          .font(.status(big ? .title3 : .subheadline))
          .monospacedDigit()
          .lineLimit(1)
          .minimumScaleFactor(0.7)
        Text(Answers.feedSummary(feed, unit: snapshot.unit))
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      } else {
        Text("–").font(.status(.subheadline))
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func nursingTile(_ nursing: ActiveNursing, big: Bool) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Label("Nursing \(nursing.currentSide.initial)", systemImage: "heart.fill")
        .font(.caption2.weight(.semibold))
        .foregroundStyle(EventKind.nursing.color)
      Text(timerInterval: nursing.effectiveStart(now: entry.date)...Date.distantFuture, countsDown: false)
        .font(.status(big ? .title2 : .subheadline))
        .monospacedDigit()
        .lineLimit(1)
      Text(nursing.isPaused ? "Paused" : "Running")
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// Start nursing on the next side, or stop the running session.
  @ViewBuilder
  private func nurseButton(prominent: Bool) -> some View {
    if snapshot.activeNursing != nil {
      Button(intent: StopNursingIntent()) {
        nurseLabel("Stop", "stop.fill")
      }
      .buttonStyle(.plain)
    } else {
      Button(intent: StartNursingIntent(side: nil)) {
        nurseLabel("Nurse \(snapshot.nextSide.initial)", "heart.fill")
      }
      .buttonStyle(.plain)
    }
  }

  private func nurseLabel(_ title: String, _ symbol: String) -> some View {
    VStack(spacing: 2) {
      Image(systemName: symbol).font(.body.weight(.semibold))
      Text(title).font(.caption2.weight(.bold))
    }
    .foregroundStyle(.white)
    .frame(maxWidth: .infinity, minHeight: 44)
    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(EventKind.nursing.color.gradient))
  }

  private func tile(_ kind: EventKind, _ title: String, date: Date?) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Label(title, systemImage: kind.symbol)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(kind.color)
      if let date {
        Text(date, style: .relative)
          .font(.status(.subheadline))
          .monospacedDigit()
          .lineLimit(1)
          .minimumScaleFactor(0.7)
      } else {
        Text("–").font(.status(.subheadline))
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func count(_ value: String, _ label: String, _ kind: EventKind) -> some View {
    VStack(spacing: 0) {
      Text(value).font(.status(.headline)).foregroundStyle(kind.color).monospacedDigit()
        .lineLimit(1).minimumScaleFactor(0.7)
      Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
    }
    .frame(maxWidth: .infinity)
  }
}

/// A one-tap log button that runs the intent without launching the app.
private struct IntentButton<I: AppIntent>: View {
  let intent: I
  let title: String
  let symbol: String
  let kind: EventKind

  var body: some View {
    Button(intent: intent) {
      VStack(spacing: 2) {
        Image(systemName: symbol).font(.body.weight(.semibold))
        Text(title).font(.caption2.weight(.semibold))
      }
      .frame(maxWidth: .infinity, minHeight: 44)
    }
    .buttonStyle(.plain)
    .foregroundStyle(kind.color)
    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(kind.color.opacity(0.16)))
  }
}

/// Today as a 24 h strip: sleep blocks with feed and diaper ticks.
struct DayStrip: View {
  let history: History
  let day: Date

  var body: some View {
    GeometryReader { proxy in
      let start = Calendar.current.startOfDay(for: day)
      let width = proxy.size.width
      let x: (Date) -> CGFloat = { date in
        CGFloat(min(max(date.timeIntervalSince(start) / 86_400, 0), 1)) * width
      }
      ZStack(alignment: .leading) {
        Capsule().fill(Color.secondary.opacity(0.15))
        ForEach(Array(history.sleeps.enumerated()), id: \.offset) { _, sleep in
          let end = sleep.endedAt ?? Date()
          if end > start {
            Capsule()
              .fill(EventKind.sleep.color.opacity(0.7))
              .frame(width: max(2, x(end) - x(sleep.startedAt)))
              .offset(x: x(sleep.startedAt))
          }
        }
        ForEach(Array(history.feeds.enumerated()), id: \.offset) { _, feed in
          if feed.startedAt >= start {
            Rectangle()
              .fill(feed.isNursing ? EventKind.nursing.color : EventKind.bottle.color)
              .frame(width: 2)
              .offset(x: x(feed.startedAt))
          }
        }
        ForEach(Array(history.diapers.enumerated()), id: \.offset) { _, diaper in
          if diaper.occurredAt >= start {
            Circle()
              .fill(EventKind.diaper.color)
              .frame(width: 6, height: 6)
              .offset(x: x(diaper.occurredAt) - 3)
          }
        }
      }
    }
    .accessibilityLabel("Today's sleep, feeds and diapers")
  }
}
