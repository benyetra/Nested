import NestedCore
import NestedData
import SwiftUI

enum DoctorMode: String, CaseIterable, Identifiable {
  case questions = "Questions"
  case medicines = "Medicines"
  var id: String { rawValue }
}

/// The Doctor tab: questions for the pediatrician, and the medicines both parents are reminded about.
struct DoctorView: View {
  @State private var mode: DoctorMode = .questions

  var body: some View {
    NavigationStack {
      Group {
        switch mode {
        case .questions: QuestionsList(mode: $mode)
        case .medicines: MedicationsList(mode: $mode)
        }
      }
      .nestedListBackground()
      .actionBarInset(tab: .questions)
      .navigationTitle("Doctor")
    }
  }
}

/// Switches between the two halves of the Doctor tab, as the first row of each list.
struct DoctorModePicker: View {
  @Binding var mode: DoctorMode

  var body: some View {
    Section {
      Picker("Show", selection: $mode) {
        ForEach(DoctorMode.allCases) { Text($0.rawValue).tag($0) }
      }
      .pickerStyle(.segmented)
      .listRowBackground(Color.clear)
      .listRowInsets(EdgeInsets())
    }
  }
}
