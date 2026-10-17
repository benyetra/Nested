import Foundation
import Testing

@testable import NestedCore

@Suite("Growth")
struct GrowthTests {
  let birth = t(day: 1, 8)
  var now: Date { t(day: 20, 12) }

  func w(_ day: Int, _ grams: Double) -> WeightRecord { WeightRecord(at: t(day: day, 9), grams: grams) }

  func ids(_ insights: [Insight]) -> [String: InsightSeverity] {
    Dictionary(insights.map { ($0.id, $0.severity) }, uniquingKeysWith: { a, _ in a })
  }

  @Test("Formats weights in kg or pounds and ounces")
  func formatting() {
    #expect(WeightFormat.format(grams: 4210, unit: .ml) == "4.21 kg")
    #expect(WeightFormat.format(grams: WeightFormat.grams(pounds: 9, ounces: 4.5), unit: .oz) == "9 lb 4.5 oz")
    #expect(WeightFormat.change(grams: 28.35, unit: .oz) == "+1.0 oz")
    #expect(WeightFormat.change(grams: -50, unit: .ml) == "−50 g")
    let (lb, oz) = WeightFormat.pounds(WeightFormat.grams(pounds: 7, ounces: 15.98))
    #expect(lb == 8 && oz == 0)
  }

  @Test("Reference curve: median at birth and one month; band is wider later")
  func reference() {
    #expect(abs(WeightReference.median(ageDays: 0) - 3200) < 1)
    #expect(abs(WeightReference.median(ageDays: 30.4375) - 4200) < 1)
    let early = WeightReference.band(ageDays: 0)
    let later = WeightReference.band(ageDays: 180)
    #expect(later.upperBound - later.lowerBound > early.upperBound - early.lowerBound)
    #expect(abs(WeightReference.percentile(grams: 4200, ageDays: 30.4375) - 50) < 0.5)
    #expect(WeightReference.percentile(grams: 5500, ageDays: 30.4375) > 95)
    #expect(WeightReference.percentile(grams: 3200, ageDays: 30.4375) < 5)
  }

  @Test("Back to birth weight inside two weeks is a win")
  func regained() {
    let found = GrowthEngine.insights(
      weights: [w(1, 3300), w(4, 3100), w(10, 3350)], history: History(), birth: birth, now: t(day: 12, 12), unit: .ml)
    #expect(ids(found)["weight.regain"] == .good)
  }

  @Test("Still under birth weight at two weeks is worth raising, with a doctor question")
  func notRegained() {
    let found = GrowthEngine.insights(
      weights: [w(1, 3300), w(10, 3150), w(15, 3200)], history: History(), birth: birth, now: t(day: 16, 12), unit: .ml)
    let item = found.first { $0.id == "weight.regain" }
    #expect(item?.severity == .attention)
    #expect(item?.doctorQuestion != nil)
  }

  @Test("Steady gain at a typical rate is good; slow gain is flagged")
  func gainRate() {
    // A month old, typical gain is about 30 g/day.
    let steady = GrowthEngine.insights(
      weights: [w(1, 3200), w(8, 3450), w(15, 3680), w(20, 3830)], history: History(), birth: t(day: 1, 8).addingTimeInterval(-20 * 86_400), now: now, unit: .ml)
    #expect(ids(steady)["weight.gain"] == .good)
    let slow = GrowthEngine.insights(
      weights: [w(8, 4000), w(14, 4050), w(20, 4100)], history: History(), birth: t(day: 1, 8).addingTimeInterval(-20 * 86_400), now: now, unit: .ml)
    #expect(ids(slow)["weight.gain"] == .attention)
  }

  @Test("A single weigh-in places her on the curve and says so")
  func singleWeight() {
    let found = GrowthEngine.insights(
      weights: [w(15, 3500)], history: History(), birth: birth, now: now, unit: .ml)
    #expect(found.contains { $0.id == "weight.curve" && $0.severity == .info })
    #expect(!found.contains { $0.id == "weight.gain" })
  }

  @Test("Falling across the curve is flagged")
  func fallingCurve() {
    let birth2 = t(day: 1, 8).addingTimeInterval(-30 * 86_400)
    // About the 50th percentile at one month, then well under it three weeks later.
    let found = GrowthEngine.insights(
      weights: [w(2, 4200), w(20, 3750)], history: History(), birth: birth2, now: now, unit: .ml)
    #expect(ids(found)["weight.curve"] == .attention)
  }

  @Test("Intervals line weigh-ins up with feeds and diapers, and need a full log")
  func intervals() {
    var feeds: [FeedRecord] = []
    for hours in stride(from: 0, to: 24 * 6, by: 3) {
      let start = t(day: 10, 0).addingTimeInterval(Double(hours) * 3600)
      feeds.append(FeedRecord(startedAt: start, endedAt: start.addingTimeInterval(900), kind: .bottle(amountMl: 90, contents: .formula)))
    }
    let history = History(feeds: feeds)
    let spans = GrowthEngine.intervals(weights: [WeightRecord(at: t(day: 10, 0), grams: 4000), WeightRecord(at: t(day: 16, 0), grams: 4180)], history: history)
    #expect(spans.count == 1)
    #expect(abs((spans.first?.feedsPerDay ?? 0) - 8) < 0.01)
    #expect(abs((spans.first?.gainPerDay ?? 0) - 30) < 0.01)
    #expect(abs((spans.first?.bottleMlPerDay ?? 0) - 720) < 0.01)
    // A sparsely logged stretch is ignored.
    #expect(GrowthEngine.intervals(weights: [WeightRecord(at: t(day: 2, 0), grams: 3000), WeightRecord(at: t(day: 6, 0), grams: 3100)], history: history).isEmpty)
  }

  @Test("A clear link between feeds and gain is reported once, in plain words")
  func link() {
    var feeds: [FeedRecord] = []
    var weights: [WeightRecord] = [WeightRecord(at: t(day: 1, 0), grams: 3000)]
    var grams = 3000.0
    // Five 3-day stretches: more feeds a day, more gain a day.
    let perDay = [6, 8, 10, 7, 9]
    var day = 1
    for count in perDay {
      for d in 0..<3 {
        for i in 0..<count {
          let start = t(day: day + d, 0).addingTimeInterval(Double(i) * 86_400 / Double(count))
          feeds.append(FeedRecord(startedAt: start, endedAt: nil, kind: .bottle(amountMl: 60, contents: .formula)))
        }
      }
      grams += Double(count) * 3.0 * 3
      day += 3
      weights.append(WeightRecord(at: t(day: day, 0), grams: grams))
    }
    let spans = GrowthEngine.intervals(weights: weights, history: History(feeds: feeds))
    #expect(spans.count == 5)
    let found = GrowthEngine.links(spans, unit: .ml)
    #expect(found.count == 1)
    #expect(found.first?.title.contains("feeds") == true || found.first?.title.contains("bottles") == true)
  }

  @Test("Facts list the recent weigh-ins")
  func facts() {
    let lines = GrowthEngine.facts(weights: [w(5, 3300), w(12, 3600)], history: History(), unit: .ml)
    #expect(lines.count == 2)
    #expect(lines[0].contains("3.30 kg"))
  }
}
