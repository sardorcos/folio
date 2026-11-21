import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct FolioRootView: View {
    @ObservedObject var store: FolioStore
    @State private var password = ""

    private var passwordTitle: LocalizedStringKey {
        if store.passwordRequest?.wrongAttempt == true { return "Неверный пароль" }
        return "PDF защищён паролем"
    }

    var body: some View {
        TabView(selection: $store.tab) {
            NavigationStack(path: $store.homePath) {
                FolioHomeView(store: store)
                    .navigationDestination(for: FolioRoute.self) { route in
                        FolioRouteDestination(store: store, route: route)
                    }
            }
            .tabItem { Label("Главная", systemImage: "house") }
            .tag(FolioTab.home)

            NavigationStack(path: $store.filesPath) {
                FolioLibraryView(store: store)
                    .navigationDestination(for: FolioRoute.self) { route in
                        FolioRouteDestination(store: store, route: route)
                    }
            }
            .tabItem { Label("Файлы", systemImage: "folder") }
            .tag(FolioTab.files)

            NavigationStack {
                FolioTemplatesView(store: store)
            }
            .tabItem { Label("Шаблоны", systemImage: "square.stack") }
            .tag(FolioTab.templates)

            NavigationStack {
                FolioSettingsView(store: store)
            }
            .tabItem { Label("Настройки", systemImage: "gearshape") }
            .tag(FolioTab.settings)
        }
        .confirmationDialog("Есть незавершённый PDF", isPresented: $store.showingTaskChoice, titleVisibility: .visible) {
            Button("Добавить к текущему PDF") { store.chooseAppendToDraft() }
            Button("Начать новый PDF") { store.chooseNewDraft() }
            Button("Отмена", role: .cancel) { }
        } message: {
            Text("Текущий набор страниц не удалится, пока новые файлы не будут успешно добавлены.")
        }
        .confirmationDialog("В текущем PDF уже есть страницы", isPresented: $store.showingEditChoice, titleVisibility: .visible) {
            Button("Добавить документ к текущему PDF") { store.chooseAddEditorDocument() }
            Button("Редактировать только этот документ") { store.chooseReplaceEditorDocument() }
            Button("Отмена", role: .cancel) { }
        } message: {
            Text("Документы в библиотеке не изменятся. Предыдущий набор страниц можно вернуть кнопкой «Отменить».")
        }
        .fileImporter(isPresented: $store.showingImporter,
                      allowedContentTypes: [.pdf, .image],
                      allowsMultipleSelection: true) { result in
            store.handleImporter(result)
        }
        .photosPicker(isPresented: $store.showingPhotoPicker,
                      selection: $store.photoSelection,
                      maxSelectionCount: FolioLimits.draftPages,
                      selectionBehavior: .ordered,
                      matching: .images)
        .onChange(of: store.photoSelection) { _, items in
            store.handlePhotoSelection(items)
        }
        .fullScreenCover(isPresented: $store.showingScanner) {
            FolioScannerView(onComplete: { store.importScannedImages($0) },
                             onCancel: { store.scannerCancelled() },
                             onError: { store.scannerFailed($0) })
                .ignoresSafeArea()
        }
        .alert("Нет доступа к камере", isPresented: $store.showingCameraDenied) {
            Button("Открыть Настройки") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Отмена", role: .cancel) { }
        } message: {
            Text("Разрешите FOLIO использовать камеру в Настройках, чтобы сканировать бумажные документы.")
        }
        .alert(passwordTitle,
               isPresented: Binding(get: { store.passwordRequest != nil }, set: { _ in }),
               presenting: store.passwordRequest) { _ in
            SecureField("Пароль", text: $password)
            Button("Открыть") {
                store.submitPassword(password)
                password = ""
            }
            Button("Пропустить", role: .cancel) {
                store.skipPassword()
                password = ""
            }
        } message: { request in
            Text("Введите пароль для «\(request.fileName)». В библиотеке FOLIO сохранится копия без пароля, оригинал не изменится.")
        }
        .alert("FOLIO", isPresented: Binding(get: { store.alertMessage != nil },
                                             set: { if !$0 { store.alertMessage = nil } })) {
            Button("Понятно", role: .cancel) { store.alertMessage = nil }
        } message: {
            Text(store.alertMessage ?? "")
        }
        .overlay {
            if store.isProcessing {
                FolioProcessingOverlay(label: store.processingLabel, progress: store.processingProgress) {
                    store.cancelProcessing()
                }
            }
        }
    }
}

/// Экран для маршрута навигации. Общий для вкладок «Главная» и «Файлы».
struct FolioRouteDestination: View {
    @ObservedObject var store: FolioStore
    let route: FolioRoute

    var body: some View {
        switch route {
        case .composer:
            FolioComposerView(store: store)
        case .export:
            FolioExportView(store: store)
        case .result:
            FolioResultView(store: store)
        case .document(let id):
            if let document = store.document(id: id) {
                FolioDocumentView(store: store, document: document)
            } else {
                ContentUnavailableView("Документ не найден", systemImage: "doc.questionmark",
                                       description: Text("Возможно, он был удалён."))
            }
        }
    }
}

struct FolioProcessingOverlay: View {
    let label: String
    var progress: Double? = nil
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 16) {
                if let progress {
                    ProgressView(value: progress)
                        .frame(width: 200)
                        .accessibilityValue(Text("\(Int(progress * 100)) %"))
                } else {
                    ProgressView().controlSize(.large)
                }
                Text(label)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Button("Отменить", role: .cancel, action: onCancel)
                    .buttonStyle(.bordered)
            }
            .padding(28)
            .frame(maxWidth: 300)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(label)
        }
        .accessibilityAddTraits(.isModal)
    }
}

#Preview("FOLIO") {
    FolioRootView(store: FolioStore())
}
