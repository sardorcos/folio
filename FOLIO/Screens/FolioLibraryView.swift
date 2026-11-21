import SwiftUI

struct FolioFileRow: View {
    let document: FolioDocument

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(FolioTheme.blue)
                .frame(width: 42, height: 52)
                .background(FolioTheme.blueSoft, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: document.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(verbatim: document.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if document.kind == .result {
                    Text("Готовый PDF")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(FolioTheme.green)
                }
            }
            Spacer(minLength: 4)
            if document.isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityLabel("В избранном")
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch document.origin {
        case .pdf: "doc.richtext"
        case .photo: "photo"
        case .scan: "doc.viewfinder"
        }
    }
}

struct FolioLibraryView: View {
    @ObservedObject var store: FolioStore
    @State private var query = ""
    @State private var scope = LibraryScope.all
    @State private var favoritesOnly = false
    @State private var sortNewest = true
    @State private var pendingDeletion: FolioDocument?
    @State private var renaming: FolioDocument?
    @State private var newName = ""

    enum LibraryScope: Hashable { case all, sources, results }

    private var results: [FolioDocument] {
        store.documents
            .filter {
                switch scope {
                case .all: true
                case .sources: $0.kind == .source
                case .results: $0.kind == .result
                }
            }
            .filter { !favoritesOnly || $0.isFavorite }
            .filter { store.matchesSearch($0, query: query) }
            .sorted {
                sortNewest ? $0.createdAt > $1.createdAt
                           : $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
    }

    var body: some View {
        List {
            Section {
                Picker("Тип", selection: $scope) {
                    Text("Все").tag(LibraryScope.all)
                    Text("Исходники").tag(LibraryScope.sources)
                    Text("Готовые").tag(LibraryScope.results)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            if results.isEmpty {
                emptyState
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(results) { document in
                        NavigationLink(value: FolioRoute.document(document.id)) {
                            VStack(alignment: .leading, spacing: 2) {
                                FolioFileRow(document: document)
                                if let snippet = store.textSnippet(for: document.id, matching: query),
                                   !document.title.localizedStandardContains(query) {
                                    Label {
                                        Text(verbatim: snippet)
                                            .lineLimit(2)
                                    } icon: {
                                        Image(systemName: "text.magnifyingglass")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 54)
                                    .padding(.bottom, 6)
                                    .accessibilityLabel(Text("Найдено в тексте: \(snippet)"))
                                }
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                pendingDeletion = document
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                store.toggleFavorite(document)
                            } label: {
                                Label(document.isFavorite ? "Убрать из избранного" : "В избранное",
                                      systemImage: document.isFavorite ? "star.slash" : "star")
                            }
                            .tint(.orange)
                        }
                        .contextMenu { menu(for: document) }
                    }
                } header: {
                    Text(FolioPlural.documents(results.count))
                }
            }
        }
        .navigationTitle("Мои файлы")
        .searchable(text: $query, prompt: Text("Название или текст документа"))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("Сортировка", selection: $sortNewest) {
                        Label("Сначала новые", systemImage: "clock").tag(true)
                        Label("По названию", systemImage: "textformat.abc").tag(false)
                    }
                    Toggle(isOn: $favoritesOnly) {
                        Label("Только избранное", systemImage: "star")
                    }
                } label: {
                    Label("Фильтры", systemImage: favoritesOnly ? "line.3.horizontal.decrease.circle.fill"
                                                                : "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Файлы", systemImage: "folder") { store.startTask(.documents) }
                    Button("Фото", systemImage: "photo.on.rectangle") { store.startTask(.photographs) }
                    Button("Сканировать", systemImage: "viewfinder") { store.startTask(.scan) }
                } label: {
                    Label("Добавить", systemImage: "plus")
                }
            }
        }
        .confirmationDialog("Удалить документ?", isPresented: deletionBinding, titleVisibility: .visible,
                            presenting: pendingDeletion) { document in
            Button("Удалить «\(document.title)»", role: .destructive) {
                store.deleteDocuments([document.id])
                pendingDeletion = nil
            }
            Button("Отмена", role: .cancel) { pendingDeletion = nil }
        } message: { document in
            Text(deletionMessage(for: document))
        }
        .alert("Новое название", isPresented: renamingBinding, presenting: renaming) { document in
            TextField("Название", text: $newName)
            Button("Сохранить") {
                store.rename(document, to: newName)
                renaming = nil
            }
            Button("Отмена", role: .cancel) { renaming = nil }
        }
    }

    @ViewBuilder
    private func menu(for document: FolioDocument) -> some View {
        Button("Изменить страницы", systemImage: "rectangle.3.group") {
            store.newDraftFrom(document)
        }
        Button("Переименовать", systemImage: "pencil") {
            newName = document.title
            renaming = document
        }
        Button(document.isFavorite ? "Убрать из избранного" : "В избранное",
               systemImage: document.isFavorite ? "star.slash" : "star") {
            store.toggleFavorite(document)
        }
        Divider()
        Button("Удалить", systemImage: "trash", role: .destructive) {
            pendingDeletion = document
        }
    }

    private var emptyState: some View {
        Group {
            if store.documents.isEmpty {
                ContentUnavailableView {
                    Label("Документов пока нет", systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text("Добавьте PDF, фото или скан, чтобы начать.")
                } actions: {
                    Button("Добавить файлы") { store.startTask(.documents) }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ContentUnavailableView {
                    Label("Ничего не найдено", systemImage: "magnifyingglass")
                } description: {
                    Text("Измените запрос или отключите фильтры.")
                } actions: {
                    Button("Сбросить фильтры") {
                        query = ""
                        favoritesOnly = false
                        scope = .all
                    }
                }
            }
        }
    }

    private var deletionBinding: Binding<Bool> {
        Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
    }

    private var renamingBinding: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private func deletionMessage(for document: FolioDocument) -> String {
        let pages = store.draftPageCount(referencing: [document.id])
        var text = String(localized: "Файл будет удалён из FOLIO без возможности восстановления. Копии, отправленные ранее, не затрагиваются.")
        if pages > 0 {
            text += "\n" + String(localized: "Из незавершённого PDF также будут убраны: \(FolioPlural.pages(pages)).")
        }
        return text
    }
}
