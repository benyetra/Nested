import NestCore
import NestData
import SQLiteData
import SwiftUI

/// Edits every field of an entry. Saving keeps the previous version in the entry's history
/// (the conflict rule: the later edit wins, the earlier one is kept).
struct EntryEditor: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let original: Entry
  let unit: VolumeUnit
  @State private var entry: Entry
  @Fetch private var revisions: [EntryRevision]

  init(entry: Entry, unit: VolumeUnit) {
    self.original = entry
    self.unit = unit
    _entry = State(initialValue: entry)
    _revisions = Fetch(wrappedValue: [], RevisionsRequest(entryID: entry.id))
  }

  var body: some View {
    NavigationStack {
      Form {
        fields
        if !revisions.isEmpty {
          Section("Earlier versions") {
            ForEach(revisions) { revision in
              VStack(alignment: .leading, spacing: 2) {
                Text(previousTitle(revision)).font(.subheadline)
                Text("Changed by \(revision.editedBy.isEmpty ? "someone" : revision.editedBy) · \(revision.editedAt.formatted(date: .abbreviated, time: .shortened))")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }
        }
        Section {
          Button("Delete", role: .destructive) {
            model.delete(original, unit: unit)
            dismiss()
          }
        }
      }
      .navigationTitle("Edit \(original.kind.title.lowercased())")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            model.save(entry, original: original)
            dismiss()
          }
          .disabled(entry == original)
        }
      }
    }
  }

  private func previousTitle(_ revision: EntryRevision) -> String {
    guard let data = revision.snapshot.data(using: .utf8),
      let previous = try? JSONDecoder().decode(Entry.self, from: data)
    else { return "Previous version" }
    return "\(previous.title(unit: unit)) at \(previous.date.formatted(date: .omitted, time: .shortened))"
  }

  @ViewBuilder
  private var fields: some View {
    switch entry {
    case .bottle(let bottle):
      BottleFields(bottle: bottle, unit: unit) { entry = .bottle($0) }
    case .nursing(let session, let segments):
      NursingFields(session: session, segments: segments) { entry = .nursing($0, segments: $1) }
    case .pump(let pump):
      PumpFields(pump: pump, unit: unit) { entry = .pump($0) }
    case .diaper(let diaper):
      DiaperFields(diaper: diaper) { entry = .diaper($0) }
    case .sleep(let sleep):
      SleepFields(sleep: sleep) { entry = .sleep($0) }
    case .note(let note):
      NoteFields(note: note) { entry = .note($0) }
    }
  }
}

extension Binding where Value: Sendable {
  /// A non-optional view of an optional binding; writing stores the value.
  func orDefault<T: Sendable>(_ fallback: T) -> Binding<T> where Value == T? {
    Binding<T>(get: { wrappedValue ?? fallback }, set: { wrappedValue = $0 })
  }
}

private struct VolumeField: View {
  let title: String
  @Binding var ml: Double
  let unit: VolumeUnit

  var body: some View {
    Stepper(value: $ml, in: 0...1000, step: Volume.ml(from: Volume.step(for: unit), unit: unit)) {
      HStack {
        Text(title)
        Spacer()
        Text(Volume.format(ml: ml, unit: unit)).monospacedDigit().foregroundStyle(.secondary)
      }
    }
  }
}

// Each field view edits a local copy and reports changes through `update`.

private struct BottleFields: View {
  @State private var value: Bottle
  let unit: VolumeUnit
  let update: (Bottle) -> Void

  init(bottle: Bottle, unit: VolumeUnit, update: @escaping (Bottle) -> Void) {
    _value = State(initialValue: bottle)
    self.unit = unit
    self.update = update
  }

  var body: some View {
    Section {
      DatePicker("Time", selection: $value.startedAt, in: ...Date())
      VolumeField(title: "Finished", ml: $value.amountMl, unit: unit)
      Picker("Contents", selection: $value.contents) {
        ForEach(BottleContents.allCases, id: \.self) { Text($0.title).tag($0) }
      }
      VolumeField(title: "Offered", ml: $value.offeredMl.orDefault(value.amountMl), unit: unit)
      TextField("Formula brand", text: $value.formulaBrand.orDefault(""))
      TextField("Note", text: $value.note, axis: .vertical)
    }
    .onChange(of: value) { _, new in update(new) }
  }
}

private struct NursingFields: View {
  @State private var session: NursingSession
  @State private var segments: [NursingSegment]
  @State private var minutes: [Double]
  let update: (NursingSession, [NursingSegment]) -> Void

  init(session: NursingSession, segments: [NursingSegment], update: @escaping (NursingSession, [NursingSegment]) -> Void) {
    _session = State(initialValue: session)
    _segments = State(initialValue: segments)
    _minutes = State(initialValue: segments.map { ($0.duration(now: Date()) / 60).rounded() })
    self.update = update
  }

  var body: some View {
    Section("Session") {
      DatePicker("Started", selection: $session.startedAt, in: ...Date())
      if session.endedOnSide != nil {
        Picker("Ended on", selection: $session.endedOnSide) {
          ForEach(Side.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
        }
      }
      TextField("Latch note", text: $session.latchNote)
      TextField("Note", text: $session.note, axis: .vertical)
    }
    Section("Sides") {
      ForEach(segments.indices, id: \.self) { index in
        Stepper(value: $minutes[index], in: 0...120) {
          HStack {
            Text(segments[index].side.title)
            Spacer()
            Text("\(Int(minutes[index])) min").monospacedDigit().foregroundStyle(.secondary)
          }
        }
        .disabled(segments[index].endedAt == nil)
      }
    }
    .onChange(of: session.startedAt) { old, new in
      // Move the whole session, keeping its shape.
      let offset = new.timeIntervalSince(old)
      session.endedAt = session.endedAt?.addingTimeInterval(offset)
      segments = segments.map {
        var segment = $0
        segment.startedAt = segment.startedAt.addingTimeInterval(offset)
        segment.endedAt = segment.endedAt?.addingTimeInterval(offset)
        return segment
      }
    }
    .onChange(of: minutes) { _, new in
      // Lay finished segments back to back with the edited lengths.
      var cursor = segments.first?.startedAt ?? session.startedAt
      for index in segments.indices where segments[index].endedAt != nil {
        segments[index].startedAt = cursor
        segments[index].endedAt = cursor.addingTimeInterval(max(0, new[index]) * 60)
        cursor = segments[index].endedAt ?? cursor
      }
      if session.endedAt != nil { session.endedAt = segments.last?.endedAt }
    }
    .onChange(of: session) { _, new in update(new, segments) }
    .onChange(of: segments) { _, new in update(session, new) }
  }
}

private struct PumpFields: View {
  @State private var value: PumpSession
  let unit: VolumeUnit
  let update: (PumpSession) -> Void

  init(pump: PumpSession, unit: VolumeUnit, update: @escaping (PumpSession) -> Void) {
    _value = State(initialValue: pump)
    self.unit = unit
    self.update = update
  }

  var body: some View {
    Section {
      DatePicker("Started", selection: $value.startedAt, in: ...Date())
      if value.endedAt != nil {
        DatePicker("Ended", selection: $value.endedAt.orDefault(value.startedAt), in: value.startedAt...Date())
      }
      VolumeField(title: "Left", ml: $value.leftMl.orDefault(0), unit: unit)
      VolumeField(title: "Right", ml: $value.rightMl.orDefault(0), unit: unit)
      Picker("Destination", selection: $value.destination) {
        Text("None").tag(PumpDestination?.none)
        ForEach(PumpDestination.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
      }
      TextField("Note", text: $value.note, axis: .vertical)
    }
    .onChange(of: value) { _, new in update(new) }
  }
}

private struct DiaperFields: View {
  @State private var value: Diaper
  let update: (Diaper) -> Void

  init(diaper: Diaper, update: @escaping (Diaper) -> Void) {
    _value = State(initialValue: diaper)
    self.update = update
  }

  var body: some View {
    Section {
      DatePicker("Time", selection: $value.occurredAt, in: ...Date())
      Picker("Type", selection: $value.kind) {
        ForEach(DiaperKind.allCases, id: \.self) { Text($0.title).tag($0) }
      }
      if value.kind.hasStool {
        Picker("Colour", selection: $value.stoolColor) {
          Text("Not noted").tag(StoolColor?.none)
          ForEach(StoolColor.allCases, id: \.self) { color in
            Label { Text(color.title) } icon: { Circle().fill(color.swatch) }.tag(Optional(color))
          }
        }
        Picker("Consistency", selection: $value.consistency) {
          Text("Not noted").tag(StoolConsistency?.none)
          ForEach(StoolConsistency.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
        }
      }
      Picker("Size", selection: $value.size) {
        Text("Not noted").tag(DiaperSize?.none)
        ForEach(DiaperSize.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
      }
      Toggle("Rash", isOn: $value.rash)
      TextField("Note", text: $value.note, axis: .vertical)
    }
    .onChange(of: value) { _, new in update(new) }
  }
}

private struct SleepFields: View {
  @State private var value: SleepSession
  let update: (SleepSession) -> Void

  init(sleep: SleepSession, update: @escaping (SleepSession) -> Void) {
    _value = State(initialValue: sleep)
    self.update = update
  }

  var body: some View {
    Section {
      DatePicker("Fell asleep", selection: $value.startedAt, in: ...Date())
      if value.endedAt != nil {
        DatePicker("Woke", selection: $value.endedAt.orDefault(value.startedAt), in: value.startedAt...Date())
      }
      Picker("Location", selection: $value.location) {
        Text("Not noted").tag(SleepLocation?.none)
        ForEach(SleepLocation.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
      }
      TextField("Note", text: $value.note, axis: .vertical)
    }
    .onChange(of: value) { _, new in update(new) }
  }
}

private struct NoteFields: View {
  @State private var value: BabyNote
  let update: (BabyNote) -> Void

  init(note: BabyNote, update: @escaping (BabyNote) -> Void) {
    _value = State(initialValue: note)
    self.update = update
  }

  var body: some View {
    Section {
      DatePicker("Time", selection: $value.occurredAt, in: ...Date())
      Picker("Tag", selection: $value.tag) {
        Text("None").tag(NoteTag?.none)
        ForEach(NoteTag.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
      }
      TextField("Note", text: $value.text, axis: .vertical)
        .lineLimit(3...10)
    }
    .onChange(of: value) { _, new in update(new) }
  }
}
