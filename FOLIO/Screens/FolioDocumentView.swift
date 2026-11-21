import PDFKit
import SwiftUI
import UIKit

struct FolioDocumentView: View {
    @ObservedObject var store: FolioStore
    let document: FolioDocument
    @State private var renamePresented = false
    @State private var newName = ""
    @State private var deletePresented = false
    @State private var shareURL: URL?
    @State private var textPresented = false
    @State private var pagesWithoutText = 0

    private var latest: FolioDocument {
        store.document(id: document.id) ?? document
    }

    var body: some View {
        VStack(spacing: 0) {
            FolioPDFPreview(url: store.localURL(for: document))
                .background(Color(uiColor: .systemGray6))
                .accessibilityLabel(Text("Просмотр документа: \(FolioPlural.pages(latest.pageCount))"))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { editButton; shareButton }
                VStack(spacing: 10) { editButton; shareButton }
            }
            .padding(14)
            .background(.bar)
        }
        .navigationTitle(Text(verbatim: latest.title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Переименовать", systemImage: "pencil") {
                        newName = latest.title
                        renamePresented = true
                    }
                    Button(latest.isFavorite ? "Убрать из избранного" : "В избранное",
                           systemImage: latest.isFavorite ? "star.slash" : "star") {
                        store.toggleFavorite(latest)
                    }
                    Divider()
                    Button("Текст документа", systemImage: "doc.plaintext") {
                        textPresented = true
                    }
                    if pagesWithoutText > 0 {
                        Button("Распознать текст", systemImage: "text.viewfinder") {
                            store.makeSearchableCopy(of: latest)
                        }
                    }
                    Divider()
                    Button("Удалить", systemImage: "trash", role: .destructive) {
                        deletePresented = true
                    }
                } label: {
                    Label("Действия с документом", systemImage: "ellipsis.circle")
                }
            }
        }
        .task(id: latest.title) {
            shareURL = try? store.makeShareCopy(for: latest)
        }
        .task(id: document.id) {
            pagesWithoutText = await store.pagesWithoutText(in: latest)
        }
        .sheet(isPresented: $textPresented) {
            FolioTextSheet(title: latest.title,
                           text: store.documentText[document.id] ?? "",
                           pagesWithoutText: pagesWithoutText,
                           onRecognize: {
                               textPresented = false
                               store.makeSearchableCopy(of: latest)
                           })
        }
        .alert("Новое название", isPresented: $renamePresented) {
            TextField("Название", text: $newName)
            Button("Сохранить") { store.rename(latest, to: newName) }
            Button("Отмена", role: .cancel) { }
        } message: {
            Text("Название изменится в библиотеке и в имени файла при отправке.")
        }
        .confirmationDialog("Удалить документ?", isPresented: $deletePresented, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                store.deleteDocuments([document.id])
            }
        } message: {
            Text("Файл будет удалён из FOLIO без возможности восстановления.")
        }
    }

    private var editButton: some View {
        Button {
            store.newDraftFrom(latest)
        } label: {
            Label("Изменить страницы", systemImage: "square.stack")
        }
        .buttonStyle(FolioSecondaryButtonStyle())
    }

    @ViewBuilder
    private var shareButton: some View {
        if let shareURL {
            ShareLink(item: shareURL, preview: SharePreview(latest.title + ".pdf")) {
                Label("Поделиться", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(FolioPrimaryButtonStyle())
        } else {
            Button { } label: {
                Label("Поделиться", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(FolioPrimaryButtonStyle())
            .disabled(true)
        }
    }
}

struct FolioPDFPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let viewer = PDFView()
        viewer.backgroundColor = .systemGray6
        viewer.autoScales = true
        viewer.displayMode = .singlePageContinuous
        viewer.displaysPageBreaks = true
        viewer.document = PDFDocument(url: url)
        return viewer
    }

    func updateUIView(_ viewer: PDFView, context: Context) {
        if viewer.document?.documentURL != url {
            viewer.document = PDFDocument(url: url)
        }
    }
}

/// Текст документа: можно выделить, скопировать и отправить.
struct FolioTextSheet: View {
    let title: String
    let text: String
    let pagesWithoutText: Int
    let onRecognize: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Group {
                if trimmed.isEmpty {
                    ContentUnavailableView {
                        Label("Текста нет", systemImage: "doc.text.magnifyingglass")
                    } description: {
                        Text("Похоже, это скан или фото. Распознайте текст, чтобы искать по нему и копировать.")
                    } actions: {
                        if pagesWithoutText > 0 {
                            Button("Распознать текст", action: onRecognize)
                                .buttonStyle(.borderedProminent)
                        }
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if pagesWithoutText > 0 {
                                FolioInlineMessage(symbol: "text.viewfinder",
                                                   title: "Часть страниц без текста",
                                                   subtitle: "Нажмите «Распознать», чтобы добавить текст со сканов.")
                            }
                            Text(verbatim: trimmed)
                                .font(.body)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(18)
                    }
                }
            }
            .navigationTitle(Text(verbatim: title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
                if !trimmed.isEmpty {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button {
                            UIPasteboard.general.string = trimmed
                            copied = true
                        } label: {
                            Label(copied ? "Скопировано" : "Копировать", systemImage: copied ? "checkmark" : "doc.on.doc")
                        }
                        Spacer()
                        if pagesWithoutText > 0 {
                            Button("Распознать", action: onRecognize)
                            Spacer()
                        }
                        ShareLink(item: trimmed) {
                            Label("Поделиться", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
    }
}
