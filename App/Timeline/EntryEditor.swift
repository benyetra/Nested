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

/// A Binding onto a copy that writes back through `update`.
private func binding<T>(_ value: T, _ update: @escaping (T) -> Void) -> Binding<T> {
  Binding(get: { value }, set: update)
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

private struct BottleFields: View {
  let bottle: Bottle
  let unit: VolumeUnit
  let update: (Bottle) -> Void

  var body: some View {
    Section {
      DatePicker("Time", selection: field(\.startedAt), in: ...Date())
      VolumeField(title: "Finished", ml: field(\.amountMl), unit: unit)
      Picker("Contents", selection: field(\.contents)) {
        ForEach(BottleContents.allCases, id: \.self) { Text($0.title).tag($0) }
      }
      VolumeField(
        title: "Offered",
        ml: binding(bottle.offeredMl ?? bottle.amountMl) { var b = bottle; b.offeredMl = $0; update(b) },
        unit: unit)
      TextField("Formula brand", text: binding(bottle.formulaBrand ?? "") { var b = bottle; b.formulaBrand = $0.isEmpty ? nil : $0; update(b) })
      TextField("Note", text: field(\.note), axis: .vertical)
    }
  }

  private func field<V>(_ keyPath: WritableKeyPath<Bottle, V>) -> Binding<V> {
    binding(bottle[keyPath: keyPath]) { var b = bottle; b[keyPath: keyPath] = $0; update(b) }
  }
}

private struct NursingFields: View {
  let session: NursingSession
  let segments: [NursingSegment]
  let update: (NursingSession, [NursingSegment]) -> Void

  var body: some View {
    Section("Session") {
      DatePicker(
        "Started",
        selection: binding(session.startedAt) { newStart in
          // Move the whole session, keeping its shape.
          let offset = newStart.timeIntervalSince(session.startedAt)
          var s = session
          s.startedAt = newStart
          s.endedAt = s.endedAt?.addingTimeInterval(offset)
          update(s, segments.map { var seg = $0; seg.startedAt += offset; seg.endedAt = seg.endedAt?.addingTimeInterval(offset); return seg })
        },
        in: ...Date())
      if let ended = session.endedOnSide {
        Picker("Ended on", selection: binding(ended) { var s = session; s.endedOnSide = $0; update(s, segments) }) {
          ForEach(Side.allCases, id: \.self) { Text($0.title).tag($0) }
        }
      }
      TextField("Latch note", text: binding(session.latchNote) { var s = session; s.latchNote = $0; update(s, segments) })
      TextField("Note", text: binding(session.note) { var s = session; s.note = $0; update(s, segments) }, axis: .vertical)
    }
    Section("Sides") {
      ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
        Stepper(
          value: binding((segment.duration(now: Date()) / 60).rounded()) { minutes in
            var updated = segments
            updated[index].endedAt = segment.startedAt.addingTimeInterval(max(0, minutes) * 60)
            // Keep later segments back to back.
            for i in updated.indices where i > index {
              let length = updated[i].duration(now: Date())
              updated[i].startedAt = updated[i - 1].endedAt ?? updated[i].startedAt
              updated[i].endedAt = updated[i].startedAt.addingTimeInterval(length)
            }
            var s = session
            if s.endedAt != nil { s.endedAt = updated.last?.endedAt }
            update(s, updated)
          },
          in: 0...120
        ) {
          HStack {
            Text(segment.side.title)
            Spacer()
            Text(Durations.format(segment.duration(now: Date()))).monospacedDigit().foregroundStyle(.secondary)
          }
        }
        .disabled(segment.endedAt == nil)
      }
    }
  }
}

private struct PumpFields: View {
  let pump: PumpSession
  let unit: VolumeUnit
  let update: (PumpSession) -> Void

  var body: some View {
    Section {
      DatePicker("Started", selection: binding(pump.startedAt) { var p = pump; p.startedAt = $0; update(p) }, in: ...Date())
      if let end = pump.endedAt {
        DatePicker("Ended", selection: binding(end) { var p = pump; p.endedAt = $0; update(p) }, in: pump.startedAt...Date())
      }
      VolumeField(title: "Left", ml: binding(pump.leftMl ?? 0) { var p = pump; p.leftMl = $0; update(p) }, unit: unit)
      VolumeField(title: "Right", ml: binding(pump.rightMl ?? 0) { var p = pump; p.rightMl = $0; update(p) }, unit: unit)
      Picker("Destination", selection: binding(pump.destination) { var p = pump; p.destination = $0; update(p) }) {
        Text("None").tag(PumpDestination?.none)
        ForEach(PumpDestination.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
      }
      TextField("Note", text: binding(pump.note) { var p = pump; p.note = $0; update(p) }, axis: .vertical)
    }
  }
}

private struct DiaperFields: View {
  let diaper: Diaper
  let update: (Diaper) -> Void

  var body: some View {
    Section {
      DatePicker("Time", selection: binding(diaper.occurredAt) { var d = diaper; d.occurredAt = $0; update(d) }, in: ...Date())
      Picker("Type", selection: binding(diaper.kind) { var d = diaper; d.kind = $0; update(d) }) {
        ForEach(DiaperKind.allCases, id: \.self) { Text($0.title).tag($0) }
      }
      if diaper.kind.hasStool {
        Picker("Colour", selection: binding(diaper.stoolColor) { var d = diaper; d.stoolColor = $0; update(d) }) {
          Text("Not noted").tag(StoolColor?.none)
          ForEach(StoolColor.allCases, id: \.self) { color in
            Label { Text(color.title) } icon: { Circle().fill(color.swatch) }.tag(Optional(color))
          }
        }
        Picker("Consistency", selection: binding(diaper.consistency) { var d = diaper; d.consistency = $0; update(d) }) {
          Text("Not noted").tag(StoolConsistency?.none)
          ForEach(StoolConsistency.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
        }
      }
      Picker("Size", selection: binding(diaper.size) { var d = diaper; d.size = $0; update(d) }) {
        Text("Not noted").tag(DiaperSize?.none)
        ForEach(DiaperSize.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
      }
      Toggle("Rash", isOn: binding(diaper.rash) { var d = diaper; d.rash = $0; update(d) })
      TextField("Note", text: binding(diaper.note) { var d = diaper; d.note = $0; update(d) }, axis: .vertical)
    }
  }
}

private struct SleepFields: View {
  let sleep: SleepSession
  let update: (SleepSession) -> Void

  var body: some View {
    Section {
      DatePicker("Fell asleep", selection: binding(sleep.startedAt) { var s = sleep; s.startedAt = $0; update(s) }, in: ...Date())
      if let end = sleep.endedAt {
        DatePicker("Woke", selection: binding(end) { var s = sleep; s.endedAt = $0; update(s) }, in: sleep.startedAt...Date())
      }
      Picker("Location", selection: binding(sleep.location) { var s = sleep; s.location = $0; update(s) }) {
        Text("Not noted").tag(SleepLocation?.none)
        ForEach(SleepLocation.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
      }
      TextField("Note", text: binding(sleep.note) { var s = sleep; s.note = $0; update(s) }, axis: .vertical)
    }
  }
}

private struct NoteFields: View {
  let note: BabyNote
  let update: (BabyNote) -> Void

  var body: some View {
    Section {
      DatePicker("Time", selection: binding(note.occurredAt) { var n = note; n.occurredAt = $0; update(n) }, in: ...Date())
      Picker("Tag", selection: binding(note.tag) { var n = note; n.tag = $0; update(n) }) {
        Text("None").tag(NoteTag?.none)
        ForEach(NoteTag.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
      }
      TextField("Note", text: binding(note.text) { var n = note; n.text = $0; update(n) }, axis: .vertical)
        .lineLimit(3...10)
    }
  }
}
