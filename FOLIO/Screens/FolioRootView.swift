import SwiftUI
import UniformTypeIdentifiers
import VisionKit

struct FolioRootView: View {
    @ObservedObject var store: FolioStore

    private var importTypes: [UTType] {
        store.importIntent == .photographs ? [.jpeg, .png, .heic] : [.pdf, .jpeg, .png, .heic]
    }

    var body: some View {
        NavigationStack(path: $store.path) {
            TabView(selection: $store.tab) {
                FolioHomeView(store: store)
                    .tabItem { Label("Главная", systemImage: "house") }
                    .tag(FolioTab.home)

                FolioLibraryView(store: store)
                    .tabItem { Label("Файлы", systemImage: "folder") }
                    .tag(FolioTab.files)

                FolioTemplatesView(store: store)
                    .tabItem { Label("Шаблоны", systemImage: "square.stack") }
                    .tag(FolioTab.templates)

                FolioSettingsView(store: store)
                    .tabItem { Label("Настройки", systemImage: "gearshape") }
                    .tag(FolioTab.settings)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: FolioRoute.self) { route in
                switch route {
                case .composer:
                    FolioComposerView(store: store)
                case .export:
                    FolioExportView(store: store)
                case .result:
                    FolioResultView(store: store)
                case .document(let id):
                    if let document = store.documents.first(where: { $0.id == id }) {
                        FolioDocumentView(store: store, document: document)
                    } else {
                        ContentUnavailableView("Документ не найден", systemImage: "doc.questionmark")
                    }
                }
            }
        }
        .confirmationDialog("Есть незавершённый PDF", isPresented: $store.showingTaskChoice) {
            Button("Добавить в текущий комплект") { store.chooseAppendToDraft() }
            Button("Создать новый комплект") { store.chooseNewDraft() }
            Button("Отмена", role: .cancel) { }
        } message: {
            Text("Выберите, нужно ли сохранить текущий порядок страниц или начать новый проект. Черновик не будет удалён до успешного импорта.")
        }
        .confirmationDialog("В текущем комплекте уже есть страницы", isPresented: $store.showingEditChoice) {
            Button("Добавить документ к комплекту") { store.chooseAddEditorDocument() }
            Button("Редактировать только выбранный документ") { store.chooseReplaceEditorDocument() }
            Button("Отмена", role: .cancel) { }
        } message: {
            Text("Исходные документы останутся в библиотеке. Выберите действие с незавершённым PDF.")
        }
        .fileImporter(isPresented: $store.showingImporter,
                      allowedContentTypes: importTypes,
                      allowsMultipleSelection: true) { result in
            store.handleImporter(result)
        }
        .sheet(isPresented: $store.showingScanner) {
            if VNDocumentCameraViewController.isSupported {
                FolioScannerView { data in
                    store.importScannedImages(data)
                }
            } else {
                ContentUnavailableView("Камера недоступна", systemImage: "camera.fill",
                                       description: Text("Сканирование работает на совместимом iPhone. Вместо камеры можно добавить фотографию из файлов."))
                    .presentationDetents([.medium])
            }
        }
        .alert("FOLIO", isPresented: Binding(get: { store.alertMessage != nil },
                                             set: { if !$0 { store.alertMessage = nil } })) {
            Button("Понятно", role: .cancel) { store.alertMessage = nil }
        } message: {
            Text(store.alertMessage ?? "")
        }
        .overlay {
            if store.isProcessing {
                ZStack {
                    Color.black.opacity(0.18).ignoresSafeArea()
                    VStack(spacing: 15) {
                        ProgressView().tint(FolioTheme.blue).controlSize(.large)
                        Text(store.processingLabel)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                    }
                    .padding(28)
                    .frame(maxWidth: 290)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }
}

#Preview("FOLIO · Главный экран") {
    FolioRootView(store: FolioStore())
}
