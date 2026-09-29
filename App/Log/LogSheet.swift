import NestCore
import NestData
import SwiftUI

/// Routes to the right sheet. Sheets use detents and present from the tapped button.
struct LogSheet: View {
  let kind: EventKind
  let snapshot: NestSnapshot
  // Open tall so the fields never sit behind the log button; drag down for the half sheet.
  @State private var detent: PresentationDetent = .large

  var body: some View {
    NavigationStack {
      Group {
        switch kind {
        case .bottle: BottleSheet(snapshot: snapshot)
        case .nursing: NursingSheet(snapshot: snapshot)
        case .pump: PumpSheet(snapshot: snapshot)
        case .diaper: DiaperSheet(snapshot: snapshot)
        case .sleep: SleepSheet(snapshot: snapshot)
        case .note: NoteSheet()
        }
      }
      .navigationTitle(kind.title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { CloseButton() }
      }
    }
    .presentationDetents([.medium, .large], selection: $detent)
    .presentationDragIndicator(.visible)
    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
  }
}

struct CloseButton: View {
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    Button("Close", systemImage: "xmark") { dismiss() }
      .labelStyle(.iconOnly)
  }
}

// MARK: - Amount control

/// Big amount readout with −/+ and quick chips; stores millilitres, shows the household unit.
struct AmountControl: View {
  @Binding var ml: Double
  let unit: VolumeUnit
  var tint: Color = EventKind.bottle.color

  private var quickAmounts: [Double] {
    unit == .ml ? [30, 60, 90, 120, 150, 180] : [1, 2, 3, 4, 5, 6].map { Volume.ml(fromOunces: $0) }
  }

  var body: some View {
    VStack(spacing: 12) {
      HStack(spacing: 20) {
        stepButton("minus") { adjust(-1) }
        Text(Volume.format(ml: ml, unit: unit))
          .font(.system(size: 48, weight: .semibold, design: .rounded))
          .monospacedDigit()
          .contentTransition(.numericText(value: ml))
          .frame(minWidth: 160)
          .accessibilityLabel("Amount \(Volume.spoken(ml: ml, unit: unit))")
          .accessibilityAdjustableAction { direction in
            adjust(direction == .increment ? 1 : -1)
          }
        stepButton("plus") { adjust(1) }
      }
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(quickAmounts, id: \.self) { amount in
            Chip(
              title: Volume.format(ml: amount, unit: unit),
              isSelected: abs(amount - ml) < 1,
              tint: tint
            ) {
              withAnimation(Motion.standard) { ml = amount }
            }
          }
        }
      }
      .scrollClipDisabled()
    }
  }

  private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.title2.weight(.semibold))
        .frame(width: 56, height: 56)
        .background(Circle().fill(tint.opacity(0.18)))
        .foregroundStyle(tint)
    }
    .buttonStyle(.pressable)
    .accessibilityLabel(symbol == "plus" ? "More" : "Less")
  }

  private func adjust(_ steps: Double) {
    let stepMl = Volume.ml(from: Volume.step(for: unit), unit: unit)
    withAnimation(Motion.standard) {
      ml = max(0, Volume.roundedMl(ml + steps * stepMl, unit: unit))
    }
  }
}

// MARK: - Bottle

struct BottleSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let snapshot: NestSnapshot

  @State private var ml: Double
  @State private var contents: BottleContents
  @State private var date = Date()
  @State private var showsMore = false
  @State private var offeredMl: Double
  @State private var tracksOffered = false
  @State private var brand: String
  @State private var note = ""

  init(snapshot: NestSnapshot) {
    self.snapshot = snapshot
    let amount = snapshot.defaultBottleMl ?? Volume.roundedMl(90, unit: snapshot.unit)
    _ml = State(initialValue: amount)
    _offeredMl = State(initialValue: amount)
    _contents = State(initialValue: snapshot.defaultBottleContents)
    _brand = State(initialValue: snapshot.baby?.formulaBrand ?? "")
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        AmountControl(ml: $ml, unit: snapshot.unit)
          .frame(maxWidth: .infinity)

        Picker("Contents", selection: $contents) {
          ForEach(BottleContents.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)

        BackdatePicker(date: $date, label: "Fed at")

        DisclosureGroup("More", isExpanded: $showsMore) {
          VStack(alignment: .leading, spacing: 12) {
            Toggle("Offered a different amount", isOn: $tracksOffered)
            if tracksOffered {
              Text("Offered").font(.subheadline.weight(.semibold))
              AmountControl(ml: $offeredMl, unit: snapshot.unit)
            }
            if contents != .breastMilk {
              TextField("Formula brand", text: $brand)
                .textFieldStyle(.roundedBorder)
            }
            TextField("Note (optional)", text: $note, axis: .vertical)
              .textFieldStyle(.roundedBorder)
          }
          .padding(.top, 8)
        }
      }
      .padding()
    }
    .safeAreaInset(edge: .bottom) {
      PrimaryButton(title: "Log \(Volume.format(ml: ml, unit: snapshot.unit))", systemImage: "checkmark", tint: EventKind.bottle.color) {
        save()
      }
      .padding()
      .disabled(ml <= 0)
    }
  }

  private func save() {
    let message = "Logged \(Volume.format(ml: ml, unit: snapshot.unit)) \(contents.title.lowercased())"
    let (ml, contents, date, note) = (ml, contents, date, note)
    let offered = tracksOffered ? offeredMl : nil
    let formulaBrand = contents == .breastMilk || brand.isEmpty ? nil : brand
    model.startFeed(title: "Log bottle", sleepRunning: snapshot.activeSleep != nil) { endSleep in
      model.perform(message) {
        try model.store.logBottle(
          amountMl: ml, contents: contents, offeredMl: offered, formulaBrand: formulaBrand, at: date, note: note,
          endSleep: endSleep)
      }
    }
    dismiss()
  }
}

// MARK: - Nursing

struct NursingSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let snapshot: NestSnapshot

  @State private var startSide: Side
  @State private var date = Date()
  @State private var showsPast = false
  @State private var leftMinutes = 10.0
  @State private var rightMinutes = 10.0
  @State private var endedOn: Side = .right
  @State private var latchNote = ""

  init(snapshot: NestSnapshot) {
    self.snapshot = snapshot
    _startSide = State(initialValue: snapshot.nextSide)
    _endedOn = State(initialValue: snapshot.nextSide)
  }

  var body: some View {
    if let active = snapshot.activeNursing {
      RunningNursingView(active: active, snapshot: snapshot, latchNote: $latchNote)
    } else {
      startView
    }
  }

  private var startView: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        SideSelector(side: $startSide)
        Text("Suggested: \(snapshot.nextSide.title) (opposite of where the last feed ended)")
          .font(.footnote)
          .foregroundStyle(.secondary)
        BackdatePicker(date: $date, label: "Started")

        DisclosureGroup("Log a past session instead", isExpanded: $showsPast) {
          VStack(alignment: .leading, spacing: 12) {
            Stepper("Left \(Int(leftMinutes)) min", value: $leftMinutes, in: 0...90, step: 1)
            Stepper("Right \(Int(rightMinutes)) min", value: $rightMinutes, in: 0...90, step: 1)
            Picker("Ended on", selection: $endedOn) {
              ForEach(Side.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            PrimaryButton(title: "Log session", systemImage: "checkmark", tint: EventKind.nursing.color) {
              logPast()
            }
            .disabled(leftMinutes + rightMinutes == 0)
          }
          .padding(.top, 8)
        }
      }
      .padding()
    }
    .safeAreaInset(edge: .bottom) {
      if !showsPast {
        PrimaryButton(title: "Start on \(startSide.title)", systemImage: "play.fill", tint: EventKind.nursing.color) {
          start()
        }
        .padding()
      }
    }
  }

  private func start() {
    let (side, date) = (startSide, date)
    model.startFeed(title: "Start nursing", sleepRunning: snapshot.activeSleep != nil) { endSleep in
      model.perform("Nursing on \(side.title.lowercased())", haptic: .impact) {
        try model.store.startNursing(side: side, at: date, endSleep: endSleep)
      }
    }
  }

  private func logPast() {
    let (l, r, endedOn, date) = (leftMinutes * 60, rightMinutes * 60, endedOn, date)
    model.perform("Logged \(Durations.format(l + r)) nursing") {
      try model.store.logNursing(leftSeconds: l, rightSeconds: r, endedOn: endedOn, at: date, note: "")
    }
    dismiss()
  }
}

/// Two big halves, L and R; the highlight slides to the chosen side with a spring.
struct SideSelector: View {
  @Binding var side: Side
  var tint: Color = EventKind.nursing.color
  @Namespace private var highlight

  var body: some View {
    HStack(spacing: 8) {
      ForEach(Side.allCases, id: \.self) { option in
        Button {
          side = option
        } label: {
          Text(option.title)
            .font(.title3.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 72)
            .foregroundStyle(side == option ? .white : tint)
            .background {
              if side == option {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                  .fill(tint)
                  .matchedGeometryEffect(id: "highlight", in: highlight)
              }
            }
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(side == option ? .isSelected : [])
      }
    }
    .padding(6)
    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(tint.opacity(0.12)))
    .nestAnimation(Motion.sideSwitch, value: side)
    .sensoryFeedback(.selection, trigger: side)
  }
}

struct RunningNursingView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let active: ActiveNursing
  let snapshot: NestSnapshot
  @Binding var latchNote: String

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let totals = active.totals(now: context.date)
      let left = totals.left
      let right = totals.right
      ScrollView {
        VStack(spacing: 20) {
          Group {
            if active.isPaused {
              Text(Durations.clock(left + right))
            } else {
              Text(timerInterval: active.effectiveStart(now: context.date)...Date.distantFuture, countsDown: false)
            }
          }
          .font(.system(size: 64, weight: .semibold, design: .rounded))
          .monospacedDigit()
          .accessibilityLabel("Total \(Durations.spoken(left + right))")

          HStack(spacing: 8) {
            sideColumn(.left, seconds: left)
            sideColumn(.right, seconds: right)
          }
          .nestAnimation(Motion.sideSwitch, value: active.currentSide)

          HStack(spacing: 12) {
            Button {
              model.perform(nil, haptic: .selection) { try model.store.switchNursingSide(at: Date()) }
            } label: {
              Label("Switch to \(active.currentSide.opposite.title)", systemImage: "arrow.left.arrow.right")
                .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)

            Button {
              model.perform(nil, haptic: .selection) {
                if active.isPaused {
                  return try model.store.resumeNursing(at: Date())
                }
                return try model.store.pauseNursing(at: Date())
              }
            } label: {
              Label(active.isPaused ? "Resume" : "Pause", systemImage: active.isPaused ? "play.fill" : "pause.fill")
                .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
          }
          .tint(EventKind.nursing.color)

          TextField("Latch note (optional)", text: $latchNote, axis: .vertical)
            .textFieldStyle(.roundedBorder)

          Text("Started by \(active.session.loggedBy.isEmpty ? "someone" : active.session.loggedBy) at \(active.session.startedAt.formatted(date: .omitted, time: .shortened))")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding()
      }
      .safeAreaInset(edge: .bottom) {
        PrimaryButton(title: "Stop", systemImage: "stop.fill", tint: EventKind.nursing.color) {
          let running = Entry.nursing(active.session, segments: active.segments)
          let note = latchNote.isEmpty ? nil : latchNote
          model.perform("Nursed \(Durations.format(left + right))", undo: .restoreVersion(running)) {
            try model.store.stopNursing(at: Date(), latchNote: note)
          }
          dismiss()
        }
        .padding()
      }
    }
  }

  private func sideColumn(_ side: Side, seconds: TimeInterval) -> some View {
    let isCurrent = active.currentSide == side
    return VStack(spacing: 6) {
      Text(side.title).font(.headline)
      Text(Durations.clock(seconds))
        .font(.status(.title2))
        .monospacedDigit()
        .contentTransition(.numericText())
    }
    .frame(maxWidth: .infinity, minHeight: 96)
    .foregroundStyle(isCurrent ? .white : EventKind.nursing.color)
    .background(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .fill(isCurrent ? EventKind.nursing.color : EventKind.nursing.color.opacity(0.12))
    )
    .accessibilityElement(children: .combine)
    .accessibilityValue(isCurrent ? "current side" : "")
  }
}

// MARK: - Pump

struct PumpSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let snapshot: NestSnapshot

  @State private var leftMl = 60.0
  @State private var rightMl = 60.0
  @State private var destination: PumpDestination = .fridge
  @State private var date = Date()
  @State private var showsPast = false
  @State private var minutes = 15.0

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        if let pump = snapshot.activePump {
          Text(timerInterval: pump.startedAt...Date.distantFuture, countsDown: false)
            .font(.system(size: 56, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .frame(maxWidth: .infinity)
          volumeFields
        } else {
          BackdatePicker(date: $date, label: "Started")
          DisclosureGroup("Log a past session instead", isExpanded: $showsPast) {
            VStack(alignment: .leading, spacing: 12) {
              Stepper("\(Int(minutes)) min", value: $minutes, in: 1...90)
              volumeFields
            }
            .padding(.top, 8)
          }
        }
      }
      .padding()
    }
    .safeAreaInset(edge: .bottom) {
      Group {
        if let pump = snapshot.activePump {
          PrimaryButton(title: "Stop and save", systemImage: "stop.fill", tint: EventKind.pump.color) {
            let (l, r, d) = (leftMl, rightMl, destination)
            model.perform("Logged \(Volume.format(ml: l + r, unit: snapshot.unit)) pumped", undo: .restoreVersion(.pump(pump))) {
              try model.store.stopPump(leftMl: l, rightMl: r, destination: d, at: Date())
            }
            dismiss()
          }
        } else if showsPast {
          PrimaryButton(title: "Log session", systemImage: "checkmark", tint: EventKind.pump.color) {
            let (l, r, d, start, length) = (leftMl, rightMl, destination, date, minutes * 60)
            model.perform("Logged \(Volume.format(ml: l + r, unit: snapshot.unit)) pumped") {
              try model.store.startPump(at: start)
              return try model.store.stopPump(leftMl: l, rightMl: r, destination: d, at: start.addingTimeInterval(length))
            }
            dismiss()
          }
        } else {
          PrimaryButton(title: "Start pumping", systemImage: "play.fill", tint: EventKind.pump.color) {
            let start = date
            model.perform("Pump timer started", haptic: .impact) { try model.store.startPump(at: start) }
          }
        }
      }
      .padding()
    }
  }

  private var volumeFields: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Left").font(.subheadline.weight(.semibold))
      AmountControl(ml: $leftMl, unit: snapshot.unit, tint: EventKind.pump.color)
      Text("Right").font(.subheadline.weight(.semibold))
      AmountControl(ml: $rightMl, unit: snapshot.unit, tint: EventKind.pump.color)
      Picker("Destination", selection: $destination) {
        ForEach(PumpDestination.allCases, id: \.self) { Text($0.title).tag($0) }
      }
      .pickerStyle(.segmented)
    }
  }
}

// MARK: - Diaper

struct DiaperSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let snapshot: NestSnapshot

  @State private var kind: DiaperKind?
  @State private var color: StoolColor?
  @State private var consistency: StoolConsistency?
  @State private var size: DiaperSize?
  @State private var rash = false
  @State private var date = Date()
  @State private var note = ""

  private var ageInDays: Int? {
    snapshot.baby?.birthDate.map { AgeMath.days(from: $0, to: date) }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
          ForEach(DiaperKind.allCases, id: \.self) { option in
            Button {
              choose(option)
            } label: {
              VStack(spacing: 6) {
                Image(systemName: symbol(option)).font(.title)
                Text(option.title).font(.headline)
              }
              .frame(maxWidth: .infinity, minHeight: 88)
              .foregroundStyle(kind == option ? .white : EventKind.diaper.color)
              .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                  .fill(kind == option ? EventKind.diaper.color : EventKind.diaper.color.opacity(0.14)))
            }
            .buttonStyle(.pressable)
            .accessibilityHint(option.hasStool ? "Then choose colour" : "Logs immediately")
          }
        }

        if kind?.hasStool == true {
          stoolDetails
            .transition(.opacity.combined(with: .move(edge: .top)))
        }

        BackdatePicker(date: $date, label: "Changed at")
        TextField("Note (optional)", text: $note, axis: .vertical)
          .textFieldStyle(.roundedBorder)
      }
      .padding()
      .nestAnimation(value: kind)
    }
    .safeAreaInset(edge: .bottom) {
      if let kind, kind.hasStool {
        PrimaryButton(title: "Log \(kind.title.lowercased())", systemImage: "checkmark", tint: EventKind.diaper.color) {
          save(kind)
        }
        .padding()
      }
    }
  }

  private var stoolDetails: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Colour").font(.subheadline.weight(.semibold))
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
        ForEach(StoolColor.allCases, id: \.self) { swatch in
          Button {
            color = color == swatch ? nil : swatch
          } label: {
            Circle()
              .fill(swatch.swatch)
              .frame(width: 44, height: 44)
              .overlay(Circle().strokeBorder(color == swatch ? Color.primary : .clear, lineWidth: 3))
              .overlay(Circle().strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1))
          }
          .buttonStyle(.pressable)
          .accessibilityLabel(swatch.title)
          .accessibilityAddTraits(color == swatch ? .isSelected : [])
        }
      }
      if let color {
        Text(color.title).font(.footnote).foregroundStyle(.secondary)
      }
      if let color, color.isWorthACall(ageInDays: ageInDays) {
        Label(HealthFlag.callPediatrician, systemImage: "phone.fill")
          .font(.subheadline.weight(.semibold))
          .padding(12)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(RoundedRectangle(cornerRadius: 14).fill(Color.orange.opacity(0.2)))
          .accessibilityAddTraits(.isStaticText)
      }

      Text("Consistency").font(.subheadline.weight(.semibold))
      FlowChips(options: StoolConsistency.allCases, selection: $consistency, title: \.title)

      Text("Size").font(.subheadline.weight(.semibold))
      FlowChips(options: DiaperSize.allCases, selection: $size, title: \.title)

      Toggle("Rash", isOn: $rash)
    }
  }

  private func symbol(_ kind: DiaperKind) -> String {
    switch kind {
    case .wet: "drop.fill"
    case .dirty: "circle.fill"
    case .mixed: "drop.circle.fill"
    case .dry: "sun.max.fill"
    }
  }

  /// Wet and dry log in one tap; dirty and mixed open stool details first.
  private func choose(_ option: DiaperKind) {
    kind = option
    if !option.hasStool { save(option) }
  }

  private func save(_ kind: DiaperKind) {
    let (color, consistency, size, rash, date, note) = (color, consistency, size, rash, date, note)
    model.perform("Logged \(kind.title.lowercased()) diaper") {
      try model.store.logDiaper(
        kind: kind, stoolColor: color, consistency: consistency, size: size, rash: rash, at: date, note: note)
    }
    dismiss()
  }
}

/// Single-select chips for small enums.
struct FlowChips<Option: Hashable>: View {
  let options: [Option]
  @Binding var selection: Option?
  let title: KeyPath<Option, String>

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(options, id: \.self) { option in
          Chip(title: option[keyPath: title], isSelected: selection == option) {
            selection = selection == option ? nil : option
          }
        }
      }
    }
    .scrollClipDisabled()
  }
}

// MARK: - Sleep

struct SleepSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let snapshot: NestSnapshot

  @State private var location: SleepLocation?
  @State private var date = Date()
  @State private var showsPast = false
  @State private var pastStart = Date().addingTimeInterval(-3600)
  @State private var pastEnd = Date()

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        if let sleep = snapshot.activeSleep {
          Text(timerInterval: sleep.startedAt...Date.distantFuture, countsDown: false)
            .font(.system(size: 56, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .frame(maxWidth: .infinity)
          Text("Asleep since \(sleep.startedAt.formatted(date: .omitted, time: .shortened))\(sleep.location.map { " · \($0.title)" } ?? "")")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
          BackdatePicker(date: $date, label: "Woke at")
        } else {
          Text("Where").font(.subheadline.weight(.semibold))
          FlowChips(options: SleepLocation.allCases, selection: $location, title: \.title)
          BackdatePicker(date: $date, label: "Fell asleep")
          DisclosureGroup("Log a past sleep instead", isExpanded: $showsPast) {
            VStack(alignment: .leading) {
              DatePicker("Fell asleep", selection: $pastStart, in: ...Date())
              DatePicker("Woke", selection: $pastEnd, in: pastStart...Date())
            }
            .padding(.top, 8)
          }
        }
      }
      .padding()
    }
    .safeAreaInset(edge: .bottom) {
      Group {
        if let sleep = snapshot.activeSleep {
          PrimaryButton(title: "Awake", systemImage: "sun.max.fill", tint: EventKind.sleep.color) {
            let end = date
            model.perform("Slept \(Durations.format(end.timeIntervalSince(sleep.startedAt)))", undo: .restoreVersion(.sleep(sleep))) {
              try model.store.stopSleep(at: end)
            }
            dismiss()
          }
        } else if showsPast {
          PrimaryButton(title: "Log sleep", systemImage: "checkmark", tint: EventKind.sleep.color) {
            let (start, end, location) = (pastStart, pastEnd, location)
            model.perform("Logged \(Durations.format(end.timeIntervalSince(start))) sleep") {
              try model.store.startSleep(location: location, at: start)
              return try model.store.stopSleep(at: end)
            }
            dismiss()
          }
        } else {
          PrimaryButton(title: "Start sleep", systemImage: "moon.zzz.fill", tint: EventKind.sleep.color) {
            let (start, location) = (date, location)
            model.perform("Sleep timer started", haptic: .impact) {
              try model.store.startSleep(location: location, at: start)
            }
            dismiss()
          }
        }
      }
      .padding()
    }
  }
}

// MARK: - Note

struct NoteSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var text = ""
  @State private var tag: NoteTag?
  @State private var date = Date()
  @FocusState private var focused: Bool

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        TextField("What happened? Tap the mic to dictate.", text: $text, axis: .vertical)
          .lineLimit(3...8)
          .textFieldStyle(.roundedBorder)
          .focused($focused)
        FlowChips(options: NoteTag.allCases, selection: $tag, title: \.title)
        BackdatePicker(date: $date)
      }
      .padding()
    }
    .safeAreaInset(edge: .bottom) {
      PrimaryButton(title: "Save note", systemImage: "checkmark", tint: EventKind.note.color) {
        let (text, tag, date) = (text, tag, date)
        model.perform("Note saved") { try model.store.logNote(text: text, tag: tag, at: date) }
        dismiss()
      }
      .padding()
      .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty && tag == nil)
    }
    .onAppear { focused = true }
  }
}
