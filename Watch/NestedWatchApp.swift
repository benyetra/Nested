import NestedCore
import NestedData
import SQLiteData
import SwiftUI

/// Apple Watch: a status glance and big buttons. It runs its own sync engine on the same
/// iCloud account, so entries logged here reach both phones.
@main
struct NestedWatchApp: App {
  init() {
    @Dependency(\.context) var context
    let database: any DatabaseWriter
    if context == .live {
      database = NestedBootstrap.run(sync: .live)
    } else {
      database = try! NestedDatabase.openInMemory()
      prepareDependencies { $0.defaultDatabase = database }
    }
    SharedStore.configure(LiveEventStore(database: database, onChange: { _ in SharedStore.reloadSurfaces() }))
  }

  var body: some Scene {
    WindowGroup {
      WatchRootView()
    }
  }
}

struct WatchRootView: View {
  @Fetch(SnapshotRequest(), animation: .default) private var snapshot = NestedSnapshot.empty
  @State private var ownerName = DevicePrefs.ownerName
  @State private var successTick = 0
  @State private var impactTick = 0
  @State private var message: String?

  private var store: (any EventStore)? { try? SharedStore.store }

  var body: some View {
    NavigationStack {
      if ownerName.isEmpty {
        whoAreYou
      } else if snapshot.baby == nil {
        ContentUnavailableView(
          "Waiting for iCloud", systemImage: "icloud",
          description: Text("Set up Nested on your iPhone first."))
      } else {
        dashboard
      }
    }
    .sensoryFeedback(.success, trigger: successTick)
    .sensoryFeedback(.impact, trigger: impactTick)
  }

  private var whoAreYou: some View {
    List {
      Section("Who's wearing this watch?") {
        ForEach(snapshot.devices.map(\.ownerName).filter { !$0.isEmpty }, id: \.self) { name in
          Button(name) { setOwner(name) }
        }
        TextField("Your name", text: $ownerName)
          .onSubmit { setOwner(ownerName) }
      }
    }
  }

  private var dashboard: some View {
    ScrollView {
      VStack(spacing: 10) {
        status
        if let message {
          Text(message).font(.footnote).foregroundStyle(.secondary)
        }
        timerButtons
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
          GridRow {
            bigButton("Bottle", "waterbottle.fill", .bottle) {
              let ml = snapshot.defaultBottleMl ?? 90
              let contents = snapshot.defaultBottleContents
              return try $0.logBottle(
                amountMl: ml, contents: contents, offeredMl: nil, formulaBrand: snapshot.baby?.formulaBrand,
                at: Date(), note: "", endSleep: true)
            }
            bigButton("Wet", "drop.fill", .diaper) { try $0.logDiaper(kind: .wet) }
          }
          GridRow {
            bigButton("Dirty", "circle.fill", .diaper) { try $0.logDiaper(kind: .dirty) }
            if snapshot.activeSleep != nil {
              bigButton("Wake", "sun.max.fill", .sleep) { try $0.stopSleep(at: Date()) }
            } else {
              bigButton("Sleep", "moon.zzz.fill", .sleep, haptic: .impact) { try $0.startSleep(location: nil, at: Date()) }
            }
          }
        }
      }
    }
    .navigationTitle(snapshot.babyName)
  }

  private var status: some View {
    VStack(alignment: .leading, spacing: 4) {
      if let feed = snapshot.lastFeed {
        Label {
          Text("Fed \(Text(feed.startedAt, style: .relative)) ago")
        } icon: {
          Image(systemName: feed.isNursing ? "heart.fill" : "waterbottle.fill")
        }
        .foregroundStyle(EventKind.bottle.color)
      }
      if let sleep = snapshot.activeSleep {
        Label { Text("Asleep \(Text(sleep.startedAt, style: .relative))") } icon: { Image(systemName: "moon.zzz.fill") }
          .foregroundStyle(EventKind.sleep.color)
      } else if let awake = snapshot.awakeSince {
        Label { Text("Awake \(Text(awake, style: .relative))") } icon: { Image(systemName: "sun.max") }
          .foregroundStyle(EventKind.sleep.color)
      }
      if let prediction = snapshot.feedPrediction {
        Text(prediction.shortLabel(now: Date(), timeStyle: { $0.formatted(date: .omitted, time: .shortened) }))
          .foregroundStyle(.secondary)
      }
    }
    .font(.footnote)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  private var timerButtons: some View {
    if let nursing = snapshot.activeNursing {
      VStack(spacing: 6) {
        Text(timerInterval: nursing.effectiveStart(now: Date())...Date.distantFuture, countsDown: false)
          .font(.title2.monospacedDigit().weight(.semibold))
        HStack {
          Button {
            run { try $0.switchNursingSide(at: Date()) }
          } label: {
            Text("→ \(nursing.currentSide.opposite.initial)")
          }
          Button("Stop", role: .destructive) {
            run { try $0.stopNursing(at: Date(), latchNote: nil) }
          }
        }
      }
      .tint(EventKind.nursing.color)
    } else {
      HStack {
        ForEach(Side.allCases, id: \.self) { side in
          Button {
            run(haptic: .impact) { try $0.startNursing(side: side, at: Date(), endSleep: true) }
          } label: {
            VStack {
              Image(systemName: "heart.fill")
              Text("Nurse \(side.initial)")
            }
            .frame(maxWidth: .infinity)
          }
          .tint(EventKind.nursing.color)
          .overlay(alignment: .topTrailing) {
            if snapshot.nextSide == side {
              Circle().fill(EventKind.nursing.color).frame(width: 7, height: 7).padding(4)
            }
          }
        }
      }
    }
  }

  enum Haptic {
    case success
    case impact
  }

  private func bigButton(
    _ title: String, _ symbol: String, _ kind: EventKind, haptic: Haptic = .success,
    action: @escaping (any EventStore) throws -> Entry
  ) -> some View {
    Button {
      run(haptic: haptic, action)
    } label: {
      VStack(spacing: 2) {
        Image(systemName: symbol).font(.title3)
        Text(title).font(.caption2.weight(.semibold))
      }
      .frame(maxWidth: .infinity, minHeight: 50)
    }
    .tint(kind.color)
  }

  private func run(haptic: Haptic = .success, _ action: (any EventStore) throws -> Entry) {
    guard let store else { return }
    do {
      let entry = try action(store)
      message = entry.title(unit: snapshot.unit)
      switch haptic {
      case .success: successTick += 1
      case .impact: impactTick += 1
      }
    } catch {
      message = String(describing: error)
    }
  }

  private func setOwner(_ name: String) {
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return }
    DevicePrefs.ownerName = trimmed
    ownerName = trimmed
    Task { try? await $snapshot.load(SnapshotRequest(me: trimmed), animation: .default) }
  }
}
