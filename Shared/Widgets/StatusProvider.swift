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

extension FeedRecord {
  /// Nursing is the main way she's fed; a bottle is the supplement.
  var eventKind: EventKind { isNursing ? .nursing : .bottle }
}

extension NestedSnapshot {
  /// Icon for "how she was last fed"; the heart until there's anything logged.
  var lastFeedSymbol: String { lastFeed?.eventKind.symbol ?? EventKind.nursing.symbol }

  /// Today's feeds split into nursing sessions and supplemental bottles.
  func feedSplit(since start: Date) -> (nursed: Int, bottles: Int, bottleMl: Double) {
    var nursed = 0
    var bottles = 0
    var ml = 0.0
    for feed in history.feeds where feed.startedAt >= start {
      switch feed.kind {
      case .nursing: nursed += 1
      case .bottle(let amount, _):
        bottles += 1
        ml += amount
      }
    }
    return (nursed, bottles, ml)
  }
}

/// Ring filling toward the predicted next feed; the icon shows how she was last fed.
struct FeedRingView: View {
  let snapshot: NestedSnapshot
  var now = Date()

  var body: some View {
    if let last = snapshot.lastFeed?.startedAt, let expected = snapshot.feedPrediction?.expected, expected > last {
      if now < expected {
        ProgressView(timerInterval: last...expected, countsDown: false) {
          Image(systemName: snapshot.lastFeedSymbol)
        } currentValueLabel: {
          Image(systemName: snapshot.lastFeedSymbol)
        }
        .progressViewStyle(.circular)
        .widgetAccentable()
        .accessibilityLabel("Next feed around \(expected.formatted(date: .omitted, time: .shortened))")
      } else {
        // Past the expected time: a full ring instead of a timer that has already finished.
        Gauge(value: 1) {
          Image(systemName: snapshot.lastFeedSymbol)
        } currentValueLabel: {
          Image(systemName: "exclamationmark")
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
        .accessibilityLabel("Feed due")
      }
    } else {
      ZStack {
        AccessoryWidgetBackground()
        Image(systemName: snapshot.lastFeedSymbol).font(.title3)
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
          Image(systemName: feed.eventKind.symbol)
          Text("Fed \(Text(feed.startedAt, style: .relative)) ago")
        }
        .font(.headline)
        .widgetAccentable()
        Text(detail(feed)).lineLimit(1)
      } else {
        Label("No feeds yet", systemImage: "heart").font(.headline)
        Text("Next side \(snapshot.nextSide.initial)").lineLimit(1)
      }
      if let sleep = snapshot.activeSleep {
        Text("Asleep \(Text(sleep.startedAt, style: .relative))").lineLimit(1)
      } else if let awake = snapshot.awakeSince {
        Text("Awake \(Text(awake, style: .relative))").lineLimit(1)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// "L 14 min · next R" after nursing; "35 ml breast milk" after a bottle.
  private func detail(_ feed: FeedRecord) -> String {
    switch feed.kind {
    case .bottle(let ml, let contents):
      return "\(Volume.format(ml: ml, unit: snapshot.unit)) \(contents.title.lowercased())"
    case .nursing(let l, let r, let side):
      let last = side.map { "\($0.initial) " } ?? ""
      return "\(last)\(Durations.format(l + r)) · next \(snapshot.nextSide.initial)"
    }
  }
}

struct StatusInlineView: View {
  let snapshot: NestedSnapshot

  var body: some View {
    if let feed = snapshot.lastFeed {
      let suffix: String = {
        switch feed.kind {
        case .nursing: " · next \(snapshot.nextSide.initial)"
        case .bottle(let ml, _): " · \(Volume.format(ml: ml, unit: snapshot.unit))"
        }
      }()
      Text("Fed \(Text(feed.startedAt, style: .relative)) ago\(suffix)")
    } else {
      Text("Nested: no feeds yet")
    }
  }
}
