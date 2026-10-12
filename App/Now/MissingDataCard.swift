import NestedCore
import NestedData
import SwiftUI

/// "Missing anything?": gaps in the log that look out of pattern, each with a one-tap guess.
struct MissingDataCard: View {
  let suggestions: [MissingSuggestion]
  let unit: VolumeUnit
  var add: (MissingSuggestion) -> Void
  var dismiss: (MissingSuggestion) -> Void

  var body: some View {
    Card(tint: .teal) {
      VStack(alignment: .leading, spacing: 12) {
        Label("Missing anything?", systemImage: "questionmark.bubble.fill")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.teal)
        ForEach(suggestions) { item in
          HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
              Text("\(title(item)) around \(item.at.formatted(date: .omitted, time: .shortened))")
                .font(.subheadline.weight(.semibold))
              Text(item.reason).font(.footnote).foregroundStyle(.secondary)
              Text("Adds \(summary(item))").font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Add") { add(item) }
              .buttonStyle(.borderedProminent).tint(.teal).controlSize(.small)
            Button { dismiss(item) } label: {
              Image(systemName: "xmark").font(.footnote.weight(.bold)).frame(width: 32, height: 32)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .accessibilityLabel("Not missing")
          }
        }
      }
    }
  }

  private func title(_ item: MissingSuggestion) -> String {
    switch item.guess {
    case .nursing: "A feed"
    case .bottle: "A bottle"
    case .diaper: "A diaper change"
    }
  }

  private func summary(_ item: MissingSuggestion) -> String {
    switch item.guess {
    case .nursing(let l, let r):
      return "nursing, \(Durations.format(l + r))"
    case .bottle(let ml, let contents):
      return "\(Volume.format(ml: ml, unit: unit)) \(contents.title.lowercased())"
    case .diaper(let kind):
      return "a \(kind.title.lowercased()) diaper"
    }
  }
}

enum MissingDismissals {
  private static let key = "dismissedMissing"
  static func load() -> Set<String> { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }
  static func add(_ id: String) {
    var all = load()
    all.insert(id)
    // Old ids are meaningless after a few days; keep the list short.
    UserDefaults.standard.set(Array(all.suffix(200)), forKey: key)
  }
}
