import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    var bundleLanguageCode: String? {
        switch self {
        case .system:
            return nil
        case .english:
            return "en"
        case .simplifiedChinese:
            return "zh-Hans"
        }
    }

    var displayName: String {
        switch self {
        case .system:
            return L10n.tr("settings.language.system")
        case .english:
            return L10n.tr("settings.language.english")
        case .simplifiedChinese:
            return L10n.tr("settings.language.chinese")
        }
    }
}
