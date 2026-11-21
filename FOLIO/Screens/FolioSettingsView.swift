import SwiftUI

struct FolioSettingsView: View {
    @ObservedObject var store: FolioStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Настройки")
                    .font(.largeTitle.weight(.bold))
                FolioInlineMessage(symbol: "lock.shield.fill",
                                   title: "Ваши документы остаются на iPhone",
                                   subtitle: "FOLIO не отправляет PDF на сервер. Файлы хранятся локально внутри приложения.")
                FolioSectionHeader(title: "Документы")
                VStack(spacing: 0) {
                    settingRow("Сохранённые файлы", value: "\(store.documents.count)", symbol: "folder")
                    Divider()
                    settingRow("Незавершённый PDF", value: "\(store.draft.count) стр.", symbol: "square.stack")
                    Divider()
                    settingRow("Импорт PDF", value: "До 40 МБ", symbol: "doc")
                    Divider()
                    settingRow("Комплект", value: "До 100 стр.", symbol: "rectangle.stack")
                }
                .padding(.horizontal, 14)
                .background(FolioTheme.card, in: RoundedRectangle(cornerRadius: FolioTheme.corner))
                FolioSectionHeader(title: "Приложение")
                Text("FOLIO — PDF, фото и сканы в порядке.")
                    .font(.subheadline.weight(.medium))
                Text("Демонстрационный iOS-проект интерфейса 0.4.0. Для публикации нужны сборка в Xcode, испытания и проверка подписи приложения.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
        }
        .background(FolioTheme.canvas)
    }

    private func settingRow(_ name: String, value: String, symbol: String) -> some View {
        HStack {
            Image(systemName: symbol)
                .foregroundStyle(FolioTheme.blue)
                .frame(width: 26)
            Text(name)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(minHeight: 51)
    }
}
