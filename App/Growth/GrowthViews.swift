import Charts
import NestedCore
import NestedData
import SwiftUI

private let weightTint = Color.mint

private extension VolumeUnit {
  /// Weight is shown in pounds when the app is set to ounces, otherwise kilograms.
  var weightAxisUnit: String { self == .oz ? "lb" : "kg" }
  func weightValue(grams: Double) -> Double { self == .oz ? grams / 453.592_37 : grams / 1000 }
}

/// Trends card: latest weight, the growth curve with her weigh-ins on it, and what lines up.
struct WeightCard: View {
  let weights: [Weighing]
  let baby: Baby?
  let history: History
  var add: () -> Void
  var edit: (Weighing) -> Void

  @State private var selection: Date?

  private var unit: VolumeUnit { baby?.unit ?? .ml }
  private var due: Date? { DevicePrefs.dueDate }

  private func ageDays(_ date: Date) -> Double {
    guard let birth = baby?.birthDate else { return 0 }
    return Double(DevelopmentGuide.ageDays(birth: birth, due: due, now: date))
  }

  var body: some View {
    Card(tint: weightTint) {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Label("Weight", systemImage: "scalemass.fill")
            .font(.headline).foregroundStyle(weightTint)
          Spacer()
          Button(action: add) {
            Label("Add weigh-in", systemImage: "plus")
              .font(.subheadline.weight(.semibold))
          }
          .buttonStyle(.borderedProminent).tint(weightTint).controlSize(.small)
        }
        if let latest = weights.last {
          summary(latest)
          if weights.count >= 2 { chart }
          recent
          intervalRows
        } else {
          Text("Log her first weigh-in to see her curve, how fast she's gaining, and how it lines up with feeding, diapers and sleep.")
            .font(.subheadline).foregroundStyle(.secondary)
        }
      }
    }
  }

  // MARK: Pieces

  private func summary(_ latest: Weighing) -> some View {
    let previous = weights.dropLast().last
    return VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(WeightFormat.format(grams: latest.grams, unit: unit))
          .font(.system(.title, design: .rounded).weight(.bold))
        if let previous {
          let days = max(1, latest.measuredAt.timeIntervalSince(previous.measuredAt) / 86_400)
          let change = latest.grams - previous.grams
          Text("\(WeightFormat.change(grams: change, unit: unit)) · \(WeightFormat.perDay(change / days, unit: unit))")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(change >= 0 ? Color.green : .orange)
        }
      }
      if baby?.birthDate != nil {
        let p = WeightReference.percentile(grams: latest.grams, ageDays: ageDays(latest.measuredAt))
        Text("About the \(GrowthEngine.ordinal(p)) percentile · \(latest.measuredAt.formatted(date: .abbreviated, time: .omitted))")
          .font(.footnote).foregroundStyle(.secondary)
      }
    }
  }

  private struct BandPoint: Identifiable {
    let date: Date
    let low: Double
    let median: Double
    let high: Double
    var id: Date { date }
  }

  private var bandPoints: [BandPoint] {
    guard baby?.birthDate != nil, let first = weights.first?.measuredAt, let last = weights.last?.measuredAt
    else { return [] }
    let calendar = Calendar.current
    let start = calendar.date(byAdding: .day, value: -7, to: first) ?? first
    let end = calendar.date(byAdding: .day, value: 14, to: max(last, Date())) ?? last
    var points: [BandPoint] = []
    var cursor = start
    while cursor <= end {
      let age = ageDays(cursor)
      let band = WeightReference.band(ageDays: age)
      points.append(
        BandPoint(
          date: cursor, low: unit.weightValue(grams: band.lowerBound),
          median: unit.weightValue(grams: WeightReference.median(ageDays: age)),
          high: unit.weightValue(grams: band.upperBound)))
      guard let next = calendar.date(byAdding: .day, value: 7, to: cursor) else { break }
      cursor = next
    }
    return points
  }

  private var selected: Weighing? {
    guard let selection else { return nil }
    return weights.min { abs($0.measuredAt.timeIntervalSince(selection)) < abs($1.measuredAt.timeIntervalSince(selection)) }
  }

  private var chart: some View {
    VStack(alignment: .leading, spacing: 6) {
      Chart {
        ForEach(bandPoints) { point in
          AreaMark(
            x: .value("Date", point.date), yStart: .value("Low", point.low), yEnd: .value("High", point.high),
            series: .value("Series", "Typical range")
          )
          .foregroundStyle(weightTint.opacity(0.14))
          LineMark(
            x: .value("Date", point.date), y: .value("Median", point.median), series: .value("Series", "Median")
          )
          .foregroundStyle(Color.secondary.opacity(0.7))
          .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        ForEach(weights) { weight in
          LineMark(
            x: .value("Date", weight.measuredAt), y: .value("Weight", unit.weightValue(grams: weight.grams)),
            series: .value("Series", "Weight")
          )
          .foregroundStyle(weightTint)
          .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
          PointMark(
            x: .value("Date", weight.measuredAt), y: .value("Weight", unit.weightValue(grams: weight.grams))
          )
          .foregroundStyle(weightTint)
          .symbolSize(selected?.id == weight.id ? 90 : 40)
        }
        if let selected {
          RuleMark(x: .value("Date", selected.measuredAt))
            .foregroundStyle(Color.secondary.opacity(0.4))
        }
      }
      .chartYScale(domain: .automatic(includesZero: false))
      .chartYAxis {
        AxisMarks(position: .leading) { value in
          AxisGridLine()
          AxisValueLabel {
            if let v = value.as(Double.self) { Text(v, format: .number.precision(.fractionLength(1))) }
          }
        }
      }
      .chartXSelection(value: $selection)
      .frame(minHeight: 190)
      .accessibilityLabel("Weight over time with the typical range")
      .accessibilityValue(
        weights.suffix(3).map {
          "\($0.measuredAt.formatted(date: .abbreviated, time: .omitted)) \(WeightFormat.format(grams: $0.grams, unit: unit))"
        }.joined(separator: ", "))

      Group {
        if let selected {
          Text(
            "\(selected.measuredAt.formatted(date: .abbreviated, time: .omitted)) · \(WeightFormat.format(grams: selected.grams, unit: unit))"
              + (baby?.birthDate == nil ? "" : " · \(GrowthEngine.ordinal(WeightReference.percentile(grams: selected.grams, ageDays: ageDays(selected.measuredAt)))) percentile")
          )
        } else {
          Text("Shaded: typical range for girls (WHO). Dashed: median. Drag to read a weigh-in.")
        }
      }
      .font(.footnote).foregroundStyle(.secondary)
    }
  }

  private var recent: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(weights.reversed().prefix(5).enumerated()), id: \.element.id) { index, weight in
        let earlier = weights.last { $0.measuredAt < weight.measuredAt }
        Button { edit(weight) } label: {
          HStack {
            Text(weight.measuredAt.formatted(date: .abbreviated, time: .shortened))
              .font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            if let earlier {
              Text(WeightFormat.change(grams: weight.grams - earlier.grams, unit: unit))
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            Text(WeightFormat.format(grams: weight.grams, unit: unit))
              .font(.subheadline.weight(.semibold).monospacedDigit())
          }
          .padding(.vertical, 8)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        if index < min(weights.count, 5) - 1 { Divider() }
      }
    }
  }

  @ViewBuilder
  private var intervalRows: some View {
    let spans = GrowthEngine.intervals(weights: weights.map(\.record), history: history).suffix(4)
    if !spans.isEmpty {
      VStack(alignment: .leading, spacing: 6) {
        Text("Between weigh-ins").font(.subheadline.weight(.semibold))
        ForEach(Array(spans.reversed()), id: \.from) { span in
          VStack(alignment: .leading, spacing: 2) {
            Text("\(span.from.formatted(.dateTime.month(.abbreviated).day())) – \(span.to.formatted(.dateTime.month(.abbreviated).day())) · \(WeightFormat.perDay(span.gainPerDay, unit: unit))")
              .font(.footnote.weight(.semibold))
            Text(detail(span)).font(.caption).foregroundStyle(.secondary)
          }
        }
      }
    }
  }

  private func detail(_ span: WeighInterval) -> String {
    var parts = [String(format: "%.0f feeds a day", span.feedsPerDay)]
    if span.nursingMinutesPerDay > 0 { parts.append(String(format: "%.0f min nursing", span.nursingMinutesPerDay)) }
    if span.bottleMlPerDay > 0 { parts.append("\(Volume.format(ml: span.bottleMlPerDay, unit: unit)) bottles") }
    parts.append(String(format: "%.0f wet", span.wetPerDay))
    parts.append(String(format: "%.0f h sleep", span.sleepHoursPerDay))
    return parts.joined(separator: " · ")
  }
}

/// Add or edit a weigh-in. Type what the scale shows; pounds and ounces or kilograms, to match the app.
struct WeightSheet: View {
  let unit: VolumeUnit
  let previous: Weighing?
  let existing: Weighing?
  var save: (_ grams: Double, _ date: Date, _ note: String) -> Void
  var delete: (() -> Void)?

  @Environment(\.dismiss) private var dismiss
  @State private var pounds = ""
  @State private var ounces = ""
  @State private var kilograms = ""
  @State private var date = Date()
  @State private var note = ""
  @FocusState private var focused: Bool

  private func number(_ text: String) -> Double? {
    Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
  }

  private var grams: Double? {
    switch unit {
    case .oz:
      let lb = number(pounds) ?? 0
      let oz = number(ounces) ?? 0
      guard lb > 0 || oz > 0 else { return nil }
      return WeightFormat.grams(pounds: lb, ounces: oz)
    case .ml:
      return number(kilograms).map { $0 * 1000 }
    }
  }

  private var valid: Bool { (grams ?? 0) >= 500 && (grams ?? 0) <= 30_000 }

  var body: some View {
    NavigationStack {
      Form {
        Section("Weight") {
          switch unit {
          case .oz:
            HStack {
              TextField("0", text: $pounds).keyboardType(.decimalPad).focused($focused).multilineTextAlignment(.trailing)
              Text("lb").foregroundStyle(.secondary)
              TextField("0", text: $ounces).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
              Text("oz").foregroundStyle(.secondary)
            }
          case .ml:
            HStack {
              TextField("0.00", text: $kilograms).keyboardType(.decimalPad).focused($focused).multilineTextAlignment(.trailing)
              Text("kg").foregroundStyle(.secondary)
            }
          }
          if let previous {
            Text("Last: \(WeightFormat.format(grams: previous.grams, unit: unit)) on \(previous.measuredAt.formatted(date: .abbreviated, time: .omitted))")
              .font(.footnote).foregroundStyle(.secondary)
          }
          if let grams, valid, let previous, date > previous.measuredAt {
            let days = max(1, date.timeIntervalSince(previous.measuredAt) / 86_400)
            let change = grams - previous.grams
            Text("\(WeightFormat.change(grams: change, unit: unit)) · \(WeightFormat.perDay(change / days, unit: unit))")
              .font(.footnote.weight(.semibold)).foregroundStyle(change >= 0 ? Color.green : .orange)
          } else if grams != nil, !valid {
            Text("That doesn't look like a baby's weight. Check the number.")
              .font(.footnote).foregroundStyle(.orange)
          }
        }
        Section {
          DatePicker("Weighed", selection: $date, in: ...Date())
          TextField("Note (clothes, scale, before or after a feed)", text: $note, axis: .vertical)
        }
        if let delete {
          Section {
            Button("Delete weigh-in", role: .destructive) {
              delete()
              dismiss()
            }
          }
        }
      }
      .navigationTitle(existing == nil ? "Add weigh-in" : "Edit weigh-in")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            if let grams, valid {
              save(grams, date, note)
              dismiss()
            }
          }
          .disabled(!valid)
        }
      }
      .onAppear {
        if let existing {
          date = existing.measuredAt
          note = existing.note
          switch unit {
          case .oz:
            let (lb, oz) = WeightFormat.pounds(existing.grams)
            pounds = "\(lb)"
            ounces = String(format: "%.1f", oz)
          case .ml:
            kilograms = String(format: "%.2f", existing.grams / 1000)
          }
        } else {
          focused = true
        }
      }
    }
    .presentationDetents([.medium, .large])
  }
}
