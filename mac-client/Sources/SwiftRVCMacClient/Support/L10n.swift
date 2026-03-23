import Foundation

enum L10n {
    private static let languageDefaultsKey = "app.language"

    static func tr(_ key: String, _ arguments: CVarArg...) -> String {
        let format = localizedString(forKey: key)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: Locale.current, arguments: arguments)
    }

    private static func localizedString(forKey key: String) -> String {
        let overrideLanguageCode: String? = {
            guard
                let rawValue = UserDefaults.standard.string(forKey: languageDefaultsKey),
                let language = AppLanguage(rawValue: rawValue)
            else {
                return nil
            }
            return language.bundleLanguageCode
        }()

        if let overrideLanguageCode,
           let path = Bundle.module.path(forResource: overrideLanguageCode, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            let value = bundle.localizedString(forKey: key, value: nil, table: nil)
            if value != key {
                return value
            }
        }

        return NSLocalizedString(key, bundle: .module, comment: "")
    }
}
