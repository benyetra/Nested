import NestedCore
import NestedData
import SwiftUI

/// Add or change a medicine: what it is, who takes it, how much, and how often.
struct MedicationEditor: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  private var snapshot: NestedSnapshot { SideEffects.shared.snapshot }

  @State private var draft: Medication
  @State private var hasEnd: Bool
  @State private var confirmingDelete = false
  private let isNew: Bool

  init(medication: Medication) {
    _draft = State(initialValue: medication)
    _hasEnd = State(initialValue: medication.endsAt != nil)
    isNew = medication.name.isEmpty && medication.editedAt == medication.createdAt
  }

  private var everyHours: Binding<Int> {
    Binding(
      get: { max(1, draft.intervalMinutes / 60) },
      set: { draft.intervalMinutes = $0 * 60 })
  }

  private var minimumGapHours: Binding<Int> {
    Binding(get: { draft.intervalMinutes / 60 }, set: { draft.intervalMinutes = $0 * 60 })
  }

  private var parents: [String] {
    var names = snapshot.devices.map(\.ownerName).filter { !$0.isEmpty }
    if !snapshot.me.isEmpty, !names.contains(snapshot.me) { names.insert(snapshot.me, at: 0) }
    return Array(Set(names)).sorted()
  }

  private var canSave: Bool {
    guard !draft.name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
    switch draft.cadence {
    case .fixedTimes: return !draft.times.isEmpty
    case .everyHours: return draft.intervalMinutes >= 60
    case .asNeeded: return true
    }
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Medicine") {
          TextField("Name, e.g. Vitamin D", text: $draft.name)
            .textInputAutocapitalization(.words)
          TextField("Dose, e.g. 1 mL", text: $draft.dose)
        }

        Section("Who takes it") {
          Picker("For", selection: $draft.forWho) {
            Text(snapshot.babyName).tag("")
            ForEach(parents, id: \.self) { Text($0).tag($0) }
          }
        }

        Section("How often") {
          Picker("Schedule", selection: $draft.cadence) {
            Text("Set times").tag(MedicationCadence.fixedTimes)
            Text("Every few hours").tag(MedicationCadence.everyHours)
            Text("As needed").tag(MedicationCadence.asNeeded)
          }
          .pickerStyle(.segmented)

          switch draft.cadence {
          case .fixedTimes:
            ForEach(Array(draft.times.enumerated()), id: \.offset) { index, _ in
              DatePicker("Time \(index + 1)", selection: timeBinding(index), displayedComponents: .hourAndMinute)
            }
            .onDelete { offsets in
              var times = draft.times
              times.remove(atOffsets: offsets)
              draft.times = times
            }
            Button("Add a time", systemImage: "plus.circle") { addTime() }
          case .everyHours:
            Stepper("Every \(everyHours.wrappedValue) hour\(everyHours.wrappedValue == 1 ? "" : "s")", value: everyHours, in: 1...24)
            DatePicker("First dose", selection: $draft.startsAt)
          case .asNeeded:
            Stepper(
              minimumGapHours.wrappedValue == 0
                ? "No minimum wait" : "Wait at least \(minimumGapHours.wrappedValue) h between doses",
              value: minimumGapHours, in: 0...24)
          }
        }

        if draft.cadence != .asNeeded {
          Section("Course") {
            if draft.cadence == .fixedTimes {
              DatePicker("Starts", selection: $draft.startsAt)
            }
            Toggle("Stops on a date", isOn: $hasEnd)
            if hasEnd {
              DatePicker("Last day", selection: endBinding, in: draft.startsAt..., displayedComponents: .date)
            }
            Toggle("Reminders on", isOn: $draft.isActive)
          }
        }

        Section("Notes") {
          TextField("With food, from the fridge…", text: $draft.notes, axis: .vertical)
        }

        Section {
        } footer: {
          Text(
            draft.cadence == .asNeeded
              ? "As-needed medicines don't send reminders. Nested remembers when each was last given so neither of you doubles up."
              : "Both phones get the reminder at the same time, and a second nudge 15 minutes later if nobody has tapped Given. Whoever taps Given clears it on the other phone."
          )
        }

        if !isNew {
          Section {
            Button("Delete medicine", role: .destructive) { confirmingDelete = true }
          }
        }
      }
      .nestedListBackground()
      .navigationTitle(isNew ? "New medicine" : "Medicine")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save", action: save).disabled(!canSave).fontWeight(.semibold)
        }
      }
      .confirmationDialog("Delete \(draft.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
        Button("Delete", role: .destructive) {
          model.deleteMedication(draft)
          dismiss()
        }
      } message: {
        Text("This also removes its log of doses from both phones.")
      }
    }
    .presentationDetents([.large])
  }

  // MARK: Bindings

  private func date(minutes: Int) -> Date {
    Calendar.current.date(byAdding: .minute, value: minutes, to: Calendar.current.startOfDay(for: Date())) ?? Date()
  }

  private func timeBinding(_ index: Int) -> Binding<Date> {
    Binding(
      get: { date(minutes: draft.times.indices.contains(index) ? draft.times[index] : 0) },
      set: { newValue in
        let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
        var times = draft.times
        guard times.indices.contains(index) else { return }
        times[index] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        draft.times = times
      })
  }

  private var endBinding: Binding<Date> {
    Binding(
      get: { draft.endsAt ?? draft.startsAt.addingTimeInterval(7 * 86_400) },
      set: { newValue in
        // The last day includes its evening doses.
        draft.endsAt = Calendar.current.date(
          bySettingHour: 23, minute: 59, second: 0, of: newValue)
      })
  }

  private func addTime() {
    var times = draft.times
    // A sensible next time: 12 hours after the last one, or 8:00 to start.
    let next = times.last.map { ($0 + 12 * 60) % (24 * 60) } ?? 8 * 60
    times.append(times.contains(next) ? (next + 60) % (24 * 60) : next)
    draft.times = times
  }

  private func save() {
    var medication = draft
    medication.name = medication.name.trimmingCharacters(in: .whitespaces)
    medication.dose = medication.dose.trimmingCharacters(in: .whitespaces)
    if !hasEnd || medication.cadence == .asNeeded { medication.endsAt = nil }
    if hasEnd, medication.endsAt == nil { medication.endsAt = endBinding.wrappedValue }
    model.saveMedication(medication)
    dismiss()
  }
}
