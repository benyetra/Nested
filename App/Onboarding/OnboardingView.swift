import NestCore
import NestData
import SwiftUI

/// First launch: who's holding this phone, then either create the baby or wait for the
/// partner's iCloud invite.
struct OnboardingView: View {
  @Environment(AppModel.self) private var model
  @State private var ownerName = DevicePrefs.ownerName
  @State private var babyName = ""
  @State private var birthDate = Date()
  @State private var feedingMode: FeedingMode = .mixed
  @State private var unit: VolumeUnit = Locale.current.measurementSystem == .us ? .oz : .ml
  @State private var joining = false

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Your first name", text: $ownerName)
            .textContentType(.givenName)
        } header: {
          Text("Who's this phone for?")
        } footer: {
          Text("Every entry records who logged it.")
        }

        Picker("", selection: $joining) {
          Text("New baby").tag(false)
          Text("Join partner").tag(true)
        }
        .pickerStyle(.segmented)
        .listRowBackground(Color.clear)

        if joining {
          Section {
            Label("Ask your partner to open Nest → Settings → Share with your partner, and send you the invite.", systemImage: "1.circle")
            Label("Open the invite link on this phone. Nest opens with your shared baby.", systemImage: "2.circle")
          } footer: {
            Text("Both of you need to be signed in to iCloud.")
          }
        } else {
          Section("Baby") {
            TextField("Name", text: $babyName)
            DatePicker("Born", selection: $birthDate, in: ...Date(), displayedComponents: .date)
            Picker("Feeding", selection: $feedingMode) {
              ForEach(FeedingMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Units", selection: $unit) {
              ForEach(VolumeUnit.allCases, id: \.self) { Text($0.title).tag($0) }
            }
          }
        }
      }
      .navigationTitle("Welcome to Nest")
      .safeAreaInset(edge: .bottom) {
        PrimaryButton(title: joining ? "Save my name" : "Start tracking", systemImage: "checkmark") {
          finish()
        }
        .padding()
        .disabled(ownerName.trimmingCharacters(in: .whitespaces).isEmpty || (!joining && babyName.isEmpty))
      }
      .onChange(of: ownerName) { _, name in model.setOwner(name) }
    }
  }

  private func finish() {
    model.setOwner(ownerName)
    SideEffects.shared.reload(me: model.ownerName)
    guard !joining else {
      model.showToast("Waiting for the invite…")
      return
    }
    let (name, birth, mode, unit) = (babyName, birthDate, feedingMode, unit)
    model.perform(nil, undo: .none) {
      try model.store.createBaby(name: name, birthDate: birth, feedingMode: mode, unit: unit)
      return nil
    }
    Task {
      await FeedAlarmService.shared.requestAuthorization()
      await NotificationService.shared.requestAuthorization()
    }
  }
}
