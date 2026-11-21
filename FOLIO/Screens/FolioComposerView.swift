import SwiftUI
import PDFKit

struct FolioComposerView: View {
    @ObservedObject var store: FolioStore
    @State private var selected: Set<UUID> = []
    @State private var showResetConfirmation = false
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    private var numberedPages: [FolioNumberedPage] {
        store.draft.enumerated().map { FolioNumberedPage(number: $0.offset + 1, page: $0.element) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FolioProgressStrip(active: 0)
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ваш PDF-комплект")
                            .font(.title2.weight(.bold))
                        Text("\(store.draftSourceCount) файла · \(store.draft.count) страниц")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Отменить", systemImage: "arrow.uturn.backward") { store.undo() }
                        .labelStyle(.iconOnly)
                        .disabled(!store.canUndo)
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Отменить последнее изменение")
                }
                FolioInlineMessage(symbol: "hand.draw",
                                   title: "Выберите страницу для редактирования",
                                   subtitle: "Можно повернуть, удалить, дублировать или изменить порядок.")

                if !selected.isEmpty { selectionToolbar }

                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(numberedPages) { item in
                        FolioPageCard(store: store, page: item.page, number: item.number,
                                      isSelected: selected.contains(item.page.id),
                                      onSelect: { toggle(item.page.id) })
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        store.openImporter(.documents)
                    } label: {
                        Label("Добавить файлы", systemImage: "plus")
                    }
                    .buttonStyle(FolioSecondaryButtonStyle())
                    Button(role: .destructive) {
                        showResetConfirmation = true
                    } label: {
                        Label("Новый комплект", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(FolioSecondaryButtonStyle())
                }
            }
            .padding(18)
        }
        .background(FolioTheme.canvas)
        .navigationTitle("Сборка PDF")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 9) {
                HStack {
                    Text("\(store.draft.count) страниц")
                        .font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                    Text("Оригиналы не изменяются")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button {
                    store.path.append(.export)
                } label: {
                    HStack {
                        Text("Далее: сохранить PDF")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(FolioPrimaryButtonStyle())
                .disabled(store.draft.isEmpty)
                .accessibilityIdentifier("folio.composeNext")
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(.regularMaterial)
        }
        .confirmationDialog("Начать новый комплект?", isPresented: $showResetConfirmation) {
            Button("Очистить текущий комплект", role: .destructive) {
                store.clearDraft()
            }
        } message: {
            Text("Добавленные в библиотеку файлы останутся на устройстве.")
        }
    }

    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private var selectionToolbar: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Выбрано: \(selected.count)").font(.footnote.weight(.semibold))
                Spacer()
                Button("Снять выбор") { selected.removeAll() }
                    .font(.footnote.weight(.medium))
            }
            ScrollView(.horizontal) {
                HStack(spacing: 9) {
                    editAction("Повернуть", "rotate.right") { store.rotatePages(selected) }
                    editAction("Дублировать", "plus.square.on.square") { store.duplicatePages(selected); selected.removeAll() }
                    editAction("Извлечь", "square.on.square") { store.keepOnlyPages(selected); selected.removeAll() }
                    editAction("Удалить", "trash", destructive: true) { store.deletePages(selected); selected.removeAll() }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(12)
        .background(FolioTheme.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private func editAction(_ name: String, _ symbol: String,
                            destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(name, systemImage: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(destructive ? Color.red : FolioTheme.blue)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(FolioTheme.canvas, in: Capsule())
        }
    }
}

private struct FolioNumberedPage: Identifiable {
    let number: Int
    let page: FolioDraftPage
    var id: UUID { page.id }
}

struct FolioPageCard: View {
    @ObservedObject var store: FolioStore
    let page: FolioDraftPage
    let number: Int
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(spacing: 8) {
            Button(action: onSelect) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(FolioTheme.card)
                        .frame(height: 186)
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(height: 173)
                            .padding(6)
                    } else {
                        Image(systemName: "doc.text")
                            .font(.largeTitle)
                            .foregroundStyle(FolioTheme.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 186)
                    }
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(FolioTheme.blue)
                            .padding(8)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isSelected ? FolioTheme.blue : FolioTheme.line,
                                      lineWidth: isSelected ? 2 : 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Страница \(number)\(isSelected ? ", выбрана" : "")")
            HStack {
                Button {
                    store.movePage(page.id, direction: -1)
                } label: {
                    Image(systemName: "arrow.left")
                        .frame(width: 44, height: 44)
                }
                .disabled(number == 1)
                .accessibilityLabel("Переместить страницу \(number) раньше")

                Spacer(minLength: 0)
                Text("\(number)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)

                Button {
                    store.movePage(page.id, direction: 1)
                } label: {
                    Image(systemName: "arrow.right")
                        .frame(width: 44, height: 44)
                }
                .disabled(number == store.draft.count)
                .accessibilityLabel("Переместить страницу \(number) позже")
            }
            .foregroundStyle(FolioTheme.blue)
            .buttonStyle(.plain)
        }
        .task(id: "\(page.documentID.uuidString)-\(page.pageIndex)-\(page.rotation)") {
            if let document = store.documents.first(where: { $0.id == page.documentID }),
               let pdf = PDFDocument(url: store.localURL(for: document)),
               let pdfPage = pdf.page(at: page.pageIndex) {
                let image = pdfPage.thumbnail(of: CGSize(width: 380, height: 520), for: .mediaBox)
                thumbnail = image
            }
        }
    }
}

struct FolioProgressStrip: View {
    let active: Int
    private let titles = ["Страницы", "Настройки", "Готово"]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(titles.indices, id: \.self) { index in
                HStack(spacing: 5) {
                    Image(systemName: index < active ? "checkmark.circle.fill" : "\(index + 1).circle.fill")
                        .foregroundStyle(index <= active ? FolioTheme.blue : FolioTheme.secondary)
                    Text(titles[index])
                        .font(.caption.weight(index == active ? .bold : .regular))
                        .foregroundStyle(index <= active ? FolioTheme.blue : FolioTheme.secondary)
                }
                if index != titles.count - 1 {
                    Rectangle()
                        .fill(FolioTheme.line)
                        .frame(maxWidth: .infinity, maxHeight: 1)
                }
            }
        }
    }
}
