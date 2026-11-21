import SwiftUI

struct FolioResultView: View {
    @ObservedObject var store: FolioStore
    @State private var shareURL: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                FolioProgressStrip(active: 2)
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(FolioTheme.green)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PDF готов")
                            .font(.title2.weight(.bold))
                            .accessibilityAddTraits(.isHeader)
                        Text("Сохранён в библиотеке FOLIO")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                if let document = store.lastResult {
                    VStack(alignment: .leading, spacing: 13) {
                        HStack(spacing: 13) {
                            Image(systemName: "doc.richtext")
                                .font(.largeTitle)
                                .foregroundStyle(FolioTheme.blue)
                                .frame(width: 60, height: 70)
                                .background(FolioTheme.blueSoft, in: RoundedRectangle(cornerRadius: 13))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(verbatim: document.title + ".pdf")
                                    .font(.headline)
                                    .lineLimit(3)
                                Text(verbatim: document.summary)
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        if let note = store.lastExportNote {
                            Label {
                                Text(verbatim: note).font(.footnote)
                            } icon: {
                                Image(systemName: "info.circle").foregroundStyle(FolioTheme.blue)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        Divider()
                        NavigationLink(value: FolioRoute.document(document.id)) {
                            Label("Открыть документ", systemImage: "eye")
                        }
                        .buttonStyle(FolioSecondaryButtonStyle())
                        if let shareURL {
                            ShareLink(item: shareURL, preview: SharePreview(document.title + ".pdf")) {
                                Label("Поделиться или сохранить в «Файлы»", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(FolioPrimaryButtonStyle())
                            .accessibilityIdentifier("folio.share")
                        } else {
                            ProgressView().frame(maxWidth: .infinity, minHeight: 52)
                        }
                    }
                    .padding(15)
                    .background(FolioTheme.card, in: RoundedRectangle(cornerRadius: 18))
                    .task(id: document.id) {
                        prepareShare(document)
                    }
                }

                FolioInlineMessage(symbol: "doc.on.doc",
                                   title: "Исходные документы сохранены",
                                   subtitle: "Можно изменить страницы и создать ещё один PDF.")
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { backButton; doneButton }
                    VStack(spacing: 10) { backButton; doneButton }
                }
            }
            .padding(18)
        }
        .background(FolioTheme.canvas)
        .navigationTitle("Готово")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .tabBar)
    }

    private var backButton: some View {
        Button {
            store.homePath = [.composer]
        } label: {
            Label("К страницам", systemImage: "arrow.uturn.backward")
        }
        .buttonStyle(FolioSecondaryButtonStyle())
    }

    private var doneButton: some View {
        Button {
            store.finishFlow()
        } label: {
            Label("Готово", systemImage: "checkmark")
        }
        .buttonStyle(FolioSecondaryButtonStyle())
    }

    private func prepareShare(_ document: FolioDocument) {
        do {
            shareURL = try store.makeShareCopy(for: document)
        } catch {
            store.alertMessage = error.localizedDescription
        }
    }
}
