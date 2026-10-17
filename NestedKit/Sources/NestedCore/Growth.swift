import Foundation

/// One weigh-in. Weights are stored in grams and shown in the baby's unit.
public struct WeightRecord: Hashable, Sendable {
  public var at: Date
  public var grams: Double
  public init(at: Date, grams: Double) {
    self.at = at
    self.grams = grams
  }
}

public enum WeightFormat {
  static let gramsPerOunce = 28.349_523_125
  static let gramsPerPound = 453.592_37

  /// "4.21 kg" or "9 lb 4.5 oz".
  public static func format(grams: Double, unit: VolumeUnit) -> String {
    switch unit {
    case .ml:
      return String(format: "%.2f kg", grams / 1000)
    case .oz:
      let (lb, oz) = pounds(grams)
      return lb == 0 ? String(format: "%.1f oz", oz) : String(format: "%d lb %.1f oz", lb, oz)
    }
  }

  /// Pounds and ounces, with the ounces rounded to a tenth and never showing "16.0".
  public static func pounds(_ grams: Double) -> (lb: Int, oz: Double) {
    let totalOz = (grams / gramsPerOunce * 10).rounded() / 10
    var lb = Int(totalOz / 16)
    var oz = totalOz - Double(lb) * 16
    if oz >= 15.95 { lb += 1; oz = 0 }
    return (lb, oz)
  }

  public static func grams(pounds: Double, ounces: Double) -> Double {
    pounds * gramsPerPound + ounces * gramsPerOunce
  }

  /// "+28 g" / "+1.0 oz" for a gain or loss.
  public static func change(grams: Double, unit: VolumeUnit) -> String {
    let sign = grams < 0 ? "−" : "+"
    switch unit {
    case .ml: return "\(sign)\(Int(abs(grams).rounded())) g"
    case .oz: return String(format: "%@%.1f oz", sign, abs(grams) / gramsPerOunce)
    }
  }

  public static func perDay(_ gramsPerDay: Double, unit: VolumeUnit) -> String {
    "\(change(grams: gramsPerDay, unit: unit)) a day"
  }
}

/// WHO weight-for-age for girls, 0–12 months. Only the median and ±2 SD are kept, so percentiles
/// are approximate. Read between monthly points by straight lines.
public enum WeightReference {
  // kg at 0, 1, ... 12 months
  static let median: [Double] = [3.2, 4.2, 5.1, 5.8, 6.4, 6.9, 7.3, 7.6, 7.9, 8.2, 8.5, 8.7, 8.9]
  static let minus2: [Double] = [2.4, 3.2, 3.9, 4.5, 5.0, 5.4, 5.7, 6.0, 6.3, 6.5, 6.7, 6.9, 7.0]
  static let plus2: [Double] = [4.2, 5.5, 6.6, 7.5, 8.2, 8.8, 9.3, 9.8, 10.2, 10.5, 10.9, 11.2, 11.5]
  static let daysPerMonth = 30.4375

  static func value(_ table: [Double], ageDays: Double) -> Double {
    let months = min(max(ageDays / daysPerMonth, 0), Double(table.count - 1))
    let lower = Int(months)
    let upper = min(lower + 1, table.count - 1)
    let t = months - Double(lower)
    return (table[lower] + (table[upper] - table[lower]) * t) * 1000
  }

  public static func median(ageDays: Double) -> Double { value(median, ageDays: ageDays) }
  public static func band(ageDays: Double) -> ClosedRange<Double> {
    value(minus2, ageDays: ageDays)...value(plus2, ageDays: ageDays)
  }

  /// Standard deviations from the median, read off the ±2 SD curves.
  public static func zScore(grams: Double, ageDays: Double) -> Double {
    let mid = median(ageDays: ageDays)
    let spread =
      grams >= mid
      ? (value(plus2, ageDays: ageDays) - mid) / 2 : (mid - value(minus2, ageDays: ageDays)) / 2
    return (grams - mid) / spread
  }

  /// 0–100, approximate.
  public static func percentile(grams: Double, ageDays: Double) -> Double {
    let z = zScore(grams: grams, ageDays: ageDays)
    return 50 * (1 + erf(z / 2.0.squareRoot()))
  }

  /// Typical gain per day at this age, from the change in the median over a month.
  public static func typicalGainPerDay(ageDays: Double) -> Double {
    let a = max(0, ageDays - 15)
    let b = ageDays + 15
    return (median(ageDays: b) - median(ageDays: a)) / (b - a)
  }
}

/// What happened between two weigh-ins, next to what was logged in that time.
public struct WeighInterval: Hashable, Sendable {
  public var from: Date
  public var to: Date
  public var days: Double
  public var gainPerDay: Double
  public var feedsPerDay: Double
  public var bottleMlPerDay: Double
  public var nursingMinutesPerDay: Double
  public var wetPerDay: Double
  public var sleepHoursPerDay: Double
  /// Share of feeds that were bottles, 0–1.
  public var bottleShare: Double
}

public enum GrowthEngine {
  // MARK: Intervals

  public static func intervals(weights: [WeightRecord], history: History) -> [WeighInterval] {
    let sorted = weights.sorted { $0.at < $1.at }
    var out: [WeighInterval] = []
    for (a, b) in zip(sorted, sorted.dropFirst()) {
      let days = b.at.timeIntervalSince(a.at) / 86_400
      guard days >= 2 else { continue }
      let feeds = history.feeds.filter { $0.startedAt >= a.at && $0.startedAt < b.at }
      // Nothing like a full log across the span: don't draw conclusions from it.
      guard Double(feeds.count) >= 4 * days else { continue }
      var bottleMl = 0.0
      var bottles = 0
      var nursingSeconds = 0.0
      for feed in feeds {
        switch feed.kind {
        case .bottle(let ml, _):
          bottleMl += ml
          bottles += 1
        case .nursing(let l, let r, _):
          nursingSeconds += l + r
        }
      }
      let wet = history.diapers.filter { $0.occurredAt >= a.at && $0.occurredAt < b.at && $0.kind.isWet }.count
      let sleep = MissingDataDetector.asleep(history.sleeps, from: a.at, to: b.at)
      out.append(
        WeighInterval(
          from: a.at, to: b.at, days: days, gainPerDay: (b.grams - a.grams) / days,
          feedsPerDay: Double(feeds.count) / days, bottleMlPerDay: bottleMl / days,
          nursingMinutesPerDay: nursingSeconds / 60 / days, wetPerDay: Double(wet) / days,
          sleepHoursPerDay: sleep / 3600 / days,
          bottleShare: feeds.isEmpty ? 0 : Double(bottles) / Double(feeds.count)))
    }
    return out
  }

  static func pearson(_ xs: [Double], _ ys: [Double]) -> Double? {
    guard xs.count == ys.count, xs.count >= 4 else { return nil }
    let n = Double(xs.count)
    let mx = xs.reduce(0, +) / n
    let my = ys.reduce(0, +) / n
    var sxy = 0.0, sxx = 0.0, syy = 0.0
    for (x, y) in zip(xs, ys) {
      sxy += (x - mx) * (y - my)
      sxx += (x - mx) * (x - mx)
      syy += (y - my) * (y - my)
    }
    guard sxx > 1e-9, syy > 1e-9 else { return nil }
    return sxy / (sxx * syy).squareRoot()
  }

  /// Least-squares grams per day through the given weigh-ins.
  static func slope(_ points: [WeightRecord]) -> Double? {
    guard points.count >= 2, let first = points.first else { return nil }
    let xs = points.map { $0.at.timeIntervalSince(first.at) / 86_400 }
    let ys = points.map(\.grams)
    let n = Double(points.count)
    let mx = xs.reduce(0, +) / n
    let my = ys.reduce(0, +) / n
    var sxy = 0.0, sxx = 0.0
    for (x, y) in zip(xs, ys) {
      sxy += (x - mx) * (y - my)
      sxx += (x - mx) * (x - mx)
    }
    return sxx > 1e-9 ? sxy / sxx : nil
  }

  // MARK: Insights

  /// Findings from the weigh-ins and how they relate to feeding, diapers and sleep. Wording is
  /// fixed and never diagnoses; anything worrying is phrased as worth asking the pediatrician.
  public static func insights(
    weights: [WeightRecord], history: History, birth: Date?, due: Date? = nil, now: Date,
    unit: VolumeUnit, calendar: Calendar = .current
  ) -> [Insight] {
    let sorted = weights.filter { $0.grams > 0 }.sorted { $0.at < $1.at }
    guard let birth, let latest = sorted.last else { return [] }
    func age(_ date: Date) -> Double {
      Double(DevelopmentGuide.ageDays(birth: birth, due: due, now: date, calendar: calendar))
    }
    let latestAge = age(latest.at)
    let series = sorted.suffix(8).map { $0.grams / 1000 }
    var out: [Insight] = []

    // Back to birth weight by about two weeks.
    let daysOld = AgeMath.days(from: birth, to: now, calendar: calendar)
    if let first = sorted.first, AgeMath.days(from: birth, to: first.at, calendar: calendar) <= 3 {
      let birthWeight = first.grams
      let regained = sorted.first { $0.at > first.at && $0.grams >= birthWeight }
      if let regained {
        let day = AgeMath.days(from: birth, to: regained.at, calendar: calendar)
        if day <= 16 {
          out.append(
            Insight(
              id: "weight.regain", severity: .good, topic: .growth,
              title: "Back to birth weight by day \(day)",
              detail: "Most babies are back to birth weight by 10–14 days.",
              metric: WeightFormat.format(grams: regained.grams, unit: unit), series: series))
        }
      } else if daysOld >= 14, latest.grams < birthWeight {
        let gap = WeightFormat.format(grams: birthWeight - latest.grams, unit: unit)
        out.append(
          Insight(
            id: "weight.regain", severity: .attention, topic: .growth,
            title: "Not yet back to birth weight",
            detail:
              "Her last weigh-in is \(gap) under her birth weight at \(daysOld) days old. Most babies are back by 10–14 days, so this is worth mentioning to your pediatrician.",
            metric: WeightFormat.format(grams: latest.grams, unit: unit), series: series,
            doctorQuestion: "Maddie was still under her birth weight at \(daysOld) days. Should we change anything about feeding or weigh her sooner?"))
      } else if daysOld >= 10, latest.grams < birthWeight {
        out.append(
          Insight(
            id: "weight.regain", severity: .notice, topic: .growth,
            title: "Still a little under birth weight",
            detail: "Babies usually get back to birth weight by 10–14 days. Another weigh-in in a few days will show the direction.",
            metric: WeightFormat.format(grams: latest.grams, unit: unit), series: series))
      }
    }

    // Rate of gain over the last three weeks, from every weigh-in in that window.
    let window = sorted.filter { now.timeIntervalSince($0.at) <= 21 * 86_400 }
    if latestAge >= 14, window.count >= 2, let first = window.first,
      latest.at.timeIntervalSince(first.at) >= 5 * 86_400, let rate = slope(window)
    {
      let typical = WeightReference.typicalGainPerDay(ageDays: latestAge)
      let ratio = rate / typical
      let rateText = WeightFormat.perDay(rate, unit: unit)
      let typicalText = WeightFormat.perDay(typical, unit: unit)
      if ratio < 0.5 {
        out.append(
          Insight(
            id: "weight.gain", severity: .attention, topic: .growth, title: "Gaining slowly",
            detail:
              "About \(rateText) lately, well under the \(typicalText) that's typical at this age. Scales vary, so this is worth raising with your pediatrician rather than worrying about it.",
            metric: rateText, series: series,
            doctorQuestion: "Maddie's weight gain has been about \(rateText) over the last few weeks. Is that where we want it?"))
      } else if ratio < 0.7 {
        out.append(
          Insight(
            id: "weight.gain", severity: .notice, topic: .growth, title: "Gain is a little under typical",
            detail: "About \(rateText), against roughly \(typicalText) for her age. One more weigh-in will show whether that holds.",
            metric: rateText, series: series))
      } else if ratio <= 1.7 {
        out.append(
          Insight(
            id: "weight.gain", severity: .good, topic: .growth, title: "Gaining steadily",
            detail: "About \(rateText), in line with the \(typicalText) typical for her age.",
            metric: rateText, series: series))
      } else {
        out.append(
          Insight(
            id: "weight.gain", severity: .info, topic: .growth, title: "Gaining quickly",
            detail: "About \(rateText), more than the usual \(typicalText). Babies often catch up in bursts.",
            metric: rateText, series: series))
      }
    }

    // Where she sits on the growth curve, and whether that's moving.
    let percentile = WeightReference.percentile(grams: latest.grams, ageDays: latestAge)
    let place = "around the \(ordinal(percentile)) percentile"
    if let earlier = sorted.last(where: { latest.at.timeIntervalSince($0.at) >= 18 * 86_400 }) {
      let change =
        WeightReference.zScore(grams: latest.grams, ageDays: latestAge)
        - WeightReference.zScore(grams: earlier.grams, ageDays: age(earlier.at))
      if change <= -1.5 {
        out.append(
          Insight(
            id: "weight.curve", severity: .attention, topic: .growth, title: "Moving down the growth curve",
            detail:
              "She is \(place) now, down from around the \(ordinal(WeightReference.percentile(grams: earlier.grams, ageDays: age(earlier.at)))) a few weeks ago. Worth asking your pediatrician about; percentiles shift a lot in the first months.",
            metric: ordinal(percentile), series: series,
            doctorQuestion: "Maddie's weight percentile has dropped from the \(ordinal(WeightReference.percentile(grams: earlier.grams, ageDays: age(earlier.at)))) to the \(ordinal(percentile)). Is that something to follow?"))
      } else if change <= -1.0 {
        out.append(
          Insight(
            id: "weight.curve", severity: .notice, topic: .growth, title: "Drifting down the curve",
            detail: "She is \(place), a little lower than a few weeks ago. It's common early on, and the next weigh-in will show the trend.",
            metric: ordinal(percentile), series: series))
      } else if change >= 1.0 {
        out.append(
          Insight(
            id: "weight.curve", severity: .info, topic: .growth, title: "Moving up the growth curve",
            detail: "She is \(place), higher than a few weeks ago.", metric: ordinal(percentile), series: series))
      } else {
        out.append(
          Insight(
            id: "weight.curve", severity: .good, topic: .growth, title: "Holding her place on the curve",
            detail: "She is \(place), about where she was a few weeks ago.", metric: ordinal(percentile),
            series: series))
      }
    } else {
      out.append(
        Insight(
          id: "weight.curve", severity: .info, topic: .growth, title: "Where she is on the curve",
          detail: "She is \(place) for her age (WHO girls' reference). One weigh-in is a snapshot; the trend matters more.",
          metric: ordinal(percentile), series: series))
    }

    // How the weigh-ins line up with what was logged between them.
    let spans = intervals(weights: sorted, history: history)
    out += links(spans, unit: unit)
    if let last = spans.last, last.bottleShare >= 0.9, last.bottleMlPerDay > 0 {
      let kg = (sorted.last { $0.at <= last.to }?.grams ?? latest.grams) / 1000
      let perKg = last.bottleMlPerDay / kg
      out.append(
        Insight(
          id: "weight.intake", severity: .info, topic: .growth, title: "Bottle intake for her size",
          detail:
            "Between the last two weigh-ins she took about \(Volume.format(ml: perKg, unit: unit)) of bottle milk per kg a day. Formula-fed babies typically take around 120–180 ml per kg.",
          metric: Volume.format(ml: last.bottleMlPerDay, unit: unit) + " / day"))
    }

    // Time since the last weigh-in.
    let sinceLast = now.timeIntervalSince(latest.at) / 86_400
    if sinceLast >= 14 {
      out.append(
        Insight(
          id: "weight.stale", severity: .info, topic: .growth, title: "Last weigh-in was \(Int(sinceLast)) days ago",
          detail: "A weigh-in every week or two keeps the trend meaningful."))
    }
    return out
  }

  /// The one variable that moves most with gain across the intervals, if any does clearly.
  static func links(_ spans: [WeighInterval], unit: VolumeUnit) -> [Insight] {
    guard spans.count >= 4 else { return [] }
    struct Variable {
      var name: String
      var pick: (WeighInterval) -> Double
      var phrase: (Bool) -> String
      var show: (Double) -> String
    }
    let variables = [
      Variable(
        name: "feeds", pick: { $0.feedsPerDay },
        phrase: { $0 ? "fed more often" : "fed less often" },
        show: { String(format: "%.0f feeds a day", $0) }),
      Variable(
        name: "nursing", pick: { $0.nursingMinutesPerDay },
        phrase: { $0 ? "nursed longer" : "nursed less" },
        show: { String(format: "%.0f min of nursing a day", $0) }),
      Variable(
        name: "bottles", pick: { $0.bottleMlPerDay },
        phrase: { $0 ? "took more bottle milk" : "took less bottle milk" },
        show: { Volume.format(ml: $0, unit: unit) + " of bottles a day" }),
      Variable(
        name: "sleep", pick: { $0.sleepHoursPerDay },
        phrase: { $0 ? "slept more" : "slept less" },
        show: { String(format: "%.0f h of sleep a day", $0) }),
      Variable(
        name: "wet", pick: { $0.wetPerDay },
        phrase: { $0 ? "had more wet diapers" : "had fewer wet diapers" },
        show: { String(format: "%.0f wet diapers a day", $0) }),
    ]
    let gains = spans.map(\.gainPerDay)
    var best: (Variable, Double)?
    for variable in variables {
      guard let r = pearson(spans.map(variable.pick), gains), abs(r) >= 0.6 else { continue }
      if best == nil || abs(r) > abs(best!.1) { best = (variable, r) }
    }
    guard let (variable, r) = best else { return [] }
    let values = spans.map(variable.pick)
    let cut = values.sorted()[values.count / 2]
    let high = spans.filter { variable.pick($0) >= cut }
    let low = spans.filter { variable.pick($0) < cut }
    guard high.count >= 2, low.count >= 2 else { return [] }
    func mean(_ xs: [WeighInterval]) -> Double { xs.map(\.gainPerDay).reduce(0, +) / Double(xs.count) }
    let positive = r > 0
    let upGroup = positive ? high : low
    let otherGroup = positive ? low : high
    return [
      Insight(
        id: "weight.link.\(variable.name)", severity: .info, topic: .growth,
        title: "Gain follows \(variable.name)",
        detail:
          "She gained more in the stretches where she \(variable.phrase(positive)): about \(WeightFormat.perDay(mean(upGroup), unit: unit)) versus \(WeightFormat.perDay(mean(otherGroup), unit: unit)). The usual level was around \(variable.show(cut)). This is a pattern in her own numbers, not proof of cause.",
        metric: String(format: "r = %.2f", r))
    ]
  }

  public static func ordinal(_ percentile: Double) -> String {
    let n = min(99, max(1, Int(percentile.rounded())))
    let suffix: String
    switch (n % 100, n % 10) {
    case (11...13, _): suffix = "th"
    case (_, 1): suffix = "st"
    case (_, 2): suffix = "nd"
    case (_, 3): suffix = "rd"
    default: suffix = "th"
    }
    return "\(n)\(suffix)"
  }

  /// One line per weigh-in plus the intervals, for the on-device model and the question sheet.
  public static func facts(
    weights: [WeightRecord], history: History, unit: VolumeUnit, calendar: Calendar = .current
  ) -> [String] {
    let sorted = weights.sorted { $0.at < $1.at }
    var lines: [String] = []
    for weight in sorted.suffix(10) {
      let c = calendar.dateComponents([.month, .day], from: weight.at)
      lines.append("Weighed \(c.month ?? 0)/\(c.day ?? 0): \(WeightFormat.format(grams: weight.grams, unit: unit))")
    }
    for span in intervals(weights: sorted, history: history).suffix(6) {
      let c = calendar.dateComponents([.month, .day], from: span.to)
      lines.append(
        String(
          format: "Between weigh-ins ending %d/%d: %@, %.0f feeds a day, %.0f min nursing, %@ bottles, %.1f wet diapers, %.1f h sleep a day",
          c.month ?? 0, c.day ?? 0, WeightFormat.perDay(span.gainPerDay, unit: unit), span.feedsPerDay,
          span.nursingMinutesPerDay, Volume.format(ml: span.bottleMlPerDay, unit: unit), span.wetPerDay,
          span.sleepHoursPerDay))
    }
    return lines
  }
}
