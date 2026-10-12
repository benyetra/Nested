import Foundation
import Testing

@testable import NestedCore

@Suite struct DevelopmentTests {
  var cal: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
  }
  func date(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d))! }

  @Test func stagesCoverEveryWeekWithoutGaps() {
    var expected = 0
    for stage in DevelopmentGuide.stages {
      #expect(stage.weeks.lowerBound == expected)
      expected = stage.weeks.upperBound + 1
    }
    #expect(expected == 53)
  }

  @Test func ageFromBirth() {
    let days = DevelopmentGuide.ageDays(
      birth: date(2026, 9, 1), due: nil, now: date(2026, 10, 12), calendar: cal)
    #expect(days == 41)
    #expect(DevelopmentGuide.stage(ageDays: days).title == "Weeks 4–5")
  }

  @Test func earlyBabyUsesDueDate() {
    let birth = date(2026, 8, 1)
    let due = date(2026, 9, 12)  // 6 weeks early
    let now = date(2026, 10, 12)
    #expect(DevelopmentGuide.correctionDays(birth: birth, due: due, calendar: cal) == 42)
    let days = DevelopmentGuide.ageDays(birth: birth, due: due, now: now, calendar: cal)
    #expect(days == 30)
    #expect(DevelopmentGuide.stage(ageDays: days).weeks.contains(4))
  }

  @Test func slightlyEarlyOrLateIsNotCorrected() {
    let birth = date(2026, 9, 1)
    #expect(DevelopmentGuide.correctionDays(birth: birth, due: date(2026, 9, 10), calendar: cal) == 0)
    #expect(DevelopmentGuide.correctionDays(birth: birth, due: date(2026, 8, 25), calendar: cal) == 0)
  }

  @Test func beforeDueDateClampsToFirstStage() {
    #expect(DevelopmentGuide.stage(ageDays: -5).weeks.lowerBound == 0)
  }

  @Test func nextStageAndCountdown() {
    #expect(DevelopmentGuide.daysUntilNext(ageDays: 41) == 1)  // week 6 starts on day 42
    #expect(DevelopmentGuide.daysUntilNext(ageDays: 30) == 12)
  }

  @Test func endsAtOneYear() {
    #expect(DevelopmentGuide.daysUntilNext(ageDays: 360) == nil)
    #expect(!DevelopmentGuide.isBeyond(ageDays: 365))
    #expect(DevelopmentGuide.isBeyond(ageDays: 400))
  }
}
