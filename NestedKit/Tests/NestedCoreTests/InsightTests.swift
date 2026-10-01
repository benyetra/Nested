import Foundation
import Testing

@testable import NestedCore

@Suite("Insights")
struct InsightTests {
  let now = t(day: 20, 12)
  let birth = t(day: 1, 8)

  func nursing(_ date: Date, minutes: Double = 15) -> FeedRecord {
    FeedRecord(
      startedAt: date, endedAt: date.addingTimeInterval(minutes * 60),
      kind: .nursing(leftSeconds: minutes * 30, rightSeconds: minutes * 30, endedOnSide: .left))
  }

  /// Ten days of feeds `perDay` times a day, `wet` wet diapers a day.
  func history(perDay: Int, wet: Int, days: Int = 10) -> History {
    var feeds: [FeedRecord] = []
    var diapers: [DiaperRecord] = []
    for offset in 1...days {
      let day = 20 - offset
      for i in 0..<perDay {
        feeds.append(nursing(t(day: day, 0).addingTimeInterval(Double(i) * 86_400 / Double(perDay))))
      }
      for i in 0..<wet { diapers.append(DiaperRecord(occurredAt: t(day: day, 1 + i), kind: .wet)) }
    }
    return History(feeds: feeds, diapers: diapers)
  }

  func gen(_ h: History) -> [Insight] {
    InsightEngine.generate(history: h, birth: birth, now: now, calendar: utc)
  }

  @Test("Sparse data says so instead of judging")
  func sparse() {
    let out = gen(History())
    #expect(out.map(\.id) == ["data.sparse"])
  }

  @Test("Healthy week has wins and no attention items")
  func healthy() {
    let out = gen(history(perDay: 10, wet: 7))
    #expect(!out.contains { $0.severity == .attention })
    #expect(out.contains { $0.id.hasPrefix("feeding") && $0.severity == .good })
    #expect(out.contains { $0.id == "diapers.wet.ok" })
  }

  @Test("Too few feeds is an attention item with a doctor question")
  func fewFeeds() throws {
    let out = gen(history(perDay: 6, wet: 7))
    let item = try #require(out.first { $0.id == "feeding.low" })
    #expect(item.severity == .attention)
    #expect(item.doctorQuestion != nil)
    #expect(out.first?.severity == .attention)
  }

  @Test("Wet diapers under the day-of-life minimum raise attention")
  func fewWet() {
    let out = gen(history(perDay: 10, wet: 3))
    #expect(out.contains { $0.id == "diapers.wet.low" && $0.severity == .attention })
  }

  @Test("A sudden jump in feeds is called out as a possible growth spurt")
  func growthSpurt() {
    var h = history(perDay: 8, wet: 7)
    for day in 17...19 {
      for i in 0..<14 { h.feeds.append(nursing(t(day: day, 0).addingTimeInterval(Double(i) * 6000 + 60))) }
    }
    h = History(feeds: h.feeds, sleeps: h.sleeps, diapers: h.diapers, pumps: h.pumps)
    let out = gen(h)
    #expect(out.contains { $0.id == "feeding.up" })
  }

  @Test("Red stool in the last days is flagged")
  func stool() {
    var h = history(perDay: 10, wet: 7)
    h.diapers.append(DiaperRecord(occurredAt: t(day: 19, 9), kind: .dirty, stoolColor: .red))
    let out = gen(h)
    #expect(out.contains { $0.id == "diapers.stool.color" && $0.severity == .attention })
  }

  @Test("Extras: longest gap and night/day sleep split")
  func extras() {
    let h = History(
      feeds: [nursing(t(day: 19, 6)), nursing(t(day: 19, 9)), nursing(t(day: 19, 17))],
      sleeps: [SleepRecord(startedAt: t(day: 19, 21), endedAt: t(day: 19, 23)),
               SleepRecord(startedAt: t(day: 19, 13), endedAt: t(day: 19, 14))])
    let extra = DailyExtrasBuilder.build(history: h, days: [t(day: 19, 0)], now: now, calendar: utc)[0]
    #expect(extra.longestFeedGap == 8 * 3600)
    #expect(extra.averageFeedGap == 5.5 * 3600)
    #expect(extra.nightSleep == 2 * 3600)
    #expect(extra.daySleep == 3600)
  }
}

@Suite("Insight brief")
struct InsightBriefTests {
  @Test("Fallback leads with what needs attention, then wins")
  func fallback() {
    let items = [
      Insight(id: "a", severity: .good, topic: .feeding, title: "Feeding is steady", detail: ""),
      Insight(id: "b", severity: .attention, topic: .diapers, title: "Fewer wet diapers", detail: ""),
    ]
    let text = InsightBrief.fallback(insights: items, babyName: "Maddie")
    #expect(text.hasPrefix("Worth raising with your pediatrician: fewer wet diapers."))
    #expect(text.contains("Going well: feeding is steady."))
  }

  @Test("Facts tag each finding so the model knows which matter")
  func facts() {
    let items = [Insight(id: "b", severity: .attention, topic: .diapers, title: "Low", detail: "d")]
    let lines = InsightBrief.facts(digest: nil, insights: items, babyName: "M", unit: .ml)
    #expect(lines == ["[WORTH RAISING WITH THE PEDIATRICIAN] Low. d"])
  }
}

@Suite("Briefing content")
struct BriefingContentTests {
  @Test("Headline reflects severity; lists are capped")
  func content() {
    let items = [
      Insight(id: "a", severity: .attention, topic: .diapers, title: "Low wet", detail: ""),
      Insight(id: "b", severity: .good, topic: .feeding, title: "Steady", detail: ""),
    ]
    let c = InsightBrief.fallbackContent(insights: items, babyName: "M")
    #expect(c.headline == "A few things are worth a look.")
    #expect(c.attention == ["Low wet"])
    #expect(c.wins == ["Steady"])
    let calm = InsightBrief.fallbackContent(insights: [items[1]], babyName: "M")
    #expect(calm.headline == "M is doing well.")
  }
}
