import NestedCore
import SwiftUI

/// Converts between the stored `RichText` and the `AttributedString` the editor works on.
/// Bold and italic ride on `font`, which is what the system's own Format menu writes too.
extension RichText {
  func attributed() -> AttributedString {
    var result = AttributedString()
    for run in runs {
      var piece = AttributedString(run.text)
      if run.bold || run.italic {
        var font = Font.body
        if run.bold { font = font.bold() }
        if run.italic { font = font.italic() }
        piece.font = font
      }
      if run.underline { piece.underlineStyle = .single }
      if run.strikethrough { piece.strikethroughStyle = .single }
      result += piece
    }
    return result
  }

  init(_ attributed: AttributedString, fontContext: Font.Context) {
    var runs: [RichRun] = []
    for run in attributed.runs {
      let resolved = run.font?.resolve(in: fontContext)
      let intent = run.inlinePresentationIntent ?? []
      runs.append(
        RichRun(
          String(attributed[run.range].characters),
          bold: resolved?.isBold == true || intent.contains(.stronglyEmphasized),
          italic: resolved?.isItalic == true || intent.contains(.emphasized),
          underline: run.underlineStyle != nil,
          strikethrough: run.strikethroughStyle != nil || intent.contains(.strikethrough)))
    }
    self.init(runs: runs)
  }
}

/// A rich text field with a Bold / Italic / Underline / Strikethrough bar above it.
struct RichTextEditor: View {
  @Binding var text: AttributedString
  var placeholder: String
  var tint: Color
  var minHeight: CGFloat = 110

  @State private var selection = AttributedTextSelection()
  @Environment(\.fontResolutionContext) private var fontContext

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        formatButton("bold", label: "Bold") { font in
          font.bold(!font.resolveIsBold(fontContext))
        }
        formatButton("italic", label: "Italic") { font in
          font.italic(!font.resolveIsItalic(fontContext))
        }
        lineButton("underline", label: "Underline", keyPath: \.underlineStyle)
        lineButton("strikethrough", label: "Strikethrough", keyPath: \.strikethroughStyle)
      }
      ZStack(alignment: .topLeading) {
        TextEditor(text: $text, selection: $selection)
          .frame(minHeight: minHeight)
          .scrollContentBackground(.hidden)
        if text.characters.isEmpty {
          Text(placeholder)
            .foregroundStyle(.tertiary)
            .padding(.top, 8)
            .padding(.leading, 5)
            .allowsHitTesting(false)
        }
      }
    }
  }

  private func formatButton(_ symbol: String, label: String, _ change: @escaping (Font) -> Font) -> some View {
    Button {
      text.transformAttributes(in: &selection) { attributes in
        attributes.font = change(attributes.font ?? .body)
      }
    } label: {
      barIcon(symbol)
    }
    .accessibilityLabel(label)
  }

  private func lineButton(
    _ symbol: String, label: String,
    keyPath: WritableKeyPath<AttributeContainer, Text.LineStyle?>
  ) -> some View {
    Button {
      text.transformAttributes(in: &selection) { attributes in
        attributes[keyPath: keyPath] = attributes[keyPath: keyPath] == nil ? .single : nil
      }
    } label: {
      barIcon(symbol)
    }
    .accessibilityLabel(label)
  }

  private func barIcon(_ symbol: String) -> some View {
    Image(systemName: symbol)
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(tint)
      .frame(width: 44, height: 36)
      .background(Capsule().fill(tint.opacity(0.12)))
      .contentShape(Capsule())
  }
}

private extension Font {
  func resolveIsBold(_ context: Font.Context) -> Bool { resolve(in: context).isBold }
  func resolveIsItalic(_ context: Font.Context) -> Bool { resolve(in: context).isItalic }
}
