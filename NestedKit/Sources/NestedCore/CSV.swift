import Foundation

/// RFC 4180 CSV encoding and parsing, used for the raw export and the one-time import.
public enum CSV {
  public static func encode(header: [String], rows: [[String]]) -> String {
    ([header] + rows).map { $0.map(escape).joined(separator: ",") }.joined(separator: "\r\n")
      + "\r\n"
  }

  public static func escape(_ field: String) -> String {
    let needsQuotes = field.contains { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }
    guard needsQuotes else { return field }
    return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
  }

  /// Parses CSV text into rows of fields. Handles quoted fields, escaped quotes, CRLF and
  /// newlines inside quotes. Blank lines are skipped.
  public static func parse(_ text: String) -> [[String]] {
    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var inQuotes = false
    var iterator = Array(text.unicodeScalars).makeIterator()
    var pending: Unicode.Scalar? = nil

    func next() -> Unicode.Scalar? {
      if let p = pending {
        pending = nil
        return p
      }
      return iterator.next()
    }
    func endRow() {
      row.append(field)
      field = ""
      if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
      row = []
    }

    while let c = next() {
      if inQuotes {
        if c == "\"" {
          if let n = next() {
            if n == "\"" {
              field.unicodeScalars.append("\"")
            } else {
              inQuotes = false
              pending = n
            }
          } else {
            inQuotes = false
          }
        } else {
          field.unicodeScalars.append(c)
        }
        continue
      }
      switch c {
      case "\"":
        inQuotes = true
      case ",":
        row.append(field)
        field = ""
      case "\r":
        if let n = next(), n != "\n" { pending = n }
        endRow()
      case "\n":
        endRow()
      default:
        field.unicodeScalars.append(c)
      }
    }
    if !field.isEmpty || !row.isEmpty { endRow() }
    return rows
  }
}

/// One row of the raw export / import format. The same columns round-trip.
public struct EntryRow: Hashable, Sendable {
  public static let header = [
    "type", "started_at", "ended_at", "amount_ml", "offered_ml", "contents", "formula_brand",
    "left_seconds", "right_seconds", "ended_on_side", "left_ml", "right_ml", "destination",
    "diaper", "stool_color", "consistency", "size", "rash", "location", "tag", "note",
    "logged_by", "time_zone",
  ]

  public var kind: EventKind
  public var startedAt: Date
  public var endedAt: Date?
  public var amountMl: Double?
  public var offeredMl: Double?
  public var contents: BottleContents?
  public var formulaBrand: String?
  public var leftSeconds: Double?
  public var rightSeconds: Double?
  public var endedOnSide: Side?
  public var leftMl: Double?
  public var rightMl: Double?
  public var destination: PumpDestination?
  public var diaper: DiaperKind?
  public var stoolColor: StoolColor?
  public var consistency: StoolConsistency?
  public var size: DiaperSize?
  public var rash: Bool?
  public var location: SleepLocation?
  public var tag: NoteTag?
  public var note: String
  public var loggedBy: String
  public var timeZone: String?

  public init(kind: EventKind, startedAt: Date, note: String = "", loggedBy: String = "") {
    self.kind = kind
    self.startedAt = startedAt
    self.note = note
    self.loggedBy = loggedBy
  }

  nonisolated(unsafe) static let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
  }()

  public var fields: [String] {
    func num(_ value: Double?) -> String {
      guard let value else { return "" }
      return value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
    return [
      kind.rawValue,
      Self.isoFormatter.string(from: startedAt),
      endedAt.map { Self.isoFormatter.string(from: $0) } ?? "",
      num(amountMl), num(offeredMl), contents?.rawValue ?? "", formulaBrand ?? "",
      num(leftSeconds), num(rightSeconds), endedOnSide?.rawValue ?? "",
      num(leftMl), num(rightMl), destination?.rawValue ?? "",
      diaper?.rawValue ?? "", stoolColor?.rawValue ?? "", consistency?.rawValue ?? "",
      size?.rawValue ?? "", rash.map { $0 ? "true" : "false" } ?? "",
      location?.rawValue ?? "", tag?.rawValue ?? "", note, loggedBy, timeZone ?? "",
    ]
  }

  public enum ImportError: Error, Equatable, CustomStringConvertible {
    case missingHeader
    case badRow(line: Int, reason: String)

    public var description: String {
      switch self {
      case .missingHeader: "The first row must be the Nested export header."
      case .badRow(let line, let reason): "Row \(line): \(reason)"
      }
    }
  }

  /// Parses an export. Unknown columns are ignored; column order is taken from the header.
  public static func parse(csv text: String) throws -> [EntryRow] {
    let table = CSV.parse(text)
    guard let header = table.first, header.contains("type"), header.contains("started_at")
    else { throw ImportError.missingHeader }
    let index = Dictionary(
      header.enumerated().map { ($1.trimmingCharacters(in: .whitespaces), $0) },
      uniquingKeysWith: { first, _ in first })

    return try table.dropFirst().enumerated().map { offset, fields in
      let line = offset + 2
      func value(_ column: String) -> String? {
        guard let i = index[column], i < fields.count else { return nil }
        let v = fields[i].trimmingCharacters(in: .whitespaces)
        return v.isEmpty ? nil : v
      }
      func date(_ column: String) throws -> Date? {
        guard let raw = value(column) else { return nil }
        if let d = isoFormatter.date(from: raw) { return d }
        throw ImportError.badRow(line: line, reason: "unreadable date '\(raw)'")
      }
      guard let kind = value("type").flatMap(EventKind.init(rawValue:)) else {
        throw ImportError.badRow(line: line, reason: "unknown type '\(value("type") ?? "")'")
      }
      guard let start = try date("started_at") else {
        throw ImportError.badRow(line: line, reason: "missing started_at")
      }
      var row = EntryRow(kind: kind, startedAt: start)
      row.endedAt = try date("ended_at")
      row.amountMl = value("amount_ml").flatMap(Double.init)
      row.offeredMl = value("offered_ml").flatMap(Double.init)
      row.contents = value("contents").flatMap(BottleContents.init(rawValue:))
      row.formulaBrand = value("formula_brand")
      row.leftSeconds = value("left_seconds").flatMap(Double.init)
      row.rightSeconds = value("right_seconds").flatMap(Double.init)
      row.endedOnSide = value("ended_on_side").flatMap(Side.init(rawValue:))
      row.leftMl = value("left_ml").flatMap(Double.init)
      row.rightMl = value("right_ml").flatMap(Double.init)
      row.destination = value("destination").flatMap(PumpDestination.init(rawValue:))
      row.diaper = value("diaper").flatMap(DiaperKind.init(rawValue:))
      row.stoolColor = value("stool_color").flatMap(StoolColor.init(rawValue:))
      row.consistency = value("consistency").flatMap(StoolConsistency.init(rawValue:))
      row.size = value("size").flatMap(DiaperSize.init(rawValue:))
      row.rash = value("rash").map { $0.lowercased() == "true" || $0 == "1" }
      row.location = value("location").flatMap(SleepLocation.init(rawValue:))
      row.tag = value("tag").flatMap(NoteTag.init(rawValue:))
      row.note = value("note") ?? ""
      row.loggedBy = value("logged_by") ?? ""
      row.timeZone = value("time_zone")
      if kind == .bottle, row.amountMl == nil {
        throw ImportError.badRow(line: line, reason: "bottle without amount_ml")
      }
      if kind == .diaper, row.diaper == nil {
        throw ImportError.badRow(line: line, reason: "diaper without a diaper type")
      }
      return row
    }
  }
}
