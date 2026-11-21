import XCTest
@testable import FOLIO

final class ShareInboxTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = try Fixtures.temporaryDirectory()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// Имитирует работу расширения: копирует файлы в пакет и (по желанию) публикует его.
    @discardableResult
    static func writeBatch(in inbox: URL, files: [(name: String, data: Data)], commit: Bool) throws -> URL {
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let batch = try FolioInbox.makeIncomingBatch(in: inbox)
        for (index, file) in files.enumerated() {
            let slot = FolioInbox.slot(index, in: batch)
            try FileManager.default.createDirectory(at: slot, withIntermediateDirectories: true)
            try file.data.write(to: slot.appendingPathComponent(file.name))
        }
        if commit { try FolioInbox.commit(batch, in: inbox) }
        return batch
    }

    func testIncompleteBatchIsIgnored() throws {
        let inbox = root.appendingPathComponent("Inbox")
        try Self.writeBatch(in: inbox, files: [("a.pdf", Data("a".utf8))], commit: false)
        let taken = FolioInbox.takeAll(from: inbox, movingTo: root.appendingPathComponent("Out"))
        XCTAssertTrue(taken.isEmpty, "Пакет, который ещё пишется, не забирается")
    }

    func testCommittedBatchesAreTakenInOrderAndRemoved() throws {
        let inbox = root.appendingPathComponent("Inbox")
        try Self.writeBatch(in: inbox, files: [("Первый.pdf", Data("1".utf8)), ("Второй.jpg", Data("2".utf8))], commit: true)
        let taken = FolioInbox.takeAll(from: inbox, movingTo: root.appendingPathComponent("Out"))
        XCTAssertEqual(taken.map(\.lastPathComponent), ["Первый.pdf", "Второй.jpg"])
        XCTAssertTrue(taken.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        let left = try FileManager.default.contentsOfDirectory(atPath: inbox.path).filter { !$0.hasPrefix(".") }
        XCTAssertTrue(left.isEmpty, "Забранные пакеты удаляются из общей папки")
    }

    func testAppGroupIdentifierFollowsBundleID() throws {
        let group = try XCTUnwrap(FolioInbox.appGroupIdentifier)
        XCTAssertTrue(group.hasPrefix("group."))
        XCTAssertFalse(group.hasSuffix(".share"))
    }
}

@MainActor
final class SharedImportStoreTests: XCTestCase {
    private func makeStore() throws -> (FolioStore, URL, URL) {
        let base = try Fixtures.temporaryDirectory()
        let suite = "FOLIOTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock {
            try? FileManager.default.removeItem(at: base)
            UserDefaults().removePersistentDomain(forName: suite)
        }
        let inbox = base.appendingPathComponent("Inbox", isDirectory: true)
        let store = FolioStore(baseURL: base.appendingPathComponent("Library", isDirectory: true),
                               defaults: defaults, inboxURL: inbox)
        return (store, base, inbox)
    }

    private func pdfData(widths: [CGFloat], in base: URL) throws -> Data {
        let url = base.appendingPathComponent("\(UUID().uuidString).pdf")
        try Fixtures.makePDF(widths: widths, at: url)
        return try Data(contentsOf: url)
    }

    func testSharedFilesOpenInEditorWhenDraftIsEmpty() async throws {
        let (store, base, inbox) = try makeStore()
        try ShareInboxTests.writeBatch(in: inbox, files: [("Счёт.pdf", try pdfData(widths: [300, 300], in: base))],
                                       commit: true)
        let urls = store.collectSharedFiles()
        XCTAssertEqual(urls.count, 1)
        await store.performSharedImport(urls, addToDraft: true)
        XCTAssertEqual(store.documents.first?.title, "Счёт")
        XCTAssertEqual(store.draft.count, 2)
        XCTAssertEqual(store.homePath, [.composer])
        XCTAssertTrue(store.collectSharedFiles().isEmpty, "Повторно файлы не импортируются")
    }

    func testSharedFilesGoToLibraryWhenDraftIsBusy() async throws {
        let (store, base, inbox) = try makeStore()
        let busy = base.appendingPathComponent("busy.pdf")
        try Fixtures.makePDF(widths: [200], at: busy)
        await store.performImport(urls: [busy], replace: false)
        let draftBefore = store.draft

        try ShareInboxTests.writeBatch(in: inbox, files: [("Новый.pdf", try pdfData(widths: [400], in: base))],
                                       commit: true)
        await store.performSharedImport(store.collectSharedFiles(), addToDraft: false)

        XCTAssertEqual(store.documents.count, 2)
        XCTAssertEqual(store.draft, draftBefore, "Текущий PDF не меняется")
        XCTAssertNotNil(store.alertMessage)
    }

    func testTextIndexEnablesContentSearch() async throws {
        let (store, base, _) = try makeStore()
        let input = base.appendingPathComponent("Отчёт.pdf")
        try Fixtures.makePDF(widths: [400, 400], at: input)
        await store.performImport(urls: [input], replace: false)
        let document = try XCTUnwrap(store.documents.first)
        XCTAssertTrue(store.matchesSearch(document, query: "Страница 2"), "Поиск по тексту внутри PDF")
        XCTAssertFalse(store.matchesSearch(document, query: "несуществующая фраза"))
        XCTAssertNotNil(store.textSnippet(for: document.id, matching: "Страница"))
        store.deleteDocuments([document.id])
        XCTAssertNil(store.documentText[document.id])
    }
}
