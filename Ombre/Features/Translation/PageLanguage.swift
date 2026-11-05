import Foundation
import NaturalLanguage
import Translation

/// Which language a page is in, and whether to offer translating it: when
/// it isn't one of the Mac's languages (like Safari).
enum PageLanguage {
    /// The language the page's text reads as, when sure enough, else the one
    /// it declares (`<html lang>`): many sites keep a template's `lang="en"`
    /// on text in another language.
    static func detect(declared: String, sample: String) -> Locale.Language? {
        let declared = declared.trimmingCharacters(in: .whitespaces)
        let declaredLanguage = declared.isEmpty ? nil : Locale.Language(identifier: declared)
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        if let (detected, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
           detected != .undetermined,
           confidence >= 0.8 || declaredLanguage?.languageCode == nil
        {
            let language = Locale.Language(identifier: detected.rawValue)
            // Same language: the declared one says more (region, script).
            if let declaredLanguage, declaredLanguage.languageCode == language.languageCode { return declaredLanguage }
            return language
        }
        return declaredLanguage?.languageCode == nil ? nil : declaredLanguage
    }

    /// The Mac's languages, the first one being what pages are translated into.
    static var userLanguages: [Locale.Language] {
        let languages = Locale.preferredLanguages.map { Locale.Language(identifier: $0) }
        return languages.isEmpty ? [Locale.Language(identifier: "en")] : languages
    }

    static var userLanguage: Locale.Language {
        userLanguages[0]
    }

    static func offersTranslation(of page: Locale.Language?, to userLanguages: [Locale.Language]) -> Bool {
        guard let pageCode = page?.languageCode else { return false }
        return !userLanguages.contains { $0.languageCode == pageCode }
    }

    /// The language's name in the Mac's language ("German").
    static func name(of language: Locale.Language) -> String {
        let code = language.languageCode?.identifier ?? language.minimalIdentifier
        return Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    /// A language Apple's Translation knows (any of its pairs).
    static func canTranslate(_ language: Locale.Language) async -> Bool {
        let languages = await supportedLanguages()
        return languages.contains { $0.languageCode == language.languageCode }
    }

    /// The languages Apple's Translation knows, read once.
    @MainActor
    static func supportedLanguages() async -> [Locale.Language] {
        if let supported { return supported }
        let languages = await LanguageAvailability().supportedLanguages
        supported = languages
        return languages
    }

    @MainActor private static var supported: [Locale.Language]?
}
