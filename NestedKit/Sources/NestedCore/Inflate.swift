import Foundation

/// A small DEFLATE (RFC 1951) decoder and ZIP reader, so `.xlsx` files can be read with no
/// dependency and on every platform (including the Linux test runner). Port of the classic
/// `puff.c` algorithm: slow-ish, tiny, and easy to verify.
public enum Inflate {
  public struct Failure: Error, CustomStringConvertible {
    public var description: String
  }

  private static let lengthBase = [
    3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163,
    195, 227, 258,
  ]
  private static let lengthExtra = [
    0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0,
  ]
  private static let distBase = [
    1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049,
    3073, 4097, 6145, 8193, 12289, 16385, 24577,
  ]
  private static let distExtra = [
    0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13,
  ]
  private static let codeLengthOrder = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

  private struct Huffman {
    var count = [Int](repeating: 0, count: 16)
    var symbol: [Int]

    init(lengths: [Int]) throws {
      symbol = [Int](repeating: 0, count: lengths.count)
      for length in lengths { count[length] += 1 }
      var left = 1
      for len in 1...15 {
        left <<= 1
        left -= count[len]
        if left < 0 { throw Failure(description: "over-subscribed code") }
      }
      var offsets = [Int](repeating: 0, count: 16)
      for len in 1..<15 { offsets[len + 1] = offsets[len] + count[len] }
      for (symbolIndex, length) in lengths.enumerated() where length != 0 {
        symbol[offsets[length]] = symbolIndex
        offsets[length] += 1
      }
    }
  }

  private struct Reader {
    let data: [UInt8]
    var position = 0
    var bitBuffer = 0
    var bitCount = 0

    init(_ data: [UInt8]) { self.data = data }

    mutating func bits(_ need: Int) throws -> Int {
      var value = bitBuffer
      while bitCount < need {
        guard position < data.count else { throw Failure(description: "unexpected end of data") }
        value |= Int(data[position]) << bitCount
        position += 1
        bitCount += 8
      }
      bitBuffer = value >> need
      bitCount -= need
      return value & ((1 << need) - 1)
    }

    mutating func decode(_ huffman: Huffman) throws -> Int {
      var code = 0
      var first = 0
      var index = 0
      for len in 1...15 {
        code |= try bits(1)
        let count = huffman.count[len]
        if code - count < first { return huffman.symbol[index + (code - first)] }
        index += count
        first += count
        first <<= 1
        code <<= 1
      }
      throw Failure(description: "bad code")
    }
  }

  /// Decompresses a raw DEFLATE stream (as stored inside ZIP entries).
  public static func inflate(_ input: [UInt8]) throws -> [UInt8] {
    var reader = Reader(input)
    var output: [UInt8] = []
    output.reserveCapacity(input.count * 4)

    var isLast = false
    while !isLast {
      isLast = try reader.bits(1) == 1
      switch try reader.bits(2) {
      case 0:
        reader.bitBuffer = 0
        reader.bitCount = 0
        guard reader.position + 4 <= input.count else { throw Failure(description: "truncated stored block") }
        let length = Int(input[reader.position]) | Int(input[reader.position + 1]) << 8
        let inverse = Int(input[reader.position + 2]) | Int(input[reader.position + 3]) << 8
        guard length == (~inverse & 0xFFFF) else { throw Failure(description: "bad stored block") }
        reader.position += 4
        guard reader.position + length <= input.count else { throw Failure(description: "truncated stored block") }
        output.append(contentsOf: input[reader.position..<reader.position + length])
        reader.position += length
      case 1:
        var lengths = [Int](repeating: 8, count: 288)
        for i in 144..<256 { lengths[i] = 9 }
        for i in 256..<280 { lengths[i] = 7 }
        let literal = try Huffman(lengths: lengths)
        let distance = try Huffman(lengths: [Int](repeating: 5, count: 30))
        try codes(&reader, &output, literal, distance)
      case 2:
        let literalCount = try reader.bits(5) + 257
        let distanceCount = try reader.bits(5) + 1
        let codeLengthCount = try reader.bits(4) + 4
        guard literalCount <= 286, distanceCount <= 30 else { throw Failure(description: "bad counts") }
        var lengths = [Int](repeating: 0, count: 19)
        for i in 0..<codeLengthCount { lengths[codeLengthOrder[i]] = try reader.bits(3) }
        let codeLengths = try Huffman(lengths: lengths)
        var all = [Int]()
        while all.count < literalCount + distanceCount {
          let symbol = try reader.decode(codeLengths)
          if symbol < 16 {
            all.append(symbol)
          } else {
            var previous = 0
            var repeatCount = 0
            switch symbol {
            case 16:
              guard let last = all.last else { throw Failure(description: "no previous length") }
              previous = last
              repeatCount = 3 + (try reader.bits(2))
            case 17: repeatCount = 3 + (try reader.bits(3))
            default: repeatCount = 11 + (try reader.bits(7))
            }
            guard all.count + repeatCount <= literalCount + distanceCount else {
              throw Failure(description: "too many lengths")
            }
            all.append(contentsOf: [Int](repeating: previous, count: repeatCount))
          }
        }
        let literal = try Huffman(lengths: Array(all[0..<literalCount]))
        let distance = try Huffman(lengths: Array(all[literalCount...]))
        try codes(&reader, &output, literal, distance)
      default:
        throw Failure(description: "bad block type")
      }
    }
    return output
  }

  private static func codes(
    _ reader: inout Reader, _ output: inout [UInt8], _ literal: Huffman, _ distance: Huffman
  ) throws {
    while true {
      var symbol = try reader.decode(literal)
      if symbol < 256 {
        output.append(UInt8(symbol))
      } else if symbol == 256 {
        return
      } else {
        symbol -= 257
        guard symbol < 29 else { throw Failure(description: "bad length symbol") }
        let length = lengthBase[symbol] + (try reader.bits(lengthExtra[symbol]))
        let distanceSymbol = try reader.decode(distance)
        guard distanceSymbol < 30 else { throw Failure(description: "bad distance symbol") }
        let back = distBase[distanceSymbol] + (try reader.bits(distExtra[distanceSymbol]))
        guard back <= output.count else { throw Failure(description: "distance too far back") }
        let start = output.count - back
        for i in 0..<length { output.append(output[start + i]) }
      }
    }
  }
}

/// Reads entries out of a ZIP archive held in memory.
public struct ZipArchive {
  public struct Entry {
    public var name: String
    var method: Int
    var compressedSize: Int
    var localHeaderOffset: Int
  }

  private let bytes: [UInt8]
  public let entries: [Entry]

  /// True if `data` starts with the ZIP signature.
  public static func looksLikeZip(_ data: Data) -> Bool {
    data.count > 4 && data.prefix(4) == Data([0x50, 0x4B, 0x03, 0x04])
  }

  public init(data: Data) throws {
    let bytes = [UInt8](data)
    self.bytes = bytes
    func u16(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
    func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }

    guard bytes.count >= 22 else { throw Inflate.Failure(description: "not a zip file") }
    var eocd = -1
    var i = bytes.count - 22
    while i >= max(0, bytes.count - 22 - 65_535) {
      if u32(i) == 0x0605_4B50 {
        eocd = i
        break
      }
      i -= 1
    }
    guard eocd >= 0 else { throw Inflate.Failure(description: "not a zip file") }
    let count = u16(eocd + 10)
    var cursor = u32(eocd + 16)
    var found: [Entry] = []
    for _ in 0..<count {
      guard cursor + 46 <= bytes.count, u32(cursor) == 0x0201_4B50 else {
        throw Inflate.Failure(description: "damaged zip directory")
      }
      let nameLength = u16(cursor + 28)
      let extraLength = u16(cursor + 30)
      let commentLength = u16(cursor + 32)
      guard cursor + 46 + nameLength <= bytes.count else { throw Inflate.Failure(description: "damaged zip directory") }
      let name = String(decoding: bytes[(cursor + 46)..<(cursor + 46 + nameLength)], as: UTF8.self)
      found.append(
        Entry(
          name: name, method: u16(cursor + 10), compressedSize: u32(cursor + 20),
          localHeaderOffset: u32(cursor + 42)))
      cursor += 46 + nameLength + extraLength + commentLength
    }
    entries = found
  }

  public func contents(of name: String) throws -> Data? {
    guard let entry = entries.first(where: { $0.name == name }) else { return nil }
    let at = entry.localHeaderOffset
    func u16(_ p: Int) -> Int { Int(bytes[p]) | Int(bytes[p + 1]) << 8 }
    guard at + 30 <= bytes.count else { throw Inflate.Failure(description: "damaged zip entry") }
    let start = at + 30 + u16(at + 26) + u16(at + 28)
    guard start + entry.compressedSize <= bytes.count else { throw Inflate.Failure(description: "damaged zip entry") }
    let raw = Array(bytes[start..<(start + entry.compressedSize)])
    switch entry.method {
    case 0: return Data(raw)
    case 8: return Data(try Inflate.inflate(raw))
    default: throw Inflate.Failure(description: "unsupported zip compression")
    }
  }
}
