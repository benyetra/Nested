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

  @Test("The Moms on Call style template follows the published stage ages and rules")
  func momsOnCallTemplate() throws {
    let p = SleepPlan.make(.momsOnCall)
    #expect(p.stages.map(\.fromWeek) == [0, 2, 4, 7, 17, 26, 35, 47, 52])
    // Newborn: no set naps; routine from about 2 weeks; two naps from 4 months; one nap by 12 months.
    #expect(p.stage(ageWeeks: 1)?.napMinutes.isEmpty == true)
    #expect(p.stage(ageWeeks: 3)?.feedEvery == 180)
    #expect(p.stage(ageWeeks: 10)?.napMinutes.count == 3)
    #expect(p.stage(ageWeeks: 20)?.napMinutes.count == 2)
    #expect(p.stage(ageWeeks: 60)?.napMinutes.count == 1)
    // Naps are over by 4 pm until the last stages, and the late feed fades after the 8–16 week stage.
    #expect(p.stage(ageWeeks: 10)?.napsEndBy == 16 * 60)
    #expect(p.stage(ageWeeks: 20)?.dreamFeedMinute == nil)
    // Every stage lays out a full day with no nap past the cutoff or after bedtime.
    for stage in p.stages {
      for minute in stage.napMinutes {
        #expect(minute < (stage.bedMinute ?? 24 * 60))
        if let cutoff = stage.napsEndBy { #expect(minute < cutoff) }
      }
      #expect(stage.napMinutes == stage.napMinutes.sorted())
      #expect(!stage.note.isEmpty)
    }
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
}
