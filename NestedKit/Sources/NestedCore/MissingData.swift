import Foundation

/// A likely gap in the log, guessed from how the last week usually goes, with a pre-filled
/// entry that can be added in one tap.
public struct MissingSuggestion: Hashable, Sendable, Identifiable {
  public enum Guess: Hashable, Sendable {
    case nursing(leftSeconds: TimeInterval, rightSeconds: TimeInterval)
    case bottle(ml: Double, contents: BottleContents)
    case diaper(DiaperKind)
  }

  public var id: String
  public var at: Date
  public var guess: Guess
  /// "4 h 20 min between feeds, longer than usual"
  public var reason: String

  public var isFeed: Bool {
    if case .diaper = guess { return false }
    return true
  }
}

/// Finds holes in the last day: feeds and diaper changes that probably happened but weren't
/// logged. Pure and conservative: it only speaks up when a gap is clearly out of pattern and the
/// baby wasn't simply asleep through it.
public enum MissingDataDetector {
  public static func suggestions(
    history: History, now: Date, night: DayWindow = .defaultNight,
    dismissed: Set<String> = [], calendar: Calendar = .current
  ) -> [MissingSuggestion] {
    var out = feeds(history: history, now: now, night: night, calendar: calendar)
    out += diapers(history: history, now: now, calendar: calendar)
    return out.filter { !dismissed.contains($0.id) }.sorted { $0.at > $1.at }.prefix(3).map { $0 }
  }

  // MARK: Feeds

  static func feeds(history: History, now: Date, night: DayWindow, calendar: Calendar) -> [MissingSuggestion] {
    let weekAgo = now.addingTimeInterval(-7 * 86_400)
    let dayAgo = now.addingTimeInterval(-86_400)
    // Treat a cluster of near-together feeds as one feed, like the predictor does.
    let starts = FeedPredictor.mergeClusters(
      history.feeds.map(\.startedAt).filter { $0 > weekAgo && $0 <= now }.sorted())
    guard starts.count >= 9 else { return [] }
    let pairs = Array(zip(starts, starts.dropFirst()))
    let allGaps = pairs.map { $1.timeIntervalSince($0) }
    let dayGaps = pairs.filter { !night.contains($0.0, calendar: calendar) }.map { $1.timeIntervalSince($0) }
    let nightGaps = pairs.filter { night.contains($0.0, calendar: calendar) }.map { $1.timeIntervalSince($0) }

    var out: [MissingSuggestion] = []
    for (a, b) in pairs where a > dayAgo {
      let gap = b.timeIntervalSince(a)
      let pool = night.contains(a, calendar: calendar) ? nightGaps : dayGaps
      let typical = Stats.median(pool.count >= 5 ? pool : allGaps) ?? 0
      guard typical > 0, gap > max(typical * 1.8, typical + 5400), gap > 3 * 3600 else { continue }
      // A long sleep across most of the gap explains it.
      if asleep(history.sleeps, from: a, to: b) > 0.7 * gap { continue }
      let missing = min(2, max(1, Int((gap / typical).rounded()) - 1))
      for k in 1...missing {
        let at = a.addingTimeInterval(gap * Double(k) / Double(missing + 1))
        out.append(
          MissingSuggestion(
            id: "feed.\(Int(a.timeIntervalSince1970)).\(k)", at: at,
            guess: typicalFeed(history.feeds, before: b),
            reason: "\(Durations.format(gap)) between feeds, usually about \(Durations.format(typical))."))
      }
    }
    return out
  }

  /// What a feed usually looks like lately: the same kind as most of the last ten.
  static func typicalFeed(_ feeds: [FeedRecord], before: Date) -> MissingSuggestion.Guess {
    let recent = feeds.filter { $0.startedAt < before }.suffix(10)
    var lefts: [Double] = [], rights: [Double] = [], bottles: [Double] = []
    var contents: [BottleContents] = []
    for feed in recent {
      switch feed.kind {
      case .nursing(let l, let r, _):
        if l > 0 { lefts.append(l) }
        if r > 0 { rights.append(r) }
      case .bottle(let ml, let c):
        bottles.append(ml)
        contents.append(c)
      }
    }
    if bottles.count > recent.count - bottles.count, let ml = Stats.median(bottles) {
      return .bottle(ml: ml.rounded(), contents: contents.last ?? .formula)
    }
    let left = Stats.median(lefts) ?? 600
    let right = Stats.median(rights) ?? 0
    // Round to the minute so it looks like something a person would log.
    func minute(_ s: Double) -> Double { s > 0 ? max(60, (s / 60).rounded() * 60) : 0 }
    // One side if that's what she usually does.
    return .nursing(leftSeconds: minute(left), rightSeconds: minute(right))
  }

  static func asleep(_ sleeps: [SleepRecord], from: Date, to: Date) -> TimeInterval {
    sleeps.reduce(0) { total, sleep in
      let end = sleep.endedAt ?? to
      let overlap = min(end, to).timeIntervalSince(max(sleep.startedAt, from))
      return total + max(0, overlap)
    }
  }

  // MARK: Diapers

  static func diapers(history: History, now: Date, calendar: Calendar) -> [MissingSuggestion] {
    let weekAgo = now.addingTimeInterval(-7 * 86_400)
    let dayAgo = now.addingTimeInterval(-86_400)
    let times = history.diapers.map(\.occurredAt).filter { $0 > weekAgo && $0 <= now }
    guard times.count >= 12 else { return [] }
    let pairs = Array(zip(times, times.dropFirst()))
    guard let typical = Stats.median(pairs.map { $1.timeIntervalSince($0) }), typical > 0 else { return [] }
    var out: [MissingSuggestion] = []
    for (a, b) in pairs where a > dayAgo {
      let gap = b.timeIntervalSince(a)
      guard gap > max(typical * 2.5, 5 * 3600) else { continue }
      if asleep(history.sleeps, from: a, to: b) > 0.7 * gap { continue }
      // A feed in between means a diaper probably went with it; put the guess just after it.
      let feedBetween = history.feeds.first { $0.startedAt > a && $0.startedAt < b }
      let at = feedBetween.map { ($0.endedAt ?? $0.startedAt).addingTimeInterval(300) }
        ?? a.addingTimeInterval(gap / 2)
      guard at < b else { continue }
      out.append(
        MissingSuggestion(
          id: "diaper.\(Int(a.timeIntervalSince1970))", at: at, guess: .diaper(.wet),
          reason: "\(Durations.format(gap)) with no diaper logged."))
    }
    return out
  }
}
