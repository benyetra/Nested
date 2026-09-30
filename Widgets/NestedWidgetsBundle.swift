import SwiftUI
import WidgetKit

@main
struct NestedWidgetsBundle: WidgetBundle {
  var body: some Widget {
    LockScreenWidget()
    HomeWidget()
    TimerLiveActivity()
    LogBottleControl()
    LogWetControl()
    LogDirtyControl()
    NapToggleControl()
    NursingToggleControl()
    WakeUsControl()
    StopTimerControl()
  }
}
