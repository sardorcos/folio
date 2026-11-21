import SwiftUI

struct FolioExportView: View {
    @ObservedObject var store: FolioStore
    @State private var filename = "Новый документ"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 19) {
                FolioProgressStrip(active: 1)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Как сохранить документ?")
                        .font(.title2.weight(.bold))
                    Text("\(store.draft.count) страниц · один PDF")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Название файла").font(.headline)
                    TextField("Например: Документы для клиента", text: $filename)
                        .textInputAutocapitalization(.sentences)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 11) {
                    Text("Качество PDF").font(.headline)
                    ForEach(PDFQuality.allCases) { quality in
                        Button {
                            store.exportQuality = quality
                        } label: {
                            HStack(spacing: 11) {
                                Image(systemName: store.exportQuality == quality ? "largecircle.fill.circle" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(FolioTheme.blue)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(quality.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                    Text(quality.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(14)
                            .background(FolioTheme.card, in: RoundedRectangle(cornerRadius: 15))
                        }
                        .buttonStyle(.plain)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Желаемый размер").font(.headline)
                    HStack(spacing: 8) {
                        targetChip(nil, title: "Без лимита")
                        targetChip(2, title: "2 МБ")
                        targetChip(5, title: "5 МБ")
                        targetChip(10, title: "10 МБ")
                    }
                }
                FolioInlineMessage(symbol: "info.circle",
                                   title: "Размер файла проверим после создания",
                                   subtitle: "Для обычных PDF текст и графика сохраняются. Уменьшение размера не гарантируется.")
            }
            .padding(18)
        }
        .background(FolioTheme.canvas)
        .navigationTitle("Настройки PDF")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                store.exportDraft(name: filename)
            } label: {
                Label("Создать PDF", systemImage: "checkmark.circle")
            }
            .buttonStyle(FolioPrimaryButtonStyle())
            .disabled(store.isProcessing)
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(.regularMaterial)
        }
    }

    private func targetChip(_ size: Int?, title: String) -> some View {
        Button {
            store.targetSizeMB = size
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(store.targetSizeMB == size ? .white : FolioTheme.blue)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(store.targetSizeMB == size ? FolioTheme.blue : FolioTheme.blueSoft,
                            in: RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
    }
}
