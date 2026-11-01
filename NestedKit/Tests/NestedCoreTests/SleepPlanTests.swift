import Foundation
import Testing

@testable import NestedCore

@Suite("Sleep plan")
struct SleepPlanTests {
  var cal: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
  }
  let day = t(day: 20, 0)
  func at(_ hour: Int, _ minute: Int = 0, day d: Int = 20) -> Date { t(day: d, hour, minute) }

  var plan: SleepPlan {
    SleepPlan(
      enabled: true,
      stages: [
        SleepPlan.Stage(
          fromWeek: 0, wakeMinute: 7 * 60, bedMinute: 19 * 60, napMinutes: [9 * 60, 12 * 60, 15 * 60], napLength: 90,
          wakeWindow: 90, feedEvery: 180)
      ])
  }

  @Test("Stage lookup uses the latest stage that has begun")
  func stageLookup() {
    let p = SleepPlan.make(.generic)
    #expect(p.stage(ageWeeks: 0)?.fromWeek == 0)
    #expect(p.stage(ageWeeks: 8)?.fromWeek == 6)
    #expect(p.stage(ageWeeks: 40)?.fromWeek == 26)
  }

  @Test("A plan that is off produces no slots")
  func disabled() {
    var p = plan
    p.enabled = false
    #expect(SleepPlanner.today(plan: p, ageDays: 40, now: at(10), history: History(), calendar: cal).isEmpty)
  }

  @Test("Slots are marked done, due, upcoming or missed from what was logged")
  func statuses() {
    let history = History(
      feeds: [FeedRecord(startedAt: at(10), kind: .bottle(amountMl: 90, contents: .formula))],
      sleeps: [SleepRecord(startedAt: at(2), endedAt: at(7, 10)), SleepRecord(startedAt: at(9, 10), endedAt: at(10, 30))])
    let slots = SleepPlanner.today(plan: plan, ageDays: 40, now: at(12, 5), history: history, calendar: cal)
    func slot(_ kind: PlanSlot.Kind, _ hour: Int) -> PlanSlot? { slots.first { $0.kind == kind && cal.component(.hour, from: $0.at) == hour } }
    #expect(slot(.wake, 7)?.status == .done)
    #expect(slot(.nap, 9)?.status == .done)
    #expect(slot(.feed, 10)?.status == .done)
    #expect(slot(.nap, 12)?.status == .due)
    #expect(slot(.nap, 15)?.status == .upcoming)
    #expect(slot(.bed, 19)?.status == .upcoming)
    #expect(SleepPlanner.next(slots)?.kind == .nap)
    // Later in the day, nothing logged for the noon nap.
    let late = SleepPlanner.today(plan: plan, ageDays: 40, now: at(14), history: history, calendar: cal)
    #expect(late.first { $0.kind == .nap && cal.component(.hour, from: $0.at) == 12 }?.status == .missed)
  }

  @Test("A running nap ends at the plan's length, only in the daytime")
  func napEnd() {
    #expect(SleepPlanner.napEnd(plan: plan, ageDays: 40, sleepStarted: at(9, 10), calendar: cal) == at(10, 40))
    #expect(SleepPlanner.napEnd(plan: plan, ageDays: 40, sleepStarted: at(2), calendar: cal) == nil)
    #expect(SleepPlanner.napEnd(plan: plan, ageDays: 40, sleepStarted: at(19, 30), calendar: cal) == nil)
  }

  @Test("A week of on-time naps is a win; long naps are noticed")
  func adherence() {
    var sleeps: [SleepRecord] = []
    for d in 13...19 {
      for hour in [9, 12, 15] {
        // 120-minute naps against a 90-minute plan.
        sleeps.append(SleepRecord(startedAt: at(hour, 5, day: d), endedAt: at(hour + 2, 5, day: d)))
      }
      sleeps.append(SleepRecord(startedAt: at(19, 0, day: d), endedAt: at(23, 0, day: d)))
    }
    let found = SleepPlanner.insights(
      plan: plan, birth: t(day: 1, 8).addingTimeInterval(-40 * 86_400), history: History(sleeps: sleeps), now: at(12), calendar: cal)
    let ids = Dictionary(found.map { ($0.id, $0.severity) }, uniquingKeysWith: { a, _ in a })
    #expect(ids["plan.naps"] == .good)
    #expect(ids["plan.napLong"] == .notice)
  }

  @Test("Plans survive a JSON round trip")
  func codable() throws {
    let original = plan
    let data = try JSONEncoder().encode(original)
    #expect(try JSONDecoder().decode(SleepPlan.self, from: data) == original)
  }

  @Test("The Moms on Call template matches the book's typical-day tables")
  func momsOnCallTemplate() throws {
    let p = SleepPlan.make(.momsOnCall)
    func h(_ hour: Int, _ minute: Int = 0) -> Int { hour * 60 + minute }
    #expect(p.stages.map(\.fromWeek) == [0, 2, 4, 8, 17, 26, 35, 47, 52])

    // 2–4 weeks: feeds 9, 12, 3, supper 6, bedtime 9; naps 9:45, 12:45, 3:45 and a 6:45 sleep; crib 9:30.
    let two = try #require(p.stage(ageWeeks: 3))
    #expect(two.feedMinutes == [h(9), h(12), h(15), h(18), h(21)])
    #expect(two.napMinutes == [h(9, 45), h(12, 45), h(15, 45), h(18, 45)])
    #expect(two.bedMinute == h(21, 30))
    #expect(two.napTarget(at: 0) == 120)

    // 4–8 weeks: supper and bedtime feeding half an hour earlier.
    let four = try #require(p.stage(ageWeeks: 5))
    #expect(four.feedMinutes == [h(9), h(12), h(15), h(17, 30), h(20, 30)])
    #expect(four.napMinutes == [h(10), h(13), h(16), h(18, 30)])
    #expect(four.bedMinute == h(21))
    #expect(four.napTarget(at: 2) == 90)

    // 8–16 weeks: 7 am wake feed; naps 8:30, 11:30, 2:30 and a 5:30 catnap; supper 4, bedtime feeding 7, crib 7:30.
    let eight = try #require(p.stage(ageWeeks: 10))
    #expect(eight.wakeMinute == h(7))
    #expect(eight.feedMinutes == [h(10), h(13), h(16), h(19)])
    #expect(eight.napMinutes == [h(8, 30), h(11, 30), h(14, 30), h(17, 30)])
    #expect(eight.napTarget(at: 3) == 60)
    #expect(eight.bedMinute == h(19, 30))

    // 4–6 months: two naps, three baby-food meals, milk at 11, 3 and 7.
    let solids = try #require(p.stage(ageWeeks: 20))
    #expect(solids.napMinutes == [h(9), h(13)])
    #expect(solids.mealMinutes == [h(8), h(12), h(16)])
    #expect(solids.feedMinutes == [h(11), h(15), h(19)])
    #expect(solids.napTarget(at: 1) == 120)

    // Every stage has its notes, naps sit in order before bedtime, and the tips are on the book's stages.
    for stage in p.stages {
      for minute in stage.napMinutes { #expect(minute < (stage.bedMinute ?? 24 * 60)) }
      #expect(stage.napMinutes == stage.napMinutes.sorted())
      #expect(!stage.note.isEmpty)
    }
    for week in [3, 5, 10, 20] { #expect(p.stage(ageWeeks: week)?.crazyDay.isEmpty == false) }
  }

  @Test("Exact feed times: a late bottle still counts, and baby food is shown without being tracked")
  func exactFeedsAndMeals() throws {
    let p = SleepPlan.make(.momsOnCall)
    var enabled = p
    enabled.enabled = true
    // 5 months old: milk at 11, 3 and 7 pm; baby food at 8, 12 and 4.
    let history = History(
      feeds: [FeedRecord(startedAt: at(11, 50), kind: .bottle(amountMl: 200, contents: .formula))])
    let slots = SleepPlanner.today(plan: enabled, ageDays: 150, now: at(12, 10), history: history, calendar: cal)
    func slot(_ kind: PlanSlot.Kind, _ hour: Int) -> PlanSlot? { slots.first { $0.kind == kind && cal.component(.hour, from: $0.at) == hour } }
    #expect(slot(.feed, 11)?.status == .done)
    #expect(slot(.feed, 15)?.status == .upcoming)
    // Meals: the 8 am one is over, the noon one is current, the 4 pm one is ahead.
    #expect(slot(.meal, 8) == nil)
    #expect(slot(.meal, 12)?.status == .due)
    #expect(slot(.meal, 16)?.status == .upcoming)
  }

  @Test("Per-nap lengths and the 4 pm cutoff shape when to wake her")
  func perNapLengths() {
    var p = plan
    p.stages[0].napLengths = [60, 120, 45]
    p.stages[0].napsEndBy = 15 * 60 + 30
    // Morning nap: 60 minutes.
    #expect(SleepPlanner.napEnd(plan: p, ageDays: 40, sleepStarted: at(9, 0), calendar: cal) == at(10, 0))
    // Midday nap: 120 minutes, started at noon.
    #expect(SleepPlanner.napEnd(plan: p, ageDays: 40, sleepStarted: at(12, 0), calendar: cal) == at(14, 0))
    // Afternoon nap: 45 minutes.
    #expect(SleepPlanner.napEnd(plan: p, ageDays: 40, sleepStarted: at(15, 0), calendar: cal) == at(15, 30))
    // A late start is capped by the cutoff.
    p.stages[0].napLengths = [60, 120, 120]
    #expect(SleepPlanner.napEnd(plan: p, ageDays: 40, sleepStarted: at(15, 0), calendar: cal) == at(15, 30))
  }

  @Test("A dream feed shows up as a feed slot after bedtime")
  func dreamFeed() {
    var p = plan
    p.stages[0].dreamFeedMinute = 22 * 60
    let slots = SleepPlanner.today(plan: p, ageDays: 40, now: at(12), history: History(), calendar: cal)
    #expect(slots.contains { $0.kind == .feed && cal.component(.hour, from: $0.at) == 22 })
  }

  @Test("Plans saved before the newer fields still load")
  func oldPlans() throws {
    let json = """
      {"enabled":true,"stages":[{"id":"6F1E7B2A-0000-4000-8000-000000000001","fromWeek":0,"wakeMinute":420,"napMinutes":[540],"napLength":90,"wakeWindow":90,"feedEvery":180}]}
      """
    let plan = try JSONDecoder().decode(SleepPlan.self, from: Data(json.utf8))
    #expect(plan.stages.first?.name == "")
    #expect(plan.stages.first?.napLengths.isEmpty == true)
    #expect(plan.stages.first?.dreamFeedMinute == nil)
    #expect(plan.stages.first?.napTarget(at: 0) == 90)
  }

  @Test("A bottle counts as a feed, even an hour off the planned time")
  func bottlesCount() {
    // Planned feeds every 3 hours from 7:00: 10:00, 13:00, 16:00, 19:00.
    let history = History(
      feeds: [
        FeedRecord(startedAt: at(10, 55), kind: .bottle(amountMl: 120, contents: .formula)),
        FeedRecord(startedAt: at(13, 10), kind: .bottle(amountMl: 90, contents: .breastMilk)),
      ])
    let slots = SleepPlanner.today(plan: plan, ageDays: 40, now: at(14), history: history, calendar: cal)
    func feed(_ hour: Int) -> PlanSlot? { slots.first { $0.kind == .feed && cal.component(.hour, from: $0.at) == hour } }
    #expect(feed(10)?.status == .done)
    #expect(feed(10)?.actual == at(10, 55))
    #expect(feed(13)?.status == .done)
  }

  @Test("One feed satisfies one slot, so a real gap still shows")
  func oneFeedOneSlot() {
    // A single feed at 11:30 sits between the 10:00 and 13:00 slots; it fills only the nearer one.
    let history = History(feeds: [FeedRecord(startedAt: at(11, 20), kind: .bottle(amountMl: 100, contents: .formula))])
    let slots = SleepPlanner.today(plan: plan, ageDays: 40, now: at(15), history: history, calendar: cal)
    let done = slots.filter { $0.kind == .feed && $0.status == .done }
    #expect(done.count == 1)
    #expect(slots.first { $0.kind == .feed && cal.component(.hour, from: $0.at) == 13 }?.status == .missed)
  }
}
