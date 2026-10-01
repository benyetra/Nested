import Foundation

/// How an insight should be presented. Order is display order.
public enum InsightSeverity: Int, Hashable, Sendable, Comparable {
  /// Worth acting on or raising with the pediatrician.
  case attention
  /// A change worth knowing about; not a concern on its own.
  case notice
  /// Something going well.
  case good
  /// Context, or not enough data yet.
  case info

  public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

public enum InsightTopic: String, Hashable, Sendable {
  case feeding, nursing, sleep, diapers, pumping, data
}

/// One finding, phrased in fixed wording from numbers computed in code. Never a diagnosis.
public struct Insight: Hashable, Sendable, Identifiable {
  public var id: String
  public var severity: InsightSeverity
  public var topic: InsightTopic
  public var title: String
  public var detail: String
  /// Headline number, e.g. "9.3 / day".
  public var metric: String?
  /// Recent daily values for a sparkline, oldest first.
  public var series: [Double]
  /// Pre-written question for the Doctor tab, when the finding is worth raising.
  public var doctorQuestion: String?

  public init(
    id: String,
    severity: InsightSeverity,
    topic: InsightTopic,
    title: String,
    detail: String,
    metric: String? = nil,
    series: [Double] = [],
    doctorQuestion: String? = nil
  ) {
    self.id = id
    self.severity = severity
    self.topic = topic
    self.title = title
    self.detail = detail
    self.metric = metric
    self.series = series
    self.doctorQuestion = doctorQuestion
  }
}

public enum InsightEngine {
  /// Findings for the recent past, most important first. Looks at whole days only (today is
  /// still in progress), comparing the last three days with the days before them.
  public static func generate(
    history: History,
    birth: Date?,
    now: Date,
    night: DayWindow = .defaultNight,
    thresholds: FlagThresholds = .default,
    calendar: Calendar = .current
  ) -> [Insight] {
    let all = DailyStatsBuilder.trimmed(
      DailyStatsBuilder.build(history: history, days: 14, now: now, calendar: calendar),
      birth: birth, calendar: calendar)
    let whole = DailyStatsBuilder.wholeDays(all, birth: birth, calendar: calendar)
      .drop(while: { DailyStatsBuilder.isEmpty($0) }).map { $0 }
    let extras = DailyExtrasBuilder.build(
      history: history, days: whole.map(\.day), now: now, night: night, calendar: calendar)

    guard whole.count >= 2 else {
      return [
        Insight(
          id: "data.sparse", severity: .info, topic: .data,
          title: "Insights need a couple of full days",
          detail: "Keep logging. Once there are two complete days, patterns and changes show up here.")
      ]
    }

    let recent = Array(whole.suffix(3))
    let earlier = Array(whole.dropLast(3).suffix(7))
    let age = birth.map { AgeMath.days(from: $0, to: now, calendar: calendar) }
    var out: [Insight] = []

    out += feeding(whole, recent, earlier, thresholds)
    out += gaps(extras, thresholds, age: age)
    out += nursing(whole, recent, earlier)
    out += supplement(recent, earlier)
    out += sleep(whole, recent, extras, age: age, history: history, now: now, night: night, calendar: calendar)
    out += diapers(whole, recent, thresholds, birth: birth, age: age, history: history, now: now, calendar: calendar)
    out += pumping(whole, recent, history: history, now: now)

    return out.sorted { ($0.severity, $0.id) < ($1.severity, $1.id) }
  }

  // MARK: - Detectors

  private static func mean(_ values: [Double]) -> Double {
    values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
  }

  private static func one(_ value: Double) -> String { String(format: "%.1f", value) }

  private static func feeding(
    _ whole: [DayStats], _ recent: [DayStats], _ earlier: [DayStats], _ th: FlagThresholds
  ) -> [Insight] {
    let series = whole.suffix(7).map { Double($0.feedCount) }
    let now = mean(recent.map { Double($0.feedCount) })
    var out: [Insight] = []
    if now < Double(th.minFeedsPer24h) {
      out.append(
        Insight(
          id: "feeding.low", severity: .attention, topic: .feeding,
          title: "Fewer feeds than usual guidance",
          detail:
            "The last \(recent.count) days averaged \(one(now)) feeds a day. Newborns usually feed at least \(th.minFeedsPer24h) times in 24 hours. \(HealthFlag.callPediatrician)",
          metric: "\(one(now)) / day", series: series,
          doctorQuestion:
            "Feeds have averaged \(one(now)) a day lately. Is that enough for her age and weight?"))
    } else if earlier.count >= 3 {
      let before = mean(earlier.map { Double($0.feedCount) })
      if now >= before * 1.25, now - before >= 2 {
        out.append(
          Insight(
            id: "feeding.up", severity: .notice, topic: .feeding,
            title: "Feeding more often lately",
            detail:
              "Up from \(one(before)) to \(one(now)) feeds a day. Short bursts like this are common during growth spurts, and usually settle within a few days.",
            metric: "\(one(now)) / day", series: series))
      } else if now <= before * 0.8, before - now >= 2 {
        out.append(
          Insight(
            id: "feeding.down", severity: .notice, topic: .feeding,
            title: "Feeding less often lately",
            detail:
              "Down from \(one(before)) to \(one(now)) feeds a day. That can be longer, more efficient feeds. Check that the totals still feel right.",
            metric: "\(one(now)) / day", series: series))
      } else {
        out.append(
          Insight(
            id: "feeding.steady", severity: .good, topic: .feeding,
            title: "Feeding is steady",
            detail: "About \(one(now)) feeds a day, in line with the days before.",
            metric: "\(one(now)) / day", series: series))
      }
    } else {
      out.append(
        Insight(
          id: "feeding.ok", severity: .good, topic: .feeding,
          title: "Feeding on track",
          detail: "About \(one(now)) feeds a day, above the usual minimum of \(th.minFeedsPer24h).",
          metric: "\(one(now)) / day", series: series))
    }
    return out
  }

  private static func gaps(_ extras: [DayExtras], _ th: FlagThresholds, age: Int?) -> [Insight] {
    let recent = extras.suffix(3)
    guard let worst = recent.max(by: { $0.longestFeedGap < $1.longestFeedGap }),
      worst.longestFeedGap > 0
    else { return [] }
    let series = extras.suffix(7).map { $0.longestFeedGap / 3600 }
    if worst.longestFeedGap > th.maxGapNight, (age ?? 0) < 28 {
      let gap = Durations.format(worst.longestFeedGap)
      return [
        Insight(
          id: "gaps.long", severity: .attention, topic: .feeding,
          title: "A long stretch without a feed",
          detail:
            "One gap reached \(gap), longer than your \(Durations.format(th.maxGapNight)) limit. Young babies often need waking to feed in the first weeks. Ask your pediatrician what's right for her.",
          metric: gap, series: series,
          doctorQuestion: "She went \(gap) between feeds. Should we wake her to feed at night?")
      ]
    }
    return []
  }

  private static func nursing(
    _ whole: [DayStats], _ recent: [DayStats], _ earlier: [DayStats]
  ) -> [Insight] {
    var out: [Insight] = []
    let week = whole.suffix(7)
    let left = week.map(\.nursingLeft).reduce(0, +)
    let right = week.map(\.nursingRight).reduce(0, +)
    if left + right > 30 * 60 {
      let leftShare = left / (left + right)
      let major = leftShare >= 0.5 ? "left" : "right"
      let share = Int((max(leftShare, 1 - leftShare) * 100).rounded())
      if share >= 62 {
        out.append(
          Insight(
            id: "nursing.side", severity: .notice, topic: .nursing,
            title: "Leaning on the \(major) side",
            detail:
              "\(share)% of nursing time this week was on the \(major). Alternating helps keep supply even on both sides.",
            metric: "\(share)% \(major)", series: week.map { ($0.nursingLeft + $0.nursingRight) / 60 }))
      } else {
        out.append(
          Insight(
            id: "nursing.balanced", severity: .good, topic: .nursing,
            title: "Sides are well balanced",
            detail: "Nursing time is split about \(100 - share)/\(share) between left and right this week.",
            series: week.map { ($0.nursingLeft + $0.nursingRight) / 60 }))
      }
    }
    let nursingDays = { (days: [DayStats]) -> Double in
      mean(days.map { $0.nursingLeft + $0.nursingRight })
    }
    if earlier.count >= 3 {
      let now = nursingDays(recent)
      let before = nursingDays(earlier)
      if before > 30 * 60, now <= before * 0.75 {
        out.append(
          Insight(
            id: "nursing.shorter", severity: .notice, topic: .nursing,
            title: "Nursing time is down",
            detail:
              "\(Durations.format(now)) a day lately versus \(Durations.format(before)) before. Babies often get quicker at nursing as they grow; watch diapers and weight for reassurance.",
            metric: Durations.format(now),
            series: whole.suffix(7).map { ($0.nursingLeft + $0.nursingRight) / 60 }))
      }
    }
    return out
  }

  private static func supplement(_ recent: [DayStats], _ earlier: [DayStats]) -> [Insight] {
    func share(_ days: [DayStats]) -> Double? {
      let feeds = days.map(\.feedCount).reduce(0, +)
      guard feeds > 0 else { return nil }
      return Double(days.map(\.bottleCount).reduce(0, +)) / Double(feeds)
    }
    guard let now = share(recent), let before = share(earlier), earlier.count >= 3 else { return [] }
    let nowPct = Int((now * 100).rounded())
    let beforePct = Int((before * 100).rounded())
    let series = (earlier + recent).suffix(7).map { Double($0.bottleCount) }
    if now - before >= 0.15 {
      return [
        Insight(
          id: "supplement.up", severity: .notice, topic: .feeding,
          title: "More bottles than before",
          detail:
            "Bottles are \(nowPct)% of feeds, up from \(beforePct)%. If that's not the plan, it may be worth looking at nursing sessions.",
          metric: "\(nowPct)% bottles", series: series)
      ]
    }
    if before - now >= 0.15 {
      return [
        Insight(
          id: "supplement.down", severity: .good, topic: .feeding,
          title: "Leaning more on the breast",
          detail: "Bottles are down to \(nowPct)% of feeds from \(beforePct)%.",
          metric: "\(nowPct)% bottles", series: series)
      ]
    }
    return []
  }

  /// Typical total sleep per 24 h by age (National Sleep Foundation ranges, in hours).
  static func sleepRange(ageDays: Int?) -> ClosedRange<Double>? {
    guard let ageDays else { return nil }
    return ageDays < 120 ? 14...17 : 12...15
  }

  private static func sleep(
    _ whole: [DayStats], _ recent: [DayStats], _ extras: [DayExtras], age: Int?,
    history: History, now: Date, night: DayWindow, calendar: Calendar
  ) -> [Insight] {
    var out: [Insight] = []
    let hours = mean(recent.map(\.sleepTotal)) / 3600
    let series = whole.suffix(7).map { $0.sleepTotal / 3600 }
    // Sleep logs are often incomplete; only comment when there's something logged each day.
    if recent.allSatisfy({ $0.sleepTotal > 0 }), let range = sleepRange(ageDays: age) {
      if hours < range.lowerBound - 1.5 {
        out.append(
          Insight(
            id: "sleep.low", severity: .notice, topic: .sleep,
            title: "Sleeping less than typical",
            detail:
              "About \(one(hours)) h a day lately; babies this age usually sleep \(Int(range.lowerBound))–\(Int(range.upperBound)) h. Unlogged naps can make this look lower than it is.",
            metric: "\(one(hours)) h", series: series))
      } else if range.contains(hours) || hours > range.upperBound {
        out.append(
          Insight(
            id: "sleep.typical", severity: .good, topic: .sleep,
            title: "Sleep is in a healthy range",
            detail:
              "About \(one(hours)) h a day, in the \(Int(range.lowerBound))–\(Int(range.upperBound)) h range typical for her age.",
            metric: "\(one(hours)) h", series: series))
      }
    }

    if let trend = NightStretchAnalyzer.trend(sleeps: history.sleeps, now: now, window: night, calendar: calendar),
      let change = trend.changeFromLastWeek
    {
      let nightSeries = trend.nights.map { $0.longest / 3600 }
      if change >= 30 * 60 {
        out.append(
          Insight(
            id: "sleep.stretch.up", severity: .good, topic: .sleep,
            title: "Longer night stretches",
            detail:
              "Her longest night sleep is \(Durations.format(trend.longestThisWeek)), up \(Durations.format(change)) on average from last week.",
            metric: Durations.format(trend.longestThisWeek), series: nightSeries))
      } else if change <= -60 * 60 {
        out.append(
          Insight(
            id: "sleep.stretch.down", severity: .notice, topic: .sleep,
            title: "Shorter night stretches",
            detail:
              "Longest night sleep is down \(Durations.format(-change)) on average from last week. Growth spurts, teething and routine changes often cause a dip.",
            metric: Durations.format(trend.longestThisWeek), series: nightSeries))
      }
    }

    let nightTotal = extras.suffix(3).map(\.nightSleep).reduce(0, +)
    let dayTotal = extras.suffix(3).map(\.daySleep).reduce(0, +)
    if nightTotal + dayTotal > 6 * 3600 {
      let share = Int((nightTotal / (nightTotal + dayTotal) * 100).rounded())
      if share < 40, (age ?? 0) > 42 {
        out.append(
          Insight(
            id: "sleep.dayNight", severity: .notice, topic: .sleep,
            title: "More sleep by day than by night",
            detail:
              "\(share)% of sleep falls in the night window. Daylight and a calm, dark evening routine help shift the balance over time.",
            metric: "\(share)% at night", series: extras.suffix(7).map { $0.nightSleep / 3600 }))
      }
    }
    return out
  }

  private static func diapers(
    _ whole: [DayStats], _ recent: [DayStats], _ th: FlagThresholds, birth: Date?, age: Int?,
    history: History, now: Date, calendar: Calendar
  ) -> [Insight] {
    var out: [Insight] = []
    let wetSeries = whole.suffix(7).map { Double($0.wetCount) }

    // Wet diapers against the day-of-life minimum.
    var short: [DayStats] = []
    if let birth {
      short = recent.filter {
        $0.wetCount < NewbornGuide.minimumWetDiapers(dayOfLife: NewbornGuide.dayOfLife($0.day, birth: birth, calendar: calendar))
      }
    } else {
      short = recent.filter { $0.wetCount < th.minWetPer24h }
    }
    let wetAvg = mean(recent.map { Double($0.wetCount) })
    if let last = recent.last, short.contains(where: { $0.day == last.day }) {
      out.append(
        Insight(
          id: "diapers.wet.low", severity: .attention, topic: .diapers,
          title: "Fewer wet diapers than expected",
          detail:
            "\(last.wetCount) wet diaper\(last.wetCount == 1 ? "" : "s") on the last full day. Wet diapers are the clearest sign she's getting enough milk. \(HealthFlag.callPediatrician)",
          metric: "\(last.wetCount) wet", series: wetSeries,
          doctorQuestion:
            "She had \(last.wetCount) wet diapers on one day. Is that enough for her age?"))
    } else if recent.count >= 2, short.isEmpty {
      out.append(
        Insight(
          id: "diapers.wet.ok", severity: .good, topic: .diapers,
          title: "Plenty of wet diapers",
          detail: "About \(one(wetAvg)) a day, a reassuring sign she's well hydrated.",
          metric: "\(one(wetAvg)) / day", series: wetSeries))
    }

    // Poop frequency in the early weeks.
    let dirtyAvg = mean(recent.map { Double($0.dirtyCount) })
    if let age, age >= 5, age < 42, recent.count >= 2, dirtyAvg < 1 {
      out.append(
        Insight(
          id: "diapers.dirty.low", severity: .notice, topic: .diapers,
          title: "Few dirty diapers",
          detail:
            "About \(one(dirtyAvg)) a day. Breastfed babies vary a lot, but in the first weeks most have several a day. Mention it at the next visit if it continues.",
          metric: "\(one(dirtyAvg)) / day", series: whole.suffix(7).map { Double($0.dirtyCount) },
          doctorQuestion: "Dirty diapers have been infrequent (about \(one(dirtyAvg)) a day). Is that normal for her?"))
    }

    // Stool colour.
    let cutoff = now.addingTimeInterval(-3 * 86_400)
    let flagged = history.diapers.last { diaper in
      guard diaper.occurredAt >= cutoff, let color = diaper.stoolColor else { return false }
      let ageThen = birth.map { AgeMath.days(from: $0, to: diaper.occurredAt, calendar: calendar) }
      return color.isWorthACall(ageInDays: ageThen)
    }
    if let color = flagged?.stoolColor {
      out.append(
        Insight(
          id: "diapers.stool.color", severity: .attention, topic: .diapers,
          title: "\(color.title) stool logged",
          detail: "This color is worth mentioning. \(HealthFlag.callPediatrician)",
          doctorQuestion: "I logged a \(color.title.lowercased()) stool. Should we be concerned?"))
    }
    return out
  }

  private static func pumping(
    _ whole: [DayStats], _ recent: [DayStats], history: History, now: Date
  ) -> [Insight] {
    let pumped = recent.map(\.pumpMl)
    guard pumped.contains(where: { $0 > 0 }) else { return [] }
    var out: [Insight] = []
    let perDay = mean(pumped)
    let series = whole.suffix(7).map(\.pumpMl)
    let stash = StashInventory.compute(history: history, now: now)
    let stashMl = stash.fridgeMl + stash.freezerMl
    let milkBottles = recent.map(\.bottleMl).reduce(0, +) / Double(max(recent.count, 1))
    if milkBottles > 0, stashMl > 0 {
      let days = stashMl / milkBottles
      if days < 1.5 {
        out.append(
          Insight(
            id: "pump.stash.low", severity: .notice, topic: .pumping,
            title: "Stash is running low",
            detail:
              "At the current bottle rate the stash covers about \(one(days)) day\(days == 1 ? "" : "s"). Another pumping session could help.",
            metric: "\(one(days)) days", series: series))
      } else {
        out.append(
          Insight(
            id: "pump.stash.ok", severity: .good, topic: .pumping,
            title: "Stash is healthy",
            detail: "About \(one(days)) days of bottles in the fridge and freezer.",
            metric: "\(one(days)) days", series: series))
      }
    } else if perDay > 0 {
      out.append(
        Insight(
          id: "pump.output", severity: .info, topic: .pumping,
          title: "Pumping output",
          detail: "About \(Int(perDay.rounded())) ml a day pumped over the last \(recent.count) days.",
          metric: "\(Int(perDay.rounded())) ml / day", series: series))
    }
    return out
  }
}

/// Text bundles for the on-device model. The model only phrases what's here; every number
/// comes from code, and `fallback` is shown when no model is available.
public enum InsightBrief {
  /// Bullet facts for the briefing prompt: the digest, then each finding with its severity.
  public static func facts(
    digest: WeeklyDigest?, insights: [Insight], babyName: String, unit: VolumeUnit
  ) -> [String] {
    var lines = digest?.facts(babyName: babyName, unit: unit) ?? []
    for insight in insights where insight.topic != .data {
      let label: String
      switch insight.severity {
      case .attention: label = "WORTH RAISING WITH THE PEDIATRICIAN"
      case .notice: label = "CHANGE TO WATCH"
      case .good: label = "GOING WELL"
      case .info: label = "CONTEXT"
      }
      lines.append("[\(label)] \(insight.title). \(insight.detail)")
    }
    return lines
  }

  /// One line per day, newest last, for answering questions about specific days.
  public static func dailyTable(
    _ days: [DayStats], extras: [DayExtras], unit: VolumeUnit, calendar: Calendar = .current
  ) -> [String] {
    let extraByDay = Dictionary(uniqueKeysWithValues: extras.map { ($0.day, $0) })
    return days.suffix(14).map { day in
      let comps = calendar.dateComponents([.month, .day], from: day.day)
      var line =
        "\(comps.month ?? 0)/\(comps.day ?? 0): \(day.feedCount) feeds (\(day.bottleCount) bottles, \(Volume.format(ml: day.bottleMl, unit: unit)) bottle milk), nursing \(Durations.format(day.nursingLeft + day.nursingRight)), sleep \(Durations.format(day.sleepTotal)), longest sleep \(Durations.format(day.longestSleep)), \(day.wetCount) wet, \(day.dirtyCount) dirty"
      if day.pumpMl > 0 { line += ", pumped \(Volume.format(ml: day.pumpMl, unit: unit))" }
      if let extra = extraByDay[day.day], extra.longestFeedGap > 0 {
        line += ", longest feed gap \(Durations.format(extra.longestFeedGap))"
      }
      return line
    }
  }

  /// Structured briefing used when the model is unavailable.
  public static func fallbackContent(insights: [Insight], babyName: String) -> BriefingContent {
    let real = insights.filter { $0.topic != .data }
    guard !real.isEmpty else {
      return BriefingContent(headline: "Keep logging and \(babyName)'s patterns will show up here.")
    }
    let attention = real.filter { $0.severity <= .notice }.prefix(3).map(\.title)
    let wins = real.filter { $0.severity == .good }.prefix(3).map(\.title)
    let headline: String
    if real.contains(where: { $0.severity == .attention }) {
      headline = "A few things are worth a look."
    } else if attention.isEmpty {
      headline = "\(babyName) is doing well."
    } else {
      headline = "Mostly steady, with a change or two to watch."
    }
    return BriefingContent(headline: headline, attention: Array(attention), wins: Array(wins))
  }

  /// Plain-text briefing used when the model is unavailable.
  public static func fallback(insights: [Insight], babyName: String) -> String {
    let real = insights.filter { $0.topic != .data }
    let attention = real.filter { $0.severity == .attention }
    let notices = real.filter { $0.severity == .notice }
    let good = real.filter { $0.severity == .good }
    if real.isEmpty { return "Keep logging and \(babyName)'s patterns will show up here." }
    var parts: [String] = []
    if !attention.isEmpty {
      parts.append("Worth raising with your pediatrician: \(attention.map { $0.title.lowercased() }.joined(separator: "; ")).")
    }
    if !notices.isEmpty {
      parts.append("Changes to watch: \(notices.map { $0.title.lowercased() }.joined(separator: "; ")).")
    }
    if !good.isEmpty {
      parts.append("Going well: \(good.map { $0.title.lowercased() }.joined(separator: "; ")).")
    }
    return parts.joined(separator: " ")
  }
}

/// The briefing as shown on the Trends card: a headline, things to watch, and wins.
public struct BriefingContent: Hashable, Sendable {
  public var headline: String
  public var attention: [String]
  public var wins: [String]

  public init(headline: String, attention: [String] = [], wins: [String] = []) {
    self.headline = headline
    self.attention = attention
    self.wins = wins
  }
}
