import NestedCore
import NestedData
import SwiftUI

private let planTint = Color.indigo

private extension PlanSlot.Kind {
  var title: String {
    switch self {
    case .wake: "Wake up"
    case .feed: "Feed"
    case .nap: "Nap"
    case .bed: "Bedtime"
    }
  }

  var symbol: String {
    switch self {
    case .wake: "sun.max.fill"
    case .feed: "drop.fill"
    case .nap: "moon.zzz.fill"
    case .bed: "bed.double.fill"
    }
  }

  var color: Color {
    switch self {
    case .wake: .orange
    case .feed: EventKind.nursing.color
    case .nap, .bed: EventKind.sleep.color
    }
  }
}

private struct SlotRow: View {
  let slot: PlanSlot

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: slot.kind.symbol)
        .font(.footnote.weight(.bold)).foregroundStyle(.white)
        .frame(width: 28, height: 28)
        .background(Circle().fill(slot.kind.color.gradient))
        .opacity(slot.status == .missed ? 0.5 : 1)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 1) {
        Text("\(slot.kind.title) · \(slot.at.formatted(date: .omitted, time: .shortened))")
          .font(.subheadline.weight(.semibold))
        if let minutes = slot.targetMinutes {
          Text("aim for about \(Durations.format(Double(minutes) * 60))")
            .font(.caption).foregroundStyle(.secondary)
        }
      }
      Spacer()
      statusLabel
    }
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  private var statusLabel: some View {
    switch slot.status {
    case .done:
      if let actual = slot.actual {
        Label(actual.formatted(date: .omitted, time: .shortened), systemImage: "checkmark.circle.fill")
          .font(.caption.weight(.semibold)).foregroundStyle(.green)
      }
    case .due:
      Text("now").font(.caption.weight(.bold)).foregroundStyle(planTint)
        .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(planTint.opacity(0.15)))
    case .upcoming:
      Text(slot.at, style: .relative).font(.caption).foregroundStyle(.secondary).monospacedDigit()
    case .missed:
      Text("not logged").font(.caption).foregroundStyle(.secondary)
    }
  }
}

/// Now tab: what's next on the day's plan, and when to wake her from the nap she's in.
struct PlanCard: View {
  let name: String
  let plan: SleepPlan
  let age: DevelopmentAge
  let history: History
  let activeSleepStart: Date?
  let now: Date
  var open: () -> Void

  var body: some View {
    let slots = SleepPlanner.today(plan: plan, ageDays: age.days, now: now, history: history)
    let upcoming = slots.filter { $0.status == .due || $0.status == .upcoming }
    let napEnd = activeSleepStart.flatMap {
      SleepPlanner.napEnd(plan: plan, ageDays: age.days, sleepStarted: $0)
    }
    if !slots.isEmpty {
      Button(action: open) {
        Card(tint: planTint) {
          VStack(alignment: .leading, spacing: 10) {
            HStack {
              Label("Today's plan", systemImage: "calendar.badge.clock")
                .font(.subheadline.weight(.semibold)).foregroundStyle(planTint)
              Spacer()
              Text("\(slots.filter { $0.status == .done }.count) of \(slots.count) done")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            if let napEnd {
              Label(
                napEnd > now
                  ? "Plan: wake her around \(napEnd.formatted(date: .omitted, time: .shortened))"
                  : "Past the plan's nap length (\(napEnd.formatted(date: .omitted, time: .shortened)))",
                systemImage: "alarm.fill"
              )
              .font(.callout.weight(.semibold))
            }
            ForEach(upcoming.prefix(3)) { SlotRow(slot: $0) }
            if upcoming.isEmpty {
              Text("Everything on today's plan is done or past.").font(.subheadline).foregroundStyle(.secondary)
            }
            Text("See the whole day").font(.footnote.weight(.semibold)).foregroundStyle(planTint)
          }
        }
      }
      .buttonStyle(.plain)
      .accessibilityHint("Opens today's full schedule")
    }
  }
}

struct PlanDaySheet: View {
  let name: String
  let plan: SleepPlan
  let age: DevelopmentAge
  let history: History
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      TimelineView(.periodic(from: .now, by: 60)) { context in
        let slots = SleepPlanner.today(plan: plan, ageDays: age.days, now: context.date, history: history)
        ScrollView {
          VStack(alignment: .leading, spacing: 8) {
            if let stage = plan.stage(ageWeeks: age.days / 7) {
              Text("\(stage.title) · longest awake \(stage.wakeWindow > 0 ? Durations.format(Double(stage.wakeWindow) * 60) : "not set")")
                .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(slots) { slot in
              SlotRow(slot: slot)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.card))
            }
            Text("Times are the plan's. Anything logged within about 45 minutes counts as on time.")
              .font(.footnote).foregroundStyle(.secondary).padding(.top, 6)
          }
          .padding()
        }
      }
      .nestedBackground()
      .navigationTitle("\(name)'s day")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
  }
}

// MARK: - Editor

private func date(minutes: Int) -> Date {
  Calendar.current.startOfDay(for: Date()).addingTimeInterval(Double(minutes) * 60)
}

private func minutes(_ date: Date) -> Int {
  Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date)
}

/// Settings → Sleep plan. Enter the schedule you're following for each stage of her age.
struct SleepPlanEditor: View {
  @Environment(AppModel.self) private var model
  @State private var plan: SleepPlan = .starter
  @State private var loaded = false
  /// What happened the last time we tried to save, shown so a failure is never silent.
  @State private var status: String?
  @State private var failed = false

  var body: some View {
    Form {
      Section {
        Toggle("Use a sleep plan", isOn: $plan.enabled)
      } footer: {
        if let status {
          Text(status).foregroundStyle(failed ? Color.red : Color.secondary)
        }
        Text("Add the schedule you're following from a sleep book or your pediatrician for each stage of her age. Nested then shows what's next on the day, when to wake her from a nap, and how the week lined up. The stages below are only a generic starting point, so change them to match your plan.")
      }
      Section("Stages") {
        ForEach($plan.stages) { $stage in
          NavigationLink {
            StageEditor(stage: $stage)
          } label: {
            VStack(alignment: .leading, spacing: 2) {
              Text(stage.title).font(.body.weight(.semibold))
              Text(summary(stage)).font(.footnote).foregroundStyle(.secondary)
            }
          }
        }
        .onDelete { offsets in
          guard plan.stages.count - offsets.count >= 1 else { return }
          plan.stages.remove(atOffsets: offsets)
        }
        Button("Add a stage") {
          let last = plan.stages.last
          plan.stages.append(
            SleepPlan.Stage(
              fromWeek: (last?.fromWeek ?? 0) + 4, wakeMinute: last?.wakeMinute ?? 420, bedMinute: last?.bedMinute,
              napMinutes: last?.napMinutes ?? [], napLength: last?.napLength ?? 0, wakeWindow: last?.wakeWindow ?? 0,
              feedEvery: last?.feedEvery ?? 0))
        }
      }
    }
    .navigationTitle("Sleep plan")
    .navigationBarTitleDisplayMode(.inline)
    .task {
      guard !loaded else { return }
      do {
        if let saved = try model.store.sleepPlan() { plan = saved }
      } catch {
        failed = true
        status = "Couldn't read the saved plan: \(error.localizedDescription)"
      }
      // Only start saving once the saved plan is in place, so loading is never mistaken for an edit.
      try? await Task.sleep(for: .milliseconds(100))
      loaded = true
    }
    .onChange(of: plan) { _, new in
      guard loaded else { return }
      persist(new)
    }
  }

  private func persist(_ new: SleepPlan) {
    var sorted = new
    sorted.stages.sort { $0.fromWeek < $1.fromWeek }
    do {
      try model.store.saveSleepPlan(sorted)
      // Read it back: "saved" only means something if it's really in the database.
      let stored = try model.store.sleepPlan()
      if stored == sorted {
        failed = false
        status = "Saved on this phone \(Date().formatted(date: .omitted, time: .shortened))."
      } else {
        failed = true
        status = "The plan didn't stick: it saved but read back different."
        model.errorMessage = "The sleep plan didn't save. Please tell Claude: read-back mismatch."
      }
    } catch {
      failed = true
      status = "Couldn't save: \(error.localizedDescription)"
      model.errorMessage = "Couldn't save the sleep plan: \(String(describing: error))"
    }
  }

  private func summary(_ stage: SleepPlan.Stage) -> String {
    var parts = ["wake \(date(minutes: stage.wakeMinute).formatted(date: .omitted, time: .shortened))"]
    if !stage.napMinutes.isEmpty { parts.append("\(stage.napMinutes.count) naps") }
    if let bed = stage.bedMinute { parts.append("bed \(date(minutes: bed).formatted(date: .omitted, time: .shortened))") }
    if stage.feedEvery > 0 { parts.append("feed every \(Durations.format(Double(stage.feedEvery) * 60))") }
    return parts.joined(separator: " · ")
  }
}

private struct StageEditor: View {
  @Binding var stage: SleepPlan.Stage

  private func clock(_ binding: Binding<Int>) -> Binding<Date> {
    Binding(get: { date(minutes: binding.wrappedValue) }, set: { binding.wrappedValue = minutes($0) })
  }

  private var bedBinding: Binding<Int> {
    Binding(get: { stage.bedMinute ?? 19 * 60 }, set: { stage.bedMinute = $0 })
  }

  var body: some View {
    Form {
      Section("Starts") {
        Stepper("From week \(stage.fromWeek)", value: $stage.fromWeek, in: 0...52)
      }
      Section("Day") {
        DatePicker("Wake up", selection: clock($stage.wakeMinute), displayedComponents: .hourAndMinute)
        Toggle("Set a bedtime", isOn: Binding(get: { stage.bedMinute != nil }, set: { stage.bedMinute = $0 ? 19 * 60 : nil }))
        if stage.bedMinute != nil {
          DatePicker("Bedtime", selection: clock(bedBinding), displayedComponents: .hourAndMinute)
        }
      }
      Section("Naps") {
        ForEach(stage.napMinutes.indices, id: \.self) { index in
          DatePicker("Nap \(index + 1)", selection: clock($stage.napMinutes[index]), displayedComponents: .hourAndMinute)
        }
        .onDelete { stage.napMinutes.remove(atOffsets: $0) }
        Button("Add a nap") {
          let next = (stage.napMinutes.last ?? stage.wakeMinute) + max(90, stage.wakeWindow + 60)
          stage.napMinutes.append(min(next, 23 * 60))
        }
        DurationEditor(title: "Nap length", minutes: Binding(get: { Double(stage.napLength) }, set: { stage.napLength = Int($0) }),
          maxMinutes: 240, presets: [45, 60, 90, 120], tint: planTint)
      }
      Section {
        DurationEditor(title: "Longest awake", minutes: Binding(get: { Double(stage.wakeWindow) }, set: { stage.wakeWindow = Int($0) }),
          maxMinutes: 300, presets: [45, 60, 90, 120, 150], tint: planTint)
        DurationEditor(title: "Feed every", minutes: Binding(get: { Double(stage.feedEvery) }, set: { stage.feedEvery = Int($0) }),
          maxMinutes: 360, presets: [120, 150, 180, 210, 240], tint: planTint)
      } header: {
        Text("Between sleeps and feeds")
      } footer: {
        Text("Longest awake sets her nap window on the Now tab. Use 0 to leave either one unset.")
      }
    }
    .navigationTitle(stage.title)
    .navigationBarTitleDisplayMode(.inline)
  }
}
