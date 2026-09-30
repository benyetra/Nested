import Foundation
import NestedCore
import Testing

@testable import NestedData

/// Synthetic rows in the shape of a real Huckleberry export (values invented). The same rows as
/// text CSV and as an Excel workbook, since the real file has turned up as either.
private let huckleberryCSV = """
Type,Start,End,Duration,Start Condition,Start Location,End Condition,Notes,Logged By
Pump,2026-09-28 06:35,,,0ml,,20ml,,
Feed,2026-09-28 05:51,2026-09-28 06:19,00:28,,Breast,00:28L,,
Feed,2026-09-28 02:49,2026-09-28 03:03,00:14,00:14R,Breast,,,
Feed,2026-09-27 22:20,,,Breast Milk,Bottle,20ml,,
Diaper,2026-09-27 22:19,,black,,,Poo:medium,,
Diaper,2026-09-27 22:01,,,,,Pee:medium,,
Feed,2026-09-27 17:20,2026-09-27 18:09,00:49,00:24R,Breast,00:25L,,
Feed,2026-09-27 17:20,2026-09-27 18:09,00:49,00:24R,Breast,00:25L,,
Pump,2026-09-27 12:01,,,0.25oz,,,,
Diaper,2026-09-26 23:13,,,,,"Both, poo:large",,
Sleep,2026-09-27 06:00,2026-09-27 07:50,01:50,,,,,
Sleep,2026-09-27 09:00,,,,,,,
Feed,2026-09-27 10:00,,,Formula,Bottle,,,
Medication,2026-09-27 08:00,,,Vitamin D,Drops,1ml,,
"""

private let huckleberryXLSX = Data(base64Encoded: "UEsDBBQAAAAIABYLPl3HHBc8CgAAAAgAAAATAAAAW0NvbnRlbnRfVHlwZXNdLnhtbLMJqSxILda3AwBQSwMEFAAAAAgAFgs+Xc6emBMNAAAACwAAAA8AAAB4bC93b3JrYm9vay54bWyzKc8vyk7Kz8/WtwMAUEsDBBQAAAAIABYLPl1a99YqUQIAAGwKAAAYAAAAeGwvd29ya3NoZWV0cy9zaGVldDEueG1sjVbBkpswDP0VhnsB22DjHWBnNwm09/YDmIRuMhsgA0y2/ftS0jWSAm50Ap4tvSfLEsnzr/rsXKuuP7VN6jIvcJ2q2beHU/OWuj++519i1+mHsjmU57apUvd31bvPWfLRdu/9saoGZ9zf9Kl7HIbLk+/3+2NVl73XXqpmRH62XV0O42v35veXrioP06b67PMgkH5dnho3S6Zv23Ios6RrP5xu5DF+3f99eGGuM6RuP75fsyDxr1ni7/9hrxBjGNtAjGNsCzGBsR3EQozlEIswVkBMYuwrxBTGvkEsNpg/5sEkg5tkcLBYk2TwG2XJtfC4CkUQ3Yzogy4YSWiBQLbMRhg2Aq4mOX4VkE4oFOGxQbgUTIc3I0eFYpCzyhFIdhYIjJa1hEZLaNMSAq6MKSHZZEQRWsVVEIvJiCAUiBTKDoGkUvJwWS0SFBlBkU1QZKhyT5tKuasV5CMmdBBIirGIHigkabhKeFfpJZeQK9fxYvK3yAUBCwTyZTbKsFE2NgqyWSuFArkQywFjEzC2HVUMAipujNQeWhVJTk5yC0NwclN2CCQ789h2x9BOuaxTG53aplM/pFP/R6e26dQ2ndqmUz+gkwXzzAosfXpa96khGqfgrfPRu4d8cLUSE8xJZivbaeEtKPO0NHVLhWIvK/OIzQOJwYnB76RyIJVmfINQMc6AeDLiZItCiGCF0jyVmLBSEjCoWpkLbB4MzDoZWAjchUx+Gi095EWQdpHjGHqF09zbGWyv4o4T7O5iNjpssBc6WzF6VycIpVn0wQ+db/4Usz9QSwMEFAAAAAgAFgs+XS38wlJDAQAAvQMAABQAAAB4bC9zaGFyZWRTdHJpbmdzLnhtbHWTTU/DMAyG/0qUMyxttaExtZ00xk4bmvi6h9a0EflS4iLGryeDC0qyY543dvzaTr3+UpJ8gvPC6IaWs4IS0J3phR4a+vK8u15S4pHrnkujoaEn8HTd1t4jCZHaN3REtCvGfDeC4n5mLOigvBunOIajG5i3DnjvRwBUklVFccMUF5qGNKKtsX0+WagZtjU7n//YE3KHMbzXfYy2k+MYas/Gkzuje3FZ3psuGxzeuRz6YBB8DPdmGKAnm1MsHCdlY1YoGaMqw3YAid2iWFXLGG5Ce33SrN+r+wwt51n4mE9LDkJ+JJJBlMnMtoJbcDF9k7xLEhyNWSnoxaQSBeCCEqqc3+ZcpqWf6SL1PqsW5jvjZbwiNhQkuRvSRZQA6QTL1aJI5hVWfpI8xodgJr9mrwK5Eppsk0Y6Y5MVK/9vCAsfsP0BUEsBAhQDFAAAAAgAFgs+XcccFzwKAAAACAAAABMAAAAAAAAAAAAAAIABAAAAAFtDb250ZW50X1R5cGVzXS54bWxQSwECFAMUAAAACAAWCz5dzp6YEw0AAAALAAAADwAAAAAAAAAAAAAAgAE7AAAAeGwvd29ya2Jvb2sueG1sUEsBAhQDFAAAAAgAFgs+XVr31ipRAgAAbAoAABgAAAAAAAAAAAAAAIABdQAAAHhsL3dvcmtzaGVldHMvc2hlZXQxLnhtbFBLAQIUAxQAAAAIABYLPl0t/MJSQwEAAL0DAAAUAAAAAAAAAAAAAACAAfwCAAB4bC9zaGFyZWRTdHJpbmdzLnhtbFBLBQYAAAAABAAEAAYBAABxBAAAAAA=")!

private let newYork = TimeZone(identifier: "America/New_York")!

@Suite("Huckleberry import")
struct HuckleberryImportTests {
  private func check(_ result: HuckleberryImport.Result) throws {
    #expect(result.count(of: .nursing) == 3)
    #expect(result.count(of: .bottle) == 1)
    #expect(result.count(of: .diaper) == 3)
    #expect(result.count(of: .sleep) == 1)
    #expect(result.count(of: .pump) == 2)
    #expect(result.count(of: .note) == 1)
    #expect(result.duplicates == 1)
    #expect(result.skipped.map(\.reason).sorted() == ["bottle without an amount", "sleep without an end time"])

    // Two-sided feed: 24 min right then 25 min left, ends on the left.
    let both = try #require(result.rows.first { $0.kind == .nursing && $0.rightSeconds == 24 * 60 })
    #expect(both.leftSeconds == 25 * 60 && both.endedOnSide == .left)
    #expect(both.endedAt?.timeIntervalSince(both.startedAt) == 2940.0)

    // A one-sided feed can sit in either condition column.
    let leftOnly = try #require(result.rows.first { $0.kind == .nursing && $0.leftSeconds == 28 * 60 })
    #expect(leftOnly.rightSeconds == 0 && leftOnly.endedOnSide == .left)

    let bottle = try #require(result.rows.first { $0.kind == .bottle })
    #expect(bottle.amountMl == 20 && bottle.contents == .breastMilk)

    // Stool colour rides in another column; "Both" carries the poo size.
    let poo = try #require(result.rows.first { $0.diaper == .dirty })
    #expect(poo.stoolColor == .black && poo.size == .medium)
    let mixed = try #require(result.rows.first { $0.diaper == .mixed })
    #expect(mixed.size == .large)
    #expect(result.rows.first { $0.diaper == .wet }?.size == .medium)

    // A lone pump amount is kept as the left side; ounces convert.
    let ounces = try #require(result.rows.first { $0.kind == .pump && $0.rightMl == nil })
    #expect(abs((ounces.leftMl ?? 0) - 0.25 * Volume.mlPerOunce) < 0.001)
    let pair = try #require(result.rows.first { $0.kind == .pump && $0.rightMl != nil })
    #expect(pair.leftMl == 0 && pair.rightMl == 20)

    let note = try #require(result.rows.first { $0.kind == .note })
    #expect(note.note == "Medication: Drops, Vitamin D, 1ml" && note.tag == .medicine)
  }

  @Test("Text CSV")
  func csv() throws {
    try check(try HuckleberryImport.parse(data: Data(huckleberryCSV.utf8), timeZone: newYork))
  }

  @Test("Excel workbook with serial dates and sparse cells")
  func excel() throws {
    try check(try HuckleberryImport.parse(data: huckleberryXLSX, timeZone: newYork))
  }

  @Test("Both formats produce identical rows, in the requested time zone")
  func sameRows() throws {
    let a = try HuckleberryImport.parse(data: Data(huckleberryCSV.utf8), timeZone: newYork)
    let b = try HuckleberryImport.parse(data: huckleberryXLSX, timeZone: newYork)
    #expect(a.rows == b.rows)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = newYork
    let first = try #require(a.earliest)
    #expect(calendar.dateComponents([.month, .day, .hour, .minute], from: first) == DateComponents(month: 9, day: 26, hour: 23, minute: 13))
  }

  @Test("Other date styles")
  func dates() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = newYork
    let expected = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 18, minute: 5))
    for text in ["2026-09-28 18:05", "9/28/2026 18:05", "9/28/2026 6:05 PM", "2026-09-28T18:05:00"] {
      #expect(HuckleberryImport.date(text, calendar: calendar) == expected, "\(text)")
    }
    #expect(HuckleberryImport.date("nonsense", calendar: calendar) == nil)
  }

  @Test("Rejects files that aren't Huckleberry exports")
  func rejects() {
    #expect(throws: (any Error).self) { try HuckleberryImport.parse(data: Data("a,b\n1,2".utf8)) }
    #expect(throws: (any Error).self) { try HuckleberryImport.parse(data: Data([0x50, 0x4B, 0x03, 0x04, 1, 2, 3])) }
  }

  @Test("Importing adds entries once; a second import adds nothing")
  func importIsIdempotent() throws {
    let clock = TestClock(t(10))
    let store = try makeStore(clock: clock)
    try store.createBaby(name: "Maddie", birthDate: nil, feedingMode: .mixed, unit: .ml)
    let result = try HuckleberryImport.parse(data: huckleberryXLSX, timeZone: newYork)

    #expect(try store.importEntries(result.rows) == 11)
    #expect(try store.importEntries(result.rows) == 0)
    #expect(try store.entries(from: .distantPast, to: .distantFuture).count == 11)

    // Exported Nested CSV reads back what was imported.
    let csv = try store.exportCSV()
    #expect(try EntryRow.parse(csv: csv).count == 11)
  }
}


@Suite("MCP output compatibility")
struct McpCompatibilityTests {
  /// What `mcp/` (Node) writes for the sample Huckleberry export in America/New_York
  /// (mcp/test/fixtures/expected-nested.csv). The Nested importer must read it, and get the same
  /// entries as the in-app Huckleberry importer does from the same export.
  private static let mcpOutput = """
type,started_at,ended_at,amount_ml,offered_ml,contents,formula_brand,left_seconds,right_seconds,ended_on_side,left_ml,right_ml,destination,diaper,stool_color,consistency,size,rash,location,tag,note,logged_by,time_zone
diaper,2026-09-27T03:13:00Z,,,,,,,,,,,,mixed,,,large,,,,,,America/New_York
sleep,2026-09-27T10:00:00Z,2026-09-27T11:50:00Z,,,,,,,,,,,,,,,,,,,,America/New_York
note,2026-09-27T12:00:00Z,,,,,,,,,,,,,,,,,,medicine,"Medication: Drops, Vitamin D, 1ml",,America/New_York
pump,2026-09-27T16:01:00Z,,,,,,,,,7.4,,,,,,,,,,,,America/New_York
nursing,2026-09-27T21:20:00Z,2026-09-27T22:09:00Z,,,,,1500,1440,left,,,,,,,,,,,,,America/New_York
diaper,2026-09-28T02:01:00Z,,,,,,,,,,,,wet,,,medium,,,,,,America/New_York
diaper,2026-09-28T02:19:00Z,,,,,,,,,,,,dirty,black,,medium,,,,,,America/New_York
bottle,2026-09-28T02:20:00Z,,20,,breastMilk,,,,,,,,,,,,,,,,,America/New_York
nursing,2026-09-28T06:49:00Z,2026-09-28T07:03:00Z,,,,,0,840,right,,,,,,,,,,,,,America/New_York
nursing,2026-09-28T09:51:00Z,2026-09-28T10:19:00Z,,,,,1680,0,left,,,,,,,,,,,,,America/New_York
pump,2026-09-28T10:35:00Z,,,,,,,,,0,20,,,,,,,,,,,America/New_York
"""

  @Test("Nested's CSV importer reads the MCP file and matches the in-app Huckleberry import")
  func matchesInAppImport() throws {
    let fromMcp = try EntryRow.parse(csv: Self.mcpOutput)
    let inApp = try HuckleberryImport.parse(data: Data(huckleberryCSV.utf8), timeZone: newYork).rows
    #expect(fromMcp.count == 11)
    #expect(fromMcp.count == inApp.count)
    for (a, b) in zip(fromMcp, inApp) {
      #expect(a.kind == b.kind)
      #expect(a.startedAt == b.startedAt)
      #expect(a.endedAt == b.endedAt)
      #expect(a.amountMl == b.amountMl)
      #expect(a.leftSeconds == b.leftSeconds && a.rightSeconds == b.rightSeconds)
      #expect(a.endedOnSide == b.endedOnSide)
      #expect(a.diaper == b.diaper && a.stoolColor == b.stoolColor && a.size == b.size)
      #expect(a.note == b.note && a.tag == b.tag)
      if let x = a.leftMl, let y = b.leftMl { #expect(abs(x - y) < 0.06) } else { #expect(a.leftMl == b.leftMl) }
      #expect(a.rightMl == b.rightMl)
    }
  }
}
