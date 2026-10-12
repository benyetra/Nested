import NestedCore
import SwiftUI

/// Edits a length in minutes without tapping - and + dozens of times: one-tap presets, 5-minute
/// nudges, and a tap on the value to spin a wheel to any minute.
struct DurationEditor: View {
  let title: String
  @Binding var minutes: Double
  var maxMinutes = 120
  var presets = [5, 10, 15, 20, 30]
  var tint: Color = EventKind.nursing.color
  @State private var wheelOpen = false

  private var whole: Binding<Int> {
    Binding(get: { Int(minutes.rounded()) }, set: { minutes = Double($0) })
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Text(title)
        Spacer()
        nudge("minus", by: -5)
        Button {
          withNestedAnimation(Motion.standard) { wheelOpen.toggle() }
        } label: {
          Text("\(whole.wrappedValue) min")
            .font(.body.weight(.semibold).monospacedDigit())
            .foregroundStyle(tint)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(tint.opacity(wheelOpen ? 0.25 : 0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) \(whole.wrappedValue) minutes")
        .accessibilityHint("Opens a wheel to pick the minutes")
        nudge("plus", by: 5)
      }
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(presets, id: \.self) { value in
            Button { minutes = Double(value) } label: {
              Text("\(value)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(minWidth: 34)
                .padding(.vertical, 6).padding(.horizontal, 8)
                .background(Capsule().fill(whole.wrappedValue == value ? tint : tint.opacity(0.12)))
                .foregroundStyle(whole.wrappedValue == value ? .white : tint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(value) minutes")
          }
        }
      }
      if wheelOpen {
        Picker(title, selection: whole) {
          ForEach(0...maxMinutes, id: \.self) { Text("\($0) min").tag($0) }
        }
        .pickerStyle(.wheel)
        .frame(height: 120)
        .transition(.opacity)
      }
    }
    .padding(.vertical, 2)
    .sensoryFeedback(.selection, trigger: whole.wrappedValue)
  }

  private func nudge(_ symbol: String, by delta: Int) -> some View {
    Button {
      minutes = Double(min(maxMinutes, max(0, whole.wrappedValue + delta)))
    } label: {
      Image(systemName: symbol)
        .font(.footnote.weight(.bold))
        .frame(width: 34, height: 30)
        .background(Capsule().fill(tint.opacity(0.12)))
        .foregroundStyle(tint)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(delta > 0 ? "Add 5 minutes" : "Subtract 5 minutes")
  }
}
