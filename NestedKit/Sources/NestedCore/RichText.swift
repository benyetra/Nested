import Foundation

/// One stretch of text with uniform formatting.
public struct RichRun: Codable, Hashable, Sendable {
  public var text: String
  public var bold: Bool
  public var italic: Bool
  public var underline: Bool
  public var strikethrough: Bool

  public init(
    _ text: String, bold: Bool = false, italic: Bool = false, underline: Bool = false,
    strikethrough: Bool = false
  ) {
    self.text = text
    self.bold = bold
    self.italic = italic
    self.underline = underline
    self.strikethrough = strikethrough
  }

  var sameStyle: (Bool, Bool, Bool, Bool) { (bold, italic, underline, strikethrough) }

  private enum CodingKeys: String, CodingKey {
    case text = "t", bold = "b", italic = "i", underline = "u", strikethrough = "s"
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    text = try c.decode(String.self, forKey: .text)
    bold = try c.decodeIfPresent(Bool.self, forKey: .bold) ?? false
    italic = try c.decodeIfPresent(Bool.self, forKey: .italic) ?? false
    underline = try c.decodeIfPresent(Bool.self, forKey: .underline) ?? false
    strikethrough = try c.decodeIfPresent(Bool.self, forKey: .strikethrough) ?? false
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(text, forKey: .text)
    if bold { try c.encode(true, forKey: .bold) }
    if italic { try c.encode(true, forKey: .italic) }
    if underline { try c.encode(true, forKey: .underline) }
    if strikethrough { try c.encode(true, forKey: .strikethrough) }
  }
}

/// Formatted text kept independent of any UI framework so it syncs as a plain string and
/// tests on Linux. The app bridges it to and from `AttributedString`.
///
/// Stored as a compact JSON array of runs. Anything that isn't that JSON (older data, another
/// client) is read as plain text, so a value is never lost.
public struct RichText: Hashable, Sendable {
  public private(set) var runs: [RichRun]

  public init(runs: [RichRun] = []) {
    var merged: [RichRun] = []
    for run in runs where !run.text.isEmpty {
      if var last = merged.last, last.sameStyle == run.sameStyle {
        last.text += run.text
        merged[merged.count - 1] = last
      } else {
        merged.append(run)
      }
    }
    self.runs = merged
  }

  public init(plain: String) {
    self.init(runs: [RichRun(plain)])
  }

  public init(stored: String) {
    if stored.hasPrefix("["),
      let data = stored.data(using: .utf8),
      let runs = try? JSONDecoder().decode([RichRun].self, from: data)
    {
      self.init(runs: runs)
    } else {
      self.init(plain: stored)
    }
  }

  /// The value written to the database. Empty text is the empty string.
  public var stored: String {
    guard !runs.isEmpty else { return "" }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(runs), let json = String(data: data, encoding: .utf8) else {
      return plain
    }
    return json
  }

  public var plain: String { runs.map(\.text).joined() }

  /// True when there is nothing but whitespace.
  public var isEmpty: Bool { plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
