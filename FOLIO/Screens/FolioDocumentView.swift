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
