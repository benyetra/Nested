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
    .description("Time since the last feed, side and awake time. Tap to log.")
    .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
  }
}

private struct LockScreenView: View {
  @Environment(\.widgetFamily) private var family
  let entry: StatusEntry

  var body: some View {
    Group {
      switch family {
      case .accessoryCircular: FeedRingView(snapshot: entry.snapshot)
      case .accessoryInline: StatusInlineView(snapshot: entry.snapshot)
      default: StatusRectangularView(snapshot: entry.snapshot)
      }
    }
    // Tap opens the matching log sheet.
    .widgetURL(NestedLink.log(entry.snapshot.lastFeed?.isNursing == true ? .nursing : .bottle))
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

  private var small: some View {
    VStack(alignment: .leading, spacing: 6) {
      tile(.bottle, "Last fed", date: snapshot.lastFeed?.startedAt)
      Spacer(minLength: 0)
      if let prediction = snapshot.feedPrediction {
        VStack(alignment: .leading, spacing: 0) {
          Text("Next feed").font(.caption2).foregroundStyle(.secondary)
          Text(
            prediction.phase(at: entry.date) == .upcoming
              ? "~\(prediction.expected.formatted(date: .omitted, time: .shortened))"
              : (prediction.phase(at: entry.date) == .due ? "Due now" : "Overdue")
          )
          .font(.status(.title3))
          .monospacedDigit()
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .widgetURL(NestedLink.now)
  }

  private var medium: some View {
    VStack(spacing: 10) {
      HStack(alignment: .top) {
        tile(.bottle, "Last fed", date: snapshot.lastFeed?.startedAt)
        if let sleep = snapshot.activeSleep {
          tile(.sleep, "Asleep", date: sleep.startedAt)
        } else {
          tile(.sleep, "Awake", date: snapshot.awakeSince)
        }
        tile(.diaper, "Diaper", date: snapshot.lastDiaper?.occurredAt)
      }
      HStack(spacing: 8) {
        IntentButton(intent: LogBottleIntent(), title: "Bottle", symbol: "waterbottle.fill", kind: .bottle)
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
    VStack(alignment: .leading, spacing: 12) {
      medium
      Divider()
      Text("Today").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
      DayStrip(history: snapshot.history, day: entry.date)
        .frame(height: 26)
      HStack {
        count("\(snapshot.todayFeeds)", "feeds", .bottle)
        count("\(snapshot.todayWet)", "wet", .diaper)
        count("\(snapshot.todayDirty)", "dirty", .diaper)
        count(Durations.compact(snapshot.totals24h.sleep), "sleep/24h", .sleep)
      }
      if let prediction = snapshot.feedPrediction {
        Text(
          prediction.phase(at: entry.date) == .upcoming
            ? "Next feed ~\(prediction.expected.formatted(date: .omitted, time: .shortened)) (\(prediction.earliest.formatted(date: .omitted, time: .shortened))–\(prediction.latest.formatted(date: .omitted, time: .shortened)))"
            : prediction.shortLabel(now: entry.date, timeStyle: { $0.formatted(date: .omitted, time: .shortened) })
        )
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }
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
      Text(label).font(.caption2).foregroundStyle(.secondary)
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
