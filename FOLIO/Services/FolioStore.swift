import Foundation
import SwiftUI

@MainActor
final class FolioStore: ObservableObject {
    @Published private(set) var documents: [FolioDocument] = []
    @Published private(set) var draft: [FolioDraftPage] = []
    @Published var path: [FolioRoute] = []
    @Published var tab: FolioTab = .home
    @Published var showingImporter = false
    @Published var showingScanner = false
    @Published var showingTaskChoice = false
    @Published var showingEditChoice = false
    @Published var isProcessing = false
    @Published var processingLabel = ""
    @Published var alertMessage: String?
    @Published var exportQuality: PDFQuality = .original
    @Published var targetSizeMB: Int? = 5
    @Published var lastResultID: UUID?
    private(set) var importIntent: ImportIntent = .documents

    private var undoStack: [[FolioDraftPage]] = []
    private var pendingIntent: ImportIntent?
    private var pendingEditorDocument: FolioDocument?
    private var replaceDraftOnImport = false
    private let folder: URL
    private let indexURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        folder = support.appendingPathComponent("FOLIO/Files", isDirectory: true)
        indexURL = support.appendingPathComponent("FOLIO/index.json")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = try Data(contentsOf: indexURL)
            let saved = try JSONDecoder().decode(FolioSnapshot.self, from: data)
            documents = saved.documents.filter {
                FileManager.default.fileExists(atPath: folder.appendingPathComponent($0.relativePath).path)
            }
            let ids = Set(documents.map(\.id))
            draft = saved.draftPages.filter { ids.contains($0.documentID) }
            lastResultID = documents.first(where: { $0.kind == .result })?.id
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // First launch: index does not exist yet.
        } catch {
            // Never replace a damaged index silently. User can export existing files from app storage.
            alertMessage = "Не удалось открыть библиотеку. Исходные файлы не удалены. Проверьте резервную копию данных приложения."
        }
    }

    var sourceDocuments: [FolioDocument] { documents.filter { $0.kind == .source } }
    var resultDocuments: [FolioDocument] { documents.filter { $0.kind == .result } }
    var recentDocuments: [FolioDocument] { Array(documents.sorted { $0.createdAt > $1.createdAt }.prefix(3)) }
    var draftSourceCount: Int { Set(draft.map(\.documentID)).count }

    func localURL(for document: FolioDocument) -> URL {
        folder.appendingPathComponent(document.relativePath)
    }

    func openImporter(_ intent: ImportIntent) {
        importIntent = intent
        if intent == .compression { exportQuality = .smallerPhotos }
        if !draft.isEmpty && path.isEmpty {
            pendingIntent = intent
            showingTaskChoice = true
        } else {
            showingImporter = true
        }
    }

    func chooseAppendToDraft() {
        if let pendingIntent { importIntent = pendingIntent }
        pendingIntent = nil
        replaceDraftOnImport = false
        showingImporter = true
    }

    func chooseNewDraft() {
        if let pendingIntent { importIntent = pendingIntent }
        pendingIntent = nil
        // Keep the previous draft until at least one new input succeeds.
        replaceDraftOnImport = true
        showingImporter = true
    }

    func handleImporter(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { replaceDraftOnImport = false; return }
            importFiles(urls)
        case .failure(let error):
            replaceDraftOnImport = false
            // User cancellation may be reported as an error by the system picker.
            if (error as NSError).code != NSUserCancelledError { alertMessage = error.localizedDescription }
        }
    }

    private func importFiles(_ urls: [URL]) {
        guard !isProcessing else { return }
        isProcessing = true
        processingLabel = "Добавляем документы…"
        let intent = importIntent
        let destination = folder

        Task {
            var imported = 0
            var errors: [String] = []
            for url in urls {
                let newID = UUID()
                do {
                    let document = try await Task.detached(priority: .userInitiated) {
                        try PDFWorker.importFile(url: url, id: newID, directory: destination)
                    }.value
                    if imported == 0 && replaceDraftOnImport {
                        captureUndo()
                        draft.removeAll()
                        replaceDraftOnImport = false
                    }
                    documents.insert(document, at: 0)
                    appendPages(of: document)
                    imported += 1
                } catch {
                    errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            if imported > 0 {
                persist()
                path = intent == .compression ? [.composer, .export] : [.composer]
            }
            replaceDraftOnImport = false
            isProcessing = false
            processingLabel = ""
            if !errors.isEmpty {
                alertMessage = "Добавлено: \(imported). Не удалось открыть: \(errors.count).\n" + errors.prefix(2).joined(separator: "\n")
            }
        }
    }

    func importScannedImages(_ images: [Data]) {
        guard !images.isEmpty, !isProcessing else { return }
        isProcessing = true
        processingLabel = "Сохраняем сканы…"
        let directory = folder
        let id = UUID()
        Task {
            do {
                let item = try await Task.detached(priority: .userInitiated) {
                    try PDFWorker.importScan(jpegs: images, id: id, directory: directory)
                }.value
                documents.insert(item, at: 0)
                appendPages(of: item)
                persist()
                path = [.composer]
            } catch {
                alertMessage = error.localizedDescription
            }
            isProcessing = false
            processingLabel = ""
        }
    }

    private func appendPages(of document: FolioDocument) {
        guard draft.count + document.pageCount <= PDFWorker.pageLimit else {
            alertMessage = "В одном комплекте допускается не более 100 страниц. Документ сохранён в библиотеке."
            return
        }
        captureUndo()
        draft.append(contentsOf: (0..<document.pageCount).map {
            FolioDraftPage(id: UUID(), documentID: document.id, pageIndex: $0)
        })
    }

    func newDraftFrom(_ document: FolioDocument) {
        if !draft.isEmpty {
            pendingEditorDocument = document
            showingEditChoice = true
        } else {
            replaceDraftWith(document)
        }
    }

    func chooseAddEditorDocument() {
        guard let doc = pendingEditorDocument else { return }
        pendingEditorDocument = nil
        appendPages(of: doc)
        persist()
        tab = .home
        path = [.composer]
    }

    func chooseReplaceEditorDocument() {
        guard let doc = pendingEditorDocument else { return }
        pendingEditorDocument = nil
        replaceDraftWith(doc)
    }

    private func replaceDraftWith(_ document: FolioDocument) {
        captureUndo()
        draft = (0..<document.pageCount).map {
            FolioDraftPage(id: UUID(), documentID: document.id, pageIndex: $0)
        }
        persist()
        tab = .home
        path = [.composer]
    }

    func continueDraft() {
        guard !draft.isEmpty else { openImporter(.documents); return }
        tab = .home
        path = [.composer]
    }

    private func captureUndo() {
        undoStack.append(draft)
        if undoStack.count > 30 { undoStack.removeFirst() }
    }

    var canUndo: Bool { !undoStack.isEmpty }
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

    func rotatePages(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        captureUndo()
        for index in draft.indices where ids.contains(draft[index].id) {
            draft[index].rotation = (draft[index].rotation + 90) % 360
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
        guard draft.count + additions.count <= PDFWorker.pageLimit else {
            alertMessage = "Достигнуто ограничение в 100 страниц."
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
        path = []
    }

    func toggleFavorite(_ document: FolioDocument) {
        guard let index = documents.firstIndex(where: { $0.id == document.id }) else { return }
        documents[index].isFavorite.toggle()
        persist()
    }

    func rename(_ document: FolioDocument, to name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let index = documents.firstIndex(where: { $0.id == document.id }) else { return }
        documents[index].title = clean
        persist()
    }

    func exportDraft(name: String) {
        guard !draft.isEmpty, !isProcessing else {
            alertMessage = FolioIssue.noPages.localizedDescription
            return
        }
        isProcessing = true
        processingLabel = "Создаём PDF…"
        let sourceDocuments = documents
        let pages = draft
        let destinationFolder = folder
        let quality = exportQuality
        let safeTitle = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Новый PDF" : name
        let id = UUID()
        let relativePath = "\(id.uuidString).pdf"
        let destination = folder.appendingPathComponent(relativePath)
        let target = targetSizeMB
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try PDFWorker.export(pages: pages, documents: sourceDocuments, directory: destinationFolder,
                                         destination: destination, quality: quality)
                }.value
                let document = FolioDocument(id: id, title: safeTitle, relativePath: relativePath,
                                             kind: .result, origin: .pdf, pageCount: pages.count,
                                             byteCount: result.byteCount, createdAt: Date())
                documents.insert(document, at: 0)
                lastResultID = id
                persist()
                path = [.composer, .export, .result]
                if let target, result.byteCount > Int64(target) * 1024 * 1024 {
                    alertMessage = "PDF создан, но его размер превышает цель \(target) МБ. Исходное качество не ухудшалось для обычных PDF."
                }
            } catch {
                alertMessage = error.localizedDescription
            }
            isProcessing = false
            processingLabel = ""
        }
    }

    /// The receiver sees an informative filename, never an internal UUID.
    func makeShareCopy(for document: FolioDocument) throws -> URL {
        let cleanName = document.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let basename = cleanName.lowercased().hasSuffix(".pdf") ? String(cleanName.dropLast(4)) : cleanName
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("FOLIO-share/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent((basename.isEmpty ? "Документ" : basename) + ".pdf")
        try FileManager.default.copyItem(at: localURL(for: document), to: target)
        return target
    }

    func removeShareCopy(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    private func persist() {
        do {
            let state = FolioSnapshot(documents: documents, draftPages: draft)
            let encoded = try JSONEncoder().encode(state)
            try encoded.write(to: indexURL, options: .atomic)
        } catch {
            alertMessage = "Не удалось записать изменения библиотеки: \(error.localizedDescription)"
        }
    }
}
