import SwiftUI

struct FolioFileRow: View {
    let document: FolioDocument

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: document.origin == .pdf ? "doc.richtext" : "doc.viewfinder")
                .font(.title2)
                .foregroundStyle(FolioTheme.blue)
                .frame(width: 42, height: 52)
                .background(FolioTheme.blueSoft, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 5) {
                Text(document.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(document.summary)
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
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

struct FolioLibraryView: View {
    @ObservedObject var store: FolioStore
    @State private var query = ""
    @State private var scope = 0
    @State private var favoritesOnly = false
    @State private var sortNewest = true

    private var results: [FolioDocument] {
        store.documents
            .filter { scope == 0 || (scope == 1 && $0.kind == .source) || (scope == 2 && $0.kind == .result) }
            .filter { !favoritesOnly || $0.isFavorite }
            .filter { query.isEmpty || $0.title.localizedStandardContains(query) }
            .sorted { sortNewest ? $0.createdAt > $1.createdAt : $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                HStack {
                    Text("Мои файлы")
                        .font(.largeTitle.weight(.bold))
                    Spacer()
                    Button {
                        store.openImporter(.documents)
                    } label: {
                        Image(systemName: "plus")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(FolioTheme.blue, in: Circle())
                    }
                    .accessibilityLabel("Добавить файлы")
                }
                TextField("Поиск по названию", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("folio.search")
                Picker("Тип", selection: $scope) {
                    Text("Все").tag(0)
                    Text("Исходники").tag(1)
                    Text("Готовые PDF").tag(2)
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("\(results.count) документов")
                        .font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        favoritesOnly.toggle()
                    } label: {
                        Label("Избранное", systemImage: favoritesOnly ? "star.fill" : "star")
                            .labelStyle(.titleAndIcon)
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(FolioQuietButtonStyle())
                    Menu {
                        Button("Сначала новые", systemImage: "clock", action: { sortNewest = true })
                        Button("По названию", systemImage: "textformat.abc", action: { sortNewest = false })
                    } label: {
                        Label("Сортировка", systemImage: "arrow.up.arrow.down")
                            .font(.caption.weight(.semibold))
                    }
                }

                if results.isEmpty {
                    ContentUnavailableView {
                        Label(query.isEmpty ? "Документов пока нет" : "Ничего не найдено", systemImage: "doc.text.magnifyingglass")
                    } description: {
                        Text(query.isEmpty ? "Добавьте PDF или фотографии, чтобы начать." : "Измените запрос или отключите фильтры.")
                    } actions: {
                        if query.isEmpty {
                            Button("Добавить файлы") { store.openImporter(.documents) }
                                .buttonStyle(.borderedProminent)
                        } else {
                            Button("Сбросить поиск") { query = ""; favoritesOnly = false; scope = 0 }
                        }
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(results) { document in
                            Button {
                                store.path = [.document(document.id)]
                            } label: {
                                FolioFileRow(document: document)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(document.isFavorite ? "Убрать из избранного" : "В избранное",
                                       systemImage: document.isFavorite ? "star.slash" : "star") {
                                    store.toggleFavorite(document)
                                }
                                Button("Открыть в редакторе", systemImage: "rectangle.3.group") {
                                    store.newDraftFrom(document)
                                }
                            }
                            if document.id != results.last?.id { Divider().padding(.leading, 54) }
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(FolioTheme.card, in: RoundedRectangle(cornerRadius: FolioTheme.corner))
                }
            }
            .padding(18)
        }
        .background(FolioTheme.canvas)
    }
}
