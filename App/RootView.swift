import NestCore
import NestData
import SQLiteData
import SwiftUI

struct RootView: View {
  @Environment(AppModel.self) private var model
  @Fetch(SnapshotRequest()) private var snapshot = NestSnapshot.empty

  var body: some View {
    @Bindable var model = model
    TimelineView(.everyMinute) { context in
      content
        .modifier(
          NightModeModifier(
            isOn: NightMode.isOn(
              setting: DevicePrefs.nightMode, window: snapshot.baby?.nightWindow ?? .defaultNight, now: context.date)))
    }
    .overlay(alignment: .bottom) { toast }
    .sheet(item: $model.editing) { entry in
      EntryEditor(entry: entry, unit: snapshot.unit)
    }
    .confirmationDialog(
      "She's asleep", isPresented: Binding(get: { model.pendingFeed != nil }, set: { if !$0 { model.pendingFeed = nil } }),
      titleVisibility: .visible, presenting: model.pendingFeed
    ) { pending in
      Button("End sleep and \(pending.title.lowercased())") { pending.perform(true) }
      Button("\(pending.title), keep sleep running") { pending.perform(false) }
    }
    .alert(
      "Something went wrong",
      isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(model.errorMessage ?? "")
    }
    // Haptic, visual and state change on the same frame.
    .sensoryFeedback(.success, trigger: model.successTick)
    .sensoryFeedback(.impact(weight: .medium), trigger: model.impactTick)
    .sensoryFeedback(.selection, trigger: model.selectionTick)
  }

  @ViewBuilder
  private var content: some View {
    @Bindable var model = model
    if snapshot.baby == nil && snapshot.generatedAt != .distantPast {
      OnboardingView()
    } else {
      TabView(selection: $model.tab) {
        Tab("Now", systemImage: "house.fill", value: AppTab.now) { NowView() }
        Tab("Timeline", systemImage: "list.bullet", value: AppTab.timeline) { TimelineScreen() }
        Tab("Trends", systemImage: "chart.bar.xaxis", value: AppTab.trends) { TrendsView() }
        Tab("Settings", systemImage: "gearshape", value: AppTab.settings) { SettingsView() }
      }
    }
  }

  @ViewBuilder
  private var toast: some View {
    if let toast = model.toast {
      HStack(spacing: 12) {
        Text(toast.message)
          .font(.subheadline.weight(.medium))
          .lineLimit(2)
        Spacer(minLength: 8)
        if toast.undo != nil {
          Button("Undo") { model.undoToast() }
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: 44)
        }
      }
      .padding(.horizontal, 18)
      .padding(.vertical, 8)
      .glassEffect(.regular, in: .capsule)
      .padding(.horizontal)
      .padding(.bottom, 96)
      .transition(.move(edge: .bottom).combined(with: .opacity))
      .accessibilityElement(children: .contain)
      .accessibilityAddTraits(.isStaticText)
      .onAppear { UIAccessibility.post(notification: .announcement, argument: toast.message) }
    }
  }
}
