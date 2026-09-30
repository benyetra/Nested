import SwiftUI
import WidgetKit

@main
struct NestedWidgetsBundle: WidgetBundle {
  var body: some Widget {
    LockScreenWidget()
    HomeWidget()
    TimerLiveActivity()
    NursingToggleControl()
    LogBottleControl()
    LogWetControl()
    LogDirtyControl()
    NapToggleControl()
    WakeUsControl()
    StopTimerControl()
  }
}
