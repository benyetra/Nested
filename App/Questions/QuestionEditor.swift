import NestCore
import NestData
import SwiftUI

/// Write a question, or come back at the appointment and write down the answer.
struct QuestionEditor: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.fontResolutionContext) private var fontContext

  let question: Question?
  @State private var body_: AttributedString
  @State private var answer: AttributedString
  @State private var isDone: Bool

  init(question: Question?) {
    self.question = question
    _body_ = State(initialValue: RichText(stored: question?.body ?? "").attributed())
    _answer = State(initialValue: RichText(stored: question?.answer ?? "").attributed())
    _isDone = State(initialValue: question?.isDone ?? false)
  }

  private var canSave: Bool { !RichText(body_, fontContext: fontContext).isEmpty }

  var body: some View {
    NavigationStack {
      Form {
        Section("Question") {
          RichTextEditor(
            text: $body_, placeholder: "What do you want to ask?", tint: QuestionStyle.tint)
        }
        Section {
          RichTextEditor(
            text: $answer, placeholder: "Write down what the doctor said", tint: QuestionStyle.tint)
        } header: {
          Text("Answer")
        } footer: {
          Text("Saving an answer checks the question off.")
        }
        if question != nil {
          Section {
            Toggle("Asked", isOn: $isDone).tint(QuestionStyle.tint)
          }
        }
      }
      .nestListBackground()
      .navigationTitle(question == nil ? "New question" : "Question")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save", action: save).disabled(!canSave).fontWeight(.semibold)
        }
      }
    }
    .presentationDetents([.large])
  }

  private func save() {
    let bodyText = RichText(body_, fontContext: fontContext)
    let answerText = RichText(answer, fontContext: fontContext)
    if let question {
      model.updateQuestion(question, body: bodyText, answer: answerText, done: isDone)
    } else {
      model.addQuestion(bodyText, answer: answerText)
    }
    dismiss()
  }
}

enum QuestionStyle {
  static let tint = Color.teal
}

extension AppModel {
  func addQuestion(_ body: RichText, answer: RichText = RichText()) {
    perform(haptic: .success, undo: .none) {
      let created = try store.addQuestion(body)
      if !answer.isEmpty {
        try store.updateQuestion(id: created.id, body: body, answer: answer)
      }
      return nil
    }
  }

  func updateQuestion(_ question: Question, body: RichText, answer: RichText, done: Bool) {
    perform(haptic: .success, undo: .none) {
      try store.updateQuestion(id: question.id, body: body, answer: answer)
      // Saving a new answer already checks it off; a hand-flipped checkbox wins otherwise.
      if done != question.isDone {
        try store.setQuestionDone(id: question.id, done: done)
      }
      return nil
    }
  }

  func toggleQuestion(_ question: Question) {
    perform(haptic: .selection, undo: .none) {
      try store.setQuestionDone(id: question.id, done: !question.isDone)
      return nil
    }
  }

  func deleteQuestion(_ question: Question) {
    perform(haptic: .impact, undo: .none) {
      try store.deleteQuestion(id: question.id)
      return nil
    }
    let store = store
    showToast("Deleted question", undo: { try? store.restoreQuestion(question) })
  }

  func clearAnswered(_ questions: [Question]) {
    perform(haptic: .impact, undo: .none) {
      for question in questions { try store.deleteQuestion(id: question.id) }
      return nil
    }
    let store = store
    showToast(
      "Cleared \(questions.count) answered",
      undo: { for question in questions { try? store.restoreQuestion(question) } })
  }
}
