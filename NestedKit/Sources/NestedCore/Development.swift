import Foundation

/// What's typically happening for a baby at a given age. Content follows general CDC / AAP
/// milestone guidance; it is orientation, never a checklist to pass. Babies vary a lot.
public enum DevelopmentArea: String, Hashable, Sendable, CaseIterable {
  case vision, hearing, movement, social, feeding, sleep, brain

  public var title: String {
    switch self {
    case .vision: "Vision"
    case .hearing: "Hearing"
    case .movement: "Movement"
    case .social: "Social"
    case .feeding: "Feeding"
    case .sleep: "Sleep"
    case .brain: "Learning"
    }
  }
}

public struct DevelopmentItem: Hashable, Sendable, Identifiable {
  public var area: DevelopmentArea
  public var text: String
  public var id: String { "\(area.rawValue).\(text)" }
}

public struct DevelopmentStage: Hashable, Sendable, Identifiable {
  /// First and last whole week of age this stage covers.
  public var weeks: ClosedRange<Int>
  /// "Weeks 2–3", "Month 3".
  public var title: String
  /// One friendly line for the card.
  public var headline: String
  public var items: [DevelopmentItem]
  /// A small, concrete thing to try with her.
  public var tryThis: String
  public var id: Int { weeks.lowerBound }
}

public enum DevelopmentGuide {
  /// Age in whole days used for development: counted from the due date when she was born at
  /// least two weeks early (corrected age), otherwise from the birth date.
  public static func ageDays(
    birth: Date, due: Date?, now: Date, calendar: Calendar = .current
  ) -> Int {
    var anchor = birth
    if let due, let early = calendar.dateComponents([.day], from: birth, to: due).day, early >= 14 {
      anchor = due
    }
    let start = calendar.startOfDay(for: anchor)
    let end = calendar.startOfDay(for: now)
    return calendar.dateComponents([.day], from: start, to: end).day ?? 0
  }

  /// Days of correction applied (0 when none), so the UI can say "adjusted for being early".
  public static func correctionDays(birth: Date, due: Date?, calendar: Calendar = .current) -> Int {
    guard let due, let early = calendar.dateComponents([.day], from: birth, to: due).day, early >= 14
    else { return 0 }
    return early
  }

  /// The stage containing this age; before the due date (negative age) maps to the first stage.
  public static func stage(ageDays: Int) -> DevelopmentStage {
    let week = max(0, ageDays) / 7
    return stages.first { $0.weeks.contains(week) } ?? stages.last!
  }

  public static func next(after stage: DevelopmentStage) -> DevelopmentStage? {
    stages.first { $0.weeks.lowerBound > stage.weeks.upperBound }
  }

  /// Days until the next stage starts.
  public static func daysUntilNext(ageDays: Int) -> Int? {
    guard let next = next(after: stage(ageDays: ageDays)) else { return nil }
    return max(0, next.weeks.lowerBound * 7 - ageDays)
  }

  /// True once past the last stage (a year), where the guide stops.
  public static func isBeyond(ageDays: Int) -> Bool {
    ageDays / 7 > (stages.last?.weeks.upperBound ?? 52)
  }

  // MARK: Content

  private static func i(_ area: DevelopmentArea, _ text: String) -> DevelopmentItem {
    DevelopmentItem(area: area, text: text)
  }

  public static let stages: [DevelopmentStage] = [
    DevelopmentStage(
      weeks: 0...1, title: "Week 1", headline: "Getting used to the world outside.",
      items: [
        i(.vision, "Sees best at 8–12 inches, about the distance to your face while feeding. Mostly black, white and high-contrast shapes."),
        i(.hearing, "Already knows your voice and will turn toward familiar sounds."),
        i(.movement, "Reflexes lead: rooting, sucking, grasping your finger, startling at sudden noise."),
        i(.feeding, "Feeds 8–12 times a day. Losing up to 10% of birth weight is normal, back to birth weight by about 2 weeks."),
        i(.sleep, "Sleeps 14–17 hours in short stretches, with no day or night sense yet."),
      ],
      tryThis: "Skin-to-skin time and talking softly while she looks at your face."),
    DevelopmentStage(
      weeks: 2...3, title: "Weeks 2–3", headline: "Starting to look at faces.",
      items: [
        i(.vision, "Your face is her favorite thing to look at. She can briefly lock eyes."),
        i(.hearing, "Quiets or turns to a familiar voice."),
        i(.movement, "Still curled up, but movements are getting a little smoother."),
        i(.brain, "Learning your smell, voice and touch. Crying is her main way to say what she needs."),
        i(.feeding, "Often a growth spurt around now: lots of extra hungry feeds for a few days."),
      ],
      tryThis: "Hold her about a foot away and slowly move your face side to side."),
    DevelopmentStage(
      weeks: 4...5, title: "Weeks 4–5", headline: "More awake, more alert.",
      items: [
        i(.vision, "Follows a moving object a short way and notices bold patterns."),
        i(.movement, "Briefly lifts her head during tummy time."),
        i(.social, "Longer alert periods. Some babies show their first real smiles around 5–6 weeks."),
        i(.sleep, "Day and night start to separate. Evenings are often the fussiest part of the day."),
        i(.brain, "Crying often peaks around 6 weeks, then eases."),
      ],
      tryThis: "A few short tummy-time sessions a day on your chest or a firm mat."),
    DevelopmentStage(
      weeks: 6...7, title: "Weeks 6–7", headline: "The first social smiles.",
      items: [
        i(.social, "Smiles back at you on purpose, and may make soft cooing sounds."),
        i(.vision, "Eyes work together better and follow you across the room."),
        i(.hearing, "Settles to calm voices and music."),
        i(.movement, "Holds her head up for a few seconds, with fists opening more."),
        i(.sleep, "Some babies start giving one longer stretch at night."),
      ],
      tryThis: "Smile and wait. Let her answer before you do it again."),
    DevelopmentStage(
      weeks: 8...11, title: "Month 2", headline: "Colors are coming in.",
      items: [
        i(.vision, "Color vision is developing; reds and brighter colors stand out first. She tracks objects further."),
        i(.social, "Smiles easily and coos. Starts to show she's enjoying you."),
        i(.movement, "Lifts her head and chest during tummy time and brings hands to her mouth."),
        i(.hearing, "Turns her head toward sounds and voices."),
        i(.brain, "Learning cause and effect: kick or wave and something happens."),
      ],
      tryThis: "Hold a bright toy 8–12 inches away and move it slowly. Watch her eyes follow."),
    DevelopmentStage(
      weeks: 12...15, title: "Month 3", headline: "Eyes and hands start working together.",
      items: [
        i(.vision, "Tracks smoothly in all directions and recognizes familiar faces from across a room."),
        i(.movement, "Pushes up on forearms, with steadier head control. Swipes at dangling toys."),
        i(.social, "Laughs and squeals, and 'talks' back when you talk to her."),
        i(.brain, "Discovers her hands and studies them for long stretches."),
        i(.sleep, "Longer night stretches for many babies; naps still unpredictable."),
      ],
      tryThis: "Dangle a soft toy just within reach during tummy time."),
    DevelopmentStage(
      weeks: 16...19, title: "Month 4", headline: "Rolling, reaching, and laughing.",
      items: [
        i(.movement, "Reaches and grabs on purpose, brings everything to her mouth. May roll tummy to back."),
        i(.vision, "Depth perception improves. Full color vision is close to an adult's."),
        i(.social, "Real laughter, and she may protest when play stops."),
        i(.sleep, "A common sleep regression around 4 months as sleep patterns mature."),
        i(.feeding, "Easily distracted while feeding; looks around at every sound."),
      ],
      tryThis: "Floor play on a blanket with a few safe, different-textured toys."),
    DevelopmentStage(
      weeks: 20...25, title: "Months 5–6", headline: "Sitting up and sampling the world.",
      items: [
        i(.movement, "Rolls both ways and sits with support, and some babies sit alone by 6 months."),
        i(.social, "Knows familiar faces and may get shy around strangers. Responds to her own name."),
        i(.brain, "Babbles with consonant sounds ('ba', 'da') and passes toys between hands."),
        i(.feeding, "Ready for solids around 6 months when she sits with support, holds her head up and shows interest in food."),
        i(.sleep, "Many babies can sleep longer at night; naps settle to about three a day."),
      ],
      tryThis: "Narrate your day. She's absorbing the rhythm of language."),
    DevelopmentStage(
      weeks: 26...34, title: "Months 6–8", headline: "On the move, and very curious.",
      items: [
        i(.movement, "Sits without support, may scoot or army-crawl, and pulls to stand with help."),
        i(.brain, "Starts to understand object permanence. Peek-a-boo becomes hilarious."),
        i(.social, "Stranger awareness grows, and she prefers her familiar people."),
        i(.hearing, "Responds to 'no' and her name; babbles in chains like 'bababa'."),
        i(.feeding, "Exploring purées and soft finger foods; milk is still her main nutrition."),
      ],
      tryThis: "Play peek-a-boo, and let her pull the cloth off herself."),
    DevelopmentStage(
      weeks: 35...43, title: "Months 8–10", headline: "Crawling, pointing, and 'mama'.",
      items: [
        i(.movement, "Crawls, pulls up to standing and cruises along furniture. Picks up small items with a pincer grasp."),
        i(.social, "Waves bye-bye and may be clingy when you leave. Separation anxiety peaks."),
        i(.brain, "Looks for hidden objects and copies gestures and sounds."),
        i(.hearing, "Says 'mama' or 'dada', often without meaning it yet."),
        i(.sleep, "Two naps and a long night, though standing in the crib can disrupt sleep for a while."),
      ],
      tryThis: "Hide a toy under a cloth in front of her and let her find it."),
    DevelopmentStage(
      weeks: 44...52, title: "Months 10–12", headline: "Almost walking, almost talking.",
      items: [
        i(.movement, "Cruises, stands alone for a moment, and some babies take first steps around her birthday."),
        i(.hearing, "Understands simple words and requests ('come here', 'where's the ball?'). First real words may appear."),
        i(.social, "Points to what she wants, plays pat-a-cake, and shows clear favorites."),
        i(.brain, "Experiments with how things work: drops, bangs, stacks and empties."),
        i(.feeding, "Joins family meals with more finger foods and starts to hold a cup."),
      ],
      tryThis: "Name things as she points, and read a short board book together."),
  ]

  public static let disclaimer =
    "Every baby moves at her own pace. These are typical ranges, not deadlines. If you're ever worried about her development, ask your pediatrician."
}
