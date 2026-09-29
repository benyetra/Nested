import NestCore
import NestData
import SwiftUI
import WidgetKit

/// Watch complications mirror the Lock Screen widgets.
@main
struct NestComplicationsBundle: WidgetBundle {
  var body: some Widget {
    NestComplication()
  }
}

struct NestComplication: Widget {
  let kind = "com.yetra.nest.complication"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: StatusProvider()) { entry in
      ComplicationView(entry: entry)
        .containerBackground(.clear, for: .widget)
    }
    .configurationDisplayName("Last fed")
    .description("Time since the last feed and the ring toward the next.")
    .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
  }
}

private struct ComplicationView: View {
  @Environment(\.widgetFamily) private var family
  let entry: StatusEntry

  var body: some View {
    switch family {
    case .accessoryCircular:
      FeedRingView(snapshot: entry.snapshot)
    case .accessoryInline:
      StatusInlineView(snapshot: entry.snapshot)
    case .accessoryCorner:
      Image(systemName: entry.snapshot.lastFeed?.isNursing == true ? "heart.fill" : "waterbottle.fill")
        .font(.title2)
        .widgetLabel {
          if let feed = entry.snapshot.lastFeed {
            Text(feed.startedAt, style: .relative)
          } else {
            Text("No feeds")
          }
        }
    default:
      StatusRectangularView(snapshot: entry.snapshot)
    }
  }
}
