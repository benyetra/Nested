import Foundation

// Plain value snapshots of stored entries. The database layer maps its rows into these so
// every algorithm in Core stays free of persistence and runs anywhere, including tests.

public struct FeedRecord: Hashable, Sendable {
  public enum Kind: Hashable, Sendable {
    case bottle(amountMl: Double, contents: BottleContents)
    case nursing(leftSeconds: TimeInterval, rightSeconds: TimeInterval, endedOnSide: Side?)
  }

  public var startedAt: Date
  public var endedAt: Date?
  public var kind: Kind

  public init(startedAt: Date, endedAt: Date? = nil, kind: Kind) {
    self.startedAt = startedAt
    self.endedAt = endedAt
    self.kind = kind
  }

  public var isNursing: Bool {
    if case .nursing = kind { return true }
    return false
  }
}

public struct SleepRecord: Hashable, Sendable {
  public var startedAt: Date
  public var endedAt: Date?

  public init(startedAt: Date, endedAt: Date? = nil) {
    self.startedAt = startedAt
    self.endedAt = endedAt
  }

  public func duration(now: Date) -> TimeInterval {
    (endedAt ?? now).timeIntervalSince(startedAt)
  }
}

public struct DiaperRecord: Hashable, Sendable {
  public var occurredAt: Date
  public var kind: DiaperKind
  public var stoolColor: StoolColor?

  public init(occurredAt: Date, kind: DiaperKind, stoolColor: StoolColor? = nil) {
    self.occurredAt = occurredAt
    self.kind = kind
    self.stoolColor = stoolColor
  }
}

public struct PumpRecord: Hashable, Sendable {
  public var startedAt: Date
  public var endedAt: Date?
  public var leftMl: Double
  public var rightMl: Double
  public var destination: PumpDestination?

  public init(
    startedAt: Date,
    endedAt: Date? = nil,
    leftMl: Double = 0,
    rightMl: Double = 0,
    destination: PumpDestination? = nil
  ) {
    self.startedAt = startedAt
    self.endedAt = endedAt
    self.leftMl = leftMl
    self.rightMl = rightMl
    self.destination = destination
  }

  public var totalMl: Double { leftMl + rightMl }
}

/// Everything the algorithms read, for one baby.
public struct History: Sendable, Hashable {
  public var feeds: [FeedRecord]
  public var sleeps: [SleepRecord]
  public var diapers: [DiaperRecord]
  public var pumps: [PumpRecord]

  public init(
    feeds: [FeedRecord] = [],
    sleeps: [SleepRecord] = [],
    diapers: [DiaperRecord] = [],
    pumps: [PumpRecord] = []
  ) {
    self.feeds = feeds.sorted { $0.startedAt < $1.startedAt }
    self.sleeps = sleeps.sorted { $0.startedAt < $1.startedAt }
    self.diapers = diapers.sorted { $0.occurredAt < $1.occurredAt }
    self.pumps = pumps.sorted { $0.startedAt < $1.startedAt }
  }
}
