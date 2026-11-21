import XCTest
@testable import FOLIO

final class ModelTests: XCTestCase {
    func testRussianPluralForms() {
        // Проверяет, что Localizable.xcstrings подключён и плюральные формы выбираются правильно.
        XCTAssertEqual(FolioPlural.pages(1), "1 страница")
        XCTAssertEqual(FolioPlural.pages(3), "3 страницы")
        XCTAssertEqual(FolioPlural.pages(5), "5 страниц")
        XCTAssertEqual(FolioPlural.pages(21), "21 страница")
        XCTAssertEqual(FolioPlural.documents(2), "2 документа")
        XCTAssertEqual(FolioPlural.files(11), "11 файлов")
    }

    func testCleanTitle() {
        XCTAssertEqual("Отчёт.pdf".folioCleanTitle(fallback: "x"), "Отчёт")
        XCTAssertEqual("Отчёт.PDF".folioCleanTitle(fallback: "x"), "Отчёт")
        XCTAssertEqual("a/b:c".folioCleanTitle(fallback: "x"), "a-b-c")
        XCTAssertEqual("   ".folioCleanTitle(fallback: "Документ"), "Документ")
        XCTAssertEqual("..hidden".folioCleanTitle(fallback: "x"), "hidden")
        XCTAssertEqual(String(repeating: "я", count: 300).folioCleanTitle(fallback: "x").count, FolioLimits.titleLength)
    }

    func testSnapshotFromVersion040Decodes() throws {
        // Формат index.json версии 0.4.0: без поля version.
        let id = UUID()
        let json = """
        {"documents":[{"id":"\(id.uuidString)","title":"Старый","relativePath":"\(id.uuidString).pdf",
        "kind":"source","origin":"pdf","pageCount":2,"byteCount":1000,"createdAt":0,"isFavorite":true}],
        "draftPages":[{"id":"\(UUID().uuidString)","documentID":"\(id.uuidString)","pageIndex":1,"rotation":90}]}
        """
        let snapshot = try JSONDecoder().decode(FolioSnapshot.self, from: Data(json.utf8))
        XCTAssertNil(snapshot.version)
        XCTAssertEqual(snapshot.documents.first?.title, "Старый")
        XCTAssertEqual(snapshot.draftPages.first?.rotation, 90)
    }

    func testDraftPreservesOrderAndRotationWhenCodable() throws {
        let pages = [
            FolioDraftPage(id: UUID(), documentID: UUID(), pageIndex: 2, rotation: 90),
            FolioDraftPage(id: UUID(), documentID: UUID(), pageIndex: 0, rotation: 0)
        ]
        let decoded = try JSONDecoder().decode([FolioDraftPage].self, from: JSONEncoder().encode(pages))
        XCTAssertEqual(decoded, pages)
    }

    func testDefaultWorkflows() {
        XCTAssertEqual(FolioSavedWorkflow.defaults.count, 3)
        XCTAssertEqual(FolioSavedWorkflow.defaults[1].intent, .photographs)
    }

    func testErrorMessagesUseLimits() {
        XCTAssertTrue(FolioIssue.tooManyPages(limit: 500).localizedDescription.contains("500"))
        XCTAssertFalse(FolioIssue.tooManyPages(limit: 500).localizedDescription.contains("МБ"))
    }
}
