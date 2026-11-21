import AVFoundation
import Foundation
import PhotosUI
import SwiftUI
import UIKit
import VisionKit

@MainActor
final class FolioStore: ObservableObject {

    // MARK: - Состояние

    @Published private(set) var documents: [FolioDocument] = []
    @Published private(set) var draft: [FolioDraftPage] = []
    @Published private(set) var templates: [FolioSavedWorkflow] = []

    @Published var tab: FolioTab = .home
    @Published var homePath: [FolioRoute] = []
    @Published var filesPath: [FolioRoute] = []

    @Published var showingImporter = false
    @Published var showingPhotoPicker = false
    @Published var photoSelection: [PhotosPickerItem] = []
    @Published var showingScanner = false
    @Published var showingCameraDenied = false
    @Published var showingTaskChoice = false
    @Published var showingEditChoice = false
    @Published private(set) var passwordRequest: FolioPasswordRequest?

    @Published private(set) var isProcessing = false
    @Published private(set) var processingLabel = ""
    /// Доля выполненной работы (0…1) для длительных операций; `nil` — неопределённый прогресс.
    @Published private(set) var processingProgress: Double?
    @Published var alertMessage: String?

    @Published var exportQuality: PDFQuality = .original
    @Published var targetSizeMB: Int?
    @Published private(set) var lastResultID: UUID?
    /// Пояснение к последнему результату (например, «цель по размеру не достигнута»).
    @Published private(set) var lastExportNote: String?
    @Published private(set) var canUndo = false

    /// Распознавать текст (OCR) в фото и сканах. Хранится в UserDefaults.
    @Published var ocrEnabled: Bool = true {
        didSet { defaults.set(ocrEnabled, forKey: Self.ocrKey) }
    }
    /// Текст документов для поиска по содержимому. Хранится в `Text/<id>.txt`.
    @Published private(set) var documentText: [UUID: String] = [:]

    private(set) var importIntent: ImportIntent = .documents

    private var undoStack: [[FolioDraftPage]] = [] {
        didSet { canUndo = !undoStack.isEmpty }
    }
    private var pendingEditorDocument: FolioDocument?
    private var replaceDraftOnImport = false
    private var pendingPasswordURLs: [URL] = []
    private var passwordImportAddsToDraft = true
    private var currentTask: Task<Void, Never>?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    private let root: URL
    private let folder: URL
    private let indexURL: URL
    private let tempFolder: URL
    private let textFolder: URL
    private let inboxURL: URL?
    private let defaults: UserDefaults
    private static let templatesKey = "folio.savedWorkflows"
    private static let ocrKey = "folio.ocrEnabled"

    // MARK: - Запуск

    /// - Parameters:
    ///   - baseURL: каталог хранилища. По умолчанию `Application Support/FOLIO` (как в 0.4.0, для миграции).
    ///   - defaults: хранилище шаблонов и настроек. В тестах передаётся отдельный suite.
    ///   - inboxURL: общая папка расширения «Поделиться». По умолчанию — папка App Group.
    init(baseURL: URL? = nil, defaults: UserDefaults = .standard, inboxURL: URL? = FolioInbox.directory) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = baseURL ?? support.appendingPathComponent("FOLIO", isDirectory: true)
        folder = root.appendingPathComponent("Files", isDirectory: true)
        indexURL = root.appendingPathComponent("index.json")
        tempFolder = root.appendingPathComponent("Temp", isDirectory: true)
        textFolder = root.appendingPathComponent("Text", isDirectory: true)
        self.inboxURL = inboxURL
        self.defaults = defaults
        ocrEnabled = defaults.object(forKey: Self.ocrKey) as? Bool ?? true

        let fileManager = FileManager.default
        try? fileManager.removeItem(at: tempFolder)
        try? fileManager.removeItem(at: Self.shareRoot)
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: tempFolder, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: textFolder, withIntermediateDirectories: true)
        } catch {
            alertMessage = String(localized: "Не удалось подготовить хранилище: \(error.localizedDescription)")
        }
        loadLibrary()
        loadTemplates()
        Task { [weak self] in await self?.loadTextIndex() }
    }

    private func loadLibrary() {
        do {
            let data = try Data(contentsOf: indexURL)
            let saved = try JSONDecoder().decode(FolioSnapshot.self, from: data)
            let existing = saved.documents.filter {
                FileManager.default.fileExists(atPath: folder.appendingPathComponent($0.relativePath).path)
            }
            documents = existing
            let ids = Set(existing.map(\.id))
            draft = saved.draftPages.filter { page in
                guard ids.contains(page.documentID),
                      let document = existing.first(where: { $0.id == page.documentID }) else { return false }
                return page.pageIndex >= 0 && page.pageIndex < document.pageCount
            }
            let recovered = recoverUnindexedFiles()
            if existing.count != saved.documents.count || draft.count != saved.draftPages.count || recovered > 0
                || saved.version != FolioSnapshot.currentVersion {
                persist()
            }
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // Первый запуск или индекс был удалён: подхватываем файлы, если они есть.
            if recoverUnindexedFiles() > 0 { persist() }
        } catch {
            // Повреждённый индекс никогда не перезаписывается молча: сохраняем копию и восстанавливаем список по файлам.
            let backup = backupCorruptedIndex()
            let recovered = recoverUnindexedFiles()
            persist()
            var message = String(localized: "Список документов был повреждён. Восстановлено из хранилища: \(FolioPlural.documents(recovered)).")
            if let backup {
                message += " " + String(localized: "Копия старого списка: \(backup.lastPathComponent).")
            }
            alertMessage = message
        }
        lastResultID = documents.first(where: { $0.kind == .result })?.id
    }

    private func backupCorruptedIndex() -> URL? {
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = root.appendingPathComponent("index.corrupted-\(stamp).json")
        do {
            try FileManager.default.moveItem(at: indexURL, to: backup)
            return backup
        } catch {
            return nil
        }
    }

    /// Возвращает в библиотеку файлы, которые лежат в хранилище, но отсутствуют в индексе
    /// (например, после сбоя между записью файла и записью индекса).
    @discardableResult
    private func recoverUnindexedFiles() -> Int {
        let known = Set(documents.map(\.relativePath))
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        var recovered: [FolioDocument] = []
        for url in files where url.pathExtension.lowercased() == "pdf" && !known.contains(url.lastPathComponent) {
            guard let pages = PDFWorker.pageCount(of: url),
                  let bytes = try? PDFWorker.byteCount(for: url) else { continue }
            let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) ?? UUID()
            guard !documents.contains(where: { $0.id == id }) else { continue }
            recovered.append(FolioDocument(id: id,
                                           title: String(localized: "Восстановленный документ \(recovered.count + 1)"),
                                           relativePath: url.lastPathComponent,
                                           kind: .source, origin: .pdf,
                                           pageCount: pages, byteCount: bytes, createdAt: Date()))
        }
        documents.append(contentsOf: recovered)
        return recovered.count
    }

    // MARK: - Производные значения

    var sourceDocuments: [FolioDocument] { documents.filter { $0.kind == .source } }
    var resultDocuments: [FolioDocument] { documents.filter { $0.kind == .result } }
    var recentDocuments: [FolioDocument] { Array(documents.sorted { $0.createdAt > $1.createdAt }.prefix(3)) }
    var draftSourceCount: Int { Set(draft.map(\.documentID)).count }
    var storageBytes: Int64 { documents.reduce(0) { $0 + $1.byteCount } }
    var lastResult: FolioDocument? { documents.first(where: { $0.id == lastResultID }) }

    func document(id: UUID) -> FolioDocument? { documents.first(where: { $0.id == id }) }

    func localURL(for document: FolioDocument) -> URL {
        folder.appendingPathComponent(document.relativePath)
    }

    func localURL(forDocumentID id: UUID) -> URL? {
        document(id: id).map(localURL(for:))
    }

    /// Фрагмент текста документа вокруг найденного запроса — для подсказки в результатах поиска.
    func textSnippet(for id: UUID, matching query: String) -> String? {
        guard !query.isEmpty, let text = documentText[id],
              let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else { return nil }
        let start = text.index(range.lowerBound, offsetBy: -40, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: 60, limitedBy: text.endIndex) ?? text.endIndex
        let fragment = text[start..<end].components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return (start > text.startIndex ? "…" : "") + fragment + (end < text.endIndex ? "…" : "")
    }

    func matchesSearch(_ document: FolioDocument, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        if document.title.localizedStandardContains(query) { return true }
        return documentText[document.id]?.localizedStandardContains(query) ?? false
    }

    func draftPageCount(referencing ids: Set<UUID>) -> Int {
        draft.filter { ids.contains($0.documentID) }.count
    }

    /// Имя по умолчанию на экране экспорта: название первого документа в комплекте.
    var suggestedExportName: String {
        if let firstID = draft.first?.documentID, let first = document(id: firstID), first.kind == .source,
           draftSourceCount == 1 {
            return first.title
        }
        return String(localized: "Документ \(Date().formatted(date: .numeric, time: .omitted))")
    }

    // MARK: - Запуск задач

    /// Точка входа для кнопок «Объединить PDF», «Фото в PDF», «Сканировать», шаблонов и т. п.
    /// Если есть незавершённый комплект, сначала спрашиваем, добавить к нему или начать новый.
    func startTask(_ intent: ImportIntent, preset: ExportPreset? = nil) {
        guard !isProcessing else { return }
        importIntent = intent
        apply(preset ?? Self.defaultPreset(for: intent))
        if draft.isEmpty {
            replaceDraftOnImport = false
            presentSource()
        } else {
            showingTaskChoice = true
        }
    }

    /// «Добавить файлы» внутри редактора: всегда дополняет текущий комплект.
    func addToCurrentDraft(_ source: ImportSource = .files) {
        guard !isProcessing else { return }
        importIntent = source == .photos ? .photographs : (source == .scanner ? .scan : .documents)
        replaceDraftOnImport = false
        presentSource()
    }

    func chooseAppendToDraft() {
        replaceDraftOnImport = false
        presentSource()
    }

    func chooseNewDraft() {
        // Текущий комплект остаётся, пока не будет успешно добавлен хотя бы один новый документ.
        replaceDraftOnImport = true
        presentSource()
    }

    private func presentSource() {
        switch importIntent.source {
        case .files:
            showingImporter = true
        case .photos:
            photoSelection = []
            showingPhotoPicker = true
        case .scanner:
            startScanner()
        }
    }

    private static func defaultPreset(for intent: ImportIntent) -> ExportPreset {
        switch intent {
        case .compression: ExportPreset(quality: .smallerPhotos, targetMB: 5)
        case .documents, .photographs, .editing, .scan: ExportPreset(quality: .original, targetMB: nil)
        }
    }

    private func apply(_ preset: ExportPreset) {
        exportQuality = preset.quality
        targetSizeMB = preset.targetMB
    }

    /// Плитка «Изменить страницы».
    func editPages() {
        if draft.isEmpty { startTask(.editing) } else { continueDraft() }
    }

    func continueDraft() {
        guard !draft.isEmpty else { startTask(.documents); return }
        tab = .home
        homePath = [.composer]
    }

    /// Кнопка «Готово» на экране результата.
    func finishFlow() {
        homePath = []
    }

    // MARK: - Импорт из «Файлов»

    func handleImporter(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }
            let replace = takeReplaceFlag()
            runProcessing(String(localized: "Добавляем документы…")) { [weak self] in
                await self?.performImport(urls: urls, replace: replace)
            }
        case .failure(let error):
            replaceDraftOnImport = false
            if (error as NSError).code != NSUserCancelledError { alertMessage = error.localizedDescription }
        }
    }

    /// Импорт файлов. Вызывается из UI через `runProcessing` и напрямую из тестов.
    /// - Parameter addToDraft: `false` — только в библиотеку (файлы из «Поделиться» при занятом черновике).
    func performImport(urls: [URL], replace: Bool, addToDraft: Bool = true) async {
        let directory = folder
        let temp = tempFolder
        let ocr = ocrEnabled
        var imported: [FolioDocument] = []
        var failures: [String] = []
        var locked: [URL] = []
        for (index, url) in urls.enumerated() {
            if Task.isCancelled { break }
            processingProgress = urls.count > 1 ? Double(index) / Double(urls.count) : nil
            do {
                let document = try await Self.offMain {
                    try PDFWorker.importFile(url: url, id: UUID(), ocr: ocr, directory: directory, tempDirectory: temp)
                }
                imported.append(document)
            } catch is CancellationError {
                break
            } catch FolioIssue.passwordProtected {
                locked.append(url)
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        finishImport(imported, replace: replace, failures: failures, total: urls.count, addToDraft: addToDraft)
        await indexText(for: imported)
        if !locked.isEmpty && !Task.isCancelled {
            pendingPasswordURLs = locked
            passwordImportAddsToDraft = addToDraft
            askNextPassword()
        }
    }

    // MARK: - Пароль PDF

    private func askNextPassword(wrongAttempt: Bool = false, url: URL? = nil) {
        if let url {
            passwordRequest = FolioPasswordRequest(url: url, wrongAttempt: wrongAttempt)
        } else if !pendingPasswordURLs.isEmpty {
            passwordRequest = FolioPasswordRequest(url: pendingPasswordURLs.removeFirst())
        } else {
            passwordRequest = nil
        }
    }

    func submitPassword(_ password: String) {
        guard let request = passwordRequest else { return }
        passwordRequest = nil
        let url = request.url
        let directory = folder
        let temp = tempFolder
        runProcessing(String(localized: "Открываем PDF…")) { [weak self] in
            guard let self else { return }
            do {
                let document = try await Self.offMain {
                    try PDFWorker.importFile(url: url, id: UUID(), password: password,
                                             directory: directory, tempDirectory: temp)
                }
                // Документ добавляется к комплекту, который уже обновлён первой частью импорта.
                self.finishImport([document], replace: false, failures: [], total: 1,
                                  addToDraft: self.passwordImportAddsToDraft)
                await self.indexText(for: [document])
                self.askNextPassword()
            } catch FolioIssue.wrongPassword {
                self.askNextPassword(wrongAttempt: true, url: url)
            } catch is CancellationError {
                self.pendingPasswordURLs = []
            } catch {
                self.alertMessage = "\(url.lastPathComponent): \(error.localizedDescription)"
                self.askNextPassword()
            }
        }
    }

    func skipPassword() {
        passwordRequest = nil
        askNextPassword()
    }

    // MARK: - Импорт из «Фото»

    func handlePhotoSelection(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        photoSelection = []
        let replace = takeReplaceFlag()
        runProcessing(String(localized: "Добавляем фотографии…")) { [weak self] in
            await self?.performPhotoImport(items, replace: replace)
        }
    }

    private func performPhotoImport(_ items: [PhotosPickerItem], replace: Bool) async {
        var payloads: [Data] = []
        var failed = 0
        for item in items {
            if Task.isCancelled { return }
            do {
                if let data = try await item.loadTransferable(type: Data.self) {
                    payloads.append(data)
                } else {
                    failed += 1
                }
            } catch {
                failed += 1
            }
        }
        await performImageImport(payloads.map { .data($0) }, origin: .photo, replace: replace,
                                 failedBefore: failed, total: items.count)
    }

    /// Создаёт один документ из изображений. Используется для фото и сканов (и в тестах).
    func performImageImport(_ inputs: [PDFWorker.ImageInput], origin: FileOrigin, replace: Bool,
                            failedBefore: Int = 0, total: Int? = nil) async {
        let directory = folder
        let temp = tempFolder
        let ocr = ocrEnabled
        let progress = progressHandler()
        let stamp = Date().formatted(date: .numeric, time: .shortened)
        let title = origin == .scan ? String(localized: "Скан \(stamp)") : String(localized: "Фото \(stamp)")
        var failures = Array(repeating: String(localized: "Фото не удалось загрузить"), count: failedBefore)
        guard !inputs.isEmpty else {
            finishImport([], replace: replace, failures: failures, total: total ?? failedBefore)
            return
        }
        do {
            if ocr { processingLabel = String(localized: "Распознаём текст…") }
            let document = try await Self.offMain {
                try PDFWorker.importImages(inputs, id: UUID(), title: title, origin: origin,
                                           ocr: ocr, progress: progress,
                                           directory: directory, tempDirectory: temp)
            }
            finishImport([document], replace: replace, failures: failures, total: total ?? inputs.count)
            await indexText(for: [document])
        } catch is CancellationError {
            return
        } catch {
            failures.append(error.localizedDescription)
            finishImport([], replace: replace, failures: failures, total: total ?? inputs.count)
        }
    }

    // MARK: - Сканер

    private func startScanner() {
        guard VNDocumentCameraViewController.isSupported else {
            alertMessage = String(localized: "Сканирование недоступно на этом устройстве. Можно добавить фотографию документа из галереи.")
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showingScanner = true
        case .notDetermined:
            Task { [weak self] in
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                if granted { self?.showingScanner = true } else { self?.showingCameraDenied = true }
            }
        default:
            showingCameraDenied = true
        }
    }

    func importScannedImages(_ images: [UIImage]) {
        showingScanner = false
        guard !images.isEmpty else { return }
        let replace = takeReplaceFlag()
        runProcessing(String(localized: "Сохраняем скан…")) { [weak self] in
            await self?.performImageImport(images.map { .image($0) }, origin: .scan, replace: replace)
        }
    }

    func scannerCancelled() {
        showingScanner = false
        replaceDraftOnImport = false
    }

    func scannerFailed(_ error: Error) {
        showingScanner = false
        replaceDraftOnImport = false
        alertMessage = String(localized: "Камера не смогла завершить сканирование: \(error.localizedDescription)")
    }

    // MARK: - Общий финал импорта

    private func takeReplaceFlag() -> Bool {
        let replace = replaceDraftOnImport
        replaceDraftOnImport = false
        return replace
    }

    private func finishImport(_ imported: [FolioDocument], replace: Bool, failures: [String], total: Int,
                              addToDraft: Bool = true) {
        var messages: [String] = []
        if !imported.isEmpty && !addToDraft {
            documents.insert(contentsOf: imported, at: 0)
            persist()
            messages.append(String(localized: "Добавлено в «Мои файлы»: \(FolioPlural.documents(imported.count)). Текущий PDF не изменён."))
        } else if !imported.isEmpty {
            documents.insert(contentsOf: imported, at: 0)
            var newDraft = replace ? [] : draft
            var skipped: [String] = []
            var added = 0
            for document in imported {
                if newDraft.count + document.pageCount <= FolioLimits.draftPages {
                    newDraft.append(contentsOf: Self.pages(of: document))
                    added += 1
                } else {
                    skipped.append(document.title)
                }
            }
            if added > 0 && newDraft != draft {
                captureUndo()
                draft = newDraft
            }
            persist()
            if !skipped.isEmpty {
                messages.append(String(localized: "В комплекте не больше \(FolioLimits.draftPages) страниц. Сохранено в библиотеке, но не добавлено: \(skipped.joined(separator: ", "))."))
            }
            if added > 0 {
                tab = .home
                homePath = importIntent == .compression ? [.composer, .export] : [.composer]
            }
        }
        if !failures.isEmpty {
            let header = String(localized: "Не удалось добавить: \(failures.count) из \(total).")
            messages.append(([header] + failures.prefix(3)).joined(separator: "\n"))
        }
        if !messages.isEmpty { alertMessage = messages.joined(separator: "\n\n") }
    }

    private static func pages(of document: FolioDocument) -> [FolioDraftPage] {
        (0..<document.pageCount).map { FolioDraftPage(id: UUID(), documentID: document.id, pageIndex: $0) }
    }

    // MARK: - Редактор из библиотеки

    func newDraftFrom(_ document: FolioDocument) {
        if draft.isEmpty {
            replaceDraftWith(document)
        } else if Set(draft.map(\.documentID)) == [document.id] {
            continueDraft()
        } else {
            pendingEditorDocument = document
            showingEditChoice = true
        }
    }

    func chooseAddEditorDocument() {
        guard let document = pendingEditorDocument else { return }
        pendingEditorDocument = nil
        guard draft.count + document.pageCount <= FolioLimits.draftPages else {
            alertMessage = String(localized: "В комплекте не больше \(FolioLimits.draftPages) страниц.")
            return
        }
        captureUndo()
        draft.append(contentsOf: Self.pages(of: document))
        persist()
        tab = .home
        homePath = [.composer]
    }

    func chooseReplaceEditorDocument() {
        guard let document = pendingEditorDocument else { return }
        pendingEditorDocument = nil
        replaceDraftWith(document)
    }

    private func replaceDraftWith(_ document: FolioDocument) {
        captureUndo()
        draft = Self.pages(of: document)
        persist()
        tab = .home
        homePath = [.composer]
    }

    // MARK: - Редактирование страниц

    private func captureUndo() {
        undoStack.append(draft)
        if undoStack.count > FolioLimits.undoDepth { undoStack.removeFirst() }
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        draft = previous
        persist()
    }

    func movePage(_ id: UUID, direction: Int) {
        guard let index = draft.firstIndex(where: { $0.id == id }) else { return }
        let newIndex = index + direction
        guard draft.indices.contains(newIndex) else { return }
        captureUndo()
        draft.swapAt(index, newIndex)
        persist()
    }

    /// Перетаскивание: страница `id` встаёт на место страницы `targetID`.
    func movePage(_ id: UUID, onto targetID: UUID) {
        guard id != targetID,
              let from = draft.firstIndex(where: { $0.id == id }),
              let to = draft.firstIndex(where: { $0.id == targetID }) else { return }
        captureUndo()
        let page = draft.remove(at: from)
        draft.insert(page, at: to)
        persist()
    }

    func movePageToEdge(_ id: UUID, toStart: Bool) {
        guard let from = draft.firstIndex(where: { $0.id == id }) else { return }
        let to = toStart ? 0 : draft.count - 1
        guard from != to else { return }
        captureUndo()
        let page = draft.remove(at: from)
        draft.insert(page, at: toStart ? 0 : draft.count)
        persist()
    }

    func rotatePages(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        captureUndo()
        for index in draft.indices where ids.contains(draft[index].id) {
            draft[index].rotation = PDFWorker.normalizedRotation(draft[index].rotation + 90)
        }
        persist()
    }

    func deletePages(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        captureUndo()
        draft.removeAll { ids.contains($0.id) }
        persist()
    }

    func keepOnlyPages(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        captureUndo()
        draft = draft.filter { ids.contains($0.id) }
        persist()
    }

    func duplicatePages(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let additions = draft.filter { ids.contains($0.id) }.map {
            FolioDraftPage(id: UUID(), documentID: $0.documentID, pageIndex: $0.pageIndex, rotation: $0.rotation)
        }
        guard draft.count + additions.count <= FolioLimits.draftPages else {
            alertMessage = String(localized: "В комплекте не больше \(FolioLimits.draftPages) страниц.")
            return
        }
        captureUndo()
        draft.append(contentsOf: additions)
        persist()
    }

    func clearDraft() {
        captureUndo()
        draft.removeAll()
        persist()
        homePath = []
    }

    // MARK: - Библиотека

    func toggleFavorite(_ document: FolioDocument) {
        guard let index = documents.firstIndex(where: { $0.id == document.id }) else { return }
        documents[index].isFavorite.toggle()
        persist()
    }

    func rename(_ document: FolioDocument, to name: String) {
        guard let index = documents.firstIndex(where: { $0.id == document.id }) else { return }
        let clean = name.folioCleanTitle(fallback: "")
        guard !clean.isEmpty else { return }
        documents[index].title = clean
        persist()
    }

    /// Удаляет документы из библиотеки вместе с их страницами в комплекте.
    /// Сначала удаляются файлы, затем пишется индекс: при сбое в промежутке запись без файла будет отброшена при запуске.
    func deleteDocuments(_ ids: Set<UUID>) {
        let removed = documents.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return }
        for document in removed {
            let url = localURL(for: document)
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: textURL(for: document.id))
            documentText[document.id] = nil
            Task { await ThumbnailRenderer.shared.forget(url: url) }
        }
        documents.removeAll { ids.contains($0.id) }
        draft.removeAll { ids.contains($0.documentID) }
        undoStack = undoStack.map { snapshot in snapshot.filter { !ids.contains($0.documentID) } }
        if let lastResultID, ids.contains(lastResultID) {
            self.lastResultID = documents.first(where: { $0.kind == .result })?.id
            lastExportNote = nil
        }
        homePath = Self.pruned(homePath, removing: ids, draftIsEmpty: draft.isEmpty)
        filesPath = Self.pruned(filesPath, removing: ids, draftIsEmpty: draft.isEmpty)
        persist()
    }

    private static func pruned(_ path: [FolioRoute], removing ids: Set<UUID>, draftIsEmpty: Bool) -> [FolioRoute] {
        var result: [FolioRoute] = []
        for route in path {
            if case .document(let id) = route, ids.contains(id) { break }
            if draftIsEmpty && (route == .composer || route == .export) { break }
            result.append(route)
        }
        return result
    }

    /// «Удалить все документы» в настройках. Шаблоны сохраняются.
    func deleteAllDocuments() {
        for document in documents {
            try? FileManager.default.removeItem(at: localURL(for: document))
            try? FileManager.default.removeItem(at: textURL(for: document.id))
        }
        documentText = [:]
        Task { await ThumbnailRenderer.shared.forgetAll() }
        documents = []
        draft = []
        undoStack = []
        lastResultID = nil
        lastExportNote = nil
        homePath = []
        filesPath = []
        persist()
    }

    // MARK: - Экспорт

    func exportDraft(name: String) {
        guard !isProcessing else { return }
        guard !draft.isEmpty else {
            alertMessage = FolioIssue.noPages.localizedDescription
            return
        }
        runProcessing(String(localized: "Создаём PDF…")) { [weak self] in
            await self?.performExport(name: name)
        }
    }

    /// Создание PDF. Вызывается из UI через `runProcessing` и напрямую из тестов.
    func performExport(name: String) async {
        let title = name.folioCleanTitle(fallback: suggestedExportName)
        let pages = draft
        let sources = documents
        let directory = folder
        let temp = tempFolder
        let quality = exportQuality
        let ocr = ocrEnabled
        let progress = progressHandler()
        let target = targetSizeMB
        let targetBytes = target.map { Int64($0) * 1_000_000 }
        let id = UUID()
        let relativePath = "\(id.uuidString).pdf"
        let destination = folder.appendingPathComponent(relativePath)
        do {
            let outcome = try await Self.offMain {
                try PDFWorker.export(pages: pages, documents: sources, directory: directory, tempDirectory: temp,
                                     destination: destination, title: title, quality: quality,
                                     targetBytes: targetBytes, ocr: ocr, progress: progress)
            }
            let document = FolioDocument(id: id, title: title, relativePath: relativePath,
                                         kind: .result, origin: .pdf, pageCount: pages.count,
                                         byteCount: outcome.byteCount, createdAt: Date())
            documents.insert(document, at: 0)
            lastResultID = id
            lastExportNote = Self.note(for: outcome, quality: quality, target: target, targetBytes: targetBytes)
            persist()
            await indexText(for: [document])
            tab = .home
            homePath = [.composer, .export, .result]
        } catch is CancellationError {
            alertMessage = String(localized: "Создание PDF отменено. Комплект не изменён.")
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private static func note(for outcome: ExportOutcome, quality: PDFQuality, target: Int?, targetBytes: Int64?) -> String? {
        let size = FolioLimits.formatted(outcome.byteCount)
        if let target, let targetBytes, outcome.byteCount > targetBytes {
            switch quality {
            case .original:
                return String(localized: "Размер \(size) больше цели \(target) МБ. В режиме «Исходное качество» страницы не сжимаются — выберите «Уменьшить фото и сканы» или «Максимальное сжатие».")
            case .smallerPhotos:
                return String(localized: "Удалось уменьшить до \(size), но цель \(target) МБ не достигнута. Обычные PDF-страницы в этом режиме не сжимаются — попробуйте «Максимальное сжатие».")
            case .maximum:
                return String(localized: "Удалось уменьшить до \(size), но цель \(target) МБ не достигнута. Уберите часть страниц или разделите документ.")
            }
        }
        if outcome.usedCompression {
            let before = FolioLimits.formatted(outcome.uncompressedByteCount)
            return String(localized: "Размер уменьшен: \(before) → \(size).")
        }
        if quality != .original {
            return String(localized: "Сжатие не дало выигрыша, сохранён вариант без потери качества.")
        }
        return nil
    }

    /// Временная копия с понятным именем для отправки: получатель видит название, а не внутренний UUID.
    func makeShareCopy(for document: FolioDocument) throws -> URL {
        let folder = Self.shareRoot.appendingPathComponent(document.id.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = document.title.folioCleanTitle(fallback: String(localized: "Документ"))
        let target = folder.appendingPathComponent(name + ".pdf")
        try FileManager.default.copyItem(at: localURL(for: document), to: target)
        return target
    }

    private static var shareRoot: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("FOLIO-share", isDirectory: true)
    }

    // MARK: - Шаблоны

    private func loadTemplates() {
        guard let data = defaults.data(forKey: Self.templatesKey),
              let decoded = try? JSONDecoder().decode([FolioSavedWorkflow].self, from: data) else { return }
        templates = decoded
    }

    private func saveTemplates() {
        if let data = try? JSONEncoder().encode(templates) {
            defaults.set(data, forKey: Self.templatesKey)
        }
    }

    func createTemplate(name: String, quality: PDFQuality, targetMB: Int?) {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        templates.insert(FolioSavedWorkflow(id: UUID(), name: String(title.prefix(FolioLimits.titleLength)),
                                            description: quality.title,
                                            quality: quality, targetMB: targetMB), at: 0)
        saveTemplates()
    }

    func deleteTemplates(_ ids: Set<UUID>) {
        templates.removeAll { ids.contains($0.id) }
        saveTemplates()
    }

    func launch(_ workflow: FolioSavedWorkflow) {
        startTask(workflow.intent, preset: workflow.preset)
    }

    // MARK: - Распознавание текста (OCR)

    /// Сколько страниц документа без текста — показывать ли действие «Распознать текст».
    func pagesWithoutText(in document: FolioDocument) async -> Int {
        let url = localURL(for: document)
        return (try? await Self.offMain { PDFWorker.pagesWithoutText(at: url) }) ?? 0
    }

    /// Создаёт копию документа с распознанным текстом и открывает её. Оригинал не меняется.
    func makeSearchableCopy(of document: FolioDocument) {
        let source = localURL(for: document)
        let directory = folder
        let temp = tempFolder
        let title = String(localized: "\(document.title) (с текстом)").folioCleanTitle(fallback: document.title)
        let progress = progressHandler()
        runProcessing(String(localized: "Распознаём текст…")) { [weak self] in
            guard let self else { return }
            do {
                let outcome = try await Self.offMain {
                    try PDFWorker.makeSearchableCopy(of: source, id: UUID(), title: title,
                                                     directory: directory, tempDirectory: temp, progress: progress)
                }
                let copy = outcome.document
                let recognized = outcome.recognizedPages
                guard recognized > 0 else {
                    try? FileManager.default.removeItem(at: self.localURL(for: copy))
                    self.alertMessage = String(localized: "Текст на страницах не найден. Попробуйте скан лучшего качества.")
                    return
                }
                self.documents.insert(copy, at: 0)
                self.persist()
                await self.indexText(for: [copy])
                self.openDocument(copy.id, replacing: document.id)
                self.alertMessage = String(localized: "Текст распознан: \(FolioPlural.pages(recognized)). Создан документ «\(copy.title)».")
            } catch is CancellationError {
                return
            } catch {
                self.alertMessage = error.localizedDescription
            }
        }
    }

    /// Открывает документ вместо текущего экрана документа во вкладке, где пользователь находится.
    private func openDocument(_ id: UUID, replacing oldID: UUID) {
        func replaceRoute(in path: inout [FolioRoute]) -> Bool {
            guard let index = path.lastIndex(of: .document(oldID)) else { return false }
            path[index] = .document(id)
            return true
        }
        if tab == .files, replaceRoute(in: &filesPath) { return }
        if tab == .home, replaceRoute(in: &homePath) { return }
        tab = .files
        filesPath = [.document(id)]
    }

    private func textURL(for id: UUID) -> URL {
        textFolder.appendingPathComponent("\(id.uuidString).txt")
    }

    private struct TextJob: Sendable {
        let id: UUID
        let pdf: URL
        let text: URL
        let readExisting: Bool
    }

    private struct TextEntry: Sendable {
        let id: UUID
        let text: String
    }

    /// Извлекает текст новых документов и сохраняет его для поиска.
    func indexText(for documents: [FolioDocument]) async {
        guard !documents.isEmpty else { return }
        let jobs = documents.map { TextJob(id: $0.id, pdf: localURL(for: $0), text: textURL(for: $0.id), readExisting: false) }
        await runTextJobs(jobs)
    }

    /// При запуске: читает сохранённый текст, а для документов без него (например, из 0.4.0) извлекает заново.
    private func loadTextIndex() async {
        let jobs = documents.map {
            TextJob(id: $0.id, pdf: localURL(for: $0), text: textURL(for: $0.id), readExisting: true)
        }
        await runTextJobs(jobs)
    }

    private func runTextJobs(_ jobs: [TextJob]) async {
        let entries = (try? await Self.offMain { () -> [TextEntry] in
            jobs.map { job in
                if job.readExisting, let saved = try? String(contentsOf: job.text, encoding: .utf8) {
                    return TextEntry(id: job.id, text: saved)
                }
                let text = PDFWorker.extractText(from: job.pdf)
                try? text.write(to: job.text, atomically: true, encoding: .utf8)
                return TextEntry(id: job.id, text: text)
            }
        }) ?? []
        for entry in entries where document(id: entry.id) != nil {
            documentText[entry.id] = entry.text
        }
    }

    // MARK: - Файлы из «Поделиться»

    /// Вызывается при каждом переходе приложения в активное состояние.
    /// Если черновик пуст, файлы сразу открываются в редакторе; иначе попадают только в библиотеку.
    func importSharedFiles() {
        guard !isProcessing else { return }
        let urls = collectSharedFiles()
        guard !urls.isEmpty else { return }
        let addToDraft = draft.isEmpty
        runProcessing(String(localized: "Добавляем файлы из «Поделиться»…")) { [weak self] in
            await self?.performSharedImport(urls, addToDraft: addToDraft)
        }
    }

    /// Забирает завершённые пакеты из общей папки во временную папку приложения.
    func collectSharedFiles() -> [URL] {
        guard let inboxURL else { return [] }
        let destination = tempFolder.appendingPathComponent("Shared-\(UUID().uuidString)", isDirectory: true)
        return FolioInbox.takeAll(from: inboxURL, movingTo: destination)
    }

    func performSharedImport(_ urls: [URL], addToDraft: Bool) async {
        importIntent = .documents
        await performImport(urls: urls, replace: false, addToDraft: addToDraft)
    }

    // MARK: - Длительные операции

    /// Обновляет `processingProgress` из фоновой работы.
    private func progressHandler() -> PDFWorker.FolioProgress {
        { [weak self] done, total in
            Task { @MainActor in
                guard let self, self.isProcessing else { return }
                self.processingProgress = total > 0 ? min(1, Double(done) / Double(total)) : nil
            }
        }
    }

    private func runProcessing(_ label: String, _ operation: @escaping @MainActor () async -> Void) {
        guard !isProcessing else { return }
        isProcessing = true
        processingLabel = label
        processingProgress = nil
        beginBackgroundWork()
        currentTask = Task { [weak self] in
            await operation()
            self?.endProcessing()
        }
    }

    private func endProcessing() {
        isProcessing = false
        processingLabel = ""
        processingProgress = nil
        currentTask = nil
        endBackgroundWork()
    }

    func cancelProcessing() {
        currentTask?.cancel()
    }

    /// iOS даёт немного времени завершить операцию, если пользователь свернул приложение.
    private func beginBackgroundWork() {
        endBackgroundWork()
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "FOLIO.processing") { [weak self] in
            MainActor.assumeIsolated {
                self?.currentTask?.cancel()
                self?.endBackgroundWork()
            }
        }
    }

    private func endBackgroundWork() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    /// Выполняет синхронную работу вне главного потока; отмена родительской задачи передаётся внутрь.
    private static func offMain<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        let task = Task.detached(priority: .userInitiated) { try work() }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    // MARK: - Сохранение индекса

    private func persist() {
        do {
            let state = FolioSnapshot(version: FolioSnapshot.currentVersion, documents: documents, draftPages: draft)
            let encoded = try JSONEncoder().encode(state)
            try encoded.write(to: indexURL, options: .atomic)
        } catch {
            alertMessage = String(localized: "Не удалось записать изменения библиотеки: \(error.localizedDescription)")
        }
    }
}
