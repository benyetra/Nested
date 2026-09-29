import NestCore
import NestData
import SQLiteData
import SwiftUI

/// Reverse-chronological history grouped by day, colour-coded by type, with the logging
/// parent's initial. Swipe to edit or delete; long-press to duplicate.
struct TimelineScreen: View {
  @Environment(AppModel.self) private var model
  @State private var days = 14
  @Fetch(TimelineRequest(days: 14), animation: Motion.standard) private var entries: [Entry] = []
  @Fetch(SnapshotRequest()) private var snapshot = NestSnapshot.empty

  private var sections: [(day: Date, entries: [Entry])] {
    let calendar = Calendar.current
    let grouped = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
    return grouped.keys.sorted(by: >).map { ($0, grouped[$0]!.sorted { $0.date > $1.date }) }
  }

  var body: some View {
    NavigationStack {
      List {
        if entries.isEmpty {
          ContentUnavailableView(
            "Nothing logged yet", systemImage: "list.bullet",
            description: Text("Entries from both of you show up here."))
        }
        ForEach(sections, id: \.day) { section in
          Section {
            ForEach(section.entries) { entry in
              // A button, so the row highlights on touch-down like a system list row.
              Button { model.editing = entry } label: {
                TimelineRow(entry: entry, unit: snapshot.unit)
              }
              .foregroundStyle(.primary)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                  Button("Delete", systemImage: "trash", role: .destructive) {
                    model.delete(entry, unit: snapshot.unit)
                  }
                }
                .swipeActions(edge: .leading) {
                  Button("Edit", systemImage: "pencil") { model.editing = entry }
                    .tint(entry.kind.color)
                }
                .contextMenu {
                  Button("Duplicate now", systemImage: "plus.square.on.square") { model.duplicate(entry) }
                  Button("Edit", systemImage: "pencil") { model.editing = entry }
                  Button("Delete", systemImage: "trash", role: .destructive) {
                    model.delete(entry, unit: snapshot.unit)
                  }
                }
            }
          } header: {
            DayHeader(day: section.day, entries: section.entries)
          }
        }
        if !entries.isEmpty {
          Button("Show earlier days") {
            days += 14
            Task { try? await $entries.load(TimelineRequest(days: days), animation: Motion.standard) }
          }
          .frame(maxWidth: .infinity)
        }
      }
      .listStyle(.insetGrouped)
      .nestListBackground()
      .navigationTitle("Timeline")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button("Add note", systemImage: "square.and.pencil") {
            model.tab = .now
            model.open(.note)
          }
        }
      }
    }
  }
}

private struct DayHeader: View {
  let day: Date
  let entries: [Entry]

  var body: some View {
    let feeds = entries.filter { $0.kind == .bottle || $0.kind == .nursing }.count
    let diapers = entries.filter { $0.kind == .diaper }.count
    HStack {
      Text(title)
      Spacer()
      Text("\(feeds) feeds · \(diapers) diapers").monospacedDigit()
    }
  }

  private var title: String {
    let calendar = Calendar.current
    if calendar.isDateInToday(day) { return "Today" }
    if calendar.isDateInYesterday(day) { return "Yesterday" }
    return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
  }
}

struct TimelineRow: View {
  let entry: Entry
  let unit: VolumeUnit

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: entry.kind.symbol)
        .font(.body.weight(.semibold))
        .foregroundStyle(.white)
        .frame(width: 34, height: 34)
        .background(Circle().fill(entry.kind.color))
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(entry.title(unit: unit))
          .font(.body)
          .lineLimit(2)
        HStack(spacing: 4) {
          Text(entry.date, format: .dateTime.hour().minute())
          if let end = entry.endDate {
            Text("– \(end.formatted(date: .omitted, time: .shortened))")
          } else if entry.isRunning {
            Text("· running")
          }
          if !entry.note.isEmpty, entry.kind != .note {
            Image(systemName: "text.bubble").accessibilityLabel("Has note")
          }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .monospacedDigit()
      }
      Spacer()
      ParentBadge(name: entry.loggedBy)
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(entry.kind.title), \(entry.title(unit: unit)), \(entry.date.formatted(date: .omitted, time: .shortened)), by \(entry.loggedBy)")
    .accessibilityHint("Double-tap to edit. Swipe for more.")
  }
}
