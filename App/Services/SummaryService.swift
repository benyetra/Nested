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

  /// A short briefing: what to bring to attention first, then what's going well. Facts come
  /// from `InsightBrief`; the model only phrases them.
  static func brief(facts: [String], fallback: String, babyName: String) async -> String {
    #if canImport(FoundationModels)
      guard modelAvailable else { return fallback }
      let session = LanguageModelSession(
        instructions: """
          You write a short briefing for the parents of a newborn named \(babyName), from tracked \
          data. Write three to four plain, warm sentences. Start with anything marked WORTH RAISING \
          WITH THE PEDIATRICIAN or CHANGE TO WATCH, saying it is worth mentioning to the pediatrician \
          where marked, then say what is going well. Use only the facts given and keep every number \
          exactly as given. Never diagnose, never recommend treatment or changes to feeding, and \
          never say anything is definitely fine or definitely wrong.
          """)
      let list = facts.map { "- \($0)" }.joined(separator: "\n")
      do {
        let response = try await session.respond(to: "Facts:\n\(list)")
        let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? fallback : text
      } catch {
        return fallback
      }
    #else
      return fallback
    #endif
  }

  /// Answers a parent's question about the recent data, grounded in the facts and daily table.
  static func answer(question: String, facts: [String], table: [String], babyName: String) async -> String {
    #if canImport(FoundationModels)
      guard modelAvailable else {
        return "Answers need Apple Intelligence, which isn't available on this device."
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
        \(facts.map { "- \($0)" }.joined(separator: "\n"))

        Daily data (oldest first):
        \(table.joined(separator: "\n"))

        Question: \(question)
        """
      do {
        let response = try await session.respond(to: prompt)
        let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "I couldn't find an answer in the data." : text
      } catch {
        return "I couldn't answer that just now. Try rephrasing."
      }
    #else
      return "Answers need Apple Intelligence, which isn't available on this device."
    #endif
  }
}
