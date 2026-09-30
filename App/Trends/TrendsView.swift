import NestedCore
import NestedData
import SQLiteData
import SwiftUI

struct TrendsView: View {
  @State private var range: StatsRange = .week
  @Fetch(TrendsRequest(days: 30), animation: Motion.standard) private var data = TrendsRequest.Value()
  @State private var summary: String?
  @State private var summaryDigest: WeeklyDigest?

  private var unit: VolumeUnit { data.baby?.unit ?? .ml }
  private var babyName: String { data.baby?.name.isEmpty == false ? data.baby!.name : "Baby" }

  private var summaryTitle: String { days.count < 7 ? "So far" : "This week" }

  private var birth: Date? { data.baby?.birthDate }

  /// The chosen range, starting at her birth so charts never open with days before she was born.
  private var days: [DayStats] {
    DailyStatsBuilder.trimmed(
      DailyStatsBuilder.build(history: data.history, days: range.days, now: Date()), birth: birth)
  }

  private var averageFeeds: Double? {
    DailyStatsBuilder.averages(days, birth: birth)?.feeds
  }

  private var nightStretch: NightStretchTrend? {
    NightStretchAnalyzer.trend(sleeps: data.history.sleeps, now: Date(), window: data.baby?.nightWindow ?? .defaultNight)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Picker("Range", selection: $range) {
            ForEach(StatsRange.allCases) { Text($0.rawValue).tag($0) }
          }
          .pickerStyle(.segmented)

          if let summary {
            Card(tint: EventKind.nursing.color) {
              VStack(alignment: .leading, spacing: 6) {
                Label(summaryTitle, systemImage: "sparkles").font(.headline)
                Text(summary).font(.callout)
              }
            }
          }

          if let nightStretch {
            Card(tint: EventKind.sleep.color) {
              Label(nightStretch.summary, systemImage: "moon.stars.fill")
                .font(.callout.weight(.medium))
            }
          }

          section("Day clock", kind: .sleep) {
            DayClockChart(history: data.history, days: max(days.count, 1))
          }
          section("Feeding", kind: .nursing, footer: feedingFooter) {
            FeedingChart(days: days, unit: unit, average: averageFeeds)
          }
          if days.contains(where: { $0.nursingLeft + $0.nursingRight > 0 }) {
            section("Nursing balance", kind: .nursing) { NursingBalanceChart(days: days) }
          }
          section("Sleep", kind: .sleep) { SleepChart(days: days) }
          section("Diapers", kind: .diaper) { DiaperChart(days: days, birth: birth) }
          if days.contains(where: { $0.pumpMl > 0 }) || !data.history.pumps.isEmpty {
            section("Pumping", kind: .pump) {
              PumpChart(days: days, unit: unit, stash: StashInventory.compute(history: data.history, now: Date()))
            }
          }
        }
        .padding()
      }
      .nestedBackground()
      .actionBarInset(tab: .trends)
      .navigationTitle("Trends")
      .task(id: data.history) { await refreshSummary() }
    }
  }

  /// "82% of feeds were nursing · median bottle 35 ml"
  private var feedingFooter: String? {
    let feeds = days.map(\.feedCount).reduce(0, +)
    let bottles = days.map(\.bottleCount).reduce(0, +)
    var parts: [String] = []
    if feeds > 0 {
      let share = Int((Double(feeds - bottles) / Double(feeds) * 100).rounded())
      parts.append("\(share)% of feeds were nursing")
    }
    if let median = medianBottleText { parts.append(median) }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  private var medianBottleText: String? {
    let recent = data.history.feeds.suffix(20).compactMap { feed -> Double? in
      if case .bottle(let ml, _) = feed.kind { return ml }
      return nil
    }
    guard let median = Stats.median(recent) else { return nil }
    return "Median bottle \(Volume.format(ml: median, unit: unit))"
  }

  @ViewBuilder
  private func section<Content: View>(
    _ title: String, kind: EventKind, footer: String? = nil, @ViewBuilder content: () -> Content
  ) -> some View {
    Card {
      VStack(alignment: .leading, spacing: 10) {
        Label(title, systemImage: kind.symbol)
          .font(.headline)
          .foregroundStyle(kind.color)
        content()
        if let footer {
          Text(footer).font(.footnote).foregroundStyle(.secondary)
        }
      }
    }
  }

  private func refreshSummary() async {
    // Whole days since her birth: zeros from before she was born, or a day still in progress,
    // would pull every average down.
    let recent = DailyStatsBuilder.trimmed(
      DailyStatsBuilder.build(history: data.history, days: 8, now: Date()), birth: birth)
    let whole = DailyStatsBuilder.wholeDays(recent, birth: birth)
    let week = whole.isEmpty ? recent : whole
    guard week.contains(where: { $0.feedCount > 0 }),
      let digest = WeeklyDigest.compute(days: week, stretch: nightStretch)
    else {
      summary = nil
      return
    }
    guard digest != summaryDigest else { return }
    summaryDigest = digest
    summary = await SummaryService.summarize(digest, babyName: babyName, unit: unit)
  }
}
