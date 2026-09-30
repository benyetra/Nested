import Foundation

/// Reads a Huckleberry data export (their "Export tracking data" file, as CSV or an Excel
/// workbook) into Nest's own row format.
///
/// The export has one row per activity with the columns
/// `Type, Start, End, Duration, Start Condition, Start Location, End Condition, Notes, Logged By`.
/// What the two "condition" columns mean depends on the type:
///
/// - **Feed / Breast**: Start Condition is the first side ("00:24R" = 24 minutes on the right),
///   End Condition is the second side. A one-sided feed can be in either.
/// - **Feed / Bottle**: Start Condition is the contents ("Breast Milk", "Formula"), End
///   Condition the amount ("60ml", "2oz").
/// - **Diaper**: End Condition is "Pee:small", "Poo:large", "Both, poo:large"; a stool colour
///   can appear in any of the other columns.
/// - **Pump**: Start Condition is the left amount, End Condition the right ("0ml", "20ml").
///   A single amount is kept as the left side, so the total is right.
/// - **Sleep**: just Start and End.
///
/// Anything else (growth, medicine, solids, baths…) is kept as a note, so nothing is lost.
public enum HuckleberryImport {
  public struct Skipped: Hashable, Sendable {
    public var line: Int
    public var reason: String
  }

  public struct Result: Sendable {
    public var rows: [EntryRow] = []
    public var skipped: [Skipped] = []
    /// Identical rows collapsed into one (Huckleberry exports often repeat a row when both
    /// parents logged it).
    public var duplicates = 0

    public func count(of kind: EventKind) -> Int { rows.filter { $0.kind == kind }.count }

    public var earliest: Date? { rows.map(\.startedAt).min() }
    public var latest: Date? { rows.map(\.startedAt).max() }
  }

  public enum ImportError: Error, CustomStringConvertible {
    case notHuckleberry
    case unreadable

    public var description: String {
      switch self {
      case .notHuckleberry:
        "This doesn't look like a Huckleberry export. It needs Type and Start columns."
      case .unreadable: "The file couldn't be read as CSV or Excel."
      }
    }
  }

  // MARK: Entry points

  /// Parses file contents, sniffing Excel (a ZIP) versus text.
  public static func parse(data: Data, timeZone: TimeZone = .current) throws -> Result {
    if ZipArchive.looksLikeZip(data) {
      let table: [[String]]
      do { table = try XLSX.firstSheet(data) } catch { throw ImportError.unreadable }
      return try parse(table: table, timeZone: timeZone)
    }
    var text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    if text?.hasPrefix("\u{FEFF}") == true { text?.removeFirst() }
    guard let text else { throw ImportError.unreadable }
    return try parse(table: CSV.parse(text), timeZone: timeZone)
  }

  public static func parse(table: [[String]], timeZone: TimeZone = .current) throws -> Result {
    guard let header = table.first else { throw ImportError.notHuckleberry }
    let index = Dictionary(
      header.enumerated().map { ($1.trimmingCharacters(in: .whitespaces).lowercased(), $0) },
      uniquingKeysWith: { first, _ in first })
    guard index["type"] != nil, index["start"] != nil else { throw ImportError.notHuckleberry }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone

    var result = Result()
    var seen = Set<EntryRow>()

    for (offset, fields) in table.dropFirst().enumerated() {
      let line = offset + 2
      func cell(_ name: String) -> String {
        guard let i = index[name], i < fields.count else { return "" }
        return fields[i].trimmingCharacters(in: .whitespacesAndNewlines)
      }
      let type = cell("type")
      if type.isEmpty { continue }
      guard let start = date(cell("start"), calendar: calendar) else {
        result.skipped.append(Skipped(line: line, reason: "unreadable start time '\(cell("start"))'"))
        continue
      }
      let record = Record(
        type: type, start: start, end: date(cell("end"), calendar: calendar),
        duration: cell("duration"), startCondition: cell("start condition"),
        startLocation: cell("start location"), endCondition: cell("end condition"),
        notes: cell("notes"), loggedBy: cell("logged by"), timeZone: timeZone)

      switch convert(record) {
      case .row(var row):
        row.timeZone = timeZone.identifier
        if seen.insert(row).inserted {
          result.rows.append(row)
        } else {
          result.duplicates += 1
        }
      case .skip(let reason):
        result.skipped.append(Skipped(line: line, reason: reason))
      }
  }
    result.rows.sort { $0.startedAt < $1.startedAt }
    return result
  }

  // MARK: Row conversion

  private struct Record {
    var type: String
    var start: Date
    var end: Date?
    var duration: String
    var startCondition: String
    var startLocation: String
    var endCondition: String
    var notes: String
    var loggedBy: String
    var timeZone: TimeZone

    var conditions: [String] { [startCondition, startLocation, endCondition] }
    /// Every free-text cell, for keyword scans (stool colour has turned up in "Duration").
    var everything: [String] { [duration, startCondition, startLocation, endCondition, notes] }
  }

  private enum Outcome {
    case row(EntryRow)
    case skip(String)
  }

  private static func base(_ kind: EventKind, _ record: Record) -> EntryRow {
    var row = EntryRow(kind: kind, startedAt: record.start, note: record.notes, loggedBy: record.loggedBy)
    row.endedAt = record.end
    return row
  }

  private static func convert(_ record: Record) -> Outcome {
    switch record.type.lowercased() {
    case "sleep": return sleep(record)
    case "feed": return feed(record)
    case "diaper": return diaper(record)
    case "pump": return pump(record)
    default: return other(record)
    }
  }

  private static func sleep(_ record: Record) -> Outcome {
    guard let end = record.end else { return .skip("sleep without an end time") }
    guard end > record.start else { return .skip("sleep ends before it starts") }
    return .row(base(.sleep, record))
  }

  private static func feed(_ record: Record) -> Outcome {
    let location = record.startLocation.lowercased()
    if location.contains("bottle") {
      guard let ml = amount(record.endCondition) ?? amount(record.startCondition) else {
        return .skip("bottle without an amount")
      }
      var row = base(.bottle, record)
      row.amountMl = ml
      let contents = record.startCondition.lowercased()
      let breast = contents.contains("breast")
      let formula = contents.contains("formula")
      row.contents = breast && formula ? .mixed : (breast ? .breastMilk : .formula)
      row.endedAt = nil
      return .row(row)
    }
    if location.contains("breast") || location.isEmpty {
      var totals: [Side: TimeInterval] = [:]
      var last: Side?
      for text in [record.startCondition, record.endCondition] {
        if let (side, seconds) = sideSegment(text) {
          totals[side, default: 0] += seconds
          last = side
        }
      }
      guard let last else { return .skip("breast feed without side times") }
      var row = base(.nursing, record)
      row.leftSeconds = totals[.left] ?? 0
      row.rightSeconds = totals[.right] ?? 0
      row.endedOnSide = last
      let total = (row.leftSeconds ?? 0) + (row.rightSeconds ?? 0)
      if row.endedAt == nil { row.endedAt = record.start.addingTimeInterval(total) }
      return .row(row)
    }
    return other(record)
  }

  private static func diaper(_ record: Record) -> Outcome {
    let kindText = [record.endCondition, record.startCondition]
      .first { !$0.isEmpty }?.lowercased() ?? ""
    let pee = kindText.contains("pee") || kindText.contains("wet")
    let poo = kindText.contains("poo") || kindText.contains("dirty") || kindText.contains("stool")
    let both = kindText.contains("both") || kindText.contains("mixed")

    let kind: DiaperKind
    if both || (pee && poo) {
      kind = .mixed
    } else if poo {
      kind = .dirty
    } else if pee {
      kind = .wet
    } else if kindText.contains("dry") || kindText.contains("clean") {
      kind = .dry
    } else {
      return .skip("diaper without a type")
    }

    var row = base(.diaper, record)
    row.endedAt = nil
    row.diaper = kind
    row.size = size(in: kindText)
    if kind == .dirty || kind == .mixed {
      let words = record.everything.joined(separator: " ").lowercased()
      row.stoolColor = stoolColor(in: words)
      row.consistency = consistency(in: words)
    }
    row.rash = record.everything.contains { $0.lowercased().contains("rash") } ? true : nil
    return .row(row)
  }

  private static func pump(_ record: Record) -> Outcome {
    let first = amount(record.startCondition)
    let second = amount(record.endCondition)
    guard first != nil || second != nil else { return .skip("pump without an amount") }
    var row = base(.pump, record)
    if let second {
      row.leftMl = first ?? 0
      row.rightMl = second
    } else {
      row.leftMl = first
    }
    return .row(row)
  }

  /// Solids, growth, medicine and everything else become a plain note.
  private static func other(_ record: Record) -> Outcome {
    var parts = [record.startLocation, record.startCondition, record.endCondition]
      .filter { !$0.isEmpty }
    if let seconds = durationSeconds(record.duration), seconds >= 60 {
      parts.append("\(Int((seconds / 60).rounded())) min")
    } else if !record.duration.isEmpty, Double(record.duration) == nil {
      parts.append(record.duration)
    }
    if !record.notes.isEmpty { parts.append(record.notes) }
    let label = record.type
    var row = EntryRow(
      kind: .note, startedAt: record.start,
      note: parts.isEmpty ? label : "\(label): \(parts.joined(separator: ", "))",
      loggedBy: record.loggedBy)
    let lower = label.lowercased()
    if lower.contains("medic") { row.tag = .medicine }
    if lower.contains("temp") { row.tag = .temperature }
    return .row(row)
  }

  // MARK: Field parsing

  /// "00:24R" -> (.right, 24 minutes). The digits are hours and minutes.
  static func sideSegment(_ text: String) -> (Side, TimeInterval)? {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    guard let last = trimmed.last, let side = Side(letter: last) else { return nil }
    let clock = trimmed.dropLast().trimmingCharacters(in: .whitespaces)
    let parts = clock.split(separator: ":").compactMap { Int($0) }
    guard parts.count == 2 else { return nil }
    return (side, TimeInterval(parts[0] * 3600 + parts[1] * 60))
  }

  /// "60ml", "2 oz", "0.25oz" -> millilitres.
  static func amount(_ text: String) -> Double? {
    let lower = text.lowercased().replacingOccurrences(of: " ", with: "")
    for (suffix, factor) in [("ml", 1.0), ("oz", Volume.mlPerOunce)] where lower.hasSuffix(suffix) {
      if let value = Double(lower.dropLast(suffix.count)) { return value * factor }
    }
    return nil
  }

  private static func durationSeconds(_ text: String) -> TimeInterval? {
    // Spreadsheets store durations as a fraction of a day.
    if let days = Double(text), days > 0, days < 2 { return days * 86_400 }
    let parts = text.split(separator: ":").compactMap { Int($0) }
    if parts.count == 2 { return TimeInterval(parts[0] * 3600 + parts[1] * 60) }
    return nil
  }

  private static func size(in text: String) -> DiaperSize? {
    // For "Both, poo:large" the size after "poo:" is the one worth keeping.
    for key in ["poo:", "pee:", ""] {
      let scope = key.isEmpty ? text : (text.components(separatedBy: key).dropFirst().first ?? "")
      if scope.hasPrefix("small") { return .small }
      if scope.hasPrefix("medium") { return .medium }
      if scope.hasPrefix("large") { return .large }
    }
    if text.contains("small") { return .small }
    if text.contains("medium") { return .medium }
    if text.contains("large") { return .large }
    return nil
  }

  private static func stoolColor(in text: String) -> StoolColor? {
    let table: [(String, StoolColor)] = [
      ("dark green", .darkGreen), ("mustard", .mustardYellow), ("yellow", .yellow),
      ("green", .green), ("black", .black), ("brown", .brown), ("orange", .orange),
      ("red", .red), ("pale", .pale), ("white", .pale), ("clay", .pale), ("gray", .pale),
      ("grey", .pale),
    ]
    return table.first { text.contains($0.0) }?.1
  }

  private static func consistency(in text: String) -> StoolConsistency? {
    let table: [(String, StoolConsistency)] = [
      ("runny", .runny), ("watery", .runny), ("seedy", .seedy), ("pasty", .pasty),
      ("formed", .formed), ("hard", .hard), ("mucous", .mucousy),
    ]
    return table.first { text.contains($0.0) }?.1
  }

  // MARK: Dates

  private static let textFormats = [
    "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm",
    "M/d/yyyy H:mm:ss", "M/d/yyyy H:mm", "M/d/yyyy h:mm:ss a", "M/d/yyyy h:mm a",
    "M/d/yy H:mm", "M/d/yy h:mm a", "yyyy/MM/dd HH:mm", "d MMM yyyy HH:mm", "MMM d, yyyy h:mm a",
  ]

  public static func date(_ raw: String, calendar: Calendar) -> Date? {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }

    // Excel serial number (days since 1899-12-30), as in a workbook or a spreadsheet's CSV.
    if let serial = Double(text), serial > 20_000, serial < 80_000 {
      var base = DateComponents()
      base.year = 1899
      base.month = 12
      base.day = 30
      guard let origin = calendar.date(from: base) else { return nil }
      let whole = Int(serial.rounded(.down))
      let minutes = Int(((serial - Double(whole)) * 1440).rounded())
      guard let day = calendar.date(byAdding: .day, value: whole, to: origin) else { return nil }
      return calendar.date(byAdding: .minute, value: minutes, to: day)
    }

    for format in textFormats {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.calendar = calendar
      formatter.timeZone = calendar.timeZone
      formatter.dateFormat = format
      if let date = formatter.date(from: text) { return date }
    }
    return nil
  }
}

extension Side {
  fileprivate init?(letter: Character) {
    switch letter {
    case "L", "l": self = .left
    case "R", "r": self = .right
    default: return nil
    }
  }
}
