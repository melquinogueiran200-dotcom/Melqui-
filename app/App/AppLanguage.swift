import Foundation

/// Player-selectable locales corresponding to Rockstar's 13 official GTA V languages.
/// The native UI can use built-in translations; untranslated text falls back to English.
/// The WebAssembly game may ignore the locale even when its resource archive contains it.
enum AppLanguage: String, CaseIterable {
    case english = "en-US"
    case french = "fr-FR"
    case italian = "it-IT"
    case german = "de-DE"
    case spanishSpain = "es-ES"
    case japanese = "ja-JP"
    case korean = "ko-KR"
    case polish = "pl-PL"
    case portugueseBrazil = "pt-BR"
    case russian = "ru-RU"
    case simplifiedChinese = "zh-CN"
    case spanishLatinAmerica = "es-MX"
    case traditionalChinese = "zh-TW"

    static let changed = Notification.Name("GTA5PortLanguageChanged")
    private static let storageKey = "gtaPortAppLanguage"

    static var current: AppLanguage {
        let saved = UserDefaults.standard.string(forKey: storageKey) ?? english.rawValue
        return AppLanguage(rawValue: saved) ?? .english
    }

    static func select(_ language: AppLanguage) {
        guard current != language else { return }
        UserDefaults.standard.set(language.rawValue, forKey: storageKey)
        NotificationCenter.default.post(name: changed, object: nil)
    }

    var name: String {
        switch self {
        case .english: return "English"
        case .french: return "Français"
        case .italian: return "Italiano"
        case .german: return "Deutsch"
        case .spanishSpain: return "Español (España)"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .polish: return "Polski"
        case .portugueseBrazil: return "Português (Brasil)"
        case .russian: return "Русский"
        case .simplifiedChinese: return "简体中文"
        case .spanishLatinAmerica: return "Español (Latinoamérica)"
        case .traditionalChinese: return "繁體中文"
        }
    }

    /// Use Apple's compiled String Catalog for every selected language.
    /// App language selection is independent of the phone's system locale.
    private var catalogIdentifier: String {
        switch self {
        case .english: return "en"
        case .french: return "fr"
        case .italian: return "it"
        case .german: return "de"
        case .spanishSpain: return "es"
        case .japanese: return "ja"
        case .korean: return "ko"
        case .polish: return "pl"
        case .portugueseBrazil: return "pt-BR"
        case .russian: return "ru"
        case .simplifiedChinese: return "zh-Hans"
        case .spanishLatinAmerica: return "es-419"
        case .traditionalChinese: return "zh-Hant"
        }
    }

    private static func bundle(for identifier: String) -> Bundle? {
        guard let url = Bundle.main.url(forResource: identifier, withExtension: "lproj") else { return nil }
        return Bundle(url: url)
    }

    /// Localize by a single stable English key, falling back to English.
    static func choose(_ key: String) -> String {
        guard current != .english else { return key }
        let localized = bundle(for: current.catalogIdentifier)?
            .localizedString(forKey: key, value: nil, table: "Localizable")
        if let localized, localized != key { return localized }
        return key
    }

    /// Replace numbered arguments in catalog values without locale-sensitive
    /// percent-formatting; dynamic values are not part of translation keys.
    static func interpolate(_ format: String, _ arguments: [String]) -> String {
        var text = format
        for (index, value) in arguments.enumerated().reversed() {
            text = text.replacingOccurrences(of: "{arg\(index)}", with: value)
        }
        return text
    }
}
