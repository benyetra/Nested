#if os(iOS)
  import ActivityKit
  import Foundation
  import NestCore
  import NestData

  /// Live Activity for a running nursing, pumping or sleep timer. Elapsed time is always drawn
  /// from the stored start with timer-style text, never counted in memory.
  ///
  /// The Cloudflare Worker sends the same JSON shape in push-to-start payloads, so keep the
  /// property names stable (see worker/src/index.js).
  struct NestTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
      /// Anchor for the total timer, excluding paused time.
      var timerStart: Date
      /// Start of the current nursing side, for the per-side timer.
      var sideStart: Date?
      var side: Side?
      var isPaused: Bool
      /// Frozen elapsed seconds while paused.
      var pausedElapsed: Double?
      var leftSeconds: Double
      var rightSeconds: Double
      var loggedBy: String
    }

    var entryID: UUID
    var kind: EventKind
    var babyName: String
  }

  extension NestTimerAttributes {
    /// Attributes and state for a running timer in the snapshot, if any.
    static func running(in snapshot: NestSnapshot, now: Date = Date()) -> [(NestTimerAttributes, ContentState)] {
      var result: [(NestTimerAttributes, ContentState)] = []
      if let nursing = snapshot.activeNursing {
        let (left, right) = nursing.totals(now: now)
        result.append(
          (
            NestTimerAttributes(entryID: nursing.session.id, kind: .nursing, babyName: snapshot.babyName),
            ContentState(
              timerStart: nursing.effectiveStart(now: now),
              sideStart: nursing.currentSegmentStart,
              side: nursing.currentSide,
              isPaused: nursing.isPaused,
              pausedElapsed: nursing.isPaused ? left + right : nil,
              leftSeconds: left,
              rightSeconds: right,
              loggedBy: nursing.session.loggedBy
            )
          ))
      }
      if let pump = snapshot.activePump {
        result.append(
          (
            NestTimerAttributes(entryID: pump.id, kind: .pump, babyName: snapshot.babyName),
            ContentState(
              timerStart: pump.startedAt, sideStart: nil, side: nil, isPaused: false, pausedElapsed: nil,
              leftSeconds: 0, rightSeconds: 0, loggedBy: pump.loggedBy)
          ))
      }
      if let sleep = snapshot.activeSleep {
        result.append(
          (
            NestTimerAttributes(entryID: sleep.id, kind: .sleep, babyName: snapshot.babyName),
            ContentState(
              timerStart: sleep.startedAt, sideStart: nil, side: nil, isPaused: false, pausedElapsed: nil,
              leftSeconds: 0, rightSeconds: 0, loggedBy: sleep.loggedBy)
          ))
      }
      return result
    }

    /// State for comparison: segment totals change every second while running, so compare
    /// only the parts that change on an event.
    static func eventSignature(_ state: ContentState) -> String {
      "\(state.side?.rawValue ?? "-")|\(state.isPaused)|\(state.sideStart?.timeIntervalSince1970 ?? 0)"
    }
  }
#endif
