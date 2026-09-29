import Charts
import NestCore
import NestData
import SwiftUI

/// Scrub support shared by every chart: a rule and value callout at the selected day.
struct ScrubState: Equatable {
  var date: Date?
}

private func dayLabel(_ date: Date) -> String {
  date.formatted(.dateTime.month(.abbreviated).day())
}

// MARK: - Day clock

/// One horizontal 24 h bar per day, most recent at the bottom: sleep blocks, feeds and diapers.
struct DayClockChart: View {
  let history: History
  let days: Int
  var now = Date()

  private struct Block: Identifiable {
    let id = UUID()
    let day: Date
    let startMinute: Double
    let endMinute: Double
  }

  private struct Mark: Identifiable {
    let id = UUID()
    let day: Date
    let minute: Double
    let kind: EventKind
  }

  private var calendar: Calendar { .current }

  private var dayStarts: [Date] {
    let today = calendar.startOfDay(for: now)
    return (0..<days).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
  }

  private var blocks: [Block] {
    guard let first = dayStarts.first else { return [] }
    var result: [Block] = []
    for sleep in history.sleeps {
      let end = sleep.endedAt ?? now
      var cursor = max(sleep.startedAt, first)
      while cursor < end {
        let dayStart = calendar.startOfDay(for: cursor)
        guard let next = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }
        let segmentEnd = min(end, next)
        result.append(
          Block(
            day: dayStart,
            startMinute: cursor.timeIntervalSince(dayStart) / 60,
            endMinute: segmentEnd.timeIntervalSince(dayStart) / 60))
        cursor = segmentEnd
      }
    }
    return result
  }

  private var marks: [Mark] {
    guard let first = dayStarts.first else { return [] }
    var result: [Mark] = []
    for feed in history.feeds where feed.startedAt >= first {
      let day = calendar.startOfDay(for: feed.startedAt)
      result.append(
        Mark(day: day, minute: feed.startedAt.timeIntervalSince(day) / 60, kind: feed.isNursing ? .nursing : .bottle))
    }
    for diaper in history.diapers where diaper.occurredAt >= first {
      let day = calendar.startOfDay(for: diaper.occurredAt)
      result.append(Mark(day: day, minute: diaper.occurredAt.timeIntervalSince(day) / 60, kind: .diaper))
    }
    return result
  }

  var body: some View {
    Chart {
      ForEach(blocks) { block in
        BarMark(
          xStart: .value("Start", block.startMinute),
          xEnd: .value("End", block.endMinute),
          y: .value("Day", dayLabel(block.day))
        )
        .foregroundStyle(EventKind.sleep.color.opacity(0.75))
        .cornerRadius(3)
      }
      ForEach(marks) { mark in
        PointMark(x: .value("Time", mark.minute), y: .value("Day", dayLabel(mark.day)))
          .symbol(mark.kind == .diaper ? .diamond : .circle)
          .symbolSize(mark.kind == .diaper ? 22 : 30)
          .foregroundStyle(mark.kind.color)
      }
    }
    .chartXScale(domain: 0...1440)
    .chartXAxis {
      AxisMarks(values: [0, 360, 720, 1080, 1440]) { value in
        AxisGridLine()
        AxisValueLabel {
          if let minute = value.as(Double.self) {
            Text(["12a", "6a", "12p", "6p", "12a"][Int(minute / 360)])
          }
        }
      }
    }
    .chartYScale(domain: dayStarts.map(dayLabel))
    .frame(height: max(120, CGFloat(days) * 18))
    .accessibilityLabel("Day clock for the last \(days) days: sleep blocks, feeds and diapers across each 24 hours.")
  }
}

// MARK: - Feeding

struct FeedingChart: View {
  let days: [DayStats]
  let unit: VolumeUnit
  @State private var selected: Date?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Chart {
        ForEach(days) { day in
          BarMark(x: .value("Day", day.day, unit: .day), y: .value("Feeds", day.feedCount))
            .foregroundStyle(EventKind.nursing.color.gradient)
        }
        if let selected, let day = days.first(where: { Calendar.current.isDate($0.day, inSameDayAs: selected) }) {
          RuleMark(x: .value("Selected", day.day, unit: .day))
            .foregroundStyle(.secondary)
            .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
              Callout(title: dayLabel(day.day), lines: [
                "\(day.feedCount) feeds",
                "\(Volume.format(ml: day.bottleMl, unit: unit)) by bottle",
              ])
            }
        }
      }
      .chartXSelection(value: $selected)
      .frame(height: 150)
      .accessibilityLabel("Feeds per day")

      if days.contains(where: { $0.bottleMl > 0 }) {
        Chart(days) { day in
          LineMark(x: .value("Day", day.day, unit: .day), y: .value("Bottle", Volume.displayValue(ml: day.bottleMl, unit: unit)))
            .foregroundStyle(EventKind.bottle.color)
            .interpolationMethod(.monotone)
          PointMark(x: .value("Day", day.day, unit: .day), y: .value("Bottle", Volume.displayValue(ml: day.bottleMl, unit: unit)))
            .foregroundStyle(EventKind.bottle.color)
        }
        .chartYAxisLabel("Bottle total (\(unit.title))")
        .frame(height: 110)
        .accessibilityLabel("Total bottle volume per day")
      }
    }
  }
}

// MARK: - Nursing balance

struct NursingBalanceChart: View {
  let days: [DayStats]
  @State private var selected: Date?

  var body: some View {
    Chart {
      ForEach(days) { day in
        BarMark(x: .value("Day", day.day, unit: .day), y: .value("Minutes", -day.nursingLeft / 60))
          .foregroundStyle(by: .value("Side", "Left"))
        BarMark(x: .value("Day", day.day, unit: .day), y: .value("Minutes", day.nursingRight / 60))
          .foregroundStyle(by: .value("Side", "Right"))
      }
      RuleMark(y: .value("Zero", 0)).foregroundStyle(.secondary)
      if let selected, let day = days.first(where: { Calendar.current.isDate($0.day, inSameDayAs: selected) }) {
        RuleMark(x: .value("Selected", day.day, unit: .day))
          .foregroundStyle(.secondary)
          .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
            Callout(title: dayLabel(day.day), lines: [
              "Left \(Durations.format(day.nursingLeft))",
              "Right \(Durations.format(day.nursingRight))",
            ])
          }
      }
    }
    .chartForegroundStyleScale(["Left": EventKind.nursing.color, "Right": EventKind.nursing.color.opacity(0.55)])
    .chartYAxis {
      AxisMarks { value in
        AxisGridLine()
        AxisValueLabel { if let v = value.as(Double.self) { Text("\(Int(abs(v)))") } }
      }
    }
    .chartYAxisLabel("min · left below, right above")
    .chartXSelection(value: $selected)
    .frame(height: 170)
    .accessibilityLabel("Nursing minutes per side per day")
  }
}

// MARK: - Sleep

struct SleepChart: View {
  let days: [DayStats]
  @State private var selected: Date?

  var body: some View {
    Chart {
      ForEach(days) { day in
        BarMark(x: .value("Day", day.day, unit: .day), y: .value("Hours", day.sleepTotal / 3600))
          .foregroundStyle(EventKind.sleep.color.opacity(0.55))
        LineMark(x: .value("Day", day.day, unit: .day), y: .value("Longest", day.longestSleep / 3600))
          .foregroundStyle(EventKind.sleep.color)
          .interpolationMethod(.monotone)
          .symbol(.circle)
      }
      if let selected, let day = days.first(where: { Calendar.current.isDate($0.day, inSameDayAs: selected) }) {
        RuleMark(x: .value("Selected", day.day, unit: .day))
          .foregroundStyle(.secondary)
          .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
            Callout(title: dayLabel(day.day), lines: [
              "Total \(Durations.format(day.sleepTotal))",
              "Longest \(Durations.format(day.longestSleep))",
            ])
          }
      }
    }
    .chartYAxisLabel("hours · bars total, line longest")
    .chartXSelection(value: $selected)
    .frame(height: 170)
    .accessibilityLabel("Total sleep and longest stretch per day")
  }
}

// MARK: - Diapers

struct DiaperChart: View {
  let days: [DayStats]
  @State private var selected: Date?

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Chart {
        ForEach(days) { day in
          BarMark(x: .value("Day", day.day, unit: .day), y: .value("Count", day.wetCount))
            .foregroundStyle(by: .value("Type", "Wet"))
          BarMark(x: .value("Day", day.day, unit: .day), y: .value("Count", day.dirtyCount))
            .foregroundStyle(by: .value("Type", "Dirty"))
        }
        if let selected, let day = days.first(where: { Calendar.current.isDate($0.day, inSameDayAs: selected) }) {
          RuleMark(x: .value("Selected", day.day, unit: .day))
            .foregroundStyle(.secondary)
            .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
              Callout(title: dayLabel(day.day), lines: ["\(day.wetCount) wet", "\(day.dirtyCount) dirty"])
            }
        }
      }
      .chartForegroundStyleScale(["Wet": EventKind.diaper.color.opacity(0.55), "Dirty": EventKind.diaper.color])
      .chartXSelection(value: $selected)
      .frame(height: 150)
      .accessibilityLabel("Wet and dirty diapers per day")

      StoolStrip(days: days)
    }
  }
}

/// A strip of stool colour swatches per day, so a change stands out.
struct StoolStrip: View {
  let days: [DayStats]

  var body: some View {
    HStack(alignment: .top, spacing: 2) {
      ForEach(days) { day in
        VStack(spacing: 2) {
          ForEach(Array(day.stoolColors.prefix(6).enumerated()), id: \.offset) { _, color in
            RoundedRectangle(cornerRadius: 2).fill(color.swatch).frame(height: 6)
          }
        }
        .frame(maxWidth: .infinity)
      }
    }
    .frame(minHeight: 8)
    .accessibilityElement()
    .accessibilityLabel(
      "Stool colours: "
        + days.filter { !$0.stoolColors.isEmpty }.map {
          "\(dayLabel($0.day)) \($0.stoolColors.map { $0.title.lowercased() }.joined(separator: ", "))"
        }.joined(separator: "; "))
  }
}

// MARK: - Pumping

struct PumpChart: View {
  let days: [DayStats]
  let unit: VolumeUnit
  let stash: StashInventory
  @State private var selected: Date?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Chart {
        ForEach(days) { day in
          BarMark(x: .value("Day", day.day, unit: .day), y: .value("Output", Volume.displayValue(ml: day.pumpMl, unit: unit)))
            .foregroundStyle(EventKind.pump.color.gradient)
        }
        if let selected, let day = days.first(where: { Calendar.current.isDate($0.day, inSameDayAs: selected) }) {
          RuleMark(x: .value("Selected", day.day, unit: .day))
            .foregroundStyle(.secondary)
            .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
              Callout(title: dayLabel(day.day), lines: [Volume.format(ml: day.pumpMl, unit: unit)])
            }
        }
      }
      .chartYAxisLabel(unit.title)
      .chartXSelection(value: $selected)
      .frame(height: 150)
      .accessibilityLabel("Pumped volume per day")

      HStack {
        Label("Fridge \(Volume.format(ml: stash.fridgeMl, unit: unit))", systemImage: "refrigerator")
        Spacer()
        Label("Freezer \(Volume.format(ml: stash.freezerMl, unit: unit))", systemImage: "snowflake")
      }
      .font(.footnote)
      .foregroundStyle(.secondary)
    }
  }
}

struct Callout: View {
  let title: String
  let lines: [String]

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title).font(.caption.weight(.semibold))
      ForEach(lines, id: \.self) { Text($0).font(.caption2).monospacedDigit() }
    }
    .padding(6)
    .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemBackground).opacity(0.95)))
    .shadow(radius: 2)
  }
}
