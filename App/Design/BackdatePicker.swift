import SwiftUI

/// "Started __ min ago" chips plus a time wheel that defaults to now and can't go into the
/// future. Entries are often logged after the fact, so this sits on every log sheet.
struct BackdatePicker: View {
  @Binding var date: Date
  var label = "Time"
  @State private var showsWheel = false
  @State private var anchor = Date()

  private let chips = [0, 5, 10, 15, 30]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(chips, id: \.self) { minutes in
            Chip(
              title: minutes == 0 ? "Now" : "\(minutes) min ago",
              isSelected: isSelected(minutes)
            ) {
              anchor = Date()
              date = anchor.addingTimeInterval(-Double(minutes) * 60)
            }
          }
          Chip(title: showsWheel ? "Done" : "Other…", systemImage: "clock", isSelected: showsWheel) {
            withAnimation(Motion.standard) { showsWheel.toggle() }
          }
        }
      }
      .scrollClipDisabled()

      if showsWheel {
        DatePicker(label, selection: $date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
          .datePickerStyle(.wheel)
          .labelsHidden()
          .frame(maxWidth: .infinity)
          .transition(.opacity.combined(with: .move(edge: .top)))
      } else if !isSelected(0) {
        Text(date, format: .dateTime.weekday(.abbreviated).hour().minute())
          .font(.footnote)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(label)
  }

  private func isSelected(_ minutes: Int) -> Bool {
    abs(anchor.addingTimeInterval(-Double(minutes) * 60).timeIntervalSince(date)) < 30
  }
}
