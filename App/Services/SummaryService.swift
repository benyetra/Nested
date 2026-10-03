import Foundation
import NestedCore

#if canImport(FoundationModels)
  import FoundationModels
#endif

/// Weekly summary: numbers are computed in code (`WeeklyDigest`); Apple's on-device model
/// only turns them into two plain sentences. No data leaves the phone.
enum SummaryService {
  static func summarize(_ digest: WeeklyDigest, babyName: String, unit: VolumeUnit) async -> String {
    let fallback = digest.fallbackText(babyName: babyName, unit: unit)
    #if canImport(FoundationModels)
      guard case .available = SystemLanguageModel.default.availability else { return fallback }
      let session = LanguageModelSession(
        instructions: """
          You write a two-sentence weekly summary of a newborn's tracked data for her parents. \
          Use only the facts given, keep every number exactly as given, be warm and plain, and \
          never give medical advice or interpret the numbers as good or bad.
          """
      )
      let facts = digest.facts(babyName: babyName, unit: unit).map { "- \($0)" }.joined(separator: "\n")
      do {
        let response = try await session.respond(to: "Facts for this week:\n\(facts)\n\nWrite exactly two sentences.")
        let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? fallback : text
      } catch {
        return fallback
      }
    #else
      return fallback
    #endif
  }

  static var modelAvailable: Bool {
    #if canImport(FoundationModels)
      if case .available = SystemLanguageModel.default.availability { return true }
    #endif
    return false
  }

  /// Why the on-device model can't be used, in words for the user; nil when it can.
  static var unavailableReason: String? {
    #if canImport(FoundationModels)
      switch SystemLanguageModel.default.availability {
      case .available: return nil
      case .unavailable(.deviceNotEligible): return "This device doesn't support Apple Intelligence."
      case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in Settings to get answers."
      case .unavailable(.modelNotReady): return "The on-device model is still downloading. Try again soon."
      case .unavailable: return "The on-device model isn't available right now."
      }
    #else
      return "Apple Intelligence isn't available on this device."
    #endif
  }

  #if canImport(FoundationModels)
    @Generable(description: "A short summary for a newborn's parents")
    struct GeneratedBriefing {
      @Guide(description: "One or two short, warm, plain sentences about the most important thing in the facts. Do not list the findings, do not repeat each one, and do not use square brackets.")
      var summary: String
    }
  #endif

  /// The briefing: a headline from code (so it can't contradict the findings) plus a one or two
  /// sentence summary the model writes from the facts. The findings themselves are shown as cards
  /// elsewhere, so the model is told not to list them.
  static func brief(facts: [String], fallback: BriefingContent, babyName: String) async -> BriefingContent {
    #if canImport(FoundationModels)
      guard modelAvailable else { return fallback }
      let session = LanguageModelSession(
        instructions: """
          You write a very short summary for the parents of a newborn named \(babyName) from tracked \
          data. Use only the facts given and keep every number exactly as given. Mention at most the \
          one or two things that matter most, and leave the rest to the detailed list the parents can \
          already see. If something is marked WORTH RAISING WITH THE PEDIATRICIAN, say it is worth \
          mentioning to the pediatrician; if nothing is marked that way or as CHANGE TO WATCH, \
          keep it reassuring. Never diagnose, never recommend treatment or changes to feeding, and \
          never say anything is definitely fine or definitely wrong. At most two short sentences.
          """)
      let list = facts.prefix(24).map { "- \($0)" }.joined(separator: "\n")
      do {
        let response = try await session.respond(
          to: "Facts:\n\(list)", generating: GeneratedBriefing.self,
          options: GenerationOptions(temperature: 0.2))
        guard let text = InsightBrief.cleaned(response.content.summary) else { return fallback }
        return BriefingContent(headline: fallback.headline, summary: text)
      } catch {
        return fallback
      }
    #else
      return fallback
    #endif
  }

  /// Answers a parent's question about the recent data, streaming the text as it's written.
  /// `onPartial` receives the full text so far.
  static func answer(
    question: String, facts: [String], table: [String], babyName: String,
    onPartial: @MainActor (String) -> Void
  ) async {
    #if canImport(FoundationModels)
      if let reason = unavailableReason {
        await onPartial(reason)
        return
      }
      let session = LanguageModelSession(
        instructions: """
          You answer a parent's question about their newborn \(babyName) using only the tracked \
          data given. Quote numbers exactly as given and mention the day when relevant. If the \
          data does not answer the question, say so. Keep answers under four sentences. Never \
          diagnose or give medical advice; for health worries suggest asking the pediatrician.
          """)
      let prompt = """
        Findings:
        \(facts.prefix(24).map { "- \($0)" }.joined(separator: "\n"))

        Daily data (oldest first):
        \(table.joined(separator: "\n"))

        Question: \(question)
        """
      do {
        for try await partial in session.streamResponse(to: prompt) {
          await onPartial(partial.content)
        }
      } catch {
        await onPartial("I couldn't answer that just now. Try rephrasing.")
      }
    #else
      await onPartial(unavailableReason ?? "")
    #endif
  }
}
