import SwiftUI
import PDFKit

struct FolioDocumentView: View {
    @ObservedObject var store: FolioStore
    let document: FolioDocument
    @State private var renamePresented = false
    @State private var newName = ""
    @State private var shareItem: FolioShareItem?
    @State private var cleanupURL: URL?

    private var latest: FolioDocument {
        store.documents.first(where: { $0.id == document.id }) ?? document
    }

    var body: some View {
        VStack(spacing: 0) {
            FolioPDFPreview(url: store.localURL(for: document))
                .background(Color(uiColor: .systemGray6))
            HStack(spacing: 10) {
                Button {
                    store.newDraftFrom(latest)
                } label: {
                    Label("Изменить страницы", systemImage: "square.stack")
                }
                .buttonStyle(FolioSecondaryButtonStyle())
                Button {
                    prepareShare()
                } label: {
                    Label("Поделиться", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(FolioPrimaryButtonStyle())
            }
            .padding(14)
            .background(.regularMaterial)
        }
        .navigationTitle(latest.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
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
                    Button("Поделиться", systemImage: "square.and.arrow.up") {
                        prepareShare()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Действия с документом")
            }
        }
        .alert("Новое имя файла", isPresented: $renamePresented) {
            TextField("Название", text: $newName)
            Button("Сохранить") { store.rename(latest, to: newName) }
            Button("Отмена", role: .cancel) { }
        } message: {
            Text("Название изменится в библиотеке и при отправке. Исходные страницы не изменятся.")
        }
        .sheet(item: $shareItem, onDismiss: {
            store.removeShareCopy(cleanupURL)
            cleanupURL = nil
        }) { item in
            FolioActivitySheet(items: [item.url])
        }
    }

    private func prepareShare() {
        do {
            let url = try store.makeShareCopy(for: latest)
            cleanupURL = url
            shareItem = FolioShareItem(url: url)
        } catch {
            store.alertMessage = error.localizedDescription
        }
    }
}

struct FolioPDFPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let viewer = PDFView()
        viewer.backgroundColor = UIColor.systemGray6
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

struct FolioShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct FolioActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}
