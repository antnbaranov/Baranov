import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// A short, wise saying for the profile, written on-device by Apple's Foundation Models.
/// Returns nil whenever the model is unavailable (older iOS, no Apple Intelligence, unsupported
/// language, model still downloading) or the reply fails the checks in
/// `AppLanguage.acceptModelText`, so the caller can fall back to the translated `CourierQuotes`.
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
              AppLanguage.modelSupports(code: languageCode) else { return nil }

        let session = LanguageModelSession(
            model: model,
            instructions: AppLanguage.modelInstructions("""
                You are an old shepherd who has walked letters across mountains and seas with a ram for fifty years.
                Write exactly ONE short, original saying of at most 12 words, as a single sentence.
                It should sound like folk wisdom a grandparent would say: calm, warm and a little dry, never preachy or grand.
                Build it around the image of the day you are given, and connect it to walking, patience, distance, letters or home.
                Do not start with "Remember" or "Always", do not address anyone by name, and do not use quotation marks.
                """, code: languageCode)
        )
        let images = [
            "dawn", "fog", "the road", "a night's rest", "wind", "mountains", "rain", "the sea",
            "a bridge", "snow", "a lamp in a window", "a well-worn boot", "a crossroads", "the first frost",
        ]
        let seed = images.randomElement() ?? "the road"
        do {
            let response = try await session.respond(
                to: "Image of the day: \(seed). Write the saying.",
                options: GenerationOptions(temperature: 0.9, maximumResponseTokens: 48)
            )
            guard let text = AppLanguage.acceptModelText(response.content, maxCharacters: 110, code: languageCode) else {
                return nil
            }
            // One sentence only; a second one is the model explaining itself.
            let sentenceEnds = text.filter { ".!?。！？".contains($0) }.count
            return sentenceEnds <= 1 ? text : nil
        } catch {
            return nil
        }
    }
    #endif
}
