import Foundation

extension SleepPlan {
  public enum Template: String, CaseIterable, Identifiable, Sendable {
    case momsOnCall
    case generic

    public var id: String { rawValue }

    public var title: String {
      switch self {
      case .momsOnCall: "Moms on Call style"
      case .generic: "Generic by age"
      }
    }

    public var summary: String {
      switch self {
      case .momsOnCall:
        "The stages and rules Moms on Call publishes: a 3-hour feed rhythm that starts at about 2 weeks, nights and naps that lengthen at 8, 12 and 16 weeks, two naps from 4 months, then one nap around 12 to 15 months. The stage ages and rules come from their published guidance; the clock times are my approximations, so check them against your book and edit freely."
      case .generic:
        "Typical wake windows and nap counts by age, without a fixed clock schedule."
      }
    }
  }

  public static func make(_ template: Template) -> SleepPlan {
    switch template {
    case .momsOnCall: return momsOnCallStyle()
    case .generic: return genericStarter()
    }
  }

  /// What a new plan starts as.
  public static var starter: SleepPlan { make(.momsOnCall) }

  private static func h(_ hour: Int, _ minute: Int = 0) -> Int { hour * 60 + minute }

  private static func genericStarter() -> SleepPlan {
    SleepPlan(
      enabled: false,
      stages: [
        Stage(fromWeek: 0, wakeMinute: h(7), wakeWindow: 60, feedEvery: 180, name: "Newborn"),
        Stage(
          fromWeek: 6, wakeMinute: h(7), bedMinute: h(20), napMinutes: [h(9), h(11, 30), h(14), h(16, 30)],
          napLength: 90, wakeWindow: 90, feedEvery: 180, name: "6 weeks"),
        Stage(
          fromWeek: 13, wakeMinute: h(7), bedMinute: h(19, 30), napMinutes: [h(9, 15), h(12), h(15, 15)],
          napLength: 90, wakeWindow: 120, feedEvery: 210, name: "3 months"),
        Stage(
          fromWeek: 26, wakeMinute: h(7), bedMinute: h(19), napMinutes: [h(9, 30), h(13, 30)], napLength: 90,
          wakeWindow: 150, feedEvery: 240, name: "6 months"),
      ])
  }

  /// Stage ages and rules follow what Moms on Call publishes on its blog; clock times are derived
  /// from those rules (feeds about every 3 hours early on, naps ending by 4 pm, overnight from about
  /// 7:30 pm to 7 am) and are approximate.
  private static func momsOnCallStyle() -> SleepPlan {
    SleepPlan(
      enabled: false,
      stages: [
        Stage(
          fromWeek: 0, wakeMinute: h(7), wakeWindow: 45, feedEvery: 180, name: "Weeks 0–2 · Newborn",
          note:
            "No set routine yet. Feed on demand, about every 2½ to 3 hours, and wake her to eat at night. Start the routine once she is about 2 weeks old, back to birth weight and growing well, as your pediatrician agrees."
        ),
        Stage(
          fromWeek: 2, wakeMinute: h(7), bedMinute: h(21), napMinutes: [h(8, 15), h(11, 15), h(14, 15)],
          napLength: 90, wakeWindow: 60, feedEvery: 180, name: "Weeks 2–4 · First routine",
          note:
            "Feed about every 3 hours by day (2¾ to 3 is fine), then a short awake stretch, then sleep. Past 2 weeks and above birth weight, night feeds can follow her lead. Expect 4 to 6 hour night stretches from 2 to 8 weeks. Naps no longer than 2 hours, and over by 4 pm.",
          napLengths: [90, 120, 90], napsEndBy: h(16), dreamFeedMinute: h(22)),
        Stage(
          fromWeek: 4, wakeMinute: h(7), bedMinute: h(19, 30), napMinutes: [h(8, 15), h(11, 15), h(14, 15)],
          napLength: 90, wakeWindow: 75, feedEvery: 180, name: "Weeks 4–8 · Settling in",
          note:
            "Same 3-hour rhythm with a consistent bedtime and a late feed around 10 pm. Naps no longer than 2 hours and over by 4 pm. Move up to the 8–16 week routine at about 6 to 8 weeks if she is healthy and gaining.",
          napLengths: [90, 120, 90], napsEndBy: h(16), dreamFeedMinute: h(22)),
        Stage(
          fromWeek: 7, wakeMinute: h(7), bedMinute: h(19, 30), napMinutes: [h(8, 30), h(11, 30), h(14, 30)],
          napLength: 90, wakeWindow: 90, feedEvery: 180, name: "Weeks 8–16 · Longer nights",
          note:
            "Aim for bedtime between 7:30 and 8 pm. Night stretches grow to 6 to 8 hours at 8 to 10 weeks and 8 to 10 hours at 10 to 12 weeks; the late feed fades as she sleeps longer. Naps settle into one okay nap, one better nap and a catnap; 30 to 45 minute naps are normal. Swaddle comes off at about 12 weeks or 12 lb, or sooner if she starts to roll. Use up to 15 minutes either side of a time on busy days.",
          napLengths: [75, 120, 45], napsEndBy: h(16), dreamFeedMinute: h(22)),
        Stage(
          fromWeek: 17, wakeMinute: h(7), bedMinute: h(19, 30), napMinutes: [h(9), h(13)], napLength: 90,
          wakeWindow: 150, feedEvery: 240, name: "4–6 months · Two naps",
          note:
            "Move here once she stays awake about 2 hours from the start of a feed to nap time. Two naps a day, with a short wind-down about 15 minutes before each. Solids can start between 4 and 6 months, one to three times a day. Naps are shorter until she is unswaddled and rolling at 5 to 6 months; the morning nap runs about 1 to 1½ hours and the afternoon 1½ to 2.",
          napLengths: [75, 105], napsEndBy: h(16)),
        Stage(
          fromWeek: 26, wakeMinute: h(7), bedMinute: h(19), napMinutes: [h(9), h(13)], napLength: 90,
          wakeWindow: 165, feedEvery: 240, name: "6–8 months · Two naps, longer days",
          note:
            "Morning nap about an hour and afternoon 1½ to 2 hours. The catnap drops around 7 months. Milk feeds with solids fitted around them.",
          napLengths: [60, 105], napsEndBy: h(16)),
        Stage(
          fromWeek: 35, wakeMinute: h(7), bedMinute: h(19), napMinutes: [h(9, 30), h(13, 30)], napLength: 90,
          wakeWindow: 180, feedEvery: 240, name: "8–10 months",
          note:
            "Two naps still. Less of this stage is published openly, so these times are an estimate; compare them with your book's schedule and edit.",
          napLengths: [60, 105], napsEndBy: h(16)),
        Stage(
          fromWeek: 47, wakeMinute: h(7), bedMinute: h(19), napMinutes: [h(10), h(14)], napLength: 90,
          wakeWindow: 195, feedEvery: 270, name: "11 months",
          note: "Still two naps, with the second getting shorter as one midday nap gets close. An estimate; edit to match your book.",
          napLengths: [60, 90], napsEndBy: h(16, 30)),
        Stage(
          fromWeek: 52, wakeMinute: h(7), bedMinute: h(19), napMinutes: [h(12, 30)], napLength: 150, wakeWindow: 270,
          feedEvery: 270, name: "12–15 months · One nap",
          note:
            "The book offers both a two-nap and a one-nap day for this range. This is the one-nap version, a single midday nap. Switch when she is ready, usually between 12 and 15 months. An estimate; edit to match your book.",
          napsEndBy: h(16, 30)),
      ])
  }
}
