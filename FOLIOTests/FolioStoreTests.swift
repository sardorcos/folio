import PDFKit
import XCTest
@testable import FOLIO

@MainActor
final class FolioStoreTests: XCTestCase {

    /// Хранилище во временной папке и отдельный UserDefaults: тесты не трогают данные приложения.
    private func makeStore(base existing: URL? = nil, suite existingSuite: String? = nil) throws -> (FolioStore, URL, String) {
        let base = try existing ?? Fixtures.temporaryDirectory()
        let suite = existingSuite ?? "FOLIOTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        if existing == nil {
            addTeardownBlock {
                try? FileManager.default.removeItem(at: base)
                UserDefaults().removePersistentDomain(forName: suite)
            }
        }
        let store = FolioStore(baseURL: base.appendingPathComponent("Library", isDirectory: true), defaults: defaults)
        return (store, base, suite)
    }

    private func importSample(_ store: FolioStore, base: URL, widths: [CGFloat] = [300, 400, 500],
                              name: String = "Пример") async throws {
        let input = base.appendingPathComponent("\(name).pdf")
        try Fixtures.makePDF(widths: widths, at: input)
        await store.performImport(urls: [input], replace: false)
    }

    func testImportAddsDocumentAndPages() async throws {
        let (store, base, _) = try makeStore()
        try await importSample(store, base: base)
        XCTAssertEqual(store.documents.count, 1)
        XCTAssertEqual(store.draft.count, 3)
        XCTAssertEqual(store.documents.first?.title, "Пример")
        XCTAssertEqual(store.homePath, [.composer])
        XCTAssertNil(store.alertMessage)
    }

    func testFailedImportKeepsExistingDraft() async throws {
        let (store, base, _) = try makeStore()
        try await importSample(store, base: base)
        let bad = base.appendingPathComponent("notes.txt")
        try Data("не PDF".utf8).write(to: bad)
        await store.performImport(urls: [bad], replace: true)
        XCTAssertEqual(store.draft.count, 3, "Черновик не очищается, если новый импорт не удался")
        XCTAssertNotNil(store.alertMessage)
    }

    func testSuccessfulImportReplacesDraftWhenRequested() async throws {
        let (store, base, _) = try makeStore()
        try await importSample(store, base: base)
        try await importSample(store, base: base, widths: [200], name: "Второй")
        XCTAssertEqual(store.draft.count, 4)
        let input = base.appendingPathComponent("Третий.pdf")
        try Fixtures.makePDF(widths: [250, 250], at: input)
        await store.performImport(urls: [input], replace: true)
        XCTAssertEqual(store.draft.count, 2)
        XCTAssertTrue(store.canUndo)
        store.undo()
        XCTAssertEqual(store.draft.count, 4)
    }

    func testExportPreservesOrderRotationAndName() async throws {
        let (store, base, _) = try makeStore()
        try await importSample(store, base: base)
        let ids = store.draft.map(\.id)
        store.rotatePages([ids[1]])
        store.movePage(ids[2], onto: ids[0])
        await store.performExport(name: "Итог.pdf")

        let result = try XCTUnwrap(store.lastResult)
        XCTAssertEqual(result.title, "Итог")
        XCTAssertEqual(result.kind, .result)
        let url = store.localURL(for: result)
        XCTAssertEqual(try Fixtures.pageWidths(of: url), [500, 300, 400])
        XCTAssertEqual(PDFDocument(url: url)?.page(at: 2)?.rotation, 90)
        XCTAssertEqual(store.homePath, [.composer, .export, .result])
    }

    func testDeleteRemovesFileDraftPagesAndRoutes() async throws {
        let (store, base, _) = try makeStore()
        try await importSample(store, base: base)
        let document = try XCTUnwrap(store.documents.first)
        let url = store.localURL(for: document)
        store.homePath = [.composer, .document(document.id)]

        store.deleteDocuments([document.id])

        XCTAssertTrue(store.documents.isEmpty)
        XCTAssertTrue(store.draft.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(store.homePath, [], "Экран удалённого документа и пустой редактор закрываются")
        store.undo()
        XCTAssertTrue(store.draft.isEmpty, "Отмена не возвращает страницы удалённого документа")
    }

    func testCorruptedIndexIsBackedUpAndFilesRecovered() throws {
        let base = try Fixtures.temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        let library = base.appendingPathComponent("Library", isDirectory: true)
        let files = library.appendingPathComponent("Files", isDirectory: true)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        try Fixtures.makePDF(widths: [300, 300], at: files.appendingPathComponent("\(UUID().uuidString).pdf"))
        try Data("{ испорченный json".utf8).write(to: library.appendingPathComponent("index.json"))

        let (store, _, _) = try makeStore(base: base, suite: "FOLIOTests-\(UUID().uuidString)")

        XCTAssertEqual(store.documents.count, 1, "Файл восстановлен из хранилища")
        XCTAssertEqual(store.documents.first?.pageCount, 2)
        XCTAssertNotNil(store.alertMessage)
        let names = try FileManager.default.contentsOfDirectory(atPath: library.path)
        XCTAssertTrue(names.contains { $0.hasPrefix("index.corrupted-") }, "Старый индекс сохранён")
        let index = try Data(contentsOf: library.appendingPathComponent("index.json"))
        XCTAssertNoThrow(try JSONDecoder().decode(FolioSnapshot.self, from: index))
    }

    func testLibrarySurvivesRestart() async throws {
        let (store, base, suite) = try makeStore()
        try await importSample(store, base: base)
        store.createTemplate(name: "Мой", quality: .maximum, targetMB: 2)
        let (reopened, _, _) = try makeStore(base: base, suite: suite)
        XCTAssertEqual(reopened.documents.map(\.id), store.documents.map(\.id))
        XCTAssertEqual(reopened.draft, store.draft)
        XCTAssertEqual(reopened.templates.first?.quality, .maximum)
    }

    func testTaskPresetsDoNotLeakBetweenTasks() throws {
        let (store, _, _) = try makeStore()
        store.startTask(.compression)
        XCTAssertEqual(store.exportQuality, .smallerPhotos)
        XCTAssertEqual(store.targetSizeMB, 5)
        store.showingImporter = false
        store.startTask(.documents)
        XCTAssertEqual(store.exportQuality, .original, "Сжатие не «залипает» для следующей задачи")
        XCTAssertNil(store.targetSizeMB)
    }

    func testPhotoImportCreatesOneDocument() async throws {
        let (store, _, _) = try makeStore()
        let jpeg = try Fixtures.makeJPEG(width: 3000, height: 4000)
        await store.performImageImport([.data(jpeg), .data(jpeg), .data(jpeg)], origin: .photo, replace: false)
        XCTAssertEqual(store.documents.count, 1)
        XCTAssertEqual(store.documents.first?.pageCount, 3)
        XCTAssertEqual(store.draft.count, 3)
    }

    func testPasswordProtectedImportAsksForPassword() async throws {
        let (store, base, _) = try makeStore()
        let input = base.appendingPathComponent("secret.pdf")
        try Fixtures.makeEncryptedPDF(at: input, password: "1234")
        await store.performImport(urls: [input], replace: false)
        XCTAssertTrue(store.documents.isEmpty)
        XCTAssertEqual(store.passwordRequest?.fileName, "secret.pdf")
        XCTAssertNil(store.alertMessage, "Пароль запрашивается, а не показывается как ошибка")
    }

    func testDuplicateRespectsPageLimit() async throws {
        let (store, base, _) = try makeStore()
        try await importSample(store, base: base, widths: Array(repeating: 100, count: FolioLimits.draftPages))
        XCTAssertEqual(store.draft.count, FolioLimits.draftPages)
        store.duplicatePages([store.draft[0].id])
        XCTAssertEqual(store.draft.count, FolioLimits.draftPages)
        XCTAssertNotNil(store.alertMessage)
    }
}
