import NestCore
import NestData
import SwiftUI

// Motion spec from the PRD, in one place. Reduce Motion swaps springs for 200 ms cross-fades.
enum Motion {
  /// Default UI change: critically damped, no bounce.
  static let standard = Animation.spring(response: 0.35, dampingFraction: 1.0)
  /// Sheet present/dismiss: slight bounce, only because a gesture drove it.
  static let sheet = Animation.spring(response: 0.3, dampingFraction: 0.8)
  /// Side switch L ↔ R.
  static let sideSwitch = Animation.spring(response: 0.4, dampingFraction: 0.8)
  /// Night mode fades over 400 ms, never a flash.
  static let nightFade = Animation.easeInOut(duration: 0.4)
  static let reduced = Animation.easeInOut(duration: 0.2)

  static func resolve(_ animation: Animation, reduceMotion: Bool) -> Animation {
    reduceMotion ? reduced : animation
  }
}

/// `withAnimation` that honours Reduce Motion (a 200 ms cross-fade instead of a spring).
@MainActor
@discardableResult
func withNestAnimation<Result>(
  _ animation: Animation = Motion.standard, _ body: () throws -> Result
) rethrows -> Result {
  try withAnimation(Motion.resolve(animation, reduceMotion: UIAccessibility.isReduceMotionEnabled), body)
}

extension View {
  /// Applies `animation` for `value`, or a short cross-fade under Reduce Motion.
  func nestAnimation<V: Equatable>(_ animation: Animation = Motion.standard, value: V) -> some View {
    modifier(NestAnimationModifier(animation: animation, value: value))
  }
}

private struct NestAnimationModifier<V: Equatable>: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let animation: Animation
  let value: V

  func body(content: Content) -> some View {
    content.animation(Motion.resolve(animation, reduceMotion: reduceMotion), value: value)
  }
}

/// Feedback on press (scale to 0.97 over 100 ms), commit on release.
struct PressableStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
      .contentShape(.rect)
  }
}

extension ButtonStyle where Self == PressableStyle {
  static var pressable: PressableStyle { PressableStyle() }
}

// MARK: - Palette

/// Warm paper and ink instead of system grays: cream in light mode, deep warm navy in dark.
/// The six event colours do the talking on top of it.
enum Palette {
  static let background = Color(
    uiColor: UIColor { traits in
      traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.07, green: 0.07, blue: 0.10, alpha: 1)
        : UIColor(red: 0.985, green: 0.965, blue: 0.94, alpha: 1)
    })

  static let card = Color(
    uiColor: UIColor { traits in
      traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.13, green: 0.13, blue: 0.17, alpha: 1)
        : UIColor(red: 1.0, green: 0.995, blue: 0.985, alpha: 1)
    })

  /// A soft wash of an event colour: stronger at the top-leading corner, fading out.
  static func wash(_ color: Color, strength: Double = 1) -> LinearGradient {
    LinearGradient(
      colors: [color.opacity(0.22 * strength), color.opacity(0.08 * strength)],
      startPoint: .topLeading, endPoint: .bottomTrailing)
  }
}

/// The screen background used by every tab.
extension View {
  func nestBackground() -> some View {
    background(Palette.background.ignoresSafeArea())
  }

  /// For List/Form screens: hide the system gray so the warm paper shows through.
  func nestListBackground() -> some View {
    scrollContentBackground(.hidden).nestBackground()
  }
}

/// An event icon on a filled circle of its colour.
struct EventBadge: View {
  let kind: EventKind
  var size: CGFloat = 28

  var body: some View {
    Image(systemName: kind.symbol)
      .font(.system(size: size * 0.5, weight: .semibold))
      .foregroundStyle(.white)
      .frame(width: size, height: size)
      .background(Circle().fill(kind.color.gradient))
      .accessibilityHidden(true)
  }
}

// MARK: - Surfaces

/// A card on the Now screen. Solid under Reduce Transparency; never glass on glass.
struct Card<Content: View>: View {
  var tint: Color? = nil
  @ViewBuilder var content: Content

  var body: some View {
    content
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(16)
      .background {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
          .fill(Palette.card)
          .overlay {
            if let tint {
              RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Palette.wash(tint))
            }
          }
          .shadow(color: (tint ?? .black).opacity(0.08), radius: 12, y: 4)
      }
  }
}

/// Chip used for backdating, amounts and quick choices.
struct Chip: View {
  let title: String
  var systemImage: String? = nil
  var isSelected = false
  var tint: Color = .accentColor
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 4) {
        if let systemImage { Image(systemName: systemImage) }
        Text(title).monospacedDigit()
      }
      .font(.subheadline.weight(.medium))
      .padding(.horizontal, 14)
      .padding(.vertical, 9)
      .frame(minHeight: 44)
      .background(
        Capsule().fill(isSelected ? tint.opacity(0.25) : Color(.tertiarySystemFill))
      )
      .overlay(Capsule().strokeBorder(isSelected ? tint : .clear, lineWidth: 1.5))
      .foregroundStyle(isSelected ? tint : .primary)
    }
    .buttonStyle(.pressable)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

/// Initial badge showing which parent logged an entry.
struct ParentBadge: View {
  let name: String

  var body: some View {
    Text(DevicePrefs.initial(for: name))
      .font(.caption2.weight(.bold))
      .frame(width: 22, height: 22)
      .background(Circle().fill(Color(.tertiarySystemFill)))
      .accessibilityLabel(name.isEmpty ? "Unknown parent" : "Logged by \(name)")
  }
}

/// Primary full-width action at the bottom of a sheet, in thumb reach.
struct PrimaryButton: View {
  let title: String
  var systemImage: String? = nil
  var tint: Color = .accentColor
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Label {
        Text(title)
      } icon: {
        if let systemImage { Image(systemName: systemImage) }
      }
      .font(.headline)
      .frame(maxWidth: .infinity, minHeight: 56)
    }
    .buttonStyle(.borderedProminent)
    .buttonBorderShape(.capsule)
    .tint(tint)
    // Content scrolling under the button fades out instead of showing through.
    .background(alignment: .bottom) {
      Rectangle()
        .fill(.background)
        .mask(LinearGradient(colors: [.clear, .black, .black], startPoint: .top, endPoint: .bottom))
        .padding(.top, -24)
        .padding(.horizontal, -20)
        .padding(.bottom, -40)
        .allowsHitTesting(false)
    }
  }
}

// MARK: - Night mode

/// Night mode: true black, red-shifted, no pure white. Applied at the root.
struct NightModeModifier: ViewModifier {
  let isOn: Bool

  func body(content: Content) -> some View {
    content
      .preferredColorScheme(isOn ? .dark : nil)
      .colorMultiply(isOn ? NightPalette.multiply : .white)
      .tint(isOn ? NightPalette.accent : nil)
      .background(isOn ? Color.black : Color.clear)
      .animation(Motion.nightFade, value: isOn)
  }
}

enum NightMode {
  static func isOn(setting: NightModeSetting, window: DayWindow, now: Date) -> Bool {
    switch setting {
    case .alwaysOn: true
    case .off: false
    case .automatic: window.contains(now)
    }
  }
}
