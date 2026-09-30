import Foundation

/// Reads the first sheet of an Excel workbook as a table of strings. Numbers come through
/// as their raw text (dates are serial numbers); empty cells are empty strings.
public enum XLSX {
  public static func firstSheet(_ data: Data) throws -> [[String]] {
    let zip = try ZipArchive(data: data)
    let sheetName =
      zip.entries.map(\.name).filter { $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml") }
      .sorted { $0.localizedStandardCompare($1) == .orderedAscending }.first
    guard let sheetName, let sheetData = try zip.contents(of: sheetName) else {
      throw Inflate.Failure(description: "The workbook has no sheets.")
    }
    var shared: [String] = []
    if let stringsData = try zip.contents(of: "xl/sharedStrings.xml") {
      shared = strings(in: String(decoding: stringsData, as: UTF8.self))
    }
    return cells(in: String(decoding: sheetData, as: UTF8.self), shared: shared)
  }

  // MARK: Parsing

  static func strings(in xml: String) -> [String] {
    blocks(of: "si", in: xml).map { text(in: $0) }
  }

  static func cells(in xml: String, shared: [String]) -> [[String]] {
    var rows: [Int: [Int: String]] = [:]
    var maxColumn = 0
    for element in cellElements(in: xml) {
      guard let reference = attribute("r", in: element.open) else { continue }
      let (column, row) = position(of: reference)
      let type = attribute("t", in: element.open)
      var value = ""
      if type == "inlineStr" {
        value = text(in: element.body)
      } else if let raw = firstBlock(of: "v", in: element.body) {
        let unescaped = unescape(raw)
        if type == "s", let index = Int(unescaped), shared.indices.contains(index) {
          value = shared[index]
        } else {
          value = unescaped
        }
      }
      rows[row, default: [:]][column] = value
      maxColumn = max(maxColumn, column)
    }
    return rows.keys.sorted().map { row in
      (0...maxColumn).map { rows[row]?[$0] ?? "" }
    }
  }

  private struct CellElement {
    var open: String
    var body: String
  }

  /// `<c ...>…</c>` and self-closing `<c .../>` elements, in order.
  private static func cellElements(in xml: String) -> [CellElement] {
    var result: [CellElement] = []
    var index = xml.startIndex
    while let start = xml.range(of: "<c ", range: index..<xml.endIndex) {
      guard let tagEnd = xml.range(of: ">", range: start.upperBound..<xml.endIndex) else { break }
      let open = String(xml[start.lowerBound..<tagEnd.upperBound])
      if open.hasSuffix("/>") {
        result.append(CellElement(open: open, body: ""))
        index = tagEnd.upperBound
      } else if let close = xml.range(of: "</c>", range: tagEnd.upperBound..<xml.endIndex) {
        result.append(CellElement(open: open, body: String(xml[tagEnd.upperBound..<close.lowerBound])))
        index = close.upperBound
      } else {
        break
      }
    }
    return result
  }

  private static func blocks(of tag: String, in xml: String) -> [String] {
    var result: [String] = []
    var index = xml.startIndex
    let opening = "<\(tag)"
    while let start = xml.range(of: opening, range: index..<xml.endIndex) {
      // Make sure it's `<t>` / `<t ...>` and not a longer tag name such as `<tableParts>`.
      let next = start.upperBound < xml.endIndex ? xml[start.upperBound] : ">"
      guard next == ">" || next == " " || next == "/" else {
        index = start.upperBound
        continue
      }
      guard let tagEnd = xml.range(of: ">", range: start.upperBound..<xml.endIndex) else { break }
      if xml[xml.index(before: tagEnd.lowerBound)] == "/" {  // self-closing
        index = tagEnd.upperBound
        continue
      }
      guard let close = xml.range(of: "</\(tag)>", range: tagEnd.upperBound..<xml.endIndex) else { break }
      result.append(String(xml[tagEnd.upperBound..<close.lowerBound]))
      index = close.upperBound
    }
    return result
  }

  private static func firstBlock(of tag: String, in xml: String) -> String? {
    blocks(of: tag, in: xml).first
  }

  /// Concatenated text of every `<t>` inside `xml` (rich text splits a string into runs).
  private static func text(in xml: String) -> String {
    unescape(blocks(of: "t", in: xml).joined())
  }

  private static func attribute(_ name: String, in tag: String) -> String? {
    guard let range = tag.range(of: " \(name)=\"") else { return nil }
    guard let end = tag.range(of: "\"", range: range.upperBound..<tag.endIndex) else { return nil }
    return String(tag[range.upperBound..<end.lowerBound])
  }

  /// "AB12" -> (column 27, row 12)
  private static func position(of reference: String) -> (Int, Int) {
    var column = 0
    var digits = ""
    for character in reference {
      if let ascii = character.asciiValue, ascii >= 65, ascii <= 90 {
        column = column * 26 + Int(ascii - 64)
      } else if character.isNumber {
        digits.append(character)
      }
    }
    return (max(0, column - 1), Int(digits) ?? 0)
  }

  private static func unescape(_ text: String) -> String {
    guard text.contains("&") else { return text }
    var result = text
    for (entity, character) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'")] {
      result = result.replacingOccurrences(of: entity, with: character)
    }
    return result.replacingOccurrences(of: "&amp;", with: "&")
  }
}
