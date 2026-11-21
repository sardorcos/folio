import SwiftUI
import UIKit

struct FolioComposerView: View {
    @ObservedObject var store: FolioStore
    @State private var selected: Set<UUID> = []
    @State private var showResetConfirmation = false
    @State private var showExtractConfirmation = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }

    private var numberedPages: [FolioNumberedPage] {
        store.draft.enumerated().map { FolioNumberedPage(number: $0.offset + 1, page: $0.element) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FolioProgressStrip(active: 0)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ваш PDF")
                        .font(.title2.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: "\(FolioPlural.files(store.draftSourceCount)) · \(FolioPlural.pages(store.draft.count))")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                if store.draft.isEmpty {
                    ContentUnavailableView {
                        Label("Страниц пока нет", systemImage: "doc.badge.plus")
                    } description: {
                        Text("Добавьте файлы, фото или скан, чтобы собрать PDF.")
                    }
                } else if selected.isEmpty {
                    FolioInlineMessage(symbol: "hand.tap",
                                       title: "Нажмите на страницу, чтобы выбрать её",
                                       subtitle: "Чтобы изменить порядок, удерживайте страницу и перетащите её на новое место.")
                } else {
                    selectionToolbar
                }

                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(numberedPages) { item in
                        FolioPageCard(page: item.page,
                                      url: store.localURL(forDocumentID: item.page.documentID),
                                      number: item.number,
                                      total: store.draft.count,
                                      isSelected: selected.contains(item.page.id),
                                      onSelect: { toggle(item.page.id) },
                                      onMove: { store.movePage(item.page.id, direction: $0) },
                                      onMoveToEdge: { store.movePageToEdge(item.page.id, toStart: $0) },
                                      onRotate: { store.rotatePages([item.page.id]) },
                                      onDuplicate: { store.duplicatePages([item.page.id]) },
                                      onDelete: {
                                          selected.remove(item.page.id)
                                          store.deletePages([item.page.id])
                                      })
                            .draggable(item.page.id.uuidString) {
                                Text(verbatim: "\(item.number)")
                                    .font(.headline)
                                    .padding(14)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                            }
                            .dropDestination(for: String.self) { items, _ in
                                guard let raw = items.first, let id = UUID(uuidString: raw) else { return false }
                                store.movePage(id, onto: item.page.id)
                                return true
                            }
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { addButton; resetButton }
                    VStack(spacing: 10) { addButton; resetButton }
                }
            }
            .padding(18)
        }
        .background(FolioTheme.canvas)
        .navigationTitle("Сборка PDF")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.undo()
                } label: {
                    Label("Отменить", systemImage: "arrow.uturn.backward")
                }
                .disabled(!store.canUndo)
                .accessibilityLabel("Отменить последнее изменение")
            }
            ToolbarItem(placement: .topBarTrailing) {
                if !store.draft.isEmpty {
                    Button(selected.count == store.draft.count ? LocalizedStringKey("Снять все") : LocalizedStringKey("Выбрать все")) {
                        if selected.count == store.draft.count {
                            selected.removeAll()
                        } else {
                            selected = Set(store.draft.map(\.id))
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .onChange(of: store.draft) { _, pages in
            // Выделение не должно ссылаться на страницы, которых больше нет (например, после «Отменить»).
            selected.formIntersection(Set(pages.map(\.id)))
        }
        .confirmationDialog("Начать новый PDF?", isPresented: $showResetConfirmation, titleVisibility: .visible) {
            Button("Очистить текущий набор страниц", role: .destructive) {
                selected.removeAll()
                store.clearDraft()
            }
        } message: {
            Text("Файлы в библиотеке останутся на устройстве. Действие можно отменить.")
        }
        .confirmationDialog("Оставить только выбранные страницы?", isPresented: $showExtractConfirmation,
                            titleVisibility: .visible) {
            Button("Оставить выбранные (\(selected.count))", role: .destructive) {
                store.keepOnlyPages(selected)
                selected.removeAll()
            }
        } message: {
            Text("Остальные страницы будут убраны из этого PDF. Исходные файлы не изменятся.")
        }
    }

    private var addButton: some View {
        Menu {
            Button("Файлы", systemImage: "folder") { store.addToCurrentDraft(.files) }
            Button("Фото", systemImage: "photo.on.rectangle") { store.addToCurrentDraft(.photos) }
            Button("Сканировать", systemImage: "viewfinder") { store.addToCurrentDraft(.scanner) }
        } label: {
            Label("Добавить", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FolioTheme.blue)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(FolioTheme.blueSoft, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
    }

    private var resetButton: some View {
        Button(role: .destructive) {
            showResetConfirmation = true
        } label: {
            Label("Новый PDF", systemImage: "arrow.counterclockwise")
        }
        .buttonStyle(FolioSecondaryButtonStyle())
        .disabled(store.draft.isEmpty)
    }

    private var bottomBar: some View {
        VStack(spacing: 9) {
            HStack {
                Text(FolioPlural.pages(store.draft.count))
                    .font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Text("Оригиналы не изменяются")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button {
                store.homePath.append(.export)
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
        .background(.bar)
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
                    .frame(minHeight: 44)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 9) {
                    editAction("Повернуть", "rotate.right") { store.rotatePages(selected) }
                    editAction("Дублировать", "plus.square.on.square") { store.duplicatePages(selected); selected.removeAll() }
                    editAction("Оставить только их", "square.on.square") { showExtractConfirmation = true }
                    editAction("Удалить", "trash", destructive: true) { store.deletePages(selected); selected.removeAll() }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(12)
        .background(FolioTheme.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private func editAction(_ name: LocalizedStringKey, _ symbol: String,
                            destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(name, systemImage: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(destructive ? Color.red : FolioTheme.blue)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(FolioTheme.canvas, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct FolioNumberedPage: Identifiable {
    let number: Int
    let page: FolioDraftPage
    var id: UUID { page.id }
}

struct FolioPageCard: View {
    let page: FolioDraftPage
    let url: URL?
    let number: Int
    let total: Int
    let isSelected: Bool
    let onSelect: () -> Void
    let onMove: (Int) -> Void
    let onMoveToEdge: (Bool) -> Void
    let onRotate: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    @State private var thumbnail: UIImage?

    private var thumbnailKey: String {
        "\(page.documentID.uuidString)-\(page.pageIndex)-\(page.rotation)"
    }

    var body: some View {
        VStack(spacing: 8) {
            Button(action: onSelect) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(FolioTheme.card)
                        .frame(height: 186)
                    Group {
                        if let thumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .scaledToFit()
                                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                        } else {
                            ProgressView()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 170)
                    .padding(8)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, FolioTheme.fill)
                            .padding(8)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isSelected ? FolioTheme.blue : FolioTheme.line,
                                      lineWidth: isSelected ? 2.5 : 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Страница \(number) из \(total)"))
            .accessibilityHint(Text("Двойное касание — выбрать"))
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            .accessibilityAction(named: Text("Переместить раньше")) { onMove(-1) }
            .accessibilityAction(named: Text("Переместить позже")) { onMove(1) }
            .accessibilityAction(named: Text("Повернуть")) { onRotate() }
            .accessibilityAction(named: Text("Удалить")) { onDelete() }
            .contextMenu {
                Button("Повернуть", systemImage: "rotate.right", action: onRotate)
                Button("Дублировать", systemImage: "plus.square.on.square", action: onDuplicate)
                Button("В начало", systemImage: "arrow.up.to.line") { onMoveToEdge(true) }
                    .disabled(number == 1)
                Button("В конец", systemImage: "arrow.down.to.line") { onMoveToEdge(false) }
                    .disabled(number == total)
                Button("Удалить", systemImage: "trash", role: .destructive, action: onDelete)
            }

            HStack {
                Button {
                    onMove(-1)
                } label: {
                    Image(systemName: "arrow.left")
                        .frame(width: 44, height: 44)
                }
                .disabled(number == 1)
                .accessibilityLabel(Text("Переместить страницу \(number) раньше"))

                Spacer(minLength: 0)
                Text(verbatim: "\(number)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)

                Button {
                    onMove(1)
                } label: {
                    Image(systemName: "arrow.right")
                        .frame(width: 44, height: 44)
                }
                .disabled(number == total)
                .accessibilityLabel(Text("Переместить страницу \(number) позже"))
            }
            .foregroundStyle(FolioTheme.blue)
            .buttonStyle(.plain)
        }
        .task(id: thumbnailKey) {
            guard let url else { return }
            let image = await ThumbnailRenderer.shared.thumbnail(url: url, pageIndex: page.pageIndex,
                                                                 rotation: page.rotation,
                                                                 size: CGSize(width: 360, height: 480))
            if !Task.isCancelled { thumbnail = image }
        }
    }
}

struct FolioProgressStrip: View {
    let active: Int
    private let titles: [LocalizedStringKey] = ["Страницы", "Настройки", "Готово"]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(titles.indices, id: \.self) { index in
                HStack(spacing: 5) {
                    Image(systemName: index < active ? "checkmark.circle.fill" : "\(index + 1).circle.fill")
                        .foregroundStyle(index <= active ? FolioTheme.blue : FolioTheme.secondary)
                    Text(titles[index])
                        .font(.caption.weight(index == active ? .bold : .regular))
                        .foregroundStyle(index <= active ? FolioTheme.blue : FolioTheme.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                if index != titles.count - 1 {
                    Rectangle()
                        .fill(FolioTheme.line)
                        .frame(maxWidth: .infinity, maxHeight: 1)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Шаг \(active + 1) из \(titles.count)"))
    }
}
