import NestCore
import NestData
import SQLiteData
import SwiftUI

/// Home: status tiles, predictions, flags, the feed alarm and running timers. The five log
/// buttons are pinned under the navigation bar (`actionBarInset`) on every tab.
struct NowView: View {
  @Environment(AppModel.self) private var model
  private var snapshot: NestSnapshot { SideEffects.shared.snapshot }

  var body: some View {
    NavigationStack {
      TimelineView(.periodic(from: .now, by: 30)) { context in
        ScrollView {
          VStack(spacing: 14) {
            flagsCard(now: context.date)
            timersSection(now: context.date)
            statusTiles(now: context.date)
            predictions(now: context.date)
            AlarmCard(snapshot: snapshot, now: context.date)
            totalsRow
          }
          .padding(.horizontal)
          .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
      }
      .nestBackground()
      .actionBarInset(tab: .now)
      // A real navigation bar, so content scrolls under a proper edge effect instead of
      // colliding with the status bar.
      .navigationTitle(snapshot.babyName)
      .navigationSubtitle(ageText)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          AvatarView(
            subject: Avatar.babySubject, name: snapshot.babyName, size: 34, tint: EventKind.bottle.color)
        }
      }
    }
  }

  // MARK: Sections

  private var ageText: String {
    snapshot.baby?.birthDate.map { AgeMath.label(birth: $0, now: Date()) } ?? ""
  }

  @ViewBuilder
  private func flagsCard(now: Date) -> some View {
    let flags = snapshot.flags(now: now)
    if !flags.isEmpty {
      Card(tint: .orange) {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(flags) { flag in
            VStack(alignment: .leading, spacing: 2) {
              Label(flag.title, systemImage: "exclamationmark.bubble")
                .font(.subheadline.weight(.semibold))
              Text(flag.detail).font(.footnote).foregroundStyle(.secondary)
            }
          }
        }
      }
      .accessibilityElement(children: .combine)
    }
  }

  @ViewBuilder
  private func timersSection(now: Date) -> some View {
    if let nursing = snapshot.activeNursing {
      RunningTimerCard(kind: .nursing, title: nursing.isPaused ? "Nursing paused" : "Nursing · \(nursing.currentSide.title)",
        start: nursing.effectiveStart(now: now), frozen: nursing.isPaused ? nursing.totals(now: now) : nil,
        loggedBy: nursing.session.loggedBy
      ) { model.open(.nursing) }
    }
    if let pump = snapshot.activePump {
      RunningTimerCard(kind: .pump, title: "Pumping", start: pump.startedAt, frozen: nil, loggedBy: pump.loggedBy) {
        model.open(.pump)
      }
    }
    if let sleep = snapshot.activeSleep {
      RunningTimerCard(kind: .sleep, title: "Asleep", start: sleep.startedAt, frozen: nil, loggedBy: sleep.loggedBy) {
        model.open(.sleep)
      }
    }
  }

  private func statusTiles(now: Date) -> some View {
    Grid(horizontalSpacing: 10, verticalSpacing: 10) {
      GridRow {
        StatusTile(kind: lastFeedKind, title: "Last fed", date: snapshot.lastFeed?.startedAt,
          detail: snapshot.lastFeed.map { Answers.feedSummary($0, unit: snapshot.unit) } ?? "Tap to log the first feed"
        ) { model.open(lastFeedKind) }
        sleepTile
      }
      GridRow {
        StatusTile(kind: .diaper, title: "Last diaper", date: snapshot.lastDiaper?.occurredAt,
          detail: snapshot.lastDiaper.map { diaperDetail($0) } ?? "Tap to log a change"
        ) { model.open(.diaper) }
        StatusTile(kind: .nursing, title: "Next side", date: nil,
          detail: snapshot.nextSide.title, big: snapshot.nextSide.initial
        ) { model.open(.nursing) }
      }
    }
  }

  private var lastFeedKind: EventKind { snapshot.lastFeed?.isNursing == true ? .nursing : .bottle }

  @ViewBuilder
  private var sleepTile: some View {
    if let sleep = snapshot.activeSleep {
      StatusTile(kind: .sleep, title: "Asleep for", date: sleep.startedAt, detail: sleep.location?.title ?? "Sleeping",
        relativeSuffix: false
      ) { model.open(.sleep) }
    } else {
      StatusTile(kind: .sleep, title: "Awake since", date: snapshot.awakeSince,
        detail: snapshot.awakeSince.map { $0.formatted(date: .omitted, time: .shortened) } ?? "Tap to start a nap",
        relativeSuffix: false
      ) { model.open(.sleep) }
    }
  }

  private func diaperDetail(_ diaper: Diaper) -> String {
    var text = diaper.kind.title
    if let color = diaper.stoolColor { text += " · \(color.title.lowercased())" }
    return text
  }

  @ViewBuilder
  private func predictions(now: Date) -> some View {
    VStack(spacing: 10) {
      if snapshot.activeNursing == nil {
        NextFeedCard(prediction: snapshot.feedPrediction, lastFeed: snapshot.lastFeed?.startedAt, now: now)
      }
      if let nap = snapshot.napPrediction, snapshot.activeSleep == nil {
        Card(tint: EventKind.sleep.color) {
          VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
              Label("Nap window", systemImage: "moon.zzz")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(EventKind.sleep.color)
              Spacer()
              if nap.opensAt > now {
                Text("opens \(Text(nap.opensAt, style: .relative))")
                  .font(.subheadline.weight(.medium))
                  .monospacedDigit()
              } else {
                Text("open now").font(.subheadline.weight(.medium))
              }
            }
            ProgressView(value: nap.progress(now: now))
              .tint(EventKind.sleep.color)
            Text(nap.basis).font(.footnote).foregroundStyle(.secondary)
          }
        }
        .accessibilityElement(children: .combine)
      }
    }
  }

  private var totalsRow: some View {
    let t = snapshot.totals24h
    return Card {
      VStack(alignment: .leading, spacing: 8) {
        Text("Last 24 hours").font(.subheadline.weight(.semibold))
        HStack {
          total("\(t.feeds)", "feeds", .bottle)
          total(Durations.compact(t.sleep), "sleep", .sleep)
          total("\(t.wet)", "wet", .diaper)
          total("\(t.dirty)", "dirty", .diaper)
        }
        if t.bottleMl > 0 || t.nursing > 0 {
          Text("\(Volume.format(ml: t.bottleMl, unit: snapshot.unit)) by bottle · \(Durations.format(t.nursing)) nursing")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  private func total(_ value: String, _ label: String, _ kind: EventKind) -> some View {
    VStack(spacing: 2) {
      Text(value).font(.status(.title3)).monospacedDigit().foregroundStyle(kind.color)
      Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 10)
    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(kind.color.opacity(0.12)))
    .accessibilityElement(children: .combine)
  }

}

// MARK: - Components

/// The screen's one bold moment: a solid card counting toward the predicted next feed, or
/// a friendly note about what it needs before it can predict.
struct NextFeedCard: View {
  let prediction: FeedPrediction?
  let lastFeed: Date?
  let now: Date

  private let tint = EventKind.bottle.color

  var body: some View {
    HStack(alignment: .center, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Next feed")
          .font(.subheadline.weight(.semibold))
          .opacity(0.85)
        if let prediction {
          Text("~\(prediction.expected.formatted(date: .omitted, time: .shortened))")
            .font(.system(.largeTitle, design: .rounded).weight(.bold))
            .tracking(-0.5)
            .monospacedDigit()
          Text("\(prediction.earliest.formatted(date: .omitted, time: .shortened))–\(prediction.latest.formatted(date: .omitted, time: .shortened)) · \(prediction.basis)")
            .font(.footnote)
            .opacity(0.85)
        } else {
          Text("Log a few feeds and Nest will learn her rhythm.")
            .font(.headline)
          Text("Predictions come from her own last 3 days, never a generic chart.")
            .font(.footnote)
            .opacity(0.85)
        }
      }
      Spacer(minLength: 0)
      if let prediction, let lastFeed, prediction.expected > lastFeed {
        ProgressView(timerInterval: lastFeed...prediction.expected, countsDown: false) {
          EmptyView()
        } currentValueLabel: {
          Image(systemName: "waterbottle.fill")
        }
        .progressViewStyle(.circular)
        .tint(.white)
        .frame(width: 56, height: 56)
      } else {
        Image(systemName: "sparkles")
          .font(.title)
          .opacity(0.9)
      }
    }
    .foregroundStyle(.white)
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .fill(tint.gradient)
        .shadow(color: tint.opacity(0.35), radius: 16, y: 8)
    }
    .accessibilityElement(children: .combine)
  }
}

/// A status tile. It's a button so it responds on touch-down, like every other control.
struct StatusTile: View {
  let kind: EventKind
  let title: String
  let date: Date?
  let detail: String
  var big: String? = nil
  var relativeSuffix = true
  let action: () -> Void

  private var isEmpty: Bool { big == nil && date == nil }

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 6) {
          EventBadge(kind: kind, size: 24)
          Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(kind.color)
        }
        if isEmpty {
          // No data yet: say what to do instead of showing a lone dash.
          Spacer(minLength: 0)
          Text(detail)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
        } else {
          Group {
            if let big {
              Text(big)
            } else if let date {
              Text(date, style: relativeSuffix ? .relative : .timer)
            }
          }
          .font(.status(.title2))
          .monospacedDigit()
          .foregroundStyle(.primary)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
          Text(detail)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
        }
      }
      .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
      .padding(14)
      .background {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
          .fill(Palette.card)
          .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.wash(kind.color)))
          .shadow(color: kind.color.opacity(0.10), radius: 10, y: 4)
      }
    }
    .buttonStyle(.pressable)
    .accessibilityElement(children: .combine)
    .accessibilityHint("Opens the \(kind.title.lowercased()) sheet")
  }
}

struct RunningTimerCard: View {
  let kind: EventKind
  let title: String
  let start: Date
  /// Frozen per-side totals while paused.
  let frozen: (left: TimeInterval, right: TimeInterval)?
  let loggedBy: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: kind.symbol)
          .font(.title2)
          .foregroundStyle(kind.color)
          .symbolEffect(.pulse, isActive: frozen == nil)
        VStack(alignment: .leading, spacing: 2) {
          Text(title).font(.subheadline.weight(.semibold))
          Text("Started by \(loggedBy.isEmpty ? "someone" : loggedBy)")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Group {
          if let frozen {
            Text(Durations.clock(frozen.left + frozen.right))
          } else {
            Text(timerInterval: start...Date.distantFuture, countsDown: false)
          }
        }
        .font(.status(.title2))
        .monospacedDigit()
      }
      .padding(16)
      .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(kind.color.opacity(0.18)))
    }
    .buttonStyle(.pressable)
    .accessibilityHint("Opens the timer")
  }
}

struct ActionSourceID: Hashable {
  var kind: EventKind
  var active: Bool
}

private struct SheetNamespaceKey: EnvironmentKey {
  static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
  /// Namespace the log sheets zoom out of.
  var sheetNamespace: Namespace.ID? {
    get { self[SheetNamespaceKey.self] }
    set { self[SheetNamespaceKey.self] = newValue }
  }
}

extension View {
  /// Pins the log buttons under the navigation bar of a tab's screen. `tab` says which tab
  /// this is, so only the visible copy is the sheets' zoom source.
  func actionBarInset(tab: AppTab) -> some View {
    // Inline titles: a large title and a pinned inset both claim the space under the status
    // bar, and the title ends up underneath the strip.
    navigationBarTitleDisplayMode(.inline)
      .safeAreaInset(edge: .top, spacing: 0) { ActionBar(tab: tab) }
  }
}

/// The five log buttons: Bottle, Nurse, Diaper, Sleep, Pump. One solid, rounded strip pinned
/// to the top of every screen, right under the navigation bar.
struct ActionBar: View {
  @Environment(AppModel.self) private var model
  @Environment(\.sheetNamespace) private var namespace
  let tab: AppTab

  private var snapshot: NestSnapshot { SideEffects.shared.snapshot }
  private let kinds: [EventKind] = [.bottle, .nursing, .diaper, .sleep, .pump]

  var body: some View {
    HStack(spacing: 0) {
      ForEach(kinds, id: \.self) { kind in
        Button {
          model.open(kind)
        } label: {
          VStack(spacing: 3) {
            EventBadge(kind: kind, size: 32)
              .symbolEffect(.pulse, isActive: isRunning(kind))
            Text(label(for: kind))
              .font(.caption2.weight(.semibold))
              .lineLimit(1)
              .minimumScaleFactor(0.8)
              .foregroundStyle(kind.color)
          }
          .frame(maxWidth: .infinity, minHeight: 56)
          .contentShape(.rect)
        }
        .buttonStyle(.pressable)
        .modifier(ZoomSource(kind: kind, active: model.tab == tab, namespace: namespace))
        .accessibilityLabel(accessibilityLabel(for: kind))
      }
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 4)
    .background {
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .fill(Palette.card)
        .shadow(color: .black.opacity(0.08), radius: 10, y: 3)
    }
    .padding(.horizontal, 12)
    .padding(.top, 4)
    .padding(.bottom, 8)
  }

  private func isRunning(_ kind: EventKind) -> Bool {
    switch kind {
    case .nursing: snapshot.activeNursing != nil
    case .sleep: snapshot.activeSleep != nil
    case .pump: snapshot.activePump != nil
    default: false
    }
  }

  private func label(for kind: EventKind) -> String {
    switch kind {
    case .nursing: snapshot.activeNursing != nil ? "Nursing" : "Nurse \(snapshot.nextSide.initial)"
    case .sleep: snapshot.activeSleep != nil ? "Wake" : "Sleep"
    case .pump: snapshot.activePump != nil ? "Pumping" : "Pump"
    default: kind.title
    }
  }

  private func accessibilityLabel(for kind: EventKind) -> String {
    switch kind {
    case .nursing:
      snapshot.activeNursing != nil ? "Nursing timer running" : "Nurse, next side \(snapshot.nextSide.title)"
    case .sleep: snapshot.activeSleep != nil ? "Sleep timer running" : "Sleep"
    case .pump: snapshot.activePump != nil ? "Pump timer running" : "Pump"
    default: "Log \(kind.title.lowercased())"
    }
  }
}

private struct ZoomSource: ViewModifier {
  let kind: EventKind
  let active: Bool
  let namespace: Namespace.ID?

  func body(content: Content) -> some View {
    if let namespace {
      content.matchedTransitionSource(id: ActionSourceID(kind: kind, active: active), in: namespace)
    } else {
      content
    }
  }
}
