import SwiftUI

struct FolioExportView: View {
    @ObservedObject var store: FolioStore
    @State private var filename = ""
    @FocusState private var nameFocused: Bool

    private let targets: [Int?] = [nil, 2, 5, 10]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 19) {
                FolioProgressStrip(active: 1)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Как сохранить документ?")
                        .font(.title2.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: "\(FolioPlural.pages(store.draft.count)) · PDF")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Название файла").font(.headline)
                    TextField("Например: Документы для клиента", text: $filename)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                        .focused($nameFocused)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 48)
                        .background(FolioTheme.card, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("folio.exportName")
                }

                VStack(alignment: .leading, spacing: 11) {
                    Text("Качество PDF").font(.headline)
                    ForEach(PDFQuality.allCases) { quality in
                        FolioChoiceRow(title: quality.title, subtitle: quality.explanation(ocr: store.ocrEnabled),
                                       isSelected: store.exportQuality == quality) {
                            store.exportQuality = quality
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Желаемый размер").font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], spacing: 8) {
                        ForEach(targets, id: \.self) { size in
                            targetChip(size)
                        }
                    }
                    Text(targetExplanation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(FolioTheme.canvas)
        .navigationTitle("Настройки PDF")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            if filename.isEmpty { filename = store.suggestedExportName }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                nameFocused = false
                store.exportDraft(name: filename)
            } label: {
                Label("Создать PDF", systemImage: "checkmark.circle")
            }
            .buttonStyle(FolioPrimaryButtonStyle())
            .disabled(store.isProcessing || store.draft.isEmpty)
            .accessibilityIdentifier("folio.createPDF")
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(.bar)
        }
    }

    private var targetExplanation: LocalizedStringKey {
        guard store.targetSizeMB != nil else {
            return "Размер не ограничен. Фактический размер покажем после создания."
        }
        switch store.exportQuality {
        case .original:
            return "В режиме «Исходное качество» страницы не сжимаются: FOLIO только предупредит, если файл получится больше."
        case .smallerPhotos:
            return "FOLIO попробует несколько уровней сжатия фото и сканов, чтобы уложиться в размер. Если не получится, покажем фактический результат."
        case .maximum:
            return "FOLIO попробует несколько уровней сжатия всех страниц, чтобы уложиться в размер."
        }
    }

    private func targetChip(_ size: Int?) -> some View {
        let isSelected = store.targetSizeMB == size
        return Button {
            store.targetSizeMB = size
        } label: {
            Group {
                if let size {
                    Text("\(size) МБ")
                } else {
                    Text("Без лимита")
                }
            }
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(isSelected ? .white : FolioTheme.blue)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(isSelected ? FolioTheme.fill : FolioTheme.blueSoft,
                        in: RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
