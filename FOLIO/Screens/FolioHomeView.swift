import SwiftUI

struct FolioHomeView: View {
    @ObservedObject var store: FolioStore
    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                brandHeader
                introduction
                mainActions
                tools
                if !store.draft.isEmpty { draftCard }
                recentFiles
                privacyLine
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 30)
        }
        .background(FolioTheme.canvas)
        .accessibilityIdentifier("folio.home")
    }

    private var brandHeader: some View {
        HStack(spacing: 11) {
            FolioBrandMark(size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("FOLIO")
                    .font(.title3.weight(.heavy))
                    .tracking(0.7)
                Text("PDF И ДОКУМЕНТЫ")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.0)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                store.tab = .settings
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(FolioTheme.card, in: Circle())
            }
            .accessibilityLabel("Настройки приложения")
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("PDF, фото и сканы.\nВсё в одном приложении.")
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Объединяйте файлы, меняйте порядок страниц, уменьшайте размер и отправляйте готовый PDF.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
        }
    }

    private var mainActions: some View {
        HStack(spacing: 10) {
            Button {
                store.openImporter(.documents)
            } label: {
                Label("Добавить файлы", systemImage: "plus")
            }
            .buttonStyle(FolioPrimaryButtonStyle())
            .accessibilityIdentifier("folio.addFiles")

            Button {
                store.showingScanner = true
            } label: {
                Label("Сканировать", systemImage: "viewfinder")
            }
            .buttonStyle(FolioSecondaryButtonStyle())
            .accessibilityIdentifier("folio.scan")
        }
    }

    private var tools: some View {
        VStack(alignment: .leading, spacing: 10) {
            FolioSectionHeader(title: "Что нужно сделать?")
            LazyVGrid(columns: columns, spacing: 10) {
                FolioToolTile(name: "Объединить PDF", detail: "Несколько файлов в один", symbol: "doc.on.doc") {
                    store.openImporter(.documents)
                }
                FolioToolTile(name: "Фото в PDF", detail: "Изображения в документ", symbol: "photo.on.rectangle") {
                    store.openImporter(.photographs)
                }
                FolioToolTile(name: "Изменить страницы", detail: "Порядок и поворот", symbol: "rectangle.3.group") {
                    if store.draft.isEmpty { store.openImporter(.editing) }
                    else { store.continueDraft() }
                }
                FolioToolTile(name: "Уменьшить размер", detail: "Фото и сканы", symbol: "arrow.down.right.and.arrow.up.left") {
                    if store.draft.isEmpty { store.openImporter(.compression) }
                    else { store.exportQuality = .smallerPhotos; store.tab = .home; store.path = [.composer, .export] }
                }
            }
        }
    }

    private var draftCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            FolioSectionHeader(title: "Продолжить работу")
            Button { store.continueDraft() } label: {
                HStack(spacing: 12) {
                    Image(systemName: "doc.text.image")
                        .font(.system(size: 29, weight: .light))
                        .foregroundStyle(FolioTheme.blue)
                        .frame(width: 52, height: 66)
                        .background(FolioTheme.blueSoft, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Незавершённый PDF")
                            .font(.headline).foregroundStyle(.primary)
                        Text("\(store.draftSourceCount) документа · \(store.draft.count) страниц")
                            .font(.footnote).foregroundStyle(.secondary)
                        Text("Продолжить сборку")
                            .font(.footnote.weight(.semibold)).foregroundStyle(FolioTheme.blue)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(FolioTheme.card, in: RoundedRectangle(cornerRadius: FolioTheme.corner))
            }
            .buttonStyle(FolioQuietButtonStyle())
        }
    }

    private var recentFiles: some View {
        VStack(alignment: .leading, spacing: 10) {
            FolioSectionHeader(title: "Недавние", trailing: "Все файлы") { store.tab = .files }
            if store.recentDocuments.isEmpty {
                VStack(spacing: 12) {
                    HStack(spacing: 7) {
                        smallStep("1", "Файлы")
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        smallStep("2", "Страницы")
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        smallStep("3", "PDF")
                    }
                    Text("Здесь появятся ваши готовые документы")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 19)
                .frame(maxWidth: .infinity)
                .background(FolioTheme.card, in: RoundedRectangle(cornerRadius: FolioTheme.corner))
            } else {
                VStack(spacing: 0) {
                    ForEach(store.recentDocuments) { document in
                        Button {
                            store.path = [.document(document.id)]
                        } label: {
                            FolioFileRow(document: document)
                        }
                        .buttonStyle(.plain)
                        if document.id != store.recentDocuments.last?.id { Divider().padding(.leading, 60) }
                    }
                }
                .padding(.horizontal, 14)
                .background(FolioTheme.card, in: RoundedRectangle(cornerRadius: FolioTheme.corner))
            }
        }
    }

    private func smallStep(_ number: String, _ name: String) -> some View {
        HStack(spacing: 5) {
            Text(number)
                .font(.caption2.weight(.bold))
                .foregroundStyle(FolioTheme.blue)
                .frame(width: 20, height: 20)
                .background(FolioTheme.blueSoft, in: Circle())
            Text(name).font(.caption.weight(.medium))
        }
    }

    private var privacyLine: some View {
        HStack(spacing: 7) {
            Image(systemName: "lock.shield")
            Text("Обработка документов на вашем iPhone")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }
}
