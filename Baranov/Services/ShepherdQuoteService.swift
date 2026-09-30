import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// A short, wise saying for the profile, written on-device by Apple's Foundation Models.
/// Returns nil whenever the model is unavailable (older iOS, no Apple Intelligence, unsupported
/// language, model still downloading) so the caller can fall back to `CourierQuotes`.
enum ShepherdQuoteService {
    static func generate(languageCode: String) async -> String? {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return nil }
        return await generateWithModel(languageCode: languageCode)
        #else
        return nil
        #endif
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func generateWithModel(languageCode: String) async -> String? {
        let model = SystemLanguageModel.default
        // No reply at all beats a reply in the wrong language: the caller
        // then shows the translated classic sayings.
        guard case .available = model.availability,
              model.supportsLocale(Locale(identifier: languageCode)) else { return nil }

        let language = Locale(identifier: "en").localizedString(forIdentifier: languageCode) ?? Locale(identifier: "en").localizedString(forLanguageCode: languageCode) ?? "English"
        let session = LanguageModelSession(
            model: model,
            instructions: """
            You are a wise old shepherd who carries letters on foot together with a ram. \
            Reply with exactly one short aphorism, at most 90 characters, written in \(language). \
            Themes: slow travel, patience, steps, distance, letters, home. \
            No quotation marks, no explanation, no emoji, no names. \
            Every word of the aphorism must be in \(language), even though these instructions are in English.
            """
        )
        let images = ["dawn", "fog", "the road", "a night's rest", "wind", "mountains", "rain", "the sea"]
        let seed = images.randomElement() ?? "the road"
        do {
            let response = try await session.respond(
                to: "Write a new saying for the shepherd. Image of the day: \(seed).",
                options: GenerationOptions(temperature: 1.0)
            )
            return clean(response.content)
        } catch {
            return nil
        }
    }
    #endif

    private static func clean(_ raw: String) -> String? {
        let quotes = CharacterSet(charactersIn: "\"«»“”„'").union(.whitespacesAndNewlines)
        let text = raw.trimmingCharacters(in: quotes)
        guard !text.isEmpty, AppLanguage.isInAppLanguage(text) else { return nil }
        return String(text.prefix(140))
    }
}
