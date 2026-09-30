import NestedCore
import NestedData
import SwiftUI
import WidgetKit

struct StatusEntry: TimelineEntry {
  let date: Date
  let snapshot: NestedSnapshot
}

/// Reads the shared snapshot. Time-based text in the views renders live with
/// `Text(date, style:)`, so the timeline only needs to change when data does (widgets are
/// reloaded on every write) or when a prediction window opens.
struct StatusProvider: TimelineProvider {
  func placeholder(in context: Context) -> StatusEntry {
    StatusEntry(date: Date(), snapshot: .empty)
  }

  func getSnapshot(in context: Context, completion: @escaping @Sendable (StatusEntry) -> Void) {
    completion(entry(at: Date()))
  }

  func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<StatusEntry>) -> Void) {
    let now = Date()
    let current = entry(at: now)
    var dates: [Date] = [
      current.snapshot.feedPrediction?.earliest,
      current.snapshot.feedPrediction?.expected,
      current.snapshot.feedPrediction?.latest,
      current.snapshot.napPrediction?.opensAt,
    ]
    .compactMap { $0 }
    .filter { $0 > now }
    .sorted()
    dates = Array(dates.prefix(3))
    let entries = [current] + dates.map { StatusEntry(date: $0, snapshot: current.snapshot) }
    completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
  }

  private func entry(at date: Date) -> StatusEntry {
    let snapshot = (try? SharedStore.store.snapshot(now: date)) ?? .empty
    return StatusEntry(date: date, snapshot: snapshot)
  }
}

// MARK: - Accessory views (Lock Screen and watch complications)

/// Ring filling toward the predicted next feed.
struct FeedRingView: View {
  let snapshot: NestedSnapshot

  var body: some View {
    if let last = snapshot.lastFeed?.startedAt, let expected = snapshot.feedPrediction?.expected, expected > last {
      ProgressView(timerInterval: last...expected, countsDown: false) {
        Image(systemName: "waterbottle.fill")
      } currentValueLabel: {
        Image(systemName: snapshot.lastFeed?.isNursing == true ? "heart.fill" : "waterbottle.fill")
      }
      .progressViewStyle(.circular)
      .widgetAccentable()
      .accessibilityLabel("Next feed around \(expected.formatted(date: .omitted, time: .shortened))")
    } else {
      ZStack {
        AccessoryWidgetBackground()
        Image(systemName: "waterbottle.fill").font(.title3)
      }
    }
  }
}

struct StatusRectangularView: View {
  let snapshot: NestedSnapshot

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      if let nursing = snapshot.activeNursing {
        Label("Nursing \(nursing.currentSide.initial)", systemImage: "heart.fill").font(.headline).widgetAccentable()
        Text(timerInterval: nursing.effectiveStart(now: Date())...Date.distantFuture, countsDown: false)
          .monospacedDigit()
      } else if let feed = snapshot.lastFeed {
        HStack(spacing: 4) {
          Image(systemName: feed.isNursing ? "heart.fill" : "waterbottle.fill")
          Text("Fed \(Text(feed.startedAt, style: .relative)) ago")
        }
        .font(.headline)
        .widgetAccentable()
        Text(sideOrAmount(feed)).lineLimit(1)
      } else {
        Text("No feeds yet").font(.headline)
      }
      if let sleep = snapshot.activeSleep {
        Text("Asleep \(Text(sleep.startedAt, style: .relative))").lineLimit(1)
      } else if let awake = snapshot.awakeSince {
        Text("Awake \(Text(awake, style: .relative))").lineLimit(1)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func sideOrAmount(_ feed: FeedRecord) -> String {
    switch feed.kind {
    case .bottle(let ml, _): Volume.format(ml: ml, unit: snapshot.unit)
    case .nursing(let l, let r, let side):
      "\(side.map { "\($0.title) · " } ?? "")\(Durations.format(l + r))"
    }
  }
}

struct StatusInlineView: View {
  let snapshot: NestedSnapshot

  var body: some View {
    if let feed = snapshot.lastFeed {
      let side: String = {
        if case .nursing(_, _, let s?) = feed.kind { return " · \(s.initial)" }
        return ""
      }()
      Text("Fed \(Text(feed.startedAt, style: .relative)) ago\(side)")
    } else {
      Text("Nested: no feeds yet")
    }
  }
}
