import CloudKit
import NestCore
import NestData
import SQLiteData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
  @Environment(AppModel.self) private var model
  private var snapshot: NestSnapshot { SideEffects.shared.snapshot }

  @AppStorage(NotificationService.feedReminderKey) private var feedReminders = false
  @State private var nightMode = DevicePrefs.nightMode
  @State private var ownerName = DevicePrefs.ownerName
  @State private var sharedRecord: SharedRecord?
  @State private var reportDays = 14
  @State private var reportURL: URL?
  @State private var csvURL: URL?
  @State private var importing = false
  @State private var confirmingDeleteAll = false
  @State private var isSharing = false

  var body: some View {
    NavigationStack {
      if let baby = snapshot.baby {
        form(baby)
          .nestListBackground()
          .actionBarInset(tab: .settings)
          .navigationTitle("Settings")
      } else {
        ContentUnavailableView("No baby yet", systemImage: "person.crop.circle.badge.plus")
          .navigationTitle("Settings")
      }
    }
  }

  private func form(_ baby: Baby) -> some View {
    Form {
      if !NestBootstrap.problems.isEmpty {
        Section("Setup needed") {
          ForEach(NestBootstrap.problems, id: \.self) { problem in
            Label(problem, systemImage: "exclamationmark.triangle.fill")
              .font(.footnote)
              .foregroundStyle(.orange)
          }
        }
      }
      Section("Baby") {
        TextField("Name", text: bind(baby, \.name))
        DatePicker(
          "Birth date",
          selection: Binding(get: { baby.birthDate ?? Date() }, set: { date in save(baby) { $0.birthDate = date } }),
          in: ...Date(), displayedComponents: .date)
        Picker("Feeding", selection: bind(baby, \.feedingMode)) {
          ForEach(FeedingMode.allCases, id: \.self) { Text($0.title).tag($0) }
        }
      }

      Section {
        TextField("Your name", text: $ownerName)
          .textContentType(.givenName)
          .onSubmit { commitOwner() }
          .onChange(of: ownerName) { _, _ in commitOwner() }
      } header: {
        Text("This phone")
      } footer: {
        Text("Shown as the initial on everything you log.")
      }

      Section("Display") {
        Picker("Units", selection: bind(baby, \.unit)) {
          ForEach(VolumeUnit.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        Picker("Night mode", selection: $nightMode) {
          ForEach(NightModeSetting.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .onChange(of: nightMode) { _, value in DevicePrefs.nightMode = value }
        if nightMode == .automatic {
          DatePicker("Night starts", selection: minutesBinding(baby, \.nightStartMinutes), displayedComponents: .hourAndMinute)
          DatePicker("Night ends", selection: minutesBinding(baby, \.nightEndMinutes), displayedComponents: .hourAndMinute)
        }
      }

      Section {
        Button {
          share(baby)
        } label: {
          HStack {
            Label("Share with your partner", systemImage: "person.2.fill")
            if isSharing { Spacer(); ProgressView() }
          }
        }
        .disabled(isSharing)
      } header: {
        Text("Sharing")
      } footer: {
        Text("Sends an iCloud invite. Once accepted, both phones log to the same record and see each other's entries within seconds. Everything stays in your iCloud.")
      }

      alarmSection(baby)
      flagsSection(baby)

      Section {
        Stepper(
          "Wake window default: \(baby.wakeWindowOverrideMinutes.map { "\($0) min" } ?? "by age")",
          value: Binding(
            get: { baby.wakeWindowOverrideMinutes ?? Int(NapPredictor.ageDefaultWakeWindow(ageInDays: ageInDays(baby)) / 60) },
            set: { value in save(baby) { $0.wakeWindowOverrideMinutes = value } }),
          in: 20...300, step: 5)
        if baby.wakeWindowOverrideMinutes != nil {
          Button("Use age-based default") { save(baby) { $0.wakeWindowOverrideMinutes = nil } }
        }
        Toggle("Remind me when a feed window opens", isOn: $feedReminders)
          .onChange(of: feedReminders) { _, on in
            if on { Task { await NotificationService.shared.requestAuthorization() } }
            SideEffects.shared.refresh()
          }
      } header: {
        Text("Predictions")
      } footer: {
        Text("Nap windows use her own last 5 days once there's enough data, blended with this default until then.")
      }

      exportSection(baby)

      Section {
        Button("Delete all data", role: .destructive) { confirmingDeleteAll = true }
      } footer: {
        Text("Nest \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
      }
    }
    .sheet(item: $sharedRecord) { record in
      if let syncEngine = NestBootstrap.syncEngine {
        CloudSharingView(
          sharedRecord: record, availablePermissions: [.allowPrivate, .allowReadWrite], syncEngine: syncEngine)
      }
    }
    .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
      importCSV(result)
    }
    .confirmationDialog(
      "Delete everything?", isPresented: $confirmingDeleteAll, titleVisibility: .visible
    ) {
      Button("Delete all data", role: .destructive) {
        model.perform(nil, haptic: .impact, undo: .none) {
          try model.store.deleteAllData()
          return nil
        }
      }
    } message: {
      Text("This removes \(baby.name.isEmpty ? "the baby" : baby.name) and every entry from this phone, iCloud and your partner's phone. It can't be undone.")
    }
  }

  // MARK: Alarm

  private func alarmSection(_ baby: Baby) -> some View {
    Section {
      Picker("Auto-arm", selection: bind(baby, \.alarmAutoArm)) {
        ForEach(AlarmAutoArm.allCases, id: \.self) { Text($0.title).tag($0) }
      }
      Picker("Interval", selection: bind(baby, \.alarmIntervalMinutes)) {
        ForEach(AlarmSettings.intervalOptions.map { Int($0 / 60) }, id: \.self) { minutes in
          Text(Durations.format(TimeInterval(minutes * 60))).tag(minutes)
        }
      }
      Picker("Measured from", selection: bind(baby, \.alarmMeasuredFrom)) {
        ForEach(AlarmMeasuredFrom.allCases, id: \.self) { Text($0.title).tag($0) }
      }
      Picker("Who rings", selection: bind(baby, \.alarmWhoRings)) {
        ForEach(AlarmWhoRings.allCases, id: \.self) { Text($0.title).tag($0) }
      }
      if baby.alarmWhoRings == .onePhone {
        Picker("Ring on", selection: Binding(
          get: { baby.alarmRingOwner ?? snapshot.me },
          set: { value in save(baby) { $0.alarmRingOwner = value } })
        ) {
          ForEach(ownerNames, id: \.self) { Text($0).tag($0) }
        }
      }
      Picker("Second button", selection: bind(baby, \.alarmSecondary)) {
        ForEach(AlarmSecondaryButton.allCases, id: \.self) { Text($0.title).tag($0) }
      }
      if FeedAlarmService.shared.authorization != .authorized {
        Button("Allow Nest to set alarms") {
          Task {
            await FeedAlarmService.shared.requestAuthorization()
            SideEffects.shared.refresh()
          }
        }
      }
    } header: {
      Text("Night feed alarm")
    } footer: {
      Text("A real alarm on both phones that breaks through silent mode and Focus. A new feed replaces the pending alarm. It uses the system alarm sound.")
    }
  }

  private var ownerNames: [String] {
    var names = snapshot.devices.map(\.ownerName).filter { !$0.isEmpty }
    if !snapshot.me.isEmpty, !names.contains(snapshot.me) { names.insert(snapshot.me, at: 0) }
    return names
  }

  // MARK: Flags

  private func flagsSection(_ baby: Baby) -> some View {
    Section {
      Toggle("Gentle flags", isOn: bind(baby, \.flagsEnabled))
      if baby.flagsEnabled {
        Stepper("Fewer than \(baby.flagMinFeeds) feeds / 24 h", value: bind(baby, \.flagMinFeeds), in: 4...14)
        Stepper("Fewer than \(baby.flagMinWet) wet / 24 h", value: bind(baby, \.flagMinWet), in: 2...10)
        Stepper("Gap by day over \(Durations.format(TimeInterval(baby.flagMaxGapDayMinutes * 60)))",
          value: bind(baby, \.flagMaxGapDayMinutes), in: 60...360, step: 15)
        Stepper("Gap at night over \(Durations.format(TimeInterval(baby.flagMaxGapNightMinutes * 60)))",
          value: bind(baby, \.flagMaxGapNightMinutes), in: 60...480, step: 15)
        Toggle("Notify both phones", isOn: bind(baby, \.flagNotifications))
      }
    } header: {
      Text("Flags")
    } footer: {
      Text("Defaults follow AAP guidance on HealthyChildren.org. Flags point out patterns worth a call to your pediatrician; they never diagnose.")
    }
  }

  // MARK: Export

  private func exportSection(_ baby: Baby) -> some View {
    Section {
      Picker("Report covers", selection: $reportDays) {
        Text("7 days").tag(7)
        Text("14 days").tag(14)
        Text("30 days").tag(30)
      }
      if let reportURL {
        ShareLink(item: reportURL) { Label("Share pediatrician report (PDF)", systemImage: "doc.richtext") }
      } else {
        Button("Create pediatrician report", systemImage: "doc.richtext") { makeReport(baby) }
      }
      if let csvURL {
        ShareLink(item: csvURL) { Label("Share raw data (CSV)", systemImage: "tablecells") }
      } else {
        Button("Export raw data (CSV)", systemImage: "tablecells") { makeCSV(baby) }
      }
      Button("Import from CSV…", systemImage: "square.and.arrow.down") { importing = true }
    } header: {
      Text("Export")
    } footer: {
      Text("Import accepts Nest's own CSV format, so history from notes or another app can be brought in once. Rows already present are skipped.")
    }
    .onChange(of: reportDays) { _, _ in reportURL = nil }
  }

  private func makeReport(_ baby: Baby) {
    do {
      let history = try model.store.history(since: Date().addingTimeInterval(-Double(reportDays + 1) * 86_400))
      let notes = try model.store.entries(from: Date().addingTimeInterval(-Double(reportDays + 1) * 86_400), to: Date())
        .compactMap { entry -> BabyNote? in
          if case .note(let note) = entry { return note }
          return nil
        }
      reportURL = try ReportRenderer.render(baby: baby, history: history, notes: notes, days: reportDays)
    } catch {
      model.errorMessage = "Couldn't create the report: \(error.localizedDescription)"
    }
  }

  private func makeCSV(_ baby: Baby) {
    do {
      let csv = try model.store.exportCSV()
      let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(baby.name.isEmpty ? "Nest" : baby.name) data \(Date().formatted(.iso8601.year().month().day())).csv")
      try csv.write(to: url, atomically: true, encoding: .utf8)
      csvURL = url
    } catch {
      model.errorMessage = "Couldn't export: \(error.localizedDescription)"
    }
  }

  private func importCSV(_ result: Result<URL, any Error>) {
    do {
      let url = try result.get()
      let accessing = url.startAccessingSecurityScopedResource()
      defer { if accessing { url.stopAccessingSecurityScopedResource() } }
      let text = try String(contentsOf: url, encoding: .utf8)
      let count = try model.store.importCSV(text)
      model.showToast("Imported \(count) entr\(count == 1 ? "y" : "ies")")
    } catch {
      model.errorMessage = "Import failed: \(error)"
    }
  }

  // MARK: Sharing

  private func share(_ baby: Baby) {
    isSharing = true
    Task {
      defer { isSharing = false }
      do {
        let title = "Join \(baby.name.isEmpty ? "our baby" : baby.name) in Nest"
        guard let syncEngine = NestBootstrap.syncEngine else {
          model.errorMessage = NestBootstrap.problems.last ?? "iCloud sync isn't set up on this device."
          return
        }
        sharedRecord = try await syncEngine.share(record: baby) { share in
          share[CKShare.SystemFieldKey.title] = title
        }
      } catch {
        model.errorMessage = "Sharing needs iCloud: \(error.localizedDescription)"
      }
    }
  }

  // MARK: Bindings

  private func commitOwner() {
    model.setOwner(ownerName)
    SideEffects.shared.reload(me: model.ownerName)
    try? model.store.updateDevice { _ in }
  }

  private func ageInDays(_ baby: Baby) -> Int {
    baby.birthDate.map { AgeMath.days(from: $0, to: Date()) } ?? 14
  }

  /// Writes the whole baby row on change.
  private func save(_ baby: Baby, _ mutate: (inout Baby) -> Void) {
    var updated = baby
    mutate(&updated)
    guard updated != baby else { return }
    model.perform(nil, haptic: .selection, undo: .none) {
      try model.store.updateBaby(updated)
      return nil
    }
  }

  private func bind<V>(_ baby: Baby, _ keyPath: WritableKeyPath<Baby, V>) -> Binding<V> {
    Binding(get: { baby[keyPath: keyPath] }, set: { value in save(baby) { $0[keyPath: keyPath] = value } })
  }

  private func minutesBinding(_ baby: Baby, _ keyPath: WritableKeyPath<Baby, Int>) -> Binding<Date> {
    Binding(
      get: {
        Calendar.current.date(byAdding: .minute, value: baby[keyPath: keyPath], to: Calendar.current.startOfDay(for: Date())) ?? Date()
      },
      set: { date in
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        save(baby) { $0[keyPath: keyPath] = minutes }
      })
  }
}
