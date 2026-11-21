import SwiftUI

struct FolioResultView: View {
    @ObservedObject var store: FolioStore
    @State private var shareItem: FolioShareItem?
    @State private var cleanupURL: URL?

    private var document: FolioDocument? {
        store.documents.first(where: { $0.id == store.lastResultID })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                FolioProgressStrip(active: 2)
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 37))
                        .foregroundStyle(FolioTheme.green)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PDF готов")
                            .font(.title2.weight(.bold))
                        Text("Сохранён в библиотеке FOLIO")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                if let document {
                    VStack(alignment: .leading, spacing: 13) {
                        HStack(spacing: 13) {
                            Image(systemName: "doc.richtext")
                                .font(.system(size: 35))
                                .foregroundStyle(FolioTheme.blue)
                                .frame(width: 60, height: 70)
                                .background(FolioTheme.blueSoft, in: RoundedRectangle(cornerRadius: 13))
                            VStack(alignment: .leading, spacing: 6) {
                                Text(document.title + ".pdf")
                                    .font(.headline)
                                    .lineLimit(2)
                                Text(document.summary)
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        Divider()
                        Button {
                            store.path.append(.document(document.id))
                        } label: {
                            Label("Открыть документ", systemImage: "eye")
                        }
                        .buttonStyle(FolioSecondaryButtonStyle())
                        Button {
                            do {
                                let temp = try store.makeShareCopy(for: document)
                                cleanupURL = temp
                                shareItem = FolioShareItem(url: temp)
                            } catch {
                                store.alertMessage = error.localizedDescription
                            }
                        } label: {
                            Label("Поделиться или сохранить в «Файлы»", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(FolioPrimaryButtonStyle())
                    }
                    .padding(15)
                    .background(FolioTheme.card, in: RoundedRectangle(cornerRadius: 18))
                }
                FolioInlineMessage(symbol: "doc.on.doc",
                                   title: "Исходные документы сохранены",
                                   subtitle: "Вы можете изменить комплект и создать ещё один PDF.")
                Button {
                    store.path = [.composer]
                } label: {
                    Label("Вернуться к страницам", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(FolioSecondaryButtonStyle())
            }
            .padding(18)
        }
        .background(FolioTheme.canvas)
        .navigationTitle("Готово")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .sheet(item: $shareItem, onDismiss: {
            store.removeShareCopy(cleanupURL)
            cleanupURL = nil
        }) { item in
            FolioActivitySheet(items: [item.url])
        }
    }
}
