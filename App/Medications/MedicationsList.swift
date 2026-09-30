import NestedCore
import NestedData
import SwiftUI

enum MedicationStyle {
  static let tint = Color.mint
}

/// Medicines for the baby or a parent. Both phones get a reminder at the same time; whoever taps
/// "Given" first clears it on the other phone.
struct MedicationsList: View {
  @Binding var mode: DoctorMode
  @Environment(AppModel.self) private var model
  private var snapshot: NestedSnapshot { SideEffects.shared.snapshot }

  @State private var editing: Medication?
  @State private var extraDose: Medication?

  private func doses(for medication: Medication) -> [MedicationDose] {
    snapshot.medicationDoses.filter { $0.medicationID == medication.id }
  }

  private func statusOf(_ medication: Medication, now: Date) -> MedicationStatus {
    MedicationSchedule.status(plan: medication.plan, doses: doses(for: medication).map(\.record), now: now)
  }

  var body: some View {
    TimelineView(.periodic(from: .now, by: 30)) { context in
      let now = context.date
      let active = snapshot.medications.filter(\.isActive)
      let dueNow = active.filter { medication in
        switch statusOf(medication, now: now) {
        case .due, .overdue: true
        default: false
        }
      }
      let rest = active.filter { medication in !dueNow.contains(where: { $0.id == medication.id }) }
      let paused = snapshot.medications.filter { !$0.isActive }

      List {
        DoctorModePicker(mode: $mode)

        if snapshot.medications.isEmpty {
          ContentUnavailableView {
            Label("No medicines yet", systemImage: "pills")
          } description: {
            Text("Add a medicine with its dose and how often, and both of you get a reminder at the same time.")
          } actions: {
            Button("Add a medicine") { add() }.buttonStyle(.borderedProminent).tint(MedicationStyle.tint)
          }
          .listRowBackground(Color.clear)
        }

        if !dueNow.isEmpty {
          Section("Due now") {
            ForEach(dueNow) { row($0, now: now) }
          }
        }
        if !rest.isEmpty {
          Section("Schedule") {
            ForEach(rest) { row($0, now: now) }
          }
        }
        if !paused.isEmpty {
          Section("Paused") {
            ForEach(paused) { row($0, now: now) }
          }
        }
        if !snapshot.medicationDoses.isEmpty {
          Section("Given recently") {
            ForEach(snapshot.medicationDoses.prefix(12)) { dose in
              doseRow(dose)
            }
          }
        }
      }
      .listStyle(.insetGrouped)
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("Add medicine", systemImage: "plus") { add() }
      }
    }
    .sheet(item: $editing) { MedicationEditor(medication: $0) }
    .confirmationDialog(
      "Give another dose?", isPresented: Binding(get: { extraDose != nil }, set: { if !$0 { extraDose = nil } }),
      titleVisibility: .visible, presenting: extraDose
    ) { medication in
      Button("Yes, log another dose") { model.giveDose(medication, dueAt: nil) }
    } message: { medication in
      Text(recentDoseText(medication))
    }
  }

  // MARK: Rows

  private func row(_ medication: Medication, now: Date) -> some View {
    let status = statusOf(medication, now: now)
    return HStack(alignment: .top, spacing: 12) {
      AvatarView(
        subject: medication.forWho.isEmpty ? Avatar.babySubject : Avatar.parentSubject(medication.forWho),
        name: medication.forWho.isEmpty ? snapshot.babyName : medication.forWho, size: 38, tint: MedicationStyle.tint
      )
      VStack(alignment: .leading, spacing: 3) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text(medication.name.isEmpty ? "Medicine" : medication.name).font(.headline)
          if !medication.dose.isEmpty {
            Text(medication.dose).font(.subheadline).foregroundStyle(.secondary)
          }
        }
        Text("\(whoText(medication)) · \(cadenceText(medication))")
          .font(.caption)
          .foregroundStyle(.secondary)
        statusLine(status, now: now)
        if let last = doses(for: medication).first(where: { !$0.skipped }) {
          Text("Last given \(last.takenAt.formatted(date: .omitted, time: .shortened))\(last.takenBy.isEmpty ? "" : " by \(last.takenBy)")")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 4)
      if medication.isActive { giveButton(medication, status: status) }
    }
    .padding(.vertical, 4)
    .contentShape(Rectangle())
    .onTapGesture { editing = medication }
    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
      Button("Delete", systemImage: "trash", role: .destructive) { model.deleteMedication(medication) }
    }
    .swipeActions(edge: .leading) {
      if case .due(let due) = status { skipButton(medication, due: due) }
      if case .overdue(let due) = status { skipButton(medication, due: due) }
    }
  }

  @ViewBuilder
  private func statusLine(_ status: MedicationStatus, now: Date) -> some View {
    switch status {
    case .due:
      Label("Due now", systemImage: "bell.fill").font(.caption.weight(.semibold)).foregroundStyle(MedicationStyle.tint)
    case .overdue(let since):
      Label("Overdue since \(since.formatted(date: .omitted, time: .shortened))", systemImage: "exclamationmark.circle.fill")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.orange)
    case .upcoming(let next):
      Text("Next \(dayTime(next, now: now))").font(.caption.weight(.medium))
    case .asNeeded(_, let okAfter):
      if let okAfter {
        Text("OK again at \(okAfter.formatted(date: .omitted, time: .shortened))").font(.caption.weight(.medium))
      }
    case .inactive:
      Text("Reminders paused").font(.caption)
    case .finished:
      Text("Course finished").font(.caption)
    }
  }

  private func giveButton(_ medication: Medication, status: MedicationStatus) -> some View {
    let due: Date? = {
      switch status {
      case .due(let since), .overdue(let since): since
      default: nil
      }
    }()
    return Button {
      give(medication, due: due)
    } label: {
      Label("Given", systemImage: "checkmark")
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
        .background(Capsule().fill(due != nil ? MedicationStyle.tint : MedicationStyle.tint.opacity(0.18)))
        .foregroundStyle(due != nil ? Color.white : MedicationStyle.tint)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Mark \(medication.name) given")
  }

  private func skipButton(_ medication: Medication, due: Date) -> some View {
    Button("Skip", systemImage: "forward.end") { model.skipDose(medication, dueAt: due) }
      .tint(.gray)
  }

  private func doseRow(_ dose: MedicationDose) -> some View {
    let medication = snapshot.medications.first { $0.id == dose.medicationID }
    return HStack {
      Image(systemName: dose.skipped ? "forward.end.circle" : "checkmark.circle.fill")
        .foregroundStyle(dose.skipped ? Color.secondary : MedicationStyle.tint)
      VStack(alignment: .leading, spacing: 1) {
        Text("\(medication?.name ?? "Medicine")\(dose.skipped ? " skipped" : "")").font(.subheadline.weight(.medium))
        Text("\(dose.takenAt.formatted(date: .abbreviated, time: .shortened))\(dose.takenBy.isEmpty ? "" : " · \(dose.takenBy)")")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
    }
    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
      Button("Delete", systemImage: "trash", role: .destructive) { model.deleteDose(dose) }
    }
  }

  // MARK: Actions

  private func add() {
    do { editing = try model.store.draftMedication() } catch { model.errorMessage = "Add your baby first." }
  }

  /// Warns before a second dose soon after the first, which is the easy mistake when two parents
  /// share the job.
  private func give(_ medication: Medication, due: Date?) {
    let recent = doses(for: medication).first { !$0.skipped && Date().timeIntervalSince($0.takenAt) < 3600 }
    if due == nil, recent != nil {
      extraDose = medication
    } else {
      model.giveDose(medication, dueAt: due)
    }
  }

  private func recentDoseText(_ medication: Medication) -> String {
    guard let last = doses(for: medication).first(where: { !$0.skipped }) else { return "" }
    let who = last.takenBy.isEmpty ? "" : " by \(last.takenBy)"
    return "\(medication.name) was given at \(last.takenAt.formatted(date: .omitted, time: .shortened))\(who)."
  }

  // MARK: Wording

  private func whoText(_ medication: Medication) -> String {
    medication.forWho.isEmpty ? "For \(snapshot.babyName)" : "For \(medication.forWho)"
  }

  private func cadenceText(_ medication: Medication) -> String {
    MedicationSchedule.cadenceSummary(medication.plan) { minutes in
      Calendar.current.date(byAdding: .minute, value: minutes, to: Calendar.current.startOfDay(for: Date()))?
        .formatted(date: .omitted, time: .shortened) ?? ""
    }
  }

  private func dayTime(_ date: Date, now: Date) -> String {
    Calendar.current.isDate(date, inSameDayAs: now)
      ? date.formatted(date: .omitted, time: .shortened)
      : date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
  }
}

extension AppModel {
  func saveMedication(_ medication: Medication) {
    perform(haptic: .success, undo: .none) {
      try store.saveMedication(medication)
      return nil
    }
    // Reminders are notifications, so ask the first time a medicine is saved.
    Task { await NotificationService.shared.requestAuthorization() }
  }

  func deleteMedication(_ medication: Medication) {
    perform(haptic: .impact, undo: .none) {
      try store.deleteMedication(id: medication.id)
      return nil
    }
    let store = store
    showToast("Deleted \(medication.name)", undo: { try? store.restoreMedication(medication) })
  }

  func giveDose(_ medication: Medication, dueAt: Date?) {
    var logged: MedicationDose?
    perform(haptic: .success, undo: .none) {
      logged = try store.logDose(medicationID: medication.id, dueAt: dueAt, at: Date(), skipped: false)
      return nil
    }
    guard let dose = logged else { return }
    let store = store
    showToast("\(medication.name) given", undo: { try? store.deleteDose(id: dose.id) })
  }

  func skipDose(_ medication: Medication, dueAt: Date) {
    perform(haptic: .selection, undo: .none) {
      try store.logDose(medicationID: medication.id, dueAt: dueAt, at: Date(), skipped: true)
      return nil
    }
  }

  func deleteDose(_ dose: MedicationDose) {
    perform(haptic: .impact, undo: .none) {
      try store.deleteDose(id: dose.id)
      return nil
    }
  }
}
