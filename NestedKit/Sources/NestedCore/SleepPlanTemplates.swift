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
        "Typical days for 2–4 weeks, 4–8 weeks, 8–16 weeks and 4–6 months, taken from the pages of the book you provided: exact feed, nap and bed times, with the book's tips for rough days. Later ages carry the 4–6 month day forward as an estimate."
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

  /// Typical-day tables for 2–4 weeks, 4–8 weeks, 8–16 weeks and 4–6 months, transcribed from the
  /// parent's own copy. Later stages are estimates carried forward from the 4–6 month day.
  private static func momsOnCallStyle() -> SleepPlan {
    SleepPlan(
      enabled: false,
      stages: [
        Stage(
          fromWeek: 0, wakeMinute: h(6, 30), wakeWindow: 45, feedEvery: 180, name: "Weeks 0–2 · Newborn",
          note:
            "Not covered by the schedule pages. No set routine yet: feed on demand, about every 2½ to 3 hours, and wake her to eat at night. Start the 2–4 week day once she is about 2 weeks old, back to birth weight and growing well."
        ),
        Stage(
          fromWeek: 2, wakeMinute: h(6, 30), bedMinute: h(21, 30), napMinutes: [h(9, 45), h(12, 45), h(15, 45), h(18, 45)],
          napLength: 120, wakeWindow: 60, name: "Weeks 2–4",
          note:
            "Feeds take 30 minutes at most, start to finish, and a bottle is 3–4 oz. The first feed is any time from 6 to 7 (at 6 if she is awake, up to 7 if she is asleep); put her straight back down and she may sleep until 9. Then feeds at 9, 12, 3 and a 6 pm supper feed, with 10–30 minutes of play after each feed before a nap of up to 2 hours. After supper no more feeding until 9 pm. The 6:45–7 sleep runs an hour to 90 minutes. Bath at 8:30, bedtime feeding at 9, then swaddle, crib, white noise and a dark room at 9:30; let her fuss 2–5 minutes. For a night feed between 12 and 2, wait 3–5 minutes before soothing and do that at least three times, counting only true crying, then feed in her room and keep it boring. Try to make it to 6 am. Naps: crib, swaddled, white noise, for at least two a day, with a little daylight in the room. The next stage is the same day with supper and bedtime feeding half an hour earlier.",
          napLengths: [120, 120, 120, 90], feedMinutes: [h(9), h(12), h(15), h(18), h(21)],
          crazyDay:
            "Feed at 9 am. Keep every nap under 2½ hours and have supper at 6 pm, even if two feeds have to be squeezed together. If she eats poorly at supper, the 9 pm feed will be a big one, and that keeps three hours between supper and bedtime feeds."
        ),
        Stage(
          fromWeek: 4, wakeMinute: h(6, 30), bedMinute: h(21), napMinutes: [h(10), h(13), h(16), h(18, 30)],
          napLength: 120, wakeWindow: 60, name: "Weeks 4–8",
          note:
            "Feeds take 30 minutes at most and a bottle is 4–6 oz. First feed any time 6 to 7; after it she may nap in the crib or rest quietly in the bouncy seat until the 9 am feed. Feeds at 9, 12, 3 and a 5:30 pm supper feed, each followed by 10–30 minutes of play, then naps of up to 2 hours (the 4 pm one nearer 1½). After supper, no feeding until 8:30. The evening sleep runs 45 minutes to 1½ hours. Bath at 8, bedtime feeding at 8:30, swaddle very well and crib at 9 with white noise and a dark room; let her fuss 5–8 minutes. Night feed between 2 and 3: wait 5–8 minutes before soothing, at least three times; if she falls back asleep you don't need to wake her. Try to make it to 6:30 or 7. Healthy babies who are gaining weight can move to the 8–16 week day as early as 6 weeks.",
          napLengths: [120, 120, 90, 90], feedMinutes: [h(9), h(12), h(15), h(17, 30), h(20, 30)],
          crazyDay:
            "Feed at 9 am. Keep every nap under 2 hours and have supper at 5:30 pm, even if two feeds have to be squeezed together. A poor supper makes the 8:30 bedtime feeding a good one, and keeps three hours between the two."
        ),
        Stage(
          fromWeek: 8, wakeMinute: h(7), bedMinute: h(19, 30), napMinutes: [h(8, 30), h(11, 30), h(14, 30), h(17, 30)],
          napLength: 90, wakeWindow: 90, name: "Weeks 8–16",
          note:
            "Feeds take 20 minutes at most and a bottle is 5–7 oz. Feed at 7, then awake and playful until the 8:30 nap; feeds at 10, 1 and a 4 pm supper feed, each followed by playtime and a nap of about 1½ hours. After supper, no feeding until 7. The 5:30 catnap lasts 45 minutes to an hour and starts to get difficult. Bath at 6:30, bedtime feeding at 7, in the crib at 7:30 with white noise and a dark room; swaddle at night until 3 months or until she is breaking out of it regularly. Under 3 months, when she wakes at night wait through three sessions of 5–10 minutes (30 at most) before feeding. She is now likely to get past 4 am, even 5. Babies who are healthy and gaining weight can start this day at 6 weeks; begin each nap about 15 minutes earlier than listed.",
          napLengths: [90, 90, 90, 60], feedMinutes: [h(10), h(13), h(16), h(19)],
          crazyDay:
            "Feed at 7 am. Keep every nap under 2 hours and have supper at 4 pm, even if two feeds have to be squeezed together. A poor supper makes the 7 pm bedtime feeding a good one, and keeps three hours between the two."
        ),
        Stage(
          fromWeek: 17, wakeMinute: h(7), bedMinute: h(19, 30), napMinutes: [h(9), h(13)], napLength: 90, wakeWindow: 150,
          name: "4–6 months · Solids",
          note:
            "For once baby food has started. A bottle is 6–8 oz and a sippy cup 2–4 oz; the amounts are only a guide. Wake and milk at 7; 8 am half a jar of fruit with 1–2 tablespoons of cereal (sippy cup may start); naptime at 9 for 1 to 1½ hours; milk at 11; at 12 veggies and fruit (2–4 oz each) with cereal; nap starting any time from 12:30 to 1:30, the same time each day, ideally 1½–2 hours; milk at 3; at 4 veggies and fruit with a sippy cup of milk; she may take a catnap at 5, then stay awake until bath, with 10 minutes of tummy time at 6. Bath at 6:30, bedtime feeding at 7, in the crib for the night at 7:30. She is now likely to sleep through the night. Take the swaddle off at night around 3 months, and by 4 months no swaddling at all. Solids start when she sits up with minimal support, has good head control and wants what you are eating; if you haven't started, stay on the 8–16 week day or use this one without the solids.",
          napLengths: [90, 120], feedMinutes: [h(11), h(15), h(19)], mealMinutes: [h(8), h(12), h(16)],
          crazyDay:
            "Feed at 7 am and keep every nap under 2 hours. You don't need all three baby-food meals; skip one and she will eat well at the next milk feeding. You just want her a little hungry for the 7 pm bedtime feeding."
        ),
        Stage(
          fromWeek: 26, wakeMinute: h(7), bedMinute: h(19), napMinutes: [h(9), h(13)], napLength: 90,
          wakeWindow: 165, feedEvery: 240, name: "6–8 months · Two naps",
          note:
            "Not in the pages provided. Carried forward from the 4–6 month day as an estimate: morning nap about an hour, afternoon 1½ to 2 hours.",
          napLengths: [60, 105]),
        Stage(
          fromWeek: 35, wakeMinute: h(7), bedMinute: h(19), napMinutes: [h(9, 30), h(13, 30)], napLength: 90,
          wakeWindow: 180, feedEvery: 240, name: "8–10 months",
          note: "Not in the pages provided. An estimate; edit to match the book's schedule when you get to it.",
          napLengths: [60, 105]),
        Stage(
          fromWeek: 47, wakeMinute: h(7), bedMinute: h(19), napMinutes: [h(10), h(14)], napLength: 90,
          wakeWindow: 195, feedEvery: 270, name: "11 months",
          note: "Not in the pages provided. An estimate; edit to match the book's schedule when you get to it.",
          napLengths: [60, 90]),
        Stage(
          fromWeek: 52, wakeMinute: h(7), bedMinute: h(19), napMinutes: [h(12, 30)], napLength: 150, wakeWindow: 270,
          feedEvery: 270, name: "12–15 months · One nap",
          note: "Not in the pages provided. An estimate: a single midday nap; edit to match the book's schedule when you get to it."),
      ])
  }
}
