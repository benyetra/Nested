import NestedCore
import NestedData
import SQLiteData
import SwiftUI

struct RootView: View {
  @Environment(AppModel.self) private var model
  private var snapshot: NestedSnapshot { SideEffects.shared.snapshot }
  @State private var now = Date()
  @Namespace private var sheetSource

  var body: some View {
    @Bindable var model = model
    content
      .modifier(
        NightModeModifier(
          isOn: NightMode.isOn(
            setting: DevicePrefs.nightMode, window: snapshot.baby?.nightWindow ?? .defaultNight, now: now))
      )
      // Only this view re-evaluates each minute (night mode can flip); the tabs don't rebuild.
      .task {
        while !Task.isCancelled {
          try? await Task.sleep(for: .seconds(60))
          now = Date()
        }
      }
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
    .task {
      // Explain setup problems (e.g. a missing capability) instead of crashing at launch.
      if let problem = NestedBootstrap.problems.first, model.errorMessage == nil {
        model.errorMessage = problem
      }
    }
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
        Tab("Now", systemImage: "house.fill", value: AppTab.now) { NowView().undoToastHost() }
        Tab("Timeline", systemImage: "list.bullet", value: AppTab.timeline) { TimelineScreen().undoToastHost() }
        Tab("Trends", systemImage: "chart.bar.xaxis", value: AppTab.trends) { TrendsView().undoToastHost() }
        Tab("Doctor", systemImage: "stethoscope", value: AppTab.questions) { QuestionsView().undoToastHost() }
        Tab("Settings", systemImage: "gearshape", value: AppTab.settings) { SettingsView().undoToastHost() }
      }
      .environment(\.sheetNamespace, sheetSource)
      // Log sheets grow from the button that opened them and return to it.
      .sheet(item: $model.route) { route in
        LogSheet(kind: route.kind, snapshot: snapshot)
          .navigationTransition(.zoom(sourceID: ActionSourceID(kind: route.kind, active: true), in: sheetSource))
      }
    }
  }

}

extension View {
  /// Shows the undo toast above this tab's tab bar.
  func undoToastHost() -> some View {
    overlay(alignment: .bottom) { UndoToastView() }
  }
}

/// Every log shows a 5-second undo toast: undo, not confirm.
private struct UndoToastView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  var body: some View {
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
      .background {
        if reduceTransparency { Capsule().fill(Color(.secondarySystemBackground)) }
      }
      .glassEffect(reduceTransparency ? .identity : .regular, in: .capsule)
      .padding(.horizontal)
      .padding(.bottom, 8)
      // Enters and leaves along the same path; a cross-fade under Reduce Motion.
      .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
      .accessibilityElement(children: .contain)
      .onAppear { UIAccessibility.post(notification: .announcement, argument: toast.message) }
    }
  }
}
