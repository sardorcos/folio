import SwiftUI

struct FolioSavedWorkflow: Identifiable, Codable {
    let id: UUID
    var name: String
    var description: String
    var quality: PDFQuality
    var targetMB: Int?

    static let defaults: [FolioSavedWorkflow] = [
        .init(id: UUID(uuidString: "A0D8877B-2D71-480E-BCCB-5A78B241F111")!,
              name: "Комплект для клиента", description: "Объединение PDF и контроль размера",
              quality: .original, targetMB: 5),
        .init(id: UUID(uuidString: "A0D8877B-2D71-480E-BCCB-5A78B241F112")!,
              name: "Фото и сканы в PDF", description: "Создание документа из фотографий",
              quality: .smallerPhotos, targetMB: 10),
        .init(id: UUID(uuidString: "A0D8877B-2D71-480E-BCCB-5A78B241F113")!,
              name: "PDF без изменения качества", description: "Подготовка копии для отправки",
              quality: .original, targetMB: nil)
    ]
}

struct FolioTemplatesView: View {
    @ObservedObject var store: FolioStore
    @State private var saved: [FolioSavedWorkflow] = []
    @State private var creating = false
    @State private var newName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                Text("Шаблоны")
                    .font(.largeTitle.weight(.bold))
                Text("Один раз выберите настройки, затем запускайте знакомую задачу в два касания.")
                    .font(.subheadline).foregroundStyle(.secondary)
                FolioSectionHeader(title: "Готовые сценарии")
                workflowList(FolioSavedWorkflow.defaults, deletable: false)
                FolioSectionHeader(title: "Мои шаблоны")
                if saved.isEmpty {
                    FolioInlineMessage(symbol: "square.stack",
                                       title: "Здесь будут ваши настройки",
                                       subtitle: "Шаблон запоминает размер и качество. Файлы для каждой задачи выбираются заново.")
                } else {
                    workflowList(saved, deletable: true)
                }
                Button {
                    newName = ""
                    creating = true
                } label: {
                    Label("Создать шаблон из текущих настроек", systemImage: "plus")
                }
                .buttonStyle(FolioPrimaryButtonStyle())
            }
            .padding(18)
        }
        .background(FolioTheme.canvas)
        .onAppear(perform: loadTemplates)
        .alert("Название шаблона", isPresented: $creating) {
            TextField("Например: Отчёт для клиента", text: $newName)
            Button("Создать") { createTemplate() }
            Button("Отмена", role: .cancel) { }
        } message: {
            Text("Сохраним текущие настройки размера и качества PDF.")
        }
    }

    private func workflowList(_ workflows: [FolioSavedWorkflow], deletable: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(workflows) { workflow in
                HStack(spacing: 10) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.title3)
                        .foregroundStyle(FolioTheme.blue)
                        .frame(width: 42, height: 42)
                        .background(FolioTheme.blueSoft, in: RoundedRectangle(cornerRadius: 12))
                    Button {
                        launch(workflow)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(workflow.name)
                                .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            Text(workflow.description)
                                .font(.caption).foregroundStyle(.secondary)
                            Text(workflow.targetMB.map { "Цель: \($0) МБ" } ?? "Без ограничения размера")
                                .font(.caption2.weight(.medium)).foregroundStyle(FolioTheme.blue)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    if deletable {
                        Button(role: .destructive) {
                            saved.removeAll { $0.id == workflow.id }
                            saveTemplates()
                        } label: {
                            Image(systemName: "trash")
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Удалить шаблон \(workflow.name)")
                    } else {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                }
                if workflow.id != workflows.last?.id { Divider() }
            }
        }
        .padding(.horizontal, 13)
        .background(FolioTheme.card, in: RoundedRectangle(cornerRadius: FolioTheme.corner))
    }

    private func launch(_ workflow: FolioSavedWorkflow) {
        store.exportQuality = workflow.quality
        store.targetSizeMB = workflow.targetMB
        store.openImporter(workflow.quality == .smallerPhotos ? .photographs : .documents)
    }

    private func loadTemplates() {
        guard let data = UserDefaults.standard.data(forKey: "folio.savedWorkflows"),
              let decoded = try? JSONDecoder().decode([FolioSavedWorkflow].self, from: data) else { return }
        saved = decoded
    }

    private func saveTemplates() {
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: "folio.savedWorkflows")
        }
    }

    private func createTemplate() {
        let title = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        saved.insert(FolioSavedWorkflow(id: UUID(), name: title,
                                        description: "Пользовательские настройки PDF",
                                        quality: store.exportQuality, targetMB: store.targetSizeMB), at: 0)
        saveTemplates()
    }
}
