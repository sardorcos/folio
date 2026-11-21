import SwiftUI

struct FolioHomeView: View {
    @ObservedObject var store: FolioStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }

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
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("folio.home")
    }

    private var brandHeader: some View {
        HStack(spacing: 11) {
            FolioBrandMark(size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "FOLIO")
                    .font(.title3.weight(.heavy))
                    .tracking(0.7)
                Text("PDF И ДОКУМЕНТЫ")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.0)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
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
        // На крупном шрифте кнопки встают друг под другом, а не обрезаются.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { addButton; scanButton }
            VStack(spacing: 10) { addButton; scanButton }
        }
    }

    private var addButton: some View {
        Button {
            store.startTask(.documents)
        } label: {
            Label("Добавить файлы", systemImage: "plus")
                .lineLimit(1)
        }
        .buttonStyle(FolioPrimaryButtonStyle())
        .accessibilityIdentifier("folio.addFiles")
    }

    private var scanButton: some View {
        Button {
            store.startTask(.scan)
        } label: {
            Label("Сканировать", systemImage: "viewfinder")
                .lineLimit(1)
        }
        .buttonStyle(FolioSecondaryButtonStyle())
        .accessibilityIdentifier("folio.scan")
    }

    private var tools: some View {
        VStack(alignment: .leading, spacing: 10) {
            FolioSectionHeader(title: "Что нужно сделать?")
            LazyVGrid(columns: columns, spacing: 10) {
                FolioToolTile(name: "Объединить PDF", detail: "Несколько файлов в один", symbol: "doc.on.doc") {
                    store.startTask(.documents)
                }
                FolioToolTile(name: "Фото в PDF", detail: "Снимки из галереи", symbol: "photo.on.rectangle") {
                    store.startTask(.photographs)
                }
                FolioToolTile(name: "Изменить страницы", detail: "Порядок и поворот", symbol: "rectangle.3.group") {
                    store.editPages()
                }
                FolioToolTile(name: "Уменьшить размер", detail: "Фото, сканы и PDF", symbol: "arrow.down.right.and.arrow.up.left") {
                    store.startTask(.compression)
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
                        .font(.title)
                        .foregroundStyle(FolioTheme.blue)
                        .frame(width: 52, height: 66)
                        .background(FolioTheme.blueSoft, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Незавершённый PDF")
                            .font(.headline).foregroundStyle(.primary)
                        Text(verbatim: "\(FolioPlural.documents(store.draftSourceCount)) · \(FolioPlural.pages(store.draft.count))")
                            .font(.footnote).foregroundStyle(.secondary)
                        Text("Продолжить сборку")
                            .font(.footnote.weight(.semibold)).foregroundStyle(FolioTheme.blue)
                    }
                    .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .padding(14)
                .background(FolioTheme.card, in: RoundedRectangle(cornerRadius: FolioTheme.corner))
            }
            .buttonStyle(FolioQuietButtonStyle())
            .accessibilityElement(children: .combine)
        }
    }

    private var recentFiles: some View {
        VStack(alignment: .leading, spacing: 10) {
            FolioSectionHeader(title: "Недавние", trailing: "Все файлы") { store.tab = .files }
            if store.recentDocuments.isEmpty {
                VStack(spacing: 12) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 7) { steps(separator: true) }
                        VStack(alignment: .leading, spacing: 8) { steps(separator: false) }
                    }
                    Text("Здесь появятся ваши готовые документы")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(19)
                .frame(maxWidth: .infinity)
                .background(FolioTheme.card, in: RoundedRectangle(cornerRadius: FolioTheme.corner))
            } else {
                VStack(spacing: 0) {
                    ForEach(store.recentDocuments) { document in
                        NavigationLink(value: FolioRoute.document(document.id)) {
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

    @ViewBuilder
    private func steps(separator: Bool) -> some View {
        smallStep("1", "Файлы")
        if separator { chevron }
        smallStep("2", "Страницы")
        if separator { chevron }
        smallStep("3", "PDF")
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").foregroundStyle(.tertiary).accessibilityHidden(true)
    }

    private func smallStep(_ number: String, _ name: LocalizedStringKey) -> some View {
        HStack(spacing: 5) {
            Text(verbatim: number)
                .font(.caption2.weight(.bold))
                .foregroundStyle(FolioTheme.blue)
                .frame(minWidth: 20, minHeight: 20)
                .background(FolioTheme.blueSoft, in: Circle())
            Text(name).font(.caption.weight(.medium))
        }
    }

    private var privacyLine: some View {
        Label("Документы обрабатываются только на вашем iPhone", systemImage: "lock.shield")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
    }
}
