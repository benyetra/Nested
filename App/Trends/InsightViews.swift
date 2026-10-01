import Charts
import NestedCore
import NestedData
import SwiftUI

extension InsightSeverity {
  var color: Color {
    switch self {
    case .attention: .orange
    case .notice: .yellow
    case .good: .green
    case .info: .blue
    }
  }

  var symbol: String {
    switch self {
    case .attention: "exclamationmark.circle.fill"
    case .notice: "arrow.triangle.2.circlepath.circle.fill"
    case .good: "checkmark.circle.fill"
    case .info: "info.circle.fill"
    }
  }

  var heading: String {
    switch self {
    case .attention: "Worth your attention"
    case .notice: "Changes to watch"
    case .good: "Going well"
    case .info: "Good to know"
    }
  }
}

extension InsightTopic {
  var kind: EventKind? {
    switch self {
    case .feeding, .nursing: .nursing
    case .sleep: .sleep
    case .diapers: .diaper
    case .pumping: .pump
    case .data: nil
    }
  }
}

/// Insights a parent has dismissed stay hidden for a week.
enum InsightSnooze {
  private static let key = "snoozedInsights"

  static func snoozed(now: Date = Date()) -> Set<String> {
    let stored = UserDefaults.standard.dictionary(forKey: key) as? [String: Date] ?? [:]
    return Set(stored.filter { now.timeIntervalSince($0.value) < 7 * 86_400 }.keys)
  }

  static func snooze(_ id: String) {
    var stored = UserDefaults.standard.dictionary(forKey: key) as? [String: Date] ?? [:]
    stored[id] = Date()
    UserDefaults.standard.set(stored, forKey: key)
  }
}

struct Sparkline: View {
  let values: [Double]
  let color: Color

  var body: some View {
    Chart(Array(values.enumerated()), id: \.offset) { index, value in
      LineMark(x: .value("Day", index), y: .value("Value", value))
        .interpolationMethod(.catmullRom)
        .foregroundStyle(color)
        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
      if index == values.count - 1 {
        PointMark(x: .value("Day", index), y: .value("Value", value))
          .foregroundStyle(color)
          .symbolSize(40)
      }
    }
    .chartXAxis(.hidden)
    .chartYAxis(.hidden)
    .chartYScale(domain: .automatic(includesZero: false))
    .accessibilityHidden(true)
  }
}

struct InsightRow: View {
  let insight: Insight
  var onTap: () -> Void

  var body: some View {
    Button(action: onTap) {
      HStack(spacing: 12) {
        Image(systemName: insight.severity.symbol)
          .font(.title3)
          .foregroundStyle(insight.severity.color)
          .frame(width: 28)
        VStack(alignment: .leading, spacing: 2) {
          Text(insight.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
          Text(insight.detail)
            .font(.footnote).foregroundStyle(.secondary)
            .lineLimit(2).multilineTextAlignment(.leading)
        }
        Spacer(minLength: 8)
        if insight.series.count > 2 {
          Sparkline(values: insight.series, color: insight.severity.color)
            .frame(width: 56, height: 28)
        }
        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

/// Groups of insights by severity, each in a tinted card.
struct InsightGroups: View {
  let insights: [Insight]
  var onSelect: (Insight) -> Void

  var body: some View {
    ForEach([InsightSeverity.attention, .notice, .good, .info], id: \.self) { severity in
      let group = insights.filter { $0.severity == severity }
      if !group.isEmpty {
        Card(tint: severity.color) {
          VStack(alignment: .leading, spacing: 12) {
            Label(severity.heading, systemImage: severity.symbol)
              .font(.headline).foregroundStyle(severity.color)
            ForEach(Array(group.enumerated()), id: \.element.id) { index, insight in
              if index > 0 { Divider() }
              InsightRow(insight: insight) { onSelect(insight) }
            }
          }
        }
      }
    }
  }
}

struct InsightDetailSheet: View {
  let insight: Insight
  let babyName: String
  var onSnooze: () -> Void

  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var added = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Label(insight.severity.heading, systemImage: insight.severity.symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(insight.severity.color)
          Text(insight.title).font(.title2.weight(.bold))
          if let metric = insight.metric {
            Text(metric)
              .font(.system(.largeTitle, design: .rounded).weight(.bold))
              .foregroundStyle(insight.severity.color)
          }
          if insight.series.count > 2 {
            Card {
              VStack(alignment: .leading, spacing: 6) {
                Text("Last \(insight.series.count) days").font(.footnote).foregroundStyle(.secondary)
                Sparkline(values: insight.series, color: insight.severity.color).frame(height: 90)
              }
            }
          }
          Text(insight.detail).font(.body)
          if let question = insight.doctorQuestion {
            Button {
              model.addQuestion(RichText(plain: question))
              added = true
            } label: {
              Label(added ? "Added to Doctor" : "Add to Doctor questions",
                systemImage: added ? "checkmark" : "stethoscope")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.teal)
            .disabled(added)
          }
          Button("Hide for a week") {
            onSnooze()
            dismiss()
          }
          .font(.footnote)
          .frame(maxWidth: .infinity)
          Text("General guidance only, not medical advice.")
            .font(.caption2).foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
        }
        .padding()
      }
      .nestedBackground()
      .navigationTitle(babyName)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
    .presentationDetents([.medium, .large])
  }
}

/// "Today vs typical" tile: a number, how it compares, and a sparkline.
struct TrendTile: View {
  let title: String
  let value: String
  let delta: String?
  let deltaGood: Bool?
  let series: [Double]
  let kind: EventKind

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Label(title, systemImage: kind.symbol)
        .font(.caption.weight(.semibold)).foregroundStyle(kind.color)
      Text(value).font(.system(.title2, design: .rounded).weight(.bold)).minimumScaleFactor(0.7).lineLimit(1)
      if let delta {
        Text(delta)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(deltaGood == nil ? Color.secondary : (deltaGood! ? .green : .orange))
      }
      if series.count > 2 {
        Sparkline(values: series, color: kind.color).frame(height: 26)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.card)
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.wash(kind.color, strength: 0.7)) }
    }
  }
}

/// Ask-a-question sheet over the last two weeks of data, answered on device.
struct AskTrendsSheet: View {
  let facts: [String]
  let table: [String]
  let babyName: String

  @Environment(\.dismiss) private var dismiss
  @State private var question = ""
  @State private var answer: String?
  @State private var asking = false
  @FocusState private var focused: Bool

  private let suggestions = [
    "Is she eating enough?", "How was last night's sleep?", "What changed this week?",
    "When does she feed most?",
  ]

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          if let answer {
            Card(tint: .purple) {
              Label("Answer", systemImage: "sparkles").font(.headline)
              Text(answer).font(.callout).padding(.top, 2)
            }
          } else if asking {
            ProgressView("Looking at the data…").frame(maxWidth: .infinity).padding(.top, 40)
          } else {
            Text("Ask about \(babyName)'s last two weeks. Answers come from your logs and are computed on this phone.")
              .font(.callout).foregroundStyle(.secondary)
            ForEach(suggestions, id: \.self) { suggestion in
              Button(suggestion) { ask(suggestion) }
                .buttonStyle(.bordered).tint(.purple)
            }
          }
        }
        .padding()
      }
      .scrollDismissesKeyboard(.interactively)
      .nestedBackground()
      .safeAreaInset(edge: .bottom) {
        HStack {
          TextField("Ask a question", text: $question)
            .focused($focused)
            .submitLabel(.send)
            .onSubmit { ask(question) }
            .padding(12)
            .background(Palette.card, in: Capsule())
          Button { ask(question) } label: {
            Image(systemName: "arrow.up.circle.fill").font(.title)
          }
          .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || asking)
        }
        .padding()
        .background(.bar)
      }
      .navigationTitle("Ask about trends")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
    .presentationDetents([.large])
  }

  private func ask(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    question = ""
    focused = false
    answer = nil
    asking = true
    Task {
      let result = await SummaryService.answer(
        question: trimmed, facts: facts, table: table, babyName: babyName)
      answer = result
      asking = false
    }
  }
}
