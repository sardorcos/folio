import Foundation

/// Публичные ссылки приложения. Те же адреса указываются в App Store Connect
/// (App Information → Privacy Policy URL, версия → Support URL).
enum AppConfig {
    /// Название в App Store («FOLIO» занято). На главном экране iPhone приложение подписано как «FOLIO».
    static let appStoreName = "FOLIO — PDF & Scan"

    /// Политика конфиденциальности: PRIVACY.md в публичном репозитории.
    static let privacyPolicyURL = URL(string: "https://github.com/sardorcos/folio/blob/main/PRIVACY.md")!

    /// Поддержка: обращения через GitHub Issues.
    static let supportURL = URL(string: "https://github.com/sardorcos/folio/issues")!

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}
