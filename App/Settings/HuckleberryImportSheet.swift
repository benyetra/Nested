import NestedCore
import NestedData
import SwiftUI
import UniformTypeIdentifiers

/// Bring in history from a Huckleberry export: pick the file, check what it found, import.
struct HuckleberryImportSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  @State private var choosing = false
  @State private var result: HuckleberryImport.Result?
  @State private var fileName = ""
  @State private var failure: String?

  private static let types: [UTType] = [
    .commaSeparatedText, .plainText, UTType(filenameExtension: "xlsx") ?? .data,
  ]
  private let kinds: [EventKind] = [.nursing, .bottle, .diaper, .sleep, .pump, .note]

  var body: some View {
    NavigationStack {
      Form {
        if let result {
          summary(result)
        } else {
          Section {
            Label("In Huckleberry: Child ▸ Reports, then “Export tracking data as CSV”. They email you a download link.", systemImage: "1.circle.fill")
            Label("Save the file to Files (or AirDrop it to this phone).", systemImage: "2.circle.fill")
            Label("Choose it below. Nothing is added until you confirm.", systemImage: "3.circle.fill")
          } header: {
            Text("How")
          }
          .font(.subheadline)

          Section {
            Button("Choose file…", systemImage: "doc.badge.plus") { choosing = true }
          } footer: {
            if let failure { Text(failure).foregroundStyle(.red) }
          }
        }
      }
      .nestedListBackground()
      .navigationTitle("Import from Huckleberry")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
      }
      .fileImporter(isPresented: $choosing, allowedContentTypes: Self.types) { pick in
        load(pick)
      }
      .safeAreaInset(edge: .bottom) {
        if let result, !result.rows.isEmpty {
          PrimaryButton(title: "Import \(result.rows.count) entries", systemImage: "square.and.arrow.down") {
            commit(result)
          }
          .padding(.horizontal, 20)
          .padding(.bottom, 8)
        }
      }
    }
    .presentationDetents([.large])
  }

  @ViewBuilder
  private func summary(_ result: HuckleberryImport.Result) -> some View {
    Section {
      ForEach(kinds.filter { result.count(of: $0) > 0 }, id: \.self) { kind in
        HStack(spacing: 12) {
          EventBadge(kind: kind, size: 30)
          Text(kind == .note ? "Notes" : kind.title)
          Spacer()
          Text("\(result.count(of: kind))").monospacedDigit().foregroundStyle(.secondary)
        }
      }
      if result.rows.isEmpty {
        Text("Nothing importable was found in \(fileName).").foregroundStyle(.secondary)
      }
    } header: {
      Text(fileName)
    } footer: {
      VStack(alignment: .leading, spacing: 4) {
        if let first = result.earliest, let last = result.latest {
          Text("\(first.formatted(date: .abbreviated, time: .omitted)) to \(last.formatted(date: .abbreviated, time: .omitted)), in this phone's time zone.")
        }
        if result.duplicates > 0 {
          Text("\(result.duplicates) repeated rows are counted once.")
        }
        Text("Anything already logged at the same time is skipped, so importing twice is harmless.")
      }
    }

    if !result.skipped.isEmpty {
      Section("Skipped (\(result.skipped.count))") {
        ForEach(result.skipped.prefix(20), id: \.self) { skipped in
          Text("Row \(skipped.line): \(skipped.reason)").font(.footnote)
        }
      }
    }

    Section {
      Button("Choose a different file…") { choosing = true }
    }
  }

  private func load(_ pick: Result<URL, any Error>) {
    do {
      let url = try pick.get()
      let accessing = url.startAccessingSecurityScopedResource()
      defer { if accessing { url.stopAccessingSecurityScopedResource() } }
      let data = try Data(contentsOf: url)
      result = try HuckleberryImport.parse(data: data)
      fileName = url.lastPathComponent
      failure = nil
    } catch {
      result = nil
      failure = String(describing: error)
    }
  }

  private func commit(_ result: HuckleberryImport.Result) {
    let store = model.store
    let rows = result.rows
    var added = 0
    model.perform(nil, haptic: .success, undo: .none) {
      added = try store.importEntries(rows)
      return nil
    }
    let already = rows.count - added
    model.showToast(
      already > 0
        ? "Imported \(added) entries (\(already) already there)"
        : "Imported \(added) entr\(added == 1 ? "y" : "ies")")
    dismiss()
  }
}
