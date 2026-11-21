import Foundation

#warning("Перед публикацией укажите свои privacyPolicyURL и supportEmail в AppConfig.swift, затем удалите эту строку")

/// Данные, которые нужно заполнить перед публикацией в App Store.
enum AppConfig {
    /// Публичная страница политики конфиденциальности. Тот же URL указывается в App Store Connect.
    static let privacyPolicyURL = URL(string: "https://example.com/folio/privacy")!

    /// Адрес поддержки. App Store Connect также требует Support URL.
    static let supportEmail = "support@example.com"

    static var supportMailURL: URL? {
        let subject = "FOLIO \(appVersion)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "FOLIO"
        return URL(string: "mailto:\(supportEmail)?subject=\(subject)")
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}
