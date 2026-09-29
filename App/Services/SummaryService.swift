import Foundation
import NestCore

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
}
