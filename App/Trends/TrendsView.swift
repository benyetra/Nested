import NestedCore
import NestedData
import SQLiteData
import SwiftUI

struct TrendsView: View {
  @State private var range: StatsRange = .week
  @Fetch(TrendsRequest(days: 30), animation: Motion.standard) private var data = TrendsRequest.Value()
  @State private var briefing: BriefingContent?
  @State private var briefingKey: [String] = []
  @State private var selectedInsight: Insight?
  @State private var asking = false
  @State private var snoozed = InsightSnooze.snoozed()

  private var unit: VolumeUnit { data.baby?.unit ?? .ml }
  private var babyName: String { data.baby?.name.isEmpty == false ? data.baby!.name : "Baby" }

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

  private var night: DayWindow { data.baby?.nightWindow ?? .defaultNight }

  private var allInsights: [Insight] {
    InsightEngine.generate(history: data.history, birth: birth, now: Date(), night: night)
  }

  private var insights: [Insight] { allInsights.filter { !snoozed.contains($0.id) } }

  private var extras: [DayExtras] {
    DailyExtrasBuilder.build(history: data.history, days: days.map(\.day), now: Date(), night: night)
  }

  /// Yesterday (the last whole day) against the average of the days before it.
  private var tiles: [TrendTile] {
    let recent = DailyStatsBuilder.trimmed(
      DailyStatsBuilder.build(history: data.history, days: 9, now: Date()), birth: birth)
    let whole = DailyStatsBuilder.wholeDays(recent, birth: birth)
    guard let last = whole.last, whole.count >= 2 else { return [] }
    let before = Array(whole.dropLast())
    func avg(_ f: (DayStats) -> Double) -> Double { before.map(f).reduce(0, +) / Double(before.count) }
    func delta(_ value: Double, _ base: Double, unit: String, goodWhenUp: Bool?) -> (String?, Bool?) {
      let diff = value - base
      guard abs(diff) >= 0.5 else { return ("Same as usual", nil) }
      let text = String(format: "%@%.0f%@ vs usual", diff > 0 ? "+" : "−", abs(diff), unit)
      return (text, goodWhenUp.map { diff > 0 ? $0 : !$0 })
    }
    let series = { (f: (DayStats) -> Double) in whole.suffix(7).map(f) }
    let feeds = delta(Double(last.feedCount), avg { Double($0.feedCount) }, unit: "", goodWhenUp: nil)
    let sleep = delta(last.sleepTotal / 3600, avg { $0.sleepTotal / 3600 }, unit: " h", goodWhenUp: nil)
    let wet = delta(Double(last.wetCount), avg { Double($0.wetCount) }, unit: "", goodWhenUp: true)
    let stretch = delta(last.longestSleep / 3600, avg { $0.longestSleep / 3600 }, unit: " h", goodWhenUp: true)
    return [
      TrendTile(title: "Feeds", value: "\(last.feedCount)", delta: feeds.0, deltaGood: feeds.1,
        series: series { Double($0.feedCount) }, kind: .nursing),
      TrendTile(title: "Sleep", value: Durations.compact(last.sleepTotal), delta: sleep.0, deltaGood: sleep.1,
        series: series { $0.sleepTotal / 3600 }, kind: .sleep),
      TrendTile(title: "Wet diapers", value: "\(last.wetCount)", delta: wet.0, deltaGood: wet.1,
        series: series { Double($0.wetCount) }, kind: .diaper),
      TrendTile(title: "Longest sleep", value: Durations.compact(last.longestSleep), delta: stretch.0,
        deltaGood: stretch.1, series: series { $0.longestSleep / 3600 }, kind: .sleep),
    ]
  }

  private var briefFacts: [String] {
    let recent = DailyStatsBuilder.trimmed(
      DailyStatsBuilder.build(history: data.history, days: 8, now: Date()), birth: birth)
    let whole = DailyStatsBuilder.wholeDays(recent, birth: birth)
    let digest = WeeklyDigest.compute(days: whole.isEmpty ? recent : whole, stretch: nightStretch)
    return InsightBrief.facts(digest: digest, insights: allInsights, babyName: babyName, unit: unit)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Picker("Range", selection: $range) {
            ForEach(StatsRange.allCases) { Text($0.rawValue).tag($0) }
          }
          .pickerStyle(.segmented)

          briefingCard

          let tileList = tiles
          if !tileList.isEmpty {
            Text("Yesterday vs usual").font(.headline).padding(.top, 4)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
              ForEach(Array(tileList.enumerated()), id: \.offset) { item in item.element }
            }
          }

          InsightGroups(insights: insights) { selectedInsight = $0 }

          if let nightStretch {
            Card(tint: EventKind.sleep.color) {
              Label(nightStretch.summary, systemImage: "moon.stars.fill")
                .font(.callout.weight(.medium))
            }
          }

          Text("Charts").font(.headline).padding(.top, 4)

          section("Day clock", kind: .sleep) {
            DayClockChart(history: data.history, days: max(days.count, 1))
          }
          section("Feeding", kind: .nursing, footer: feedingFooter) {
            FeedingChart(days: days, unit: unit, average: averageFeeds)
          }
          if days.contains(where: { $0.nursingLeft + $0.nursingRight > 0 }) {
            section("Nursing balance", kind: .nursing) { NursingBalanceChart(days: days) }
          }
          if extras.contains(where: { $0.longestFeedGap > 0 }) {
            section("Time between feeds", kind: .nursing) { FeedGapChart(extras: extras) }
          }
          section("Sleep", kind: .sleep) {
            SleepChart(
              days: days,
              typical: birth.flatMap {
                InsightEngine.sleepRange(ageDays: AgeMath.days(from: $0, to: Date()))
              })
          }
          if extras.contains(where: { $0.nightSleep + $0.daySleep > 0 }) {
            section("Night vs day sleep", kind: .sleep) { NightDaySleepChart(extras: extras) }
          }
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
      .task(id: data.history) { await refreshBriefing() }
      .sheet(item: $selectedInsight) { insight in
        InsightDetailSheet(insight: insight, babyName: babyName) {
          InsightSnooze.snooze(insight.id)
          snoozed = InsightSnooze.snoozed()
        }
      }
      .sheet(isPresented: $asking) {
        AskTrendsSheet(
          facts: briefFacts,
          table: InsightBrief.dailyTable(
            DailyStatsBuilder.trimmed(
              DailyStatsBuilder.build(history: data.history, days: 14, now: Date()), birth: birth),
            extras: DailyExtrasBuilder.build(
              history: data.history,
              days: DailyStatsBuilder.trimmed(
                DailyStatsBuilder.build(history: data.history, days: 14, now: Date()), birth: birth
              ).map(\.day),
              now: Date(), night: night),
            unit: unit),
          babyName: babyName)
      }
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

  @ViewBuilder
  private var briefingCard: some View {
    if let briefing {
      Card(tint: .purple) {
        VStack(alignment: .leading, spacing: 8) {
          Label("Briefing", systemImage: "sparkles").font(.headline).foregroundStyle(.purple)
          Text(briefing.headline).font(.callout.weight(.semibold))
          ForEach(briefing.attention, id: \.self) { line in
            Label(line, systemImage: "exclamationmark.circle.fill")
              .font(.callout).foregroundStyle(.primary)
              .symbolRenderingMode(.multicolor)
          }
          ForEach(briefing.wins, id: \.self) { line in
            Label(line, systemImage: "checkmark.circle.fill")
              .font(.callout).foregroundStyle(.primary)
              .symbolRenderingMode(.multicolor)
          }
          if SummaryService.modelAvailable {
            Button { asking = true } label: {
              Label("Ask about trends", systemImage: "bubble.left.and.text.bubble.right")
                .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered).tint(.purple)
            .padding(.top, 2)
          }
        }
      }
    }
  }

  private func refreshBriefing() async {
    let all = allInsights
    guard all.contains(where: { $0.topic != .data }) else {
      briefing = nil
      return
    }
    let facts = briefFacts
    guard facts != briefingKey else { return }
    briefingKey = facts
    let fallback = InsightBrief.fallbackContent(insights: all, babyName: babyName)
    briefing = fallback
    briefing = await SummaryService.brief(facts: facts, fallback: fallback, babyName: babyName)
  }
}
