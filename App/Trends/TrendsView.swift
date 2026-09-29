import NestCore
import NestData
import SQLiteData
import SwiftUI

struct TrendsView: View {
  @State private var range: StatsRange = .week
  @Fetch(TrendsRequest(days: 30), animation: Motion.standard) private var data = TrendsRequest.Value()
  @State private var summary: String?
  @State private var summaryDigest: WeeklyDigest?

  private var unit: VolumeUnit { data.baby?.unit ?? .ml }
  private var babyName: String { data.baby?.name.isEmpty == false ? data.baby!.name : "Baby" }

  private var days: [DayStats] {
    DailyStatsBuilder.build(history: data.history, days: range.days, now: Date())
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
                Label("This week", systemImage: "sparkles").font(.headline)
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
            DayClockChart(history: data.history, days: max(range.days, 1))
          }
          section("Feeding", kind: .bottle, footer: medianBottleText) {
            FeedingChart(days: days, unit: unit)
          }
          if days.contains(where: { $0.nursingLeft + $0.nursingRight > 0 }) {
            section("Nursing balance", kind: .nursing) { NursingBalanceChart(days: days) }
          }
          section("Sleep", kind: .sleep) { SleepChart(days: days) }
          section("Diapers", kind: .diaper) { DiaperChart(days: days) }
          if days.contains(where: { $0.pumpMl > 0 }) || !data.history.pumps.isEmpty {
            section("Pumping", kind: .pump) {
              PumpChart(days: days, unit: unit, stash: StashInventory.compute(history: data.history, now: Date()))
            }
          }
        }
        .padding()
      }
      .nestBackground()
      .navigationTitle("Trends")
      .task(id: data.history) { await refreshSummary() }
    }
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
    let week = DailyStatsBuilder.build(history: data.history, days: 7, now: Date())
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
