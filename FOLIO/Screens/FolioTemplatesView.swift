import SwiftUI

struct FolioTemplatesView: View {
    @ObservedObject var store: FolioStore
    @State private var creating = false

    var body: some View {
        List {
            Section {
                Text("Шаблон запоминает качество и желаемый размер. Файлы для каждой задачи выбираются заново.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))
            }
            Section("Готовые сценарии") {
                ForEach(FolioSavedWorkflow.defaults) { workflow in
                    row(workflow)
                }
            }
            Section("Мои шаблоны") {
                if store.templates.isEmpty {
                    Button {
                        creating = true
                    } label: {
                        Label("Создать первый шаблон", systemImage: "plus.circle")
                    }
                } else {
                    ForEach(store.templates) { workflow in
                        row(workflow)
                    }
                    .onDelete { offsets in
                        store.deleteTemplates(Set(offsets.map { store.templates[$0].id }))
                    }
                }
            }
        }
        .navigationTitle("Шаблоны")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    creating = true
                } label: {
                    Label("Новый шаблон", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $creating) {
            FolioTemplateEditor { name, quality, target in
                store.createTemplate(name: name, quality: quality, targetMB: target)
            }
        }
    }

    private func row(_ workflow: FolioSavedWorkflow) -> some View {
        Button {
            store.launch(workflow)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: workflow.quality == .smallerPhotos ? "photo.stack" : "square.stack.3d.up")
                    .font(.title3)
                    .foregroundStyle(FolioTheme.blue)
                    .frame(width: 42, height: 42)
                    .background(FolioTheme.blueSoft, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: workflow.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(verbatim: workflow.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Group {
                        if let target = workflow.targetMB {
                            Text("Цель: \(target) МБ")
                        } else {
                            Text("Без ограничения размера")
                        }
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(FolioTheme.blue)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Выбрать файлы с этими настройками"))
    }
}

struct FolioTemplateEditor: View {
    let onSave: (String, PDFQuality, Int?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var quality: PDFQuality = .original
    @State private var target: Int? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Название") {
                    TextField("Например: Отчёт для клиента", text: $name)
                }
                Section("Качество PDF") {
                    Picker("Качество", selection: $quality) {
                        ForEach(PDFQuality.allCases) { option in
                            Text(verbatim: option.title).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    Text(verbatim: quality.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Желаемый размер") {
                    Picker("Размер", selection: $target) {
                        Text("Без лимита").tag(Int?.none)
                        Text("2 МБ").tag(Int?.some(2))
                        Text("5 МБ").tag(Int?.some(5))
                        Text("10 МБ").tag(Int?.some(10))
                    }
                }
            }
            .navigationTitle("Новый шаблон")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        onSave(name, quality, target)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
