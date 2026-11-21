import SwiftUI

struct FolioSettingsView: View {
    @ObservedObject var store: FolioStore
    @State private var confirmDeleteAll = false

    var body: some View {
        List {
            Section {
                FolioInlineMessage(symbol: "lock.shield.fill",
                                   title: "Документы остаются на iPhone",
                                   subtitle: "FOLIO не отправляет файлы на серверы и не собирает данные. Всё хранится внутри приложения.")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                Toggle(isOn: $store.ocrEnabled) {
                    Label("Распознавать текст", systemImage: "text.viewfinder")
                }
            } header: {
                Text("Распознавание текста (OCR)")
            } footer: {
                Text("Текст на фото и сканах распознаётся прямо на iPhone: по нему можно искать в «Файлах», его можно выделить и скопировать в готовом PDF. Языки: русский и английский.")
            }

            Section("Хранилище") {
                LabeledContent {
                    Text(FolioPlural.documents(store.documents.count))
                } label: {
                    Label("Документы", systemImage: "folder")
                }
                LabeledContent {
                    Text(verbatim: FolioLimits.formatted(store.storageBytes))
                } label: {
                    Label("Занято", systemImage: "internaldrive")
                }
                LabeledContent {
                    Text(FolioPlural.pages(store.draft.count))
                } label: {
                    Label("Незавершённый PDF", systemImage: "square.stack")
                }
            }

            Section {
                LabeledContent {
                    Text(verbatim: FolioLimits.formatted(FolioLimits.pdfImportBytes))
                } label: {
                    Label("PDF", systemImage: "doc")
                }
                LabeledContent {
                    Text(verbatim: FolioLimits.formatted(FolioLimits.imageImportBytes))
                } label: {
                    Label("Изображение", systemImage: "photo")
                }
                LabeledContent {
                    Text(FolioPlural.pages(FolioLimits.draftPages))
                } label: {
                    Label("Страниц в одном PDF", systemImage: "rectangle.stack")
                }
            } header: {
                Text("Ограничения")
            } footer: {
                Text("Максимальный размер одного файла при импорте и число страниц в одном PDF.")
            }

            Section("Поддержка") {
                Link(destination: AppConfig.privacyPolicyURL) {
                    Label("Политика конфиденциальности", systemImage: "hand.raised")
                }
                if let mail = AppConfig.supportMailURL {
                    Link(destination: mail) {
                        Label("Написать в поддержку", systemImage: "envelope")
                    }
                }
                LabeledContent {
                    Text(verbatim: AppConfig.appVersion)
                } label: {
                    Label("Версия", systemImage: "info.circle")
                }
            }

            Section {
                Button(role: .destructive) {
                    confirmDeleteAll = true
                } label: {
                    Label("Удалить все документы", systemImage: "trash")
                        .foregroundStyle(.red)
                }
                .disabled(store.documents.isEmpty)
            } footer: {
                Text("Удаляет все файлы из библиотеки FOLIO на этом устройстве. Шаблоны сохраняются.")
            }
        }
        .navigationTitle("Настройки")
        .confirmationDialog("Удалить все документы?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Удалить все (\(store.documents.count))", role: .destructive) {
                store.deleteAllDocuments()
            }
        } message: {
            Text("Это действие нельзя отменить. Оригиналы в «Файлах» и «Фото» не затрагиваются.")
        }
    }
}
