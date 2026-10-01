import Charts
import NestedCore
import NestedData
import SwiftUI

/// Scrub support shared by every chart: a rule and value callout at the selected day.
struct ScrubState: Equatable {
  var date: Date?
}

private func dayLabel(_ date: Date) -> String {
  date.formatted(.dateTime.month(.abbreviated).day())
}

extension View {
  /// Day labels under a per-day chart: a narrow weekday for up to two weeks, a date every fifth
  /// day beyond that.
  func dayAxis(days: Int) -> some View {
    chartXAxis {
      AxisMarks(values: .stride(by: .day, count: days > 14 ? 5 : 1)) { _ in
        AxisValueLabel(
          format: days > 14 ? .dateTime.month(.abbreviated).day() : .dateTime.weekday(.narrow),
          centered: days <= 14)
      }
    }
  }
}

// MARK: - Day clock

/// "Tue 29": short and unique per day, so it can label a row.
private func rowLabel(_ date: Date) -> String {
  date.formatted(.dateTime.weekday(.abbreviated).day())
}

/// One horizontal 24 h bar per day, most recent at the bottom: sleep blocks, feeds and diapers.
///
/// Drawn by hand rather than with Charts: the day labels get their own column, so they can
/// never sit on top of a mark.
struct DayClockChart: View {
  let history: History
  let days: Int
  var now = Date()
  var rowHeight: CGFloat = 30
  var showsLegend = true

  private let labelWidth: CGFloat = 48

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
    let blocksByDay = Dictionary(grouping: blocks, by: \.day)
    let marksByDay = Dictionary(grouping: marks, by: \.day)
    VStack(alignment: .leading, spacing: 10) {
      VStack(spacing: 0) {
        ForEach(dayStarts, id: \.self) { day in
          HStack(spacing: 6) {
            Text(rowLabel(day))
              .font(.caption2)
              .foregroundStyle(.secondary)
              .frame(width: labelWidth, alignment: .leading)
            row(blocks: blocksByDay[day] ?? [], marks: marksByDay[day] ?? [])
          }
          .frame(height: rowHeight)
        }
        HStack(spacing: 6) {
          Color.clear.frame(width: labelWidth, height: 1)
          axis
        }
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Day clock for the last \(days) days: sleep blocks, feeds and diapers across each 24 hours.")

      if showsLegend {
        HStack(spacing: 14) {
          legend(RoundedRectangle(cornerRadius: 2).fill(EventKind.sleep.color.opacity(0.45)).frame(width: 14, height: 8), "Sleep")
          legend(Circle().fill(EventKind.nursing.color).frame(width: 8, height: 8), "Nursing")
          legend(Circle().fill(EventKind.bottle.color).frame(width: 8, height: 8), "Bottle")
          legend(Image(systemName: "diamond.fill").font(.system(size: 8)).foregroundStyle(EventKind.diaper.color), "Diaper")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
      }
    }
  }

  /// One day's strip: faint 6-hour guides, sleep blocks, then the marks on top.
  private func row(blocks: [Block], marks: [Mark]) -> some View {
    GeometryReader { proxy in
      let width = proxy.size.width
      let height = proxy.size.height
      let x: (Double) -> CGFloat = { CGFloat($0 / 1440) * width }
      ZStack(alignment: .topLeading) {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
          .fill(Color.primary.opacity(0.05))
        ForEach([6.0, 12.0, 18.0], id: \.self) { hour in
          Rectangle()
            .fill(Color.primary.opacity(0.10))
            .frame(width: 0.5, height: height)
            .offset(x: x(hour * 60))
        }
        ForEach(blocks) { block in
          RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(EventKind.sleep.color.opacity(0.45))
            .frame(width: max(3, x(block.endMinute) - x(block.startMinute)), height: height * 0.56)
            .offset(x: x(block.startMinute), y: height * 0.22)
        }
        ForEach(marks) { mark in
          Group {
            if mark.kind == .diaper {
              Image(systemName: "diamond.fill").font(.system(size: 8))
            } else {
              Circle().frame(width: 9, height: 9)
            }
          }
          .foregroundStyle(mark.kind.color)
          .position(x: x(mark.minute), y: mark.kind == .diaper ? height * 0.8 : height * 0.36)
        }
      }
    }
    .frame(height: rowHeight - 4)
  }

  private var axis: some View {
    GeometryReader { proxy in
      let width = proxy.size.width
      ZStack(alignment: .topLeading) {
        ForEach(Array(["12a", "6a", "12p", "6p", "12a"].enumerated()), id: \.offset) { index, title in
          Text(title)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .position(x: min(max(width * CGFloat(index) / 4, 10), width - 10), y: 9)
        }
      }
    }
    .frame(height: 18)
  }

  private func legend<Symbol: View>(_ symbol: Symbol, _ title: String) -> some View {
    HStack(spacing: 4) {
      symbol
      Text(title)
    }
    .accessibilityElement(children: .combine)
  }
}

// MARK: - Feeding

/// Feeds per day, split into nursing and bottle so the top-ups are easy to see, with the
/// average across whole days as a dashed line.
struct FeedingChart: View {
  let days: [DayStats]
  let unit: VolumeUnit
  /// Feeds per day over whole days, or nil until there are two.
  var average: Double?
  @State private var selected: Date?

  private func nursingFeeds(_ day: DayStats) -> Int { max(0, day.feedCount - day.bottleCount) }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Chart {
        ForEach(days) { day in
          BarMark(x: .value("Day", day.day, unit: .day), y: .value("Feeds", nursingFeeds(day)))
            .foregroundStyle(by: .value("Type", "Nursing"))
          BarMark(x: .value("Day", day.day, unit: .day), y: .value("Feeds", day.bottleCount))
            .foregroundStyle(by: .value("Type", "Bottle"))
        }
        if let average {
          RuleMark(y: .value("Average", average))
            .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
            .foregroundStyle(.secondary)
            .annotation(position: .top, alignment: .leading, spacing: 2) {
              Text("avg \(average.formatted(.number.precision(.fractionLength(1))))")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            }
        }
        if let selected, let day = days.first(where: { Calendar.current.isDate($0.day, inSameDayAs: selected) }) {
          RuleMark(x: .value("Selected", day.day, unit: .day))
            .foregroundStyle(.secondary.opacity(0.5))
            .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
              Callout(
                title: dayLabel(day.day),
                lines: [
                  "\(nursingFeeds(day)) nursing · \(day.bottleCount) bottle",
                  "Nursed \(Durations.format(day.nursingLeft + day.nursingRight))",
                ] + (day.bottleMl > 0 ? ["\(Volume.format(ml: day.bottleMl, unit: unit)) by bottle"] : []))
            }
        }
      }
      .chartForegroundStyleScale(["Nursing": EventKind.nursing.color, "Bottle": EventKind.bottle.color])
      .chartLegend(position: .bottom, alignment: .leading)
      .dayAxis(days: days.count)
      .chartXSelection(value: $selected)
      .frame(height: 170)
      .accessibilityLabel("Nursing and bottle feeds per day")

      if days.contains(where: { $0.bottleMl > 0 }) {
        Text("Top-up volume").font(.caption.weight(.semibold)).foregroundStyle(EventKind.bottle.color)
        Chart(days) { day in
          BarMark(x: .value("Day", day.day, unit: .day), y: .value("Bottle", Volume.displayValue(ml: day.bottleMl, unit: unit)))
            .foregroundStyle(EventKind.bottle.color.gradient)
            .annotation(position: .top) {
              if day.bottleMl > 0, days.count <= 10 {
                Text(Volume.format(ml: day.bottleMl, unit: unit)).font(.system(size: 9)).foregroundStyle(.secondary)
              }
            }
        }
        .chartYAxisLabel(unit.title)
        .dayAxis(days: days.count)
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
  /// Typical hours of sleep per day for her age; drawn as a soft band behind the bars.
  var typical: ClosedRange<Double>? = nil
  @State private var selected: Date?

  var body: some View {
    Chart {
      if let typical, let first = days.first?.day, let last = days.last?.day,
        let end = Calendar.current.date(byAdding: .day, value: 1, to: last)
      {
        RectangleMark(
          xStart: .value("From", first), xEnd: .value("To", end),
          yStart: .value("Typical low", typical.lowerBound), yEnd: .value("Typical high", typical.upperBound)
        )
        .foregroundStyle(.green.opacity(0.12))
        .accessibilityHidden(true)
      }
      ForEach(days) { day in
        BarMark(x: .value("Day", day.day, unit: .day), y: .value("Hours", day.sleepTotal / 3600))
          .foregroundStyle(EventKind.sleep.color.opacity(0.55))
          .accessibilityLabel(dayLabel(day.day))
          .accessibilityValue("Total \(Durations.spoken(day.sleepTotal)), longest \(Durations.spoken(day.longestSleep))")
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
    .chartYAxisLabel(typical == nil ? "hours · bars total, line longest" : "hours · bars total, line longest, band typical")
    .chartXSelection(value: $selected)
    .frame(minHeight: 170)
    .accessibilityLabel("Total sleep and longest stretch per day")
  }
}

// MARK: - Diapers

/// Wet and dirty side by side, so wet can be read against the usual minimum for her age
/// (the dashed line, shown for the first two weeks).
struct DiaperChart: View {
  let days: [DayStats]
  var birth: Date?
  @State private var selected: Date?

  private func minimum(_ day: DayStats) -> Int? {
    guard let birth else { return nil }
    let dayOfLife = NewbornGuide.dayOfLife(day.day, birth: birth)
    return dayOfLife <= 14 ? NewbornGuide.minimumWetDiapers(dayOfLife: dayOfLife) : nil
  }

  private var showsGuide: Bool { days.contains { minimum($0) != nil } }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Chart {
        ForEach(days) { day in
          BarMark(x: .value("Day", day.day, unit: .day), y: .value("Count", day.wetCount))
            .foregroundStyle(by: .value("Type", "Wet"))
            .position(by: .value("Type", "Wet"))
          BarMark(x: .value("Day", day.day, unit: .day), y: .value("Count", day.dirtyCount))
            .foregroundStyle(by: .value("Type", "Dirty"))
            .position(by: .value("Type", "Dirty"))
        }
        if showsGuide {
          ForEach(days) { day in
            if let minimum = minimum(day) {
              LineMark(
                x: .value("Day", day.day, unit: .day), y: .value("Usual minimum", minimum),
                series: .value("Guide", "Usual minimum wet")
              )
              .interpolationMethod(.stepCenter)
              .lineStyle(StrokeStyle(lineWidth: 1.4, dash: [4, 3]))
              .foregroundStyle(.secondary)
            }
          }
        }
        if let selected, let day = days.first(where: { Calendar.current.isDate($0.day, inSameDayAs: selected) }) {
          RuleMark(x: .value("Selected", day.day, unit: .day))
            .foregroundStyle(.secondary.opacity(0.5))
            .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
              Callout(
                title: dayLabel(day.day),
                lines: ["\(day.wetCount) wet", "\(day.dirtyCount) dirty"]
                  + (minimum(day).map { ["usual minimum \($0) wet"] } ?? []))
            }
        }
      }
      .chartForegroundStyleScale(["Wet": EventKind.diaper.color.opacity(0.55), "Dirty": EventKind.diaper.color])
      .chartLegend(position: .bottom, alignment: .leading)
      .dayAxis(days: days.count)
      .chartXSelection(value: $selected)
      .frame(height: 160)
      .accessibilityLabel("Wet and dirty diapers per day")

      if showsGuide {
        Text("Dashed line: the usual minimum wet diapers for her age, a general guide and not medical advice.")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

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

// MARK: - Feed gaps and night/day sleep

/// Longest time between feeds each day, with the day's average gap as a line.
struct FeedGapChart: View {
  let extras: [DayExtras]
  @State private var selected: Date?

  var body: some View {
    Chart {
      ForEach(extras) { day in
        BarMark(x: .value("Day", day.day, unit: .day), y: .value("Longest", day.longestFeedGap / 3600))
          .foregroundStyle(EventKind.nursing.color.opacity(0.55))
          .accessibilityLabel(dayLabel(day.day))
          .accessibilityValue(
            "Longest gap \(Durations.spoken(day.longestFeedGap)), average \(Durations.spoken(day.averageFeedGap))")
        LineMark(x: .value("Day", day.day, unit: .day), y: .value("Average", day.averageFeedGap / 3600))
          .foregroundStyle(EventKind.nursing.color)
          .interpolationMethod(.monotone)
          .symbol(.circle)
      }
      if let selected, let day = extras.first(where: { Calendar.current.isDate($0.day, inSameDayAs: selected) }) {
        RuleMark(x: .value("Selected", day.day, unit: .day))
          .foregroundStyle(.secondary)
          .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
            Callout(title: dayLabel(day.day), lines: [
              "Longest \(Durations.format(day.longestFeedGap))",
              "Average \(Durations.format(day.averageFeedGap))",
            ])
          }
      }
    }
    .chartYAxisLabel("hours · bars longest, line average")
    .chartXSelection(value: $selected)
    .dayAxis(days: extras.count)
    .frame(minHeight: 150)
  }
}

/// Sleep per day split into the night window and daytime.
struct NightDaySleepChart: View {
  let extras: [DayExtras]
  @State private var selected: Date?

  var body: some View {
    Chart {
      ForEach(extras) { day in
        BarMark(x: .value("Day", day.day, unit: .day), y: .value("Hours", day.nightSleep / 3600))
          .foregroundStyle(by: .value("When", "Night"))
          .accessibilityLabel("\(dayLabel(day.day)), night")
          .accessibilityValue(Durations.spoken(day.nightSleep))
        BarMark(x: .value("Day", day.day, unit: .day), y: .value("Hours", day.daySleep / 3600))
          .foregroundStyle(by: .value("When", "Day"))
          .accessibilityLabel("\(dayLabel(day.day)), daytime")
          .accessibilityValue(Durations.spoken(day.daySleep))
      }
      if let selected, let day = extras.first(where: { Calendar.current.isDate($0.day, inSameDayAs: selected) }) {
        RuleMark(x: .value("Selected", day.day, unit: .day))
          .foregroundStyle(.secondary)
          .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
            Callout(title: dayLabel(day.day), lines: [
              "Night \(Durations.format(day.nightSleep))",
              "Day \(Durations.format(day.daySleep))",
            ])
          }
      }
    }
    .chartForegroundStyleScale([
      "Night": EventKind.sleep.color, "Day": EventKind.sleep.color.opacity(0.4),
    ])
    .chartYAxisLabel("hours")
    .chartXSelection(value: $selected)
    .dayAxis(days: extras.count)
    .frame(minHeight: 150)
  }
}
