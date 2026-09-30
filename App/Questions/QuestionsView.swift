import NestedCore
import NestedData
import SQLiteData
import SwiftUI

/// Questions for the pediatrician as a shared to-do list. Jot one down any time; at the
/// appointment, tick it off and write the answer underneath.
struct QuestionsView: View {
  @Environment(AppModel.self) private var model
  @Fetch(QuestionsRequest(), animation: Motion.standard) private var questions: [Question] = []
  @State private var draft = ""
  @State private var editing: Question?
  @State private var creating = false
  @State private var confirmClear = false
  @FocusState private var draftFocused: Bool

  private var canAdd: Bool { !RichText(plain: draft).isEmpty }
  private var open: [Question] { questions.filter { !$0.isDone } }
  private var answered: [Question] { questions.filter(\.isDone) }

  var body: some View {
    NavigationStack {
      List {
        Section {
          HStack(spacing: 10) {
            Button(action: addDraft) {
              Image(systemName: "plus.circle.fill")
                .font(.title2)
                .foregroundStyle(canAdd ? QuestionStyle.tint : Color.secondary.opacity(0.5))
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(!canAdd)
            .accessibilityLabel("Add question")
            // Single line: a vertical-axis field treats return as a new line, not submit.
            TextField("Add a question for the doctor", text: $draft)
              .focused($draftFocused)
              .submitLabel(.done)
              .onSubmit(addDraft)
          }
        }

        if questions.isEmpty {
          ContentUnavailableView(
            "No questions yet", systemImage: "stethoscope",
            description: Text("Jot down anything you want to ask at the next visit. You both see the list."))
            .listRowBackground(Color.clear)
        }

        if !open.isEmpty {
          Section("To ask · \(open.count)") {
            ForEach(open) { row($0) }
          }
        }
        if !answered.isEmpty {
          Section("Asked") {
            ForEach(answered) { row($0) }
          }
        }
      }
      .listStyle(.insetGrouped)
      .scrollDismissesKeyboard(.interactively)
      .nestedListBackground()
      .actionBarInset(tab: .questions)
      .navigationTitle("Doctor")
      .toolbar {
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button("Done") { draftFocused = false }
        }
        ToolbarItem(placement: .primaryAction) {
          Button("New question with formatting", systemImage: "square.and.pencil") { creating = true }
        }
        if !answered.isEmpty {
          ToolbarItem(placement: .secondaryAction) {
            Button("Clear asked", systemImage: "trash", role: .destructive) { confirmClear = true }
          }
        }
      }
      .confirmationDialog("Clear \(answered.count) asked questions?", isPresented: $confirmClear, titleVisibility: .visible) {
        Button("Clear asked", role: .destructive) { model.clearAnswered(answered) }
      }
      .sheet(item: $editing) { QuestionEditor(question: $0) }
      .sheet(isPresented: $creating) { QuestionEditor(question: nil) }
    }
  }

  private func addDraft() {
    let text = RichText(plain: draft)
    guard !text.isEmpty else { return }
    model.addQuestion(text)
    draft = ""
    draftFocused = false
  }

  private func row(_ question: Question) -> some View {
    QuestionRow(question: question, onToggle: { model.toggleQuestion(question) })
      .contentShape(Rectangle())
      .onTapGesture { editing = question }
      .swipeActions(edge: .trailing, allowsFullSwipe: true) {
        Button("Delete", systemImage: "trash", role: .destructive) { model.deleteQuestion(question) }
      }
      .swipeActions(edge: .leading) {
        Button(question.isDone ? "Not asked" : "Asked", systemImage: question.isDone ? "arrow.uturn.backward" : "checkmark") {
          model.toggleQuestion(question)
        }
        .tint(QuestionStyle.tint)
      }
  }
}

private struct QuestionRow: View {
  let question: Question
  let onToggle: () -> Void

  var body: some View {
    let text = RichText(stored: question.body).attributed()
    let answer = RichText(stored: question.answer)
    HStack(alignment: .top, spacing: 12) {
      Button(action: onToggle) {
        Image(systemName: question.isDone ? "checkmark.circle.fill" : "circle")
          .font(.title2)
          .foregroundStyle(question.isDone ? QuestionStyle.tint : Color.secondary)
          .contentTransition(.symbolEffect(.replace))
          .frame(width: 44, height: 44)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(question.isDone ? "Asked" : "Not asked yet")
      .accessibilityHint("Double tap to toggle")
      .padding(.leading, -8)

      VStack(alignment: .leading, spacing: 8) {
        Text(text)
          .foregroundStyle(question.isDone ? .secondary : .primary)
          .frame(maxWidth: .infinity, alignment: .leading)
        if !answer.isEmpty {
          VStack(alignment: .leading, spacing: 4) {
            Label("Answer", systemImage: "stethoscope")
              .font(.caption.weight(.semibold))
              .foregroundStyle(QuestionStyle.tint)
            Text(answer.attributed())
              .font(.subheadline)
          }
          .padding(10)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(QuestionStyle.tint.opacity(0.12)))
        }
        HStack(spacing: 6) {
          if !question.askedBy.isEmpty { ParentBadge(name: question.askedBy) }
          Text(question.createdAt, format: .dateTime.month(.abbreviated).day())
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .padding(.vertical, 6)
    }
  }
}
