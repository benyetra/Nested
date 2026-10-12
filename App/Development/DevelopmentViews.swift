import NestedCore
import NestedData
import SwiftUI

extension DevelopmentArea {
  var color: Color {
    switch self {
    case .vision: .indigo
    case .hearing: .teal
    case .movement: .orange
    case .social: .pink
    case .feeding: .green
    case .sleep: .purple
    case .brain: .yellow
    }
  }

  var symbol: String {
    switch self {
    case .vision: "eye.fill"
    case .hearing: "ear.fill"
    case .movement: "figure.and.child.holdinghands"
    case .social: "face.smiling.fill"
    case .feeding: "drop.fill"
    case .sleep: "moon.zzz.fill"
    case .brain: "lightbulb.fill"
    }
  }
}

/// Age used for development, from the birth date or, for a baby born early, the due date.
struct DevelopmentAge {
  let days: Int
  let correctionDays: Int
  var stage: DevelopmentStage { DevelopmentGuide.stage(ageDays: days) }

  init?(birth: Date?, due: Date? = DevicePrefs.dueDate, now: Date = Date()) {
    guard let birth else { return nil }
    days = DevelopmentGuide.ageDays(birth: birth, due: due, now: now)
    correctionDays = DevelopmentGuide.correctionDays(birth: birth, due: due)
  }

  var correctionNote: String? {
    guard correctionDays > 0 else { return nil }
    let weeks = correctionDays / 7
    return "Adjusted for being born \(weeks) week\(weeks == 1 ? "" : "s") early."
  }
}

/// Home card: the one thing worth knowing about this stage, tap for the full picture.
struct DevelopmentCard: View {
  let name: String
  let age: DevelopmentAge
  var open: () -> Void

  var body: some View {
    let stage = age.stage
    Button(action: open) {
      Card(tint: .pink) {
        VStack(alignment: .leading, spacing: 10) {
          HStack(alignment: .firstTextBaseline) {
            Label("\(name)'s development", systemImage: "sparkles")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.pink)
            Spacer()
            Text(stage.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
          }
          Text(stage.headline).font(.title3.weight(.semibold)).foregroundStyle(.primary)
          if let first = stage.items.first {
            HStack(alignment: .top, spacing: 8) {
              AreaBadge(area: first.area)
              Text(first.text).font(.subheadline).foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            }
          }
          Text("See what's happening").font(.footnote.weight(.semibold)).foregroundStyle(.pink)
        }
      }
    }
    .buttonStyle(.plain)
    .accessibilityHint("Opens what to expect at this age")
  }
}

struct AreaBadge: View {
  let area: DevelopmentArea
  var body: some View {
    Image(systemName: area.symbol)
      .font(.caption.weight(.bold))
      .foregroundStyle(.white)
      .frame(width: 26, height: 26)
      .background(Circle().fill(area.color.gradient))
      .accessibilityHidden(true)
  }
}

struct DevelopmentSheet: View {
  let name: String
  let age: DevelopmentAge
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          let stage = age.stage
          VStack(alignment: .leading, spacing: 6) {
            Text(stage.title).font(.subheadline.weight(.semibold)).foregroundStyle(.pink)
            Text(stage.headline).font(.largeTitle.bold())
            if let note = age.correctionNote {
              Text(note).font(.footnote).foregroundStyle(.secondary)
            }
          }

          ForEach(stage.items) { item in
            Card(tint: item.area.color) {
              HStack(alignment: .top, spacing: 12) {
                AreaBadge(area: item.area)
                VStack(alignment: .leading, spacing: 3) {
                  Text(item.area.title).font(.subheadline.weight(.semibold)).foregroundStyle(item.area.color)
                  Text(item.text).font(.body)
                }
              }
            }
            .accessibilityElement(children: .combine)
          }

          Card(tint: .mint) {
            VStack(alignment: .leading, spacing: 4) {
              Label("Try this", systemImage: "hands.sparkles.fill")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.mint)
              Text(stage.tryThis)
            }
          }

          if let next = DevelopmentGuide.next(after: stage), let days = DevelopmentGuide.daysUntilNext(ageDays: age.days) {
            VStack(alignment: .leading, spacing: 4) {
              Text("Coming up in \(days == 1 ? "1 day" : "\(days) days")")
                .font(.headline)
              Text("\(next.title): \(next.headline)").font(.subheadline).foregroundStyle(.secondary)
              if let teaser = next.items.first {
                Text(teaser.text).font(.footnote).foregroundStyle(.secondary)
              }
            }
            .padding(.top, 4)
          }

          Text(DevelopmentGuide.disclaimer).font(.footnote).foregroundStyle(.secondary).padding(.top, 4)
        }
        .padding()
      }
      .nestedBackground()
      .navigationTitle("\(name)'s development")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
      }
    }
    .presentationDetents([.large])
  }
}
